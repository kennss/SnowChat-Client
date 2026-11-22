/// @file        encrypted_message_handler_blocked_test.dart
/// @description X1 at the decrypt: what an account this user blocked sent — a sealed envelope
///              (its sender known only once unsealed) or a non-sealed 1:1 — is decrypted (the
///              1:1 session stays in step) and then refused with BlockedSenderException, before
///              anything of it is acted on; the sealed path throws it unwrapped (not a
///              SealedDecryptException that the queue would retry). An account that is not
///              blocked is read as before.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (SealedSenderService takes trustedServerKeys). Earlier 2026-11-21
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

/// The Signal layer of "me": the real identity keys; every decrypt gives a
/// text payload, and is counted.
class _Sessions extends Fake implements SignalSessionManager {
  final TestParty me;
  int decrypts = 0;
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
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'text': 'hello', 'type': 'text'})),
    );
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

  test('a non-sealed 1:1 from a blocked account: decrypted, then refused',
      () async {
    blocked.add(bob.snowId);
    await expectLater(
      handler.decryptIncomingMessage({
        'id': 'm3',
        'senderSnowchatId': bob.snowId,
        'senderDeviceId': bob.deviceId,
        'encryptedContent': base64Encode([5, 6, 7]),
        'messageType': 1,
      }),
      throwsA(isA<BlockedSenderException>()),
    );
    expect(sessions.decrypts, 1);
  });
}
