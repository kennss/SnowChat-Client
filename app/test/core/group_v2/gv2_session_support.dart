/// @file        gv2_session_support.dart
/// @description Shared support for the group protocol v2 tests that run on
///              real 1:1 sessions: Gv2SignalSessions over a test party (X3DH
///              + Double Ratchet with Identity Binding), a sealed sender
///              certificate signed by a test server key, send tokens a
///              stand-in server can check, and a crypto wrapper that counts
///              how often envelopes are opened.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (refreshEndorsements says how it ended; revisionDiffers). Earlier 2026-11-21 (the counting crypto records whose sessions were dropped). Earlier 2026-11-20
///
/// @functions
///  - Gv2TestDirectory: who the test parties are (implemented by a test's
///    world)
///  - Gv2TestSessions: Gv2SignalSessions over a TestParty
///  - Gv2TestCountingCrypto: counts opened envelopes
///  - Gv2TestTokens: send tokens of the form "groupId|ciphertext,..."
///  - gv2TestCertificate(): a sender certificate signed by a test server key
///  - gv2TestDeviceIdOf(): a 36-character device id for a name
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/sender_certificate.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_credentials.dart'
    show Gv2EndorsementOutcome;
import 'package:snowchat/core/group_v2/gv2_outbox.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise_crypto.dart';
import 'package:snowchat/core/group_v2/gv2_transport.dart';

import '../crypto/identity_test_support.dart';
import 'gv2_test_support.dart';

/// The parties of a test, by snowId, and the next one-time prekey of each.
abstract interface class Gv2TestDirectory {
  TestParty party(String snowId);
  int nextOpk(String snowId);
}

const gv2TestIssuedAtMs = 1794528000000;
const gv2TestBindingEpoch = 1000;

/// The binding epoch of a party that is not at [gv2TestBindingEpoch]: a
/// reinstalled device has new session keys and binds them at a later epoch.
final Expando<int> gv2TestEpochOf = Expando<int>('gv2 test binding epoch');

String gv2TestDeviceIdOf(String name) {
  final hex = gv2Hex(gv2TestBytes('device $name', 16));
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-'
      '8${hex.substring(17, 20)}-${hex.substring(20, 32)}';
}

/// Gv2SignalSessions over a test party: sessions are set up from the
/// peer's bundle (Identity Binding v1 included), as SignalSessionManager
/// does after fetching it.
class Gv2TestSessions implements Gv2SignalSessions {
  final TestParty me;
  final Gv2TestDirectory world;
  Gv2TestSessions(this.me, this.world);

  @override
  Uint8List? get identityPublicKey => me.signal.identityPublicKey;

  @override
  Uint8List? get identityPrivateKey => me.signal.identityPrivateKey;

  @override
  Future<void> ensureSession(String peer) async {
    final p = world.party(peer);
    if (await me.signal.hasSession(peer, p.deviceId)) return;
    await _establish(p);
  }

  Future<void> _establish(TestParty p) => me.signal.createSession(
    recipientId: p.snowId,
    deviceId: p.deviceId,
    preKeyBundle: p.bundle(
      binding: p.bindingFor(
        epoch: gv2TestEpochOf[p] ?? gv2TestBindingEpoch,
      ),
      accountPublicKey: p.accountPub,
      opkIndex: world.nextOpk(p.snowId),
    ),
  );

  @override
  Uint8List? remoteIdentityKey(String peer) =>
      me.signal.getRemoteIdentityKey(peer);

  @override
  Future<String> deviceIdFor(String peer) async => world.party(peer).deviceId;

  @override
  Future<Uint8List> encrypt(
    String peer,
    String deviceId,
    Uint8List plaintext,
  ) async =>
      (await me.signal.encryptMessage(
            recipientId: peer,
            deviceId: deviceId,
            plaintext: plaintext,
          ))['ciphertext']
          as Uint8List;

  @override
  int messageTypeOf(Uint8List ciphertext, Uint8List certifiedIdentityKey) =>
      me.signal.resolveSealedMessageType(ciphertext, certifiedIdentityKey);

  @override
  Future<Uint8List> decrypt(
    String peer,
    String deviceId,
    Uint8List ciphertext,
    int messageType,
  ) => me.signal.decryptMessage(
    senderId: peer,
    deviceId: deviceId,
    ciphertext: ciphertext,
    messageType: messageType,
    envelopeDeviceId: deviceId,
  );

  int resets = 0;
  bool failResets = false;

  @override
  Future<void> archiveAndRestart(String peer) async {
    if (failResets) throw const Gv2NetworkException();
    resets++;
    final p = world.party(peer);
    await me.signal.archiveSession(peer, p.deviceId);
    await _establish(p);
  }

  int archives = 0;

  /// The next this many archives fail (the device could not record them).
  int failArchives = 0;

  @override
  Future<void> archive(String peer) async {
    if (failArchives > 0) {
      failArchives--;
      throw StateError('the archive could not be recorded');
    }
    archives++;
    await me.signal.archiveSessionsOf(peer);
  }
}

/// Counts how often envelopes are opened (each one moves a 1:1 session).
class Gv2TestCountingCrypto implements Gv2PairwiseCrypto {
  final Gv2PairwiseCrypto inner;
  int opens = 0;
  Gv2TestCountingCrypto(this.inner);

  @override
  Future<Uint8List> seal(String recipient, Uint8List plaintext) =>
      inner.seal(recipient, plaintext);

  @override
  Future<Gv2PairwiseOpened> open(Uint8List envelope) {
    opens++;
    return inner.open(envelope);
  }

  @override
  Future<void> resetSession(String peer) => inner.resetSession(peer);

  /// Peers whose sessions were dropped, in order.
  final List<String> forgotten = [];

  @override
  Future<void> forgetSession(String peer) {
    forgotten.add(peer);
    return inner.forgetSession(peer);
  }
}

/// Tokens the stand-in server recognises: one value per (group, recipient
/// set). [missing] groups have no endorsements until refreshed.
class Gv2TestTokens implements Gv2SendTokens {
  final Set<String> missing = {};
  final Set<String> stuck = {};
  int refreshes = 0;

  static Uint8List tokenFor(String groupId, List<String> ciphertexts) =>
      Uint8List.fromList(utf8.encode('$groupId|${ciphertexts.join(',')}'));

  @override
  Future<Uint8List?> sendToken(
    String groupId,
    List<String> ciphertexts,
  ) async => missing.contains(groupId) ? null : tokenFor(groupId, ciphertexts);

  /// Whether a refresh finds the server at another revision of the log
  /// than this device (none set: never).
  Future<bool> Function(String groupId)? revisionDiffers;

  @override
  Future<Gv2EndorsementOutcome> refreshEndorsements(String groupId) async {
    refreshes++;
    if (await revisionDiffers?.call(groupId) ?? false) {
      return Gv2EndorsementOutcome.revisionDiffers;
    }
    if (!stuck.contains(groupId)) missing.remove(groupId);
    return Gv2EndorsementOutcome.stored;
  }
}

SenderCertificate gv2TestCertificate(ed.SigningKey serverKey, TestParty p) {
  final expiryMs = DateTime.now().millisecondsSinceEpoch + 86400000;
  SenderCertificate make(Uint8List sig) => SenderCertificate(
    version: 1,
    senderSnowchatId: p.snowId,
    senderDeviceId: p.deviceId,
    senderIdentityKey: p.identityKey,
    expiryMs: expiryMs,
    serverSignature: sig,
  );
  final unsigned = make(Uint8List(64)).toBytes();
  return make(
    Uint8List.fromList(
      serverKey.sign(unsigned.sublist(0, 113)).signature.asTypedList,
    ),
  );
}
