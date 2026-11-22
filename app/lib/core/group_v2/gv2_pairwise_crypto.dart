/// @file        gv2_pairwise_crypto.dart
/// @description Group protocol v2 — how a pairwise message is encrypted and
///              opened: on the 1:1 Double Ratchet session with the other
///              member, wrapped in the existing sealed sender envelope
///              (design §7.2: the session's headers stay hidden from anyone
///              holding the group key, and the server sees no sender). The
///              sessions themselves are the app's (SignalSessionManager);
///              this file only orders the steps and says why an envelope did
///              not open.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (no IdentityKeyChangedException (the legacy identity policy is gone)). Earlier 2026-11-20
///
/// @functions
///  - Gv2PairwiseCrypto: seal / open / reset / forget, as the pairwise layer
///    uses it
///  - Gv2SealedPairwiseCrypto: the implementation over the 1:1 sessions
///  - Gv2SignalSessions: the 1:1 sessions, narrowed to what is needed here
///  - Gv2SessionManagerSessions: Gv2SignalSessions over SignalSessionManager
///  - Gv2PairwiseOpened / Gv2PairwiseOpenException / Gv2PairwiseOpenFailure
///
/// Notes:
///  - Sealing fetches everything that can fail (session, certificate,
///    recipient identity key, device) BEFORE the ratchet moves: a failure
///    then burns no session counter (encrypted_message_handler.dart does the
///    same for 1:1).
///  - Opening tells three failures apart, because they call for different
///    reactions: [Gv2PairwiseOpenFailure.unsealed] (nothing to act on — not
///    for this device, a replay, a bad certificate), identity (the sender's
///    identity is not accepted — never reset a session over it), session
///    (certified, but the session did not decrypt it — the session is
///    broken and is reset).
///  - The sealed envelope carries the message context "group" (0x02): an
///    envelope of the 1:1 path that reached the group queue is not opened
///    here.
///  - Nothing here logs: envelopes, plaintexts and peers.
library;

import 'dart:typed_data';

import '../crypto/identity_binding_exception.dart';
import '../crypto/sealed_sender.dart';
import '../crypto/sender_certificate.dart';
import '../crypto/signal_session_manager.dart';

/// Why a pairwise envelope did not open.
enum Gv2PairwiseOpenFailure {
  /// Not a sealed envelope for this device of the group context, a replay,
  /// outside the time window, a certificate that does not verify. Nothing to
  /// act on.
  unsealed,

  /// The sender's identity is not accepted (a changed key awaiting
  /// re-verification, a forged binding, a prekey message whose identity is
  /// not the certificate's). Dropped; a session reset cannot fix it.
  identity,

  /// Certified, but the 1:1 session with the sender did not decrypt it.
  session,
}

class Gv2PairwiseOpenException implements Exception {
  final Gv2PairwiseOpenFailure reason;

  /// The certified sender, known for [Gv2PairwiseOpenFailure.session] and
  /// [Gv2PairwiseOpenFailure.identity].
  final String? sender;

  const Gv2PairwiseOpenException(this.reason, [this.sender]);

  @override
  String toString() => 'Gv2PairwiseOpenException(${reason.name})';
}

/// An opened pairwise envelope.
class Gv2PairwiseOpened {
  /// From the verified sender certificate, and the 1:1 session that
  /// decrypted it.
  final String senderSnowId;
  final String senderDeviceId;
  final Uint8List plaintext;

  const Gv2PairwiseOpened({
    required this.senderSnowId,
    required this.senderDeviceId,
    required this.plaintext,
  });
}

abstract interface class Gv2PairwiseCrypto {
  /// Encrypt [plaintext] for [recipient] (snowId) and seal it. May fetch a
  /// prekey bundle and a sender certificate (network); throws when it
  /// cannot.
  Future<Uint8List> seal(String recipient, Uint8List plaintext);

  /// Open a sealed envelope. Throws [Gv2PairwiseOpenException]. The 1:1
  /// session moves: the same envelope does not open twice.
  Future<Gv2PairwiseOpened> open(Uint8List envelope);

  /// Give up the session with [peer] and start a new one, without telling
  /// the peer (the caller sends the first message of the new session).
  Future<void> resetSession(String peer);

  /// [peer] stated that its sessions are gone: put ours with it aside. The
  /// next [seal] for it starts a new session. Nothing is fetched or sent.
  /// Throws when it could not even be recorded (the caller tries again).
  Future<void> forgetSession(String peer);
}

/// The 1:1 Signal sessions, narrowed to what the pairwise channel needs.
abstract interface class Gv2SignalSessions {
  /// This device's X25519 identity key pair (null before onboarding).
  Uint8List? get identityPublicKey;
  Uint8List? get identityPrivateKey;

  /// A session with [peer] exists afterwards (X3DH when needed).
  Future<void> ensureSession(String peer);

  /// [peer]'s X25519 identity key, once a session exists.
  Uint8List? remoteIdentityKey(String peer);

  Future<String> deviceIdFor(String peer);

  /// The Double Ratchet ciphertext of [plaintext] for [peer].
  Future<Uint8List> encrypt(String peer, String deviceId, Uint8List plaintext);

  /// 1 or 2 (prekey); throws when a prekey message's identity is not
  /// [certifiedIdentityKey].
  int messageTypeOf(Uint8List ciphertext, Uint8List certifiedIdentityKey);

  Future<Uint8List> decrypt(
    String peer,
    String deviceId,
    Uint8List ciphertext,
    int messageType,
  );

  /// Archive the session with [peer] and set up a new one, telling no one.
  Future<void> archiveAndRestart(String peer);

  /// Archive the sessions with [peer] (any device of it) and nothing else.
  /// Throws when the archive could not be recorded.
  Future<void> archive(String peer);
}

class Gv2SealedPairwiseCrypto implements Gv2PairwiseCrypto {
  final SealedSenderService _sealed;
  final Future<SenderCertificate> Function() _certificate;
  final Gv2SignalSessions _sessions;

  Gv2SealedPairwiseCrypto({
    required SealedSenderService sealed,
    required Future<SenderCertificate> Function() certificate,
    required Gv2SignalSessions sessions,
  }) : _sealed = sealed,
       _certificate = certificate,
       _sessions = sessions;

  @override
  Future<Uint8List> seal(String recipient, Uint8List plaintext) async {
    await _sessions.ensureSession(recipient);
    final certificate = await _certificate();
    final identityKey = _sessions.remoteIdentityKey(recipient);
    if (identityKey == null) {
      throw StateError('gv2 pairwise: no identity key for the recipient');
    }
    final deviceId = await _sessions.deviceIdFor(recipient);
    // Everything that can fail is behind us: the ratchet moves now.
    final ciphertext = await _sessions.encrypt(recipient, deviceId, plaintext);
    return _sealed.seal(
      recipientIdentityPubKey: identityKey,
      drCiphertext: ciphertext,
      certificate: certificate,
      messageContext: sealedTypeGroup,
    );
  }

  @override
  Future<Gv2PairwiseOpened> open(Uint8List envelope) async {
    final myPublic = _sessions.identityPublicKey;
    final myPrivate = _sessions.identityPrivateKey;
    if (myPublic == null || myPrivate == null) {
      throw StateError('gv2 pairwise: no identity keys on this device');
    }
    final UnsealedMessage unsealed;
    try {
      unsealed = _sealed.unseal(
        myIdentityPrivateKey: myPrivate,
        myIdentityPublicKey: myPublic,
        sealedEnvelope: envelope,
      );
    } on StateError {
      throw const Gv2PairwiseOpenException(Gv2PairwiseOpenFailure.unsealed);
    }
    if (unsealed.messageContext != sealedTypeGroup) {
      throw const Gv2PairwiseOpenException(Gv2PairwiseOpenFailure.unsealed);
    }
    final sender = unsealed.senderSnowchatId;

    final int messageType;
    try {
      messageType = _sessions.messageTypeOf(
        unsealed.drCiphertext,
        unsealed.senderIdentityKey,
      );
    } on StateError {
      // A prekey message whose identity is not the certificate's.
      throw Gv2PairwiseOpenException(Gv2PairwiseOpenFailure.identity, sender);
    }
    try {
      final plaintext = await _sessions.decrypt(
        sender,
        unsealed.senderDeviceId,
        unsealed.drCiphertext,
        messageType,
      );
      return Gv2PairwiseOpened(
        senderSnowId: sender,
        senderDeviceId: unsealed.senderDeviceId,
        plaintext: plaintext,
      );
    } on IdentityBindingInvalidException {
      throw Gv2PairwiseOpenException(Gv2PairwiseOpenFailure.identity, sender);
    } on Exception {
      // No session, a ratchet that does not open it, a ciphertext that does
      // not parse: whatever the session layer refuses. (Errors — bugs — are
      // not caught here.)
      throw Gv2PairwiseOpenException(Gv2PairwiseOpenFailure.session, sender);
    }
  }

  @override
  Future<void> resetSession(String peer) => _sessions.archiveAndRestart(peer);

  @override
  Future<void> forgetSession(String peer) => _sessions.archive(peer);
}

/// [Gv2SignalSessions] over the app's session manager.
class Gv2SessionManagerSessions implements Gv2SignalSessions {
  final SignalSessionManager _manager;
  Gv2SessionManagerSessions(this._manager);

  @override
  Uint8List? get identityPublicKey => _manager.signal.identityPublicKey;

  @override
  Uint8List? get identityPrivateKey => _manager.signal.identityPrivateKey;

  @override
  Future<void> ensureSession(String peer) => _manager.ensureSession(peer);

  @override
  Uint8List? remoteIdentityKey(String peer) =>
      _manager.signal.getRemoteIdentityKey(peer);

  @override
  Future<String> deviceIdFor(String peer) =>
      _manager.getDeviceIdForRecipient(peer);

  @override
  Future<Uint8List> encrypt(
    String peer,
    String deviceId,
    Uint8List plaintext,
  ) async =>
      (await _manager.encrypt(peer, deviceId, plaintext))['ciphertext']
          as Uint8List;

  @override
  int messageTypeOf(Uint8List ciphertext, Uint8List certifiedIdentityKey) =>
      _manager.signal.resolveSealedMessageType(
        ciphertext,
        certifiedIdentityKey,
      );

  @override
  Future<Uint8List> decrypt(
    String peer,
    String deviceId,
    Uint8List ciphertext,
    int messageType,
  ) => _manager.decrypt(
    peer,
    deviceId,
    ciphertext,
    messageType,
    envelopeDeviceId: deviceId,
  );

  @override
  Future<void> archiveAndRestart(String peer) =>
      _manager.archiveAndResetSession(peer, notifyPeer: false);

  @override
  Future<void> archive(String peer) => _manager.archivePeerSessions(peer);
}
