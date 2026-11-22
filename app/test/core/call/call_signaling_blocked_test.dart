/// @file        call_signaling_blocked_test.dart
/// @description X1 in the call signaling: a call signal from an account this user blocked is
///              decrypted (the 1:1 session stays in step) and goes no further — no event (nothing
///              rings), nothing for an accept / decline to answer (parseEnvelope gives null) —
///              while one from an account that is not blocked is dispatched as before.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (SealedSenderService takes trustedServerKeys). Earlier 2026-11-21
///
/// @functions
///  - main(): the test cases.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/call/call_signaling.dart';
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/sender_certificate_manager.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/network/socket_manager.dart';

import '../crypto/identity_test_support.dart';
import '../group_v2/gv2_session_support.dart' show gv2TestCertificate;

/// The Signal layer of "me": real identity keys; every decrypt gives a
/// call_invite, and is counted.
class _Sessions extends Fake implements SignalSessionManager {
  final TestParty me;
  int decrypts = 0;
  _Sessions(this.me);

  @override
  SignalProtocolService get signal => me.signal;

  @override
  Future<Uint8List> decrypt(
    String senderId,
    String deviceId,
    Uint8List ciphertext,
    int messageType, {
    String? envelopeDeviceId,
  }) async {
    decrypts++;
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'type': 'call_invite',
      'data': {'callId': '33333333-3333-4333-8333-333333333333'},
      'timestamp': '2026-11-21T00:00:00Z',
    })));
  }
}

class _Socket extends Fake implements SocketManager {
  final StreamController<Map<String, dynamic>> incoming =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get onSealedCallSignaling => incoming.stream;
}

class _Certificates extends Fake implements SenderCertificateManager {}

void main() {
  late TestParty me;
  late TestParty bob;
  late ed.SigningKey serverKey;
  late SealedSenderService sealed;
  late _Sessions sessions;
  late CallSignaling signaling;
  final blocked = <String>{};
  final events = <CallSignalingEvent>[];

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
    events.clear();
    signaling = CallSignaling(
      sessionManager: sessions,
      sealedSenderService: sealed,
      senderCertificateManager: _Certificates(),
      socketManager: _Socket(),
      mySnowchatIdResolver: () => me.snowId,
      isBlocked: (id) async => blocked.contains(id),
    );
    signaling.onSignalingEvent.listen(events.add);
  });
  tearDown(() => signaling.dispose());

  String fromBob() => base64Encode(
    sealed.seal(
      recipientIdentityPubKey: me.signal.identityPublicKey!,
      drCiphertext: Uint8List.fromList([1, 2, 3, 4]),
      certificate: gv2TestCertificate(serverKey, bob),
      messageContext: sealedType1to1,
    ),
  );

  test('a call from an account that is not blocked is dispatched', () async {
    await signaling.injectEnvelope(fromBob());
    await pumpEventQueue();
    expect(events.single.type, 'call_invite');
    expect(events.single.senderSnowchatId, bob.snowId);
    expect((await signaling.parseEnvelope(fromBob()))?.type, 'call_invite');
  });

  test('a call from a blocked account: decrypted, nothing dispatched, '
      'nothing to answer', () async {
    blocked.add(bob.snowId);
    await signaling.injectEnvelope(fromBob());
    await pumpEventQueue();
    expect(events, isEmpty, reason: 'nothing rings');
    expect(sessions.decrypts, 1, reason: 'the session stays in step');
    expect(await signaling.parseEnvelope(fromBob()), isNull,
        reason: 'a decline sends nothing to it');
  });
}
