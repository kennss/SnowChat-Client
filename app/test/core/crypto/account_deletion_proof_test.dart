/// @file        account_deletion_proof_test.dart
/// @description Account deletion proof v1 against the vectors shared with the
///              server (test/fixtures/account_deleted_v1.json, a
///              byte-identical copy of
///              server/src/utils/__fixtures__/account_deleted_v1.json): the
///              message bytes, the signature IdentityManager produces for the
///              vector's account, every rejected vector, and the strict wire
///              parser.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - main(): the test groups below.
///  - _managerFor(): an IdentityManager holding the account of a fixed label.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/account_deletion_proof.dart';
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';

import 'identity_test_support.dart';

const _appFixture = 'test/fixtures/account_deleted_v1.json';
const _serverFixture =
    '../server/src/utils/__fixtures__/account_deleted_v1.json';

/// The label the server test derives the valid vector's account from.
const _aliceLabel = 'account deleted v1 — alice';

Uint8List _sha(String label) =>
    Uint8List.fromList(hash.sha256.convert(utf8.encode(label)).bytes);

/// An IdentityManager whose stored account is the one derived from [label]
/// (seed = SHA256(label), as in the server test).
Future<IdentityManager> _managerFor(String label) async {
  final seed = _sha(label);
  final publicKey =
      Uint8List.fromList(ed.SigningKey(seed: seed).verifyKey.asTypedList);
  final storage = InMemorySecureStorage()
    ..data['identity_private_key'] = bytesToHexLower(seed)
    ..data['identity_public_key'] = bytesToHexLower(publicKey)
    ..data['snow_chat_id'] = KeyDerivation.deriveSnowChatId(publicKey);
  return IdentityManager(storage);
}

void main() {
  final fixture =
      jsonDecode(File(_appFixture).readAsStringSync()) as Map<String, dynamic>;
  final valid = Map<String, dynamic>.from(fixture['valid'] as Map);
  final rejected = [
    for (final v in fixture['rejected'] as List)
      Map<String, dynamic>.from(v as Map),
  ];

  AccountDeletionProof proofOf(Map<String, dynamic> v) =>
      AccountDeletionProof.tryParseWire(
          {'deletedAtMs': v['deletedAtMs'], 'sig': v['sigB64']})!;

  test('the fixture is the server fixture, byte for byte', () {
    expect(File(_appFixture).readAsBytesSync(),
        File(_serverFixture).readAsBytesSync());
  });

  group('valid vector', () {
    final snowId = valid['snowId'] as String;
    final accountKey =
        IdentityBindingV1.parseAccountKeyHex(valid['accountPublicKeyHex'] as String)!;
    final deletedAtMs = int.parse(valid['deletedAtMs'] as String);

    test('the message is the 71 bytes the server signs', () {
      final message = AccountDeletionProofV1.buildMessage(
          snowId: snowId, deletedAtMs: deletedAtMs);
      expect(message.length, AccountDeletionProofV1.messageLength);
      expect(bytesToHexLower(message), valid['messageHex']);
      expect(message[0], 0xff);
      expect(ascii.decode(message.sublist(1, 27)), 'SnowChat_AccountDeleted_v1');
      expect(ascii.decode(message.sublist(27, 63)), snowId);
    });

    test('the server signature verifies', () {
      expect(
        AccountDeletionProofV1.verify(
            snowId: snowId, accountPublicKey: accountKey, proof: proofOf(valid)),
        isTrue,
      );
    });

    test('IdentityManager.signAccountDeleted produces the same signature',
        () async {
      final manager = await _managerFor(_aliceLabel);
      expect(await manager.getSnowChatId(), snowId);
      final proof = await manager.signAccountDeleted(deletedAtMs);
      expect(proof.toWireJson(),
          {'deletedAtMs': valid['deletedAtMs'], 'sig': valid['sigB64']});
    });
  });

  group('rejected vectors', () {
    for (final v in rejected) {
      final reason = v['reason'] as String;
      test('${v['name']} ($reason)', () {
        final accountKey = IdentityBindingV1.parseAccountKeyHex(
            v['accountPublicKeyHex'] as String);
        if (accountKey == null) {
          // Not a lowercase 64-hex key: refused before any verification.
          expect(reason, 'account');
          return;
        }
        final verified = AccountDeletionProofV1.verify(
          snowId: v['snowId'] as String,
          accountPublicKey: accountKey,
          proof: proofOf(v),
        );
        // The ten-minute window around the server clock is the server's rule
        // at deletion time; the signature itself is good in those vectors.
        expect(verified, reason == 'time');
      });
    }

    test('every reason the server gives is covered', () {
      expect(rejected.map((v) => v['reason']).toSet(),
          {'signature', 'account', 'time'});
    });
  });

  group('wire form', () {
    final sig = valid['sigB64'] as String;

    test('round trip', () {
      final proof = proofOf(valid);
      expect(AccountDeletionProof.tryParseWire(proof.toWireJson())!.signature,
          proof.signature);
      expect(proof.deletedAtMs, int.parse(valid['deletedAtMs'] as String));
    });

    test('anything else is refused', () {
      Object? parse(Object? raw) => AccountDeletionProof.tryParseWire(raw);
      expect(parse(null), isNull);
      expect(parse('proof'), isNull);
      expect(parse({'deletedAtMs': 1794528000000, 'sig': sig}), isNull,
          reason: 'time as a number');
      expect(parse({'deletedAtMs': '+1794528000000', 'sig': sig}), isNull);
      expect(parse({'deletedAtMs': '01794528000000', 'sig': sig}), isNull);
      expect(parse({'deletedAtMs': '-1', 'sig': sig}), isNull);
      expect(parse({'deletedAtMs': '9223372036854775808', 'sig': sig}), isNull,
          reason: '2^63 does not fit');
      expect(parse({'deletedAtMs': '1', 'sig': sig.substring(0, 84)}), isNull,
          reason: 'short signature');
      expect(parse({'deletedAtMs': '1', 'sig': '${sig.substring(0, 86)}=A'}),
          isNull);
      // Same 64 bytes, non-canonical trailing bits in the last base64 digit.
      final last = sig[85];
      const alphabet =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      final other = alphabet[alphabet.indexOf(last) | 0x0f];
      if (other != last) {
        expect(
            parse({
              'deletedAtMs': '1',
              'sig': '${sig.substring(0, 85)}$other==',
            }),
            isNull,
            reason: 'non-canonical base64');
      }
      expect(parse({'deletedAtMs': '1'}), isNull);
      expect(parse({'sig': sig}), isNull);
    });
  });

  group('IdentityManager.signAccountDeleted', () {
    test('signs only for the stored account', () async {
      final manager = await _managerFor('account deleted v1 — bob');
      final proof = await manager.signAccountDeleted(1794528000000);
      final snowId = (await manager.getSnowChatId())!;
      final accountKey = (await manager.getPublicKey())!;
      expect(
        AccountDeletionProofV1.verify(
            snowId: snowId, accountPublicKey: accountKey, proof: proof),
        isTrue,
      );
      // Not a proof for another account, nor for another time.
      expect(
        AccountDeletionProofV1.verify(
          snowId: valid['snowId'] as String,
          accountPublicKey: IdentityBindingV1.parseAccountKeyHex(
              valid['accountPublicKeyHex'] as String)!,
          proof: proof,
        ),
        isFalse,
      );
      expect(
        AccountDeletionProofV1.verify(
          snowId: snowId,
          accountPublicKey: accountKey,
          proof: AccountDeletionProof(
              deletedAtMs: proof.deletedAtMs + 1, signature: proof.signature),
        ),
        isFalse,
      );
    });

    test('refuses without an identity, or with a mismatched one', () async {
      expect(IdentityManager(InMemorySecureStorage()).signAccountDeleted(1),
          throwsStateError);
      final manager = await _managerFor(_aliceLabel);
      final storage = InMemorySecureStorage()
        ..data['identity_private_key'] =
            bytesToHexLower((await manager.getPrivateKey())!)
        ..data['identity_public_key'] =
            bytesToHexLower((await manager.getPublicKey())!)
        ..data['snow_chat_id'] = 'snow${'0' * 32}';
      expect(IdentityManager(storage).signAccountDeleted(1), throwsStateError);
    });
  });
}
