/// @file        sealed_sends_test.dart
/// @description The sealed sends of EncryptedMessageHandler. SC-05: the session_reset notice
///              is a sealed control (sealed_control); the peer reads it as metadata
///              `_isSessionReset`. Contract §12.2 / SC-25: every sealed send — a message, a
///              control, a group invite, a raw payload — carries a random UUID as its wire
///              clientMessageId, never a kind prefix, a time or the local message id (that
///              travels only inside, as `cid`). sendSealedPayload refreshes the peer's identity
///              first and sends a contact notice as a normal row or a control. A message's name
///              certificate sits at the top level of the inner JSON. With Sealed Sender not
///              active nothing is sent at all. Review fixes: a message goes under the wire id its
///              caller chose (the 1:1 outbox maps status events by it); every inner plaintext is
///              padded with spaces to a multiple of 512 bytes; an answer notice surfaces as such;
///              a peer's metadata loses keys of this device's own (`_…`); a peer's inner type
///              `system` is not shown; a prekey message from a peer is reported
///              (onNewInboundSession).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (review fixes: the caller's wire id, padding, the answer, peer metadata,
///              `system`, onNewInboundSession). Earlier 2026-11-22 (from sealed_reset_retry_test.dart: no retry answer — the server relays no
///              retry requests; the wire id and sendSealedPayload cases)
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
  final refreshed = <String>[];
  _SenderSessions(this._signal);

  @override
  Future<void> refreshPeerIdentity(String snowId) async => refreshed.add(snowId);

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
  bool get isReadyToSend => connected;

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
    onAck?.call({'messageId': 'srv-${sent.length}'});
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

  final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  test('every sealed send carries a random UUID wire id — no kind prefix, no '
      'time, never the local message id', () async {
    await aliceHandler.sendSealedSessionReset(bob.snowId);
    await aliceHandler.sendSealedReadReceipt(
        recipientId: bob.snowId, readIds: ['r1']);
    await aliceHandler.sendSealedUnsend(
        recipientId: bob.snowId, deleteIds: ['d1']);
    await aliceHandler.sendSealedDeleteChat(recipientId: bob.snowId);
    await aliceHandler.sendSealedMessage(
      conversationId: bob.snowId,
      recipientId: bob.snowId,
      text: 'hi',
      clientMessageId: 'msg_1700000000000_voice',
      wireMessageId: newWireMessageId(),
    );
    await aliceHandler.sendSealedPayload(
      recipientId: bob.snowId,
      payload: {'type': 'contact_removed', 'v': 1},
      control: true,
    );
    expect(
      await aliceHandler.sendSealedGroupInvite(
          recipientId: bob.snowId, invite: Uint8List.fromList([1, 2, 3])),
      isTrue,
    );
    expect(socket.sent, hasLength(7));
    final ids = {for (final out in socket.sent) out.clientMessageId};
    expect(ids, hasLength(7), reason: 'a new id for every send');
    for (final id in ids) {
      expect(uuidV4.hasMatch(id), isTrue, reason: id);
      for (final prefix in [
        'receipt',
        'unsend',
        'delchat',
        'reset',
        'retry',
        'gv2inv',
        'msg_',
      ]) {
        expect(id.startsWith(prefix), isFalse, reason: id);
      }
    }
    // The local id travels inside the E2EE payload only.
    final message = jsonDecode(utf8.decode(aliceSessions.encrypted[4]));
    expect(message['cid'], 'msg_1700000000000_voice');
  });

  test('sendSealedPayload: the peer identity is refreshed first; a control '
      'or a pushed row; the inner JSON is the payload itself', () async {
    await aliceHandler.sendSealedPayload(
      recipientId: bob.snowId,
      payload: {'type': 'contact_added', 'v': 1, 'nameCert': 'Q0VSVA=='},
      control: false,
    );
    expect(aliceSessions.refreshed, [bob.snowId]);
    final out = socket.sent.single;
    expect(out.control, isFalse, reason: 'contact_added is pushed like a message');
    final read = await bobHandler.decryptSealedMessage({
      'id': 'row3',
      'sealedContent': out.sealedContent,
    });
    expect(read.metadata, {'_isContactNotice': true, 'notice': 'contact_added', 'answer': false});
    expect(read.peerNameCert, 'Q0VSVA==');
  });

  test('sendSealedPayload with the socket down: nothing encrypted, an error',
      () async {
    socket.connected = false;
    await expectLater(
      aliceHandler.sendSealedPayload(
        recipientId: bob.snowId,
        payload: {'type': 'contact_removed', 'v': 1},
        control: true,
      ),
      throwsStateError,
    );
    expect(aliceSessions.encrypted, isEmpty);
    expect(socket.sent, isEmpty);
  });

  test("a message's name certificate is at the top level of the inner JSON",
      () async {
    await aliceHandler.sendSealedMessage(
      conversationId: bob.snowId,
      recipientId: bob.snowId,
      text: 'hello',
      clientMessageId: 'msg_2',
      wireMessageId: newWireMessageId(),
      nameCert: 'Q0VSVA==',
    );
    final inner = jsonDecode(utf8.decode(aliceSessions.encrypted.single));
    expect(inner['nameCert'], 'Q0VSVA==');
    final read = await bobHandler.decryptSealedMessage({
      'id': 'row4',
      'sealedContent': socket.sent.single.sealedContent,
    });
    expect(read.plaintext, 'hello');
    expect(read.peerNameCert, 'Q0VSVA==');
  });

  test('Sealed Sender not active: nothing is sent, and nothing else either',
      () async {
    final inactive = EncryptedMessageHandler(
      sessionManager: aliceSessions,
      socketManager: socket,
      isBlocked: (_) async => false,
    );
    expect(await inactive.sendSealedSessionReset(bob.snowId), isFalse);
    await expectLater(
      inactive.sendSealedPayload(
        recipientId: bob.snowId,
        payload: {'type': 'contact_removed', 'v': 1},
        control: true,
      ),
      throwsStateError,
    );
    expect(socket.sent, isEmpty);
    expect(aliceSessions.encrypted, isEmpty, reason: 'no ratchet step spent');
  });

  test('socket down or no cached peer identity: not sent, no ratchet step',
      () async {
    socket.connected = false;
    expect(await aliceHandler.sendSealedSessionReset(bob.snowId), isFalse);
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

  test('a message goes under the wire id its caller chose', () async {
    final wire = newWireMessageId();
    await aliceHandler.sendSealedMessage(
      conversationId: bob.snowId,
      recipientId: bob.snowId,
      text: 'hi',
      clientMessageId: 'msg_3',
      wireMessageId: wire,
    );
    expect(socket.sent.single.clientMessageId, wire);
  });

  test('every inner plaintext is padded with spaces to a multiple of 512 '
      'bytes and still reads the same', () async {
    await aliceHandler.sendSealedSessionReset(bob.snowId);
    await aliceHandler.sendSealedPayload(
      recipientId: bob.snowId,
      payload: {'type': 'contact_added', 'v': 1, 'nameCert': 'Q0VSVA=='},
      control: false,
    );
    await aliceHandler.sendSealedMessage(
      conversationId: bob.snowId,
      recipientId: bob.snowId,
      text: 'x' * 600,
      clientMessageId: 'msg_4',
      wireMessageId: newWireMessageId(),
    );
    final sizes = [for (final p in aliceSessions.encrypted) p.length];
    expect(sizes, [512, 512, 1024]);
    for (final p in aliceSessions.encrypted) {
      final json = utf8.encode(utf8.decode(p).trimRight());
      expect(p.sublist(json.length).every((b) => b == 0x20), isTrue);
    }
    final read = await bobHandler.decryptSealedMessage({
      'id': 'row9',
      'sealedContent': socket.sent.last.sealedContent,
    });
    expect(read.plaintext, 'x' * 600);
  });

  test('an answer notice surfaces as one', () async {
    await aliceHandler.sendSealedPayload(
      recipientId: bob.snowId,
      payload: {'type': 'contact_added', 'v': 1, 'answer': true},
      control: false,
    );
    final read = await bobHandler.decryptSealedMessage({
      'id': 'row10',
      'sealedContent': socket.sent.single.sealedContent,
    });
    expect(read.metadata?['_isContactNotice'], isTrue);
    expect(read.metadata?['answer'], isTrue);
  });

  test("a peer's metadata never carries this device's own flags, and a peer's "
      'type system is not shown', () async {
    await aliceHandler.sendSealedMessage(
      conversationId: bob.snowId,
      recipientId: bob.snowId,
      text: 'hi',
      clientMessageId: 'msg_5',
      wireMessageId: newWireMessageId(),
      metadata: {'_isReadReceipt': true, 'readIds': ['m1'], 'fileName': 'a.txt'},
    );
    final read = await bobHandler.decryptSealedMessage({
      'id': 'row11',
      'sealedContent': socket.sent.single.sealedContent,
    });
    expect(read.metadata, {'readIds': ['m1'], 'fileName': 'a.txt'});

    await aliceHandler.sendSealedPayload(
      recipientId: bob.snowId,
      payload: {'type': 'system', 'text': 'Your account was suspended'},
      control: false,
    );
    final system = await bobHandler.decryptSealedMessage({
      'id': 'row12',
      'sealedContent': socket.sent.last.sealedContent,
    });
    expect(system.metadata?['_isUnknownType'], isTrue);
    expect(system.plaintext, isEmpty);
  });
}
