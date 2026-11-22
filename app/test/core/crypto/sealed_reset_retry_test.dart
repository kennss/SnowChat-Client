/// @file        sealed_reset_retry_test.dart
/// @description SC-05: the session_reset notice and the answer to a retry request travel sealed.
///              sendSealedSessionReset seals an inner `session_reset` control (sealed_control);
///              the peer reads it as metadata `_isSessionReset` (consumed, never a bubble).
///              sendSealedRetry seals the logged payload again with isRetry / originalMessageId
///              inside it (the peer fills the placeholder). With Sealed Sender not active nothing
///              is sent at all — there is no non-sealed fallback.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases above
///  - _SenderSessions / _SenderSignal: the sender's Signal layer — encrypt passes the payload
///    through and records it
///  - _Socket: records what the handler hands to sealed_message
///  - _ReceiverSessions: the recipient's Signal layer — decrypt gives back what was encrypted
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/encrypted_message_handler.dart';
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/sender_certificate.dart';
import 'package:snowchat/core/crypto/sender_certificate_manager.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/network/socket_manager.dart';

import '../group_v2/gv2_session_support.dart' show gv2TestCertificate;
import 'identity_test_support.dart';

class _SenderSignal extends Fake implements SignalProtocolService {
  final Uint8List? peerIdentity;
  _SenderSignal(this.peerIdentity);

  @override
  Uint8List? getRemoteIdentityKey(String recipientId) => peerIdentity;
}

class _SenderSessions extends Fake implements SignalSessionManager {
  final _SenderSignal _signal;
  final encrypted = <Uint8List>[];
  _SenderSessions(this._signal);

  @override
  SignalProtocolService get signal => _signal;

  @override
  Future<void> ensureSession(String recipientSnowchatId) async {}

  @override
  Future<String> getDeviceIdForRecipient(String recipientSnowchatId) async =>
      'device';

  @override
  Future<Map<String, dynamic>> encrypt(
    String recipientId,
    String deviceId,
    Uint8List plaintext,
  ) async {
    encrypted.add(plaintext);
    return {'ciphertext': plaintext, 'messageType': 2};
  }
}

class _Sealed {
  _Sealed(this.recipientId, this.sealedContent, this.clientMessageId, this.control);
  final String recipientId;
  final String sealedContent;
  final String clientMessageId;
  final bool control;
}

class _Socket extends Fake implements SocketManager {
  final sent = <_Sealed>[];
  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  void sendSealedMessage({
    required String recipientId,
    required String sealedContent,
    required String clientMessageId,
    int? expiresIn,
    bool control = false,
    Function(dynamic)? onAck,
  }) {
    sent.add(_Sealed(recipientId, sealedContent, clientMessageId, control));
  }
}

class _Certificates extends Fake implements SenderCertificateManager {
  final SenderCertificate certificate;
  _Certificates(this.certificate);

  @override
  Future<SenderCertificate> getCertificate() async => certificate;
}

/// The recipient's Signal layer: real identity keys; decrypt gives back the
/// "ciphertext" (the sender's encrypt passed the payload through).
class _ReceiverSessions extends Fake implements SignalSessionManager {
  final TestParty me;
  _ReceiverSessions(this.me);

  @override
  SignalProtocolService get signal => me.signal;

  @override
  String peekDeviceIdForIncoming(String senderId, String? envelopeDeviceId) =>
      envelopeDeviceId ?? 'device';

  @override
  Future<Uint8List> decrypt(
    String senderId,
    String deviceId,
    Uint8List ciphertext,
    int messageType, {
    String? envelopeDeviceId,
  }) async => ciphertext;
}

void main() {
  late TestParty alice; // sender
  late TestParty bob; // recipient
  late ed.SigningKey serverKey;
  late SealedSenderService sealed;
  late _SenderSessions aliceSessions;
  late _Socket socket;
  late EncryptedMessageHandler aliceHandler;
  late EncryptedMessageHandler bobHandler;

  setUp(() async {
    alice = await TestParty.create(
      seedByte: 1,
      deviceId: '11111111-1111-4111-8111-111111111111',
    );
    bob = await TestParty.create(
      seedByte: 2,
      deviceId: '22222222-2222-4222-8222-222222222222',
    );
    serverKey = ed.SigningKey.generate();
    sealed = SealedSenderService(
      trustedServerKeys: [Uint8List.fromList(serverKey.verifyKey.asTypedList)],
    );
    aliceSessions = _SenderSessions(_SenderSignal(bob.signal.identityPublicKey));
    socket = _Socket();
    aliceHandler = EncryptedMessageHandler(
      sessionManager: aliceSessions,
      socketManager: socket,
      sealedSenderService: sealed,
      senderCertificateManager: _Certificates(gv2TestCertificate(serverKey, alice)),
      isBlocked: (_) async => false,
    );
    bobHandler = EncryptedMessageHandler(
      sessionManager: _ReceiverSessions(bob),
      socketManager: _Socket(),
      sealedSenderService: SealedSenderService(
        trustedServerKeys: [Uint8List.fromList(serverKey.verifyKey.asTypedList)],
      ),
      isBlocked: (_) async => false,
    );
  });

  test('the session reset notice is a sealed control, read as _isSessionReset',
      () async {
    expect(await aliceHandler.sendSealedSessionReset(bob.snowId), isTrue);
    final out = socket.sent.single;
    expect(out.recipientId, bob.snowId);
    expect(out.control, isTrue);
    final inner = jsonDecode(utf8.decode(aliceSessions.encrypted.single));
    expect(inner['type'], 'session_reset');

    final read = await bobHandler.decryptSealedMessage({
      'id': 'row1',
      'sealedContent': out.sealedContent,
    });
    expect(read.senderSnowchatId, alice.snowId);
    expect(read.metadata?['_isSessionReset'], isTrue);
    expect(read.plaintext, isEmpty);
  });

  test('the retry answer is sealed, with isRetry and originalMessageId inside',
      () async {
    final logged = Uint8List.fromList(utf8.encode(jsonEncode({
      'text': 'hello again',
      'type': 'text',
      'cid': 'local-1',
      'metadata': {'keep': 1},
    })));
    expect(
      await aliceHandler.sendSealedRetry(
        recipientId: bob.snowId,
        loggedPayload: logged,
        originalMessageId: 'srv-9',
      ),
      isTrue,
    );
    final out = socket.sent.single;
    expect(out.control, isFalse, reason: 'a chat message: pushed like one');
    expect(out.clientMessageId, 'retry_srv-9');

    final read = await bobHandler.decryptSealedMessage({
      'id': 'row2',
      'sealedContent': out.sealedContent,
    });
    expect(read.senderSnowchatId, alice.snowId);
    expect(read.plaintext, 'hello again');
    expect(read.metadata?['isRetry'], isTrue);
    expect(read.metadata?['originalMessageId'], 'srv-9');
    expect(read.metadata?['keep'], 1, reason: 'the original metadata stays');
  });

  test('Sealed Sender not active: neither is sent, and nothing else either',
      () async {
    final inactive = EncryptedMessageHandler(
      sessionManager: aliceSessions,
      socketManager: socket,
      isBlocked: (_) async => false,
    );
    expect(await inactive.sendSealedSessionReset(bob.snowId), isFalse);
    expect(
      await inactive.sendSealedRetry(
        recipientId: bob.snowId,
        loggedPayload: Uint8List.fromList(utf8.encode('{}')),
        originalMessageId: 'srv-1',
      ),
      isFalse,
    );
    expect(socket.sent, isEmpty);
    expect(aliceSessions.encrypted, isEmpty, reason: 'no ratchet step spent');
  });

  test('socket down or no cached peer identity: not sent, no ratchet step',
      () async {
    socket.connected = false;
    expect(await aliceHandler.sendSealedSessionReset(bob.snowId), isFalse);
    expect(
      await aliceHandler.sendSealedRetry(
        recipientId: bob.snowId,
        loggedPayload: Uint8List.fromList(utf8.encode('{}')),
        originalMessageId: 'srv-1',
      ),
      isFalse,
    );
    socket.connected = true;
    final noIdentity = EncryptedMessageHandler(
      sessionManager: _SenderSessions(_SenderSignal(null))
        ..encrypted.clear(),
      socketManager: socket,
      sealedSenderService: sealed,
      senderCertificateManager: _Certificates(gv2TestCertificate(serverKey, alice)),
      isBlocked: (_) async => false,
    );
    expect(await noIdentity.sendSealedSessionReset(bob.snowId), isFalse);
    expect(socket.sent, isEmpty);
    expect(aliceSessions.encrypted, isEmpty);
  });
}
