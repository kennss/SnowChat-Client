/// @file        sealed_padding_test.dart
/// @description Security review S4 — the sizes the server sees. Real X3DH / Double Ratchet
///              sessions (SignalProtocolService) and real Sealed Sender envelopes, built by
///              EncryptedMessageHandler itself: a contact notice carrying this account's name
///              certificate (the longest name the app allows, in 4-byte characters), its answer, a
///              short text carrying the certificate and one without it all travel in envelopes of
///              one size — as the first envelope to a new peer (a prekey message with the identity
///              binding) and in an established session alike. This is what fixes the padding block
///              (sealedPlaintextBlock = 512): every one of them fits one block.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - _Sessions: the sender's SignalSessionManager over a real SignalProtocolService
///  - _Socket: records the sealed envelopes the handler hands to the socket
///  - main(): the measurements
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/contacts/name_certificate.dart';
import 'package:snowchat/core/crypto/encrypted_message_handler.dart';
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/sender_certificate.dart';
import 'package:snowchat/core/crypto/sender_certificate_manager.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/network/socket_manager.dart';

import '../contacts/name_cert_support.dart';
import '../group_v2/gv2_session_support.dart' show gv2TestCertificate;
import 'identity_test_support.dart';

const _devA = '11111111-1111-4111-8111-111111111111';
const _devB = '22222222-2222-4222-8222-222222222222';

class _Sessions extends Fake implements SignalSessionManager {
  final TestParty me;
  final TestParty peer;
  _Sessions(this.me, this.peer);

  @override
  SignalProtocolService get signal => me.signal;

  @override
  Future<void> refreshPeerIdentity(String snowId) async {}

  @override
  Future<void> ensureSession(String recipientSnowchatId) async {
    if (await me.signal.hasSession(peer.snowId, peer.deviceId)) return;
    await me.signal.createSession(
      recipientId: peer.snowId,
      deviceId: peer.deviceId,
      preKeyBundle: peer.bundle(
        binding: peer.bindingFor(epoch: 1000),
        accountPublicKey: peer.accountPub,
      ),
    );
  }

  @override
  Future<String> getDeviceIdForRecipient(String recipientSnowchatId) async =>
      peer.deviceId;

  @override
  Future<Map<String, dynamic>> encrypt(
    String recipientId,
    String deviceId,
    Uint8List plaintext,
  ) =>
      me.signal.encryptMessage(
        recipientId: recipientId,
        deviceId: deviceId,
        plaintext: plaintext,
      );
}

class _Socket extends Fake implements SocketManager {
  final sent = <String>[];

  @override
  bool get isConnected => true;

  @override
  bool get isReadyToSend => true;

  @override
  void sendSealedMessage({
    required String recipientId,
    required String sealedContent,
    required String clientMessageId,
    int? expiresIn,
    bool control = false,
    Function(dynamic)? onAck,
  }) {
    sent.add(sealedContent);
    onAck?.call({'messageId': 'srv-${sent.length}'});
  }
}

class _Certificates extends Fake implements SenderCertificateManager {
  final SenderCertificate certificate;
  _Certificates(this.certificate);

  @override
  Future<SenderCertificate> getCertificate() async => certificate;
}

/// One sender → recipient pair with real sessions.
class _Pair {
  final TestParty alice;
  final TestParty bob;
  final EncryptedMessageHandler handler;
  final _Socket socket;
  _Pair(this.alice, this.bob, this.handler, this.socket);

  static Future<_Pair> make() async {
    final alice = await TestParty.create(seedByte: 1, deviceId: _devA);
    final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
    alice.signal.setLocalIdentityBinding(alice.localBinding(epoch: 1000));
    final serverKey = ed.SigningKey(seed: Uint8List.fromList(List.filled(32, 9)));
    final socket = _Socket();
    final handler = EncryptedMessageHandler(
      sessionManager: _Sessions(alice, bob),
      socketManager: socket,
      sealedSenderService: SealedSenderService(
        trustedServerKeys: [Uint8List.fromList(serverKey.verifyKey.asTypedList)],
      ),
      senderCertificateManager: _Certificates(gv2TestCertificate(serverKey, alice)),
      isBlocked: (_) async => false,
    );
    return _Pair(alice, bob, handler, socket);
  }

  /// The size of the last envelope (bytes, as stored by the server).
  int get lastSize => base64Decode(socket.sent.last).length;

  /// Bob reads Alice's first (prekey) message and replies; Alice reads the
  /// reply: from then on Alice sends normal messages.
  Future<void> establish() async {
    await _Sessions(alice, bob).ensureSession(bob.snowId);
    final first = await alice.signal.encryptMessage(
      recipientId: bob.snowId,
      deviceId: bob.deviceId,
      plaintext: Uint8List.fromList(utf8.encode('{}')),
    );
    await bob.signal.decryptMessage(
      senderId: alice.snowId,
      deviceId: alice.deviceId,
      ciphertext: first['ciphertext'] as Uint8List,
      messageType: 2,
      envelopeDeviceId: alice.deviceId,
      identityDirectoryLookup: () async => throw StateError('bound sender'),
    );
    final reply = await bob.signal.encryptMessage(
      recipientId: alice.snowId,
      deviceId: alice.deviceId,
      plaintext: Uint8List.fromList(utf8.encode('{}')),
    );
    await alice.signal.decryptMessage(
      senderId: bob.snowId,
      deviceId: bob.deviceId,
      ciphertext: reply['ciphertext'] as Uint8List,
      messageType: 1,
      envelopeDeviceId: bob.deviceId,
    );
  }
}

void main() {
  // The longest name the app takes (20 characters), in 4-byte characters:
  // the largest certificate a user can have.
  final longestName = '\u{1F600}' * 20;

  Future<String> certOf(TestParty p) async => NameCertificate.parse(signNameCert(
        key: testServerKey(),
        snowId: p.snowId,
        name: longestName,
        issuedAtMs: 1795000000000,
      )).base64;

  /// The four kinds, each sent by [pair].
  Future<Map<String, int>> sizesOf(
    Future<_Pair> Function() pairFor, {
    required bool established,
  }) async {
    final sizes = <String, int>{};
    Future<void> measure(
      String kind,
      Future<void> Function(_Pair pair, String cert) send,
    ) async {
      final pair = await pairFor();
      if (established) await pair.establish();
      await send(pair, await certOf(pair.alice));
      sizes[kind] = pair.lastSize;
    }

    await measure('contact_added + cert', (p, cert) => p.handler.sendSealedPayload(
          recipientId: p.bob.snowId,
          payload: {'type': 'contact_added', 'v': 1, 'nameCert': cert},
          control: false,
        ));
    await measure('answer + cert', (p, cert) => p.handler.sendSealedPayload(
          recipientId: p.bob.snowId,
          payload: {'type': 'contact_added', 'v': 1, 'answer': true, 'nameCert': cert},
          control: false,
        ));
    await measure('short text + cert', (p, cert) => p.handler.sendSealedMessage(
          conversationId: p.bob.snowId,
          recipientId: p.bob.snowId,
          text: 'see you at 7?',
          clientMessageId: 'msg_1795000000000_text',
          wireMessageId: newWireMessageId(),
          nameCert: cert,
        ));
    await measure('short text', (p, _) => p.handler.sendSealedMessage(
          conversationId: p.bob.snowId,
          recipientId: p.bob.snowId,
          text: 'see you at 7?',
          clientMessageId: 'msg_1795000000000_text',
          wireMessageId: newWireMessageId(),
        ));
    return sizes;
  }

  test('first contact (a prekey message): a notice and a short text, with or '
      'without the certificate, are one size', () async {
    final sizes = await sizesOf(_Pair.make, established: false);
    // ignore: avoid_print
    print('first-contact envelope sizes: $sizes');
    expect(sizes.values.toSet(), hasLength(1), reason: '$sizes');
  });

  test('an established session: the same, one size', () async {
    final sizes = await sizesOf(_Pair.make, established: true);
    // ignore: avoid_print
    print('established-session envelope sizes: $sizes');
    expect(sizes.values.toSet(), hasLength(1), reason: '$sizes');
  });

  test('every one of them fits one block: a notice with the largest '
      'certificate is no bigger than the block', () {
    final cert = base64Encode(Uint8List(1 + 8 + 1 + 36 + 2 + 80 + 64));
    expect(
      encodeSealedPlaintext({
        'type': 'contact_added',
        'v': 1,
        'answer': true,
        'nameCert': cert,
      }).length,
      sealedPlaintextBlock,
    );
    expect(encodeSealedPlaintext({'type': 'contact_removed', 'v': 1}).length,
        sealedPlaintextBlock);
  });
}
