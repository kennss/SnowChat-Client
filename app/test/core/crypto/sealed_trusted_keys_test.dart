/// @file        sealed_trusted_keys_test.dart
/// @description SC-06 / A-3: the Sealed Sender server keys are pinned in the build. A certificate
///              signed by a key outside the list does not open; during a rotation a certificate
///              signed by either listed key opens; the development key is the one the development
///              server derives from its public label; dev and prod have keys, nothing else does.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases above
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/sealed_sender.dart';
import 'package:snowchat/core/crypto/sealed_trusted_keys.dart';
import 'package:snowchat/core/crypto/x25519.dart';

import '../group_v2/gv2_session_support.dart';
import 'identity_test_support.dart';

void main() {
  ed.SigningKey key(int b) => ed.SigningKey(seed: Uint8List.fromList(List.filled(32, b)));
  Uint8List pub(ed.SigningKey k) => Uint8List.fromList(k.verifyKey.asTypedList);

  final current = key(7);
  final next = key(8);
  final rogue = key(9);
  late TestParty sender;
  late X25519KeyPair recipient;
  late Uint8List payload;

  setUp(() async {
    sender = await TestParty.create(
      seedByte: 2,
      deviceId: '22222222-2222-4222-8222-222222222222',
    );
    recipient = X25519KeyPair.generate();
    final random = Random.secure();
    payload = Uint8List.fromList(List.generate(64, (_) => random.nextInt(256)));
  });

  Uint8List sealBy(ed.SigningKey server) =>
      SealedSenderService(trustedServerKeys: [pub(server)]).seal(
        recipientIdentityPubKey: recipient.publicKey,
        drCiphertext: payload,
        certificate: gv2TestCertificate(server, sender),
        messageContext: sealedType1to1,
      );

  UnsealedMessage openWith(List<ed.SigningKey> trusted, Uint8List envelope) =>
      SealedSenderService(trustedServerKeys: trusted.map(pub).toList()).unseal(
        myIdentityPrivateKey: recipient.privateKey,
        myIdentityPublicKey: recipient.publicKey,
        sealedEnvelope: envelope,
      );

  test('a certificate signed by a key outside the list does not open', () {
    expect(() => openWith([current], sealBy(rogue)), throwsStateError);
    expect(() => openWith([current, next], sealBy(rogue)), throwsStateError);
  });

  test('during a rotation, a certificate signed by either listed key opens', () {
    expect(openWith([current, next], sealBy(current)).senderSnowchatId, sender.snowId);
    expect(openWith([current, next], sealBy(next)).senderSnowchatId, sender.snowId);
  });

  test('a service with no trusted key cannot be built', () {
    expect(() => SealedSenderService(trustedServerKeys: const []), throwsArgumentError);
  });

  test('dev and prod each pin one key; no other environment has any', () {
    expect(sealedTrustedServerKeysFor('dev'), hasLength(1));
    expect(sealedTrustedServerKeysFor('prod'), hasLength(1));
    expect(sealedTrustedServerKeysFor('dev')!.single, hasLength(32));
    expect(sealedTrustedServerKeysFor('prod')!.single, hasLength(32));
    expect(sealedTrustedServerKeysFor('staging'), isNull);
    expect(sealedTrustedServerKeysFor(''), isNull);
  });

  test('the development key is the one the development server derives from its label', () {
    final seed = hash.sha256
        .convert(utf8.encode('SnowChat development sealed sender key — not a secret'))
        .bytes;
    final derived = pub(ed.SigningKey(seed: Uint8List.fromList(seed)));
    expect(sealedTrustedServerKeysFor('dev')!.single, derived);
    expect(sealedTrustedServerKeysFor('prod')!.single, isNot(derived));
  });
}
