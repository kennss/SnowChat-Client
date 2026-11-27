/// @file        encrypted_message_handler_blocked_test.dart
/// @description The sealed decrypt. X1: what an account this user blocked sent (its sender
///              known only once unsealed) is decrypted (the 1:1 session stays in step) and then
///              refused with BlockedSenderException, unwrapped (not a SealedDecryptException
///              that the queue would retry). The inner types (contract §12.4): a type this build
///              does not know is marked `_isUnknownType` (consumed, never shown — no empty
///              bubble); contact_added / contact_removed are contact notices with their name
///              certificate; a message carries its sender's name certificate as peerNameCert; the
///              transfer notices of the removed wallet (transfer_*) are unknown types like any other.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-27 (an older build's wallet transfer notices are unknown types). Earlier
///              2026-11-22 (a contact notice also says whether it is an answer). Earlier 2026-11-22
///              (no non-sealed 1:1 — Part 3 E; the inner-type rules of §12.4). Earlier
///              2026-11-22 (SealedSenderService takes trustedServerKeys). Earlier 2026-11-21
///
/// @functions
///  - main(): the test cases.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/blocking/block_list.dart';
import 'package:snowchat/core/crypto/encrypted_message_handler.dart';
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/network/socket_manager.dart';

import '../group_v2/gv2_session_support.dart' show gv2TestCertificate;
import 'identity_test_support.dart';

/// The Signal layer of "me": the real identity keys; every decrypt gives
/// [payload] (a text message unless a test sets another), and is counted.
class _Sessions extends Fake implements SignalSessionManager {
  final TestParty me;
  int decrypts = 0;
  Map<String, dynamic> payload = {'text': 'hello', 'type': 'text'};
  _Sessions(this.me);

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
  }) async {
    decrypts++;
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }
}

class _Socket extends Fake implements SocketManager {}

void main() {
  late TestParty me;
  late TestParty bob;
  late ed.SigningKey serverKey;
  late SealedSenderService sealed;
  late _Sessions sessions;
  final blocked = <String>{};
  late EncryptedMessageHandler handler;

  setUp(() async {
    me = await TestParty.create(
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
    sessions = _Sessions(me);
    blocked.clear();
    handler = EncryptedMessageHandler(
      sessionManager: sessions,
      socketManager: _Socket(),
      sealedSenderService: sealed,
      isBlocked: (id) async => blocked.contains(id),
    );
  });

  Map<String, dynamic> sealedFromBob(String id) => {
    'id': id,
    'sealedContent': base64Encode(
      sealed.seal(
        recipientIdentityPubKey: me.signal.identityPublicKey!,
        drCiphertext: Uint8List.fromList([1, 2, 3, 4]),
        certificate: gv2TestCertificate(serverKey, bob),
        messageContext: sealedType1to1,
      ),
    ),
  };

  test('a sealed envelope from an account that is not blocked is read',
      () async {
    final message = await handler.decryptSealedMessage(sealedFromBob('m1'));
    expect(message.senderSnowchatId, bob.snowId);
    expect(message.plaintext, 'hello');
  });

  test('a sealed envelope from a blocked account: decrypted, then refused '
      'unwrapped', () async {
    blocked.add(bob.snowId);
    await expectLater(
      handler.decryptSealedMessage(sealedFromBob('m2')),
      throwsA(isA<BlockedSenderException>()),
    );
    expect(sessions.decrypts, 1, reason: 'the session stays in step');
  });

  test('an inner type this build does not know: consumed, never a bubble',
      () async {
    sessions.payload = {'type': 'poll_v9', 'text': 'x', 'question': '?'};
    final message = await handler.decryptSealedMessage(sealedFromBob('u1'));
    expect(message.metadata, {'_isUnknownType': true});
    expect(message.plaintext, isEmpty);
    expect(message.peerClientId, isNull);
  });

  test("the removed wallet's transfer notices (an older build sends them) are "
      'unknown types: consumed, never a bubble', () async {
    var n = 0;
    for (final type in const [
      'transfer_request',
      'transfer_response',
      'transfer_completed',
      'transfer_failed',
    ]) {
      sessions.payload = {
        'type': type,
        'requestId': '1f4e2c0a-1234-4abc-89ab-0123456789ab',
        'amount': '1000',
        'text': 'x',
      };
      final message =
          await handler.decryptSealedMessage(sealedFromBob('t${n++}'));
      expect(message.metadata, {'_isUnknownType': true}, reason: type);
      expect(message.plaintext, isEmpty, reason: type);
    }
  });

  test('a payload without a type is a text message (the rule is for a type '
      'present and unknown)', () async {
    sessions.payload = {'text': 'plain'};
    final message = await handler.decryptSealedMessage(sealedFromBob('u2'));
    expect(message.metadata, isNull);
    expect(message.plaintext, 'plain');
  });

  test('contact_added and contact_removed are contact notices', () async {
    sessions.payload = {'type': 'contact_added', 'v': 1, 'nameCert': 'Q0VSVA=='};
    final added = await handler.decryptSealedMessage(sealedFromBob('c1'));
    expect(added.metadata, {'_isContactNotice': true, 'notice': 'contact_added', 'answer': false});
    expect(added.peerNameCert, 'Q0VSVA==');

    sessions.payload = {'type': 'contact_removed', 'v': 1};
    final removed = await handler.decryptSealedMessage(sealedFromBob('c2'));
    expect(removed.metadata,
        {'_isContactNotice': true, 'notice': 'contact_removed', 'answer': false});
    expect(removed.peerNameCert, isNull);
  });

  test("a message carries its sender's name certificate", () async {
    sessions.payload = {
      'type': 'text',
      'text': 'hi',
      'cid': 'msg_1',
      'nameCert': 'Q0VSVA==',
    };
    final message = await handler.decryptSealedMessage(sealedFromBob('n1'));
    expect(message.plaintext, 'hi');
    expect(message.peerNameCert, 'Q0VSVA==');
    expect(message.peerClientId, 'msg_1');
  });

  test('a contact notice from a blocked account is refused like anything else',
      () async {
    blocked.add(bob.snowId);
    sessions.payload = {'type': 'contact_added', 'v': 1};
    await expectLater(
      handler.decryptSealedMessage(sealedFromBob('c3')),
      throwsA(isA<BlockedSenderException>()),
    );
  });
}
