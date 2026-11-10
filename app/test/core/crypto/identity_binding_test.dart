/// @file        identity_binding_test.dart
/// @description B-2 Identity Binding v1 — shared golden vectors (same JSON the
///              server's identityBinding.ts tests use) plus encoder / verifier
///              edge cases: 0xFF domain prefix, lowercase UUID enforcement,
///              epoch parsing, small-order / non-canonical account keys, wire
///              and embedded codecs, and IdentityManager's purpose-bound
///              signing (auth-challenge regex, monotonic binding epochs).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10
///
/// @functions
///  - main(): golden vector + edge-case + IdentityManager signing tests
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';

import 'identity_test_support.dart';

Uint8List _hex(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool _verifyVector(Map<String, dynamic> v) {
  final epoch = IdentityBindingV1.parseEpoch(v['epoch'] as String);
  if (epoch == null) return false;
  return IdentityBindingV1.verify(
    snowId: v['snowId'] as String,
    accountPublicKey: _hex(v['accountPublicKeyHex'] as String),
    deviceId: v['deviceId'] as String,
    epoch: epoch,
    identityKey: _hex(v['identityKeyHex'] as String),
    ed25519: _hex(v['ed25519Hex'] as String),
    signature: _hex(v['signatureHex'] as String),
  );
}

void main() {
  final fixture = jsonDecode(
          File('test/fixtures/identity_binding_v1.json').readAsStringSync())
      as Map<String, dynamic>;
  final valid = Map<String, dynamic>.from(fixture['valid'] as Map);

  group('golden vectors', () {
    test('valid vector: message bytes match and signature verifies', () {
      final msg = IdentityBindingV1.buildMessage(
        snowId: valid['snowId'] as String,
        deviceId: valid['deviceId'] as String,
        epoch: IdentityBindingV1.parseEpoch(valid['epoch'] as String)!,
        identityKey: _hex(valid['identityKeyHex'] as String),
        ed25519: _hex(valid['ed25519Hex'] as String),
      );
      expect(msg.length, IdentityBindingV1.messageLength);
      expect(msg.first, 0xFF);
      expect(bytesToHexLower(msg), valid['messageHex']);
      expect(_verifyVector(valid), isTrue);
    });

    for (final raw in fixture['invalid'] as List) {
      final c = Map<String, dynamic>.from(raw as Map);
      test('invalid vector "${c['name']}" fails verification', () {
        final merged = Map<String, dynamic>.from(valid)
          ..addAll(Map<String, dynamic>.from(c['override'] as Map));
        expect(_verifyVector(merged), isFalse);
      });
    }
  });

  group('encoder / verifier edge cases', () {
    final acct = ed.SigningKey(seed: Uint8List.fromList(List.filled(32, 7)));
    final acctPub = Uint8List.fromList(acct.verifyKey.toList());
    final snowId = KeyDerivation.deriveSnowChatId(acctPub);
    const dev = '3f2a9c1e-5b7d-4e8a-9c21-7d4e5f6a8b90';
    final ik = Uint8List.fromList(List.filled(32, 1));
    final edk = Uint8List.fromList(List.filled(32, 2));
    Uint8List sign(Uint8List m) =>
        Uint8List.fromList(acct.sign(m).signature.toList());

    test('0xFF prefix: a utf8 string signature can never be a binding', () {
      final msg = IdentityBindingV1.buildMessage(
          snowId: snowId, deviceId: dev, epoch: 5, identityKey: ik, ed25519: edk);
      // Signing the same bytes minus the 0xFF byte (what a string-signing
      // oracle could at best produce) must not verify.
      final withoutPrefix = sign(Uint8List.fromList(msg.sublist(1)));
      expect(
        IdentityBindingV1.verify(
            snowId: snowId,
            accountPublicKey: acctPub,
            deviceId: dev,
            epoch: 5,
            identityKey: ik,
            ed25519: edk,
            signature: withoutPrefix),
        isFalse,
      );
      // utf8.encode never yields 0xFF, even for lone surrogates.
      expect(utf8.encode('\u{FFFF}ÿ').contains(0xFF), isFalse);
      expect(
        IdentityBindingV1.verify(
            snowId: snowId,
            accountPublicKey: acctPub,
            deviceId: dev,
            epoch: 5,
            identityKey: ik,
            ed25519: edk,
            signature: sign(msg)),
        isTrue,
      );
    });

    test('deviceId must be a lowercase canonical UUID', () {
      expect(IdentityBindingV1.isValidDeviceId(dev), isTrue);
      expect(IdentityBindingV1.isValidDeviceId(dev.toUpperCase()), isFalse);
      expect(IdentityBindingV1.isValidDeviceId('primary'), isFalse);
      expect(
          () => IdentityBindingV1.buildMessage(
              snowId: snowId,
              deviceId: dev.toUpperCase(),
              epoch: 1,
              identityKey: ik,
              ed25519: edk),
          throwsArgumentError);
    });

    test('epoch parser is strict', () {
      expect(IdentityBindingV1.parseEpoch('0'), 0);
      expect(IdentityBindingV1.parseEpoch('1794326400000'), 1794326400000);
      expect(IdentityBindingV1.parseEpoch('9223372036854775807'),
          9223372036854775807);
      expect(IdentityBindingV1.parseEpoch('9223372036854775808'), isNull);
      expect(IdentityBindingV1.parseEpoch('-1'), isNull);
      expect(IdentityBindingV1.parseEpoch('01'), isNull);
      expect(IdentityBindingV1.parseEpoch('1e3'), isNull);
      expect(IdentityBindingV1.parseEpoch(''), isNull);
    });

    test('small-order and non-canonical account keys are rejected', () {
      for (final h in [
        '0000000000000000000000000000000000000000000000000000000000000000',
        '0100000000000000000000000000000000000000000000000000000000000000',
        '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05',
        'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a',
        'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
        // sign-bit variants of the above must be rejected too
        '0000000000000000000000000000000000000000000000000000000000000080',
        '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85',
        // non-canonical y >= p
        'f0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
      ]) {
        expect(IdentityBindingV1.isAcceptableAccountKey(_hex(h)), isFalse,
            reason: h);
      }
      expect(IdentityBindingV1.isAcceptableAccountKey(acctPub), isTrue);
      expect(IdentityBindingV1.isAcceptableAccountKey(Uint8List(31)), isFalse);
    });

    test('account key must derive the snowId', () {
      final other = ed.SigningKey(seed: Uint8List.fromList(List.filled(32, 8)));
      final otherPub = Uint8List.fromList(other.verifyKey.toList());
      expect(IdentityBindingV1.accountKeyMatchesSnowId(acctPub, snowId), isTrue);
      expect(
          IdentityBindingV1.accountKeyMatchesSnowId(otherPub, snowId), isFalse);
    });

    test('account key hex decoding is lowercase-only', () {
      final h = bytesToHexLower(acctPub);
      expect(IdentityBindingV1.parseAccountKeyHex(h), acctPub);
      expect(IdentityBindingV1.parseAccountKeyHex(h.toUpperCase()), isNull);
      expect(IdentityBindingV1.parseAccountKeyHex(h.substring(2)), isNull);
    });

    test('wire + embedded codecs round-trip and reject malformed input', () {
      final b = IdentityBinding(signature: Uint8List(64), epoch: 42);
      final parsed = IdentityBinding.tryParseWire(b.toWireJson());
      expect(parsed!.epoch, 42);
      expect(IdentityBinding.tryParseWire({'sig': 'AA==', 'epoch': '1', 'version': 1}),
          isNull);
      expect(
          IdentityBinding.tryParseWire(
              {'sig': base64Encode(Uint8List(64)), 'epoch': 1, 'version': 2}),
          isNull);

      final e = EmbeddedIdentityBinding(
        accountPublicKey: acctPub,
        deviceId: dev,
        epoch: 9,
        ed25519: edk,
        signature: Uint8List(64),
      );
      final back = EmbeddedIdentityBinding.tryParse(
          jsonDecode(jsonEncode(e.toJson())));
      expect(back!.deviceId, dev);
      expect(back.epoch, 9);
      expect(EmbeddedIdentityBinding.tryParse({'version': 1}), isNull);
    });
  });

  group('IdentityManager purpose-bound signing', () {
    late InMemorySecureStorage storage;
    late IdentityManager im;
    late Uint8List acctPub;
    const dev = '11111111-2222-4333-8444-555555555555';

    setUp(() async {
      storage = InMemorySecureStorage();
      final seed = Uint8List.fromList(List.filled(32, 9));
      final sk = ed.SigningKey(seed: seed);
      acctPub = Uint8List.fromList(sk.verifyKey.toList());
      storage.data['identity_private_key'] = bytesToHexLower(seed);
      storage.data['identity_public_key'] = bytesToHexLower(acctPub);
      storage.data['snow_chat_id'] = KeyDerivation.deriveSnowChatId(acctPub);
      im = IdentityManager(storage);
    });

    test('signAuthChallenge accepts the server nonce shape only', () async {
      final ok = await im
          .signAuthChallenge('6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b-lq2x9k1z');
      expect(ok.length, 128);
      for (final bad in [
        'hello',
        '6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b',
        '6F1C2B3A-4D5E-4F60-8A7B-9C0D1E2F3A4B-abc',
        '6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b-abcdefghijklm',
        '6f1c2b3a-4d5e-4f60-8a7b-9c0d1e2f3a4b-ab\n',
      ]) {
        expect(() => im.signAuthChallenge(bad), throwsFormatException,
            reason: bad);
      }
    });

    test('currentIdentityBinding verifies, is reused, and re-signs on key change',
        () async {
      final ik = Uint8List.fromList(List.filled(32, 3));
      final edk = Uint8List.fromList(List.filled(32, 4));
      final b1 = await im.currentIdentityBinding(
          deviceId: dev, identityKey: ik, ed25519: edk);
      expect(
        IdentityBindingV1.verify(
            snowId: b1.snowId,
            accountPublicKey: acctPub,
            deviceId: dev,
            epoch: b1.epoch,
            identityKey: ik,
            ed25519: edk,
            signature: b1.signature),
        isTrue,
      );
      final again = await im.currentIdentityBinding(
          deviceId: dev, identityKey: ik, ed25519: edk);
      expect(again.epoch, b1.epoch);

      final newEd = Uint8List.fromList(List.filled(32, 5));
      final b2 = await im.currentIdentityBinding(
          deviceId: dev, identityKey: ik, ed25519: newEd);
      expect(b2.epoch, greaterThan(b1.epoch));

      final b3 = await im.currentIdentityBinding(
          deviceId: dev,
          identityKey: ik,
          ed25519: newEd,
          minEpochExclusive: b2.epoch + 1000);
      expect(b3.epoch, b2.epoch + 1001);
    });

    test('concurrent minting yields one epoch', () async {
      final ik = Uint8List.fromList(List.filled(32, 6));
      final edk = Uint8List.fromList(List.filled(32, 7));
      final results = await Future.wait([
        im.currentIdentityBinding(deviceId: dev, identityKey: ik, ed25519: edk),
        im.currentIdentityBinding(deviceId: dev, identityKey: ik, ed25519: edk),
      ]);
      expect(results[0].epoch, results[1].epoch);
    });
  });
}
