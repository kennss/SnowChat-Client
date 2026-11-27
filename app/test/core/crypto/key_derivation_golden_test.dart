/// @file        key_derivation_golden_test.dart
/// @description Golden vectors for the identity key derivation (BIP39 seed → SLIP-0010
///              Ed25519, path m/44'/0'/0'/0'). The vectors were produced on 2026-11-27 by the
///              implementation that shipped through build 1006 (the solana package's
///              Ed25519HDKeyPair, which calls ed25519_hd_key 2.3.0). Any change to the
///              derivation must keep these bytes, or the same recovery phrase restores a
///              different account. The second group pins ed25519_hd_key to the official
///              SLIP-0010 Ed25519 test vector 1.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-27
/// @lastUpdated 2026-11-27
///
/// @functions
///  - main(): golden identity vectors + SLIP-0010 spec vector 1

import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String s) => [
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ];

void main() {
  group('identity derivation golden vectors (build 1006)', () {
    // (mnemonic, private key seed, public key, snowId)
    const vectors = [
      (
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
        '7ed25a6fe011c6f10f8563a859de97b2bb9ae32aacdd542a0ca344680fd09549',
        '5aa3651cfc2e2980005c4272297410dee864bacf947c84111d048c77e0d62cf0',
        'snow5aa3651cfc2e2980005c4272297410de',
      ),
      (
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon '
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art',
        '77623fa2c4859cb85c2fa601b4531d62cc6861871381e45e10548ab726354402',
        '729a25679d1cab4129532854c6560ca7007a875bd51c4b28bb82ee2d444fe664',
        'snow729a25679d1cab4129532854c6560ca7',
      ),
      (
        'legal winner thank year wave sausage worth useful legal winner thank yellow',
        'f7496d3045cac66fe4a72923067ecfddfebd51b1ee5be6f1c78edc7ff024194c',
        'e8b5139ea92bcd7a4292fc6c82a8bb59be4c321c2249fa3abeadd1530a2a1bdc',
        'snowe8b5139ea92bcd7a4292fc6c82a8bb59',
      ),
    ];

    for (final (mnemonic, privateKey, publicKey, snowId) in vectors) {
      test('${mnemonic.split(' ').length} words: ${snowId.substring(0, 12)}…', () async {
        final r = await KeyDerivation.deriveKeyPair(mnemonic.split(' '));
        expect(_hex(r.privateKey), privateKey);
        expect(_hex(r.publicKey), publicKey);
        expect(r.snowChatId, snowId);
      });
    }
  });

  group('SLIP-0010 Ed25519 test vector 1', () {
    final seed = _unhex('000102030405060708090a0b0c0d0e0f');

    test('master key', () async {
      final m = await ED25519_HD_KEY.getMasterKeyFromSeed(seed);
      expect(_hex(m.key),
          '2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7');
      expect(_hex(m.chainCode),
          '90046a93de5380a72b5e45010748567d5ea02bbf6522f979e05c0d8d8ca9fffb');
    });

    test("m/0'/1'/2'/2'/1000000000'", () async {
      final d = await ED25519_HD_KEY.derivePath("m/0'/1'/2'/2'/1000000000'", seed);
      expect(_hex(d.key),
          '8f94d394a8e8fd6b1bc2f3f49f5c47e385281d5c17e65324b0f62483e37e8793');
      expect(_hex(d.chainCode),
          '68789923a0cac2cd5a29172a475fe9e0fb14cd6adb5ad98a3fa70333e7afa230');
      expect(_hex(await ED25519_HD_KEY.getPublicKey(d.key)),
          '003c24da049451555d51a7014a37337aa4e12d41e485abccfa46b47dfb2af54b7a');
    });
  });
}
