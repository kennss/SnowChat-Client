/// @file        sealed_sender_tamper_test.dart
/// @description A sealed 1:1 envelope changed on its way is refused whole
///              (design §14, adversarial server: "invite interception"). The
///              group protocol v2 invite travels as such an envelope; the
///              server holds it between sender and recipient and may flip,
///              cut, extend or replay it. Every one of those must fail to
///              unseal — nothing of a changed envelope reaches the invite
///              handling.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (SealedSenderService takes trustedServerKeys). Earlier 2026-11-20
///
/// @functions
///  - main(): the cases above
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/x25519.dart';

import '../group_v2/gv2_session_support.dart';
import 'identity_test_support.dart';

void main() {
  final serverKey = ed.SigningKey(seed: Uint8List.fromList(List.filled(32, 7)));
  final serverVerifyKey = Uint8List.fromList(serverKey.verifyKey.asTypedList);
  late TestParty sender;
  late X25519KeyPair recipient;
  late Uint8List payload;
  late Uint8List envelope;

  setUp(() async {
    sender = await TestParty.create(
      seedByte: 2,
      deviceId: '22222222-2222-4222-8222-222222222222',
    );
    recipient = X25519KeyPair.generate();
    final random = Random.secure();
    payload = Uint8List.fromList(List.generate(180, (_) => random.nextInt(256)));
    envelope = SealedSenderService(trustedServerKeys: [serverVerifyKey]).seal(
      recipientIdentityPubKey: recipient.publicKey,
      drCiphertext: payload,
      certificate: gv2TestCertificate(serverKey, sender),
      messageContext: sealedType1to1,
    );
  });

  UnsealedMessage open(Uint8List bytes, {SealedSenderService? by}) =>
      (by ?? SealedSenderService(trustedServerKeys: [serverVerifyKey])).unseal(
        myIdentityPrivateKey: recipient.privateKey,
        myIdentityPublicKey: recipient.publicKey,
        sealedEnvelope: bytes,
      );

  test('the envelope as sent opens, with its sender and its payload', () {
    final opened = open(envelope);
    expect(opened.senderSnowchatId, sender.snowId);
    expect(opened.drCiphertext, payload);
  });

  test('one flipped bit anywhere in it — version, ephemeral key, nonce-derived '
      'box, certificate, payload — and it does not open', () {
    for (var i = 0; i < envelope.length; i++) {
      final changed = Uint8List.fromList(envelope)..[i] ^= 0x01;
      expect(() => open(changed), throwsStateError, reason: 'byte $i');
    }
  });

  test('cut short, extended, or with its box swapped onto another ephemeral '
      'key, it does not open', () {
    expect(() => open(envelope.sublist(0, envelope.length - 1)), throwsStateError);
    expect(
      () => open(Uint8List.fromList([...envelope, 0])),
      throwsStateError,
    );
    final other = SealedSenderService(trustedServerKeys: [serverVerifyKey]).seal(
      recipientIdentityPubKey: recipient.publicKey,
      drCiphertext: payload,
      certificate: gv2TestCertificate(serverKey, sender),
      messageContext: sealedType1to1,
    );
    final spliced = Uint8List.fromList(envelope)..setRange(1, 33, other.sublist(1, 33));
    expect(() => open(spliced), throwsStateError);
  });

  test('the same envelope delivered twice opens once', () {
    final service = SealedSenderService(trustedServerKeys: [serverVerifyKey]);
    open(envelope, by: service);
    expect(() => open(envelope, by: service), throwsStateError);
  });

  test('sealed for someone else, it does not open here', () {
    final elsewhere = SealedSenderService(trustedServerKeys: [serverVerifyKey]).seal(
      recipientIdentityPubKey: X25519KeyPair.generate().publicKey,
      drCiphertext: payload,
      certificate: gv2TestCertificate(serverKey, sender),
      messageContext: sealedType1to1,
    );
    expect(() => open(elsewhere), throwsStateError);
  });
}
