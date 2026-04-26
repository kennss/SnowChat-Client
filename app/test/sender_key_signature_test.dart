/// @file        sender_key_signature_test.dart
/// @description Phase 6.8 audit — verify pinenacl Ed25519 seed roundtrip and
///              sign/verify behavior. Tests the exact patterns used in
///              sender_key.dart to isolate the signature verification bug.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-07

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;

void main() {
  test('Hypothesis 1: signingKey.seed → fromSeed → same verifyKey', () {
    final sk1 = ed.SigningKey.generate();

    // Mimic sender_key.dart createSenderKey storage
    final storedPub = Uint8List.fromList(sk1.verifyKey.toList());
    final storedSeed = Uint8List.fromList(sk1.seed);

    print('storedSeed.length=${storedSeed.length}');
    print('storedPub.length=${storedPub.length}');
    print('storedSeedHex=${_hex(storedSeed)}');
    print('storedPubHex=${_hex(storedPub)}');

    // Mimic sender_key.dart encryptGroupMessage recreation
    final sk2 = ed.SigningKey.fromSeed(storedSeed);
    final recreatedPub = Uint8List.fromList(sk2.verifyKey.toList());

    print('recreatedPub.length=${recreatedPub.length}');
    print('recreatedPubHex=${_hex(recreatedPub)}');

    expect(storedSeed.length, 32, reason: 'seed must be 32 bytes');
    expect(storedPub.length, 32, reason: 'pub must be 32 bytes');
    expect(recreatedPub.length, 32, reason: 'recreated pub must be 32 bytes');
    expect(_bytesEqual(recreatedPub, storedPub), true,
        reason: 'recreated public key must match stored public key');
  });

  test('Hypothesis 2: sign / verify roundtrip with recreated key', () {
    final sk1 = ed.SigningKey.generate();
    final storedSeed = Uint8List.fromList(sk1.seed);
    final storedPub = Uint8List.fromList(sk1.verifyKey.toList());

    // Sign with the RECREATED key (mimics encryptGroupMessage)
    final sk2 = ed.SigningKey.fromSeed(storedSeed);
    final ciphertext = Uint8List.fromList(List.generate(100, (i) => i % 256));
    final signedMessage = sk2.sign(ciphertext);

    // Extract first 64 bytes as signature (mimics sender_key.dart line 405)
    final signatureBytes = Uint8List.fromList(
        signedMessage.sublist(0, ed.Signature.signatureLength));

    print('signatureBytes.length=${signatureBytes.length}');
    print('signatureHex=${_hex(signatureBytes)}');

    expect(signatureBytes.length, 64, reason: 'signature must be 64 bytes');

    // Verify with the STORED public key (mimics decryptGroupMessage)
    final verifyKey = ed.VerifyKey(storedPub);
    bool verified = false;
    try {
      verifyKey.verify(
        signature: ed.Signature(signatureBytes),
        message: ciphertext,
      );
      verified = true;
    } catch (e) {
      print('verify threw: $e');
    }
    expect(verified, true, reason: 'signature must verify');
  });

  test('Hypothesis 3: store seed via Uint8List.fromList vs raw', () {
    final sk1 = ed.SigningKey.generate();

    // Method A: Uint8List.fromList(signingKey.seed) — what sender_key.dart uses
    final seedA = Uint8List.fromList(sk1.seed);

    // Method B: explicit toList() then fromList
    final seedB = Uint8List.fromList(sk1.seed.toList());

    // Method C: asTypedList (only the prefix's underlying buffer)
    final seedC = (sk1.seed as ed.ByteList).asTypedList;

    print('seedA.length=${seedA.length}');
    print('seedB.length=${seedB.length}');
    print('seedC.length=${seedC.length}');
    print('seedAHex=${_hex(seedA)}');
    print('seedBHex=${_hex(seedB)}');
    print('seedCHex=${_hex(seedC)}');

    expect(seedA.length, 32);
    expect(seedB.length, 32);
    expect(seedC.length, 32);
    expect(_bytesEqual(seedA, seedB), true);
    expect(_bytesEqual(seedA, seedC), true);
  });

  test('Hypothesis 4: SignedMessage.sublist(0, 64) extracts signature correctly', () {
    final sk = ed.SigningKey.generate();
    final message = Uint8List.fromList([1, 2, 3, 4, 5]);
    final signedMessage = sk.sign(message);

    print('signedMessage.length=${signedMessage.length}');
    expect(signedMessage.length, 64 + 5,
        reason: 'SignedMessage = signature(64) + message(5)');

    // Extract signature via sublist (matches sender_key.dart pattern)
    final sigViaSublist = signedMessage.sublist(0, 64);
    print('sigViaSublist runtimeType=${sigViaSublist.runtimeType}');
    print('sigViaSublist.length=${sigViaSublist.length}');

    final sigBytes = Uint8List.fromList(sigViaSublist);
    print('sigBytes.length=${sigBytes.length}');

    // Verify the extracted signature is correct by direct verify
    final verifyKey = sk.verifyKey;
    bool ok = false;
    try {
      verifyKey.verify(
        signature: ed.Signature(sigBytes),
        message: message,
      );
      ok = true;
    } catch (e) {
      print('verify error: $e');
    }
    expect(ok, true, reason: 'signature extracted via sublist must verify');
  });
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
