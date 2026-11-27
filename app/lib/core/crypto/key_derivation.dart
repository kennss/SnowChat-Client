/// @file        key_derivation.dart
/// @description BIP39 mnemonic generation and SLIP-0010 Ed25519 key derivation. Includes SnowChat ID derivation logic
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-27 (SLIP-0010 through ed25519_hd_key 2.3.0 directly — the solana package,
///              whose Ed25519HDKeyPair called the same ED25519_HD_KEY.derivePath, left with the
///              wallet; the bytes are pinned by key_derivation_golden_test.dart). Earlier
///              2026-04-26 (header English translation)
///
/// @functions
///  - KeyDerivation: BIP39/SLIP-0010 key derivation utility class
///  - KeyDerivation.generateMnemonic(): Generate a 24-word BIP39 mnemonic
///  - KeyDerivation.deriveKeyPair(): Derive Ed25519 keypair from mnemonic
///  - KeyDerivation.deriveSnowChatId(): Derive SnowChat ID from public key
///  - KeyDerivation.isValidSnowChatId(): Validate SnowChat ID format
///  - KeyDerivation.isValidMnemonic(): Validate mnemonic phrase
///  - KeyPairResult: Keypair derivation result data class

import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:pinenacl/ed25519.dart';

/// BIP39 + SLIP-0010 key derivation for SnowChat.
///
/// Derivation path: m/44'/0'/0'/0' (SLIP-0010 for Ed25519)
/// SnowChat ID = "snow" + hex(publicKey)[0:32] = 36 chars total
class KeyDerivation {
  /// Derivation path for SnowChat identity keys (SLIP-0010).
  static const _derivationPath = "m/44'/0'/0'/0'";

  /// Generate a new 24-word BIP39 mnemonic.
  static List<String> generateMnemonic() {
    final mnemonic = bip39.generateMnemonic(strength: 256);
    return mnemonic.split(' ');
  }

  /// Derive Ed25519 keypair from mnemonic using SLIP-0010.
  /// Path: m/44'/0'/0'/0'
  /// The derived 32-byte key is the Ed25519 seed (ed25519_hd_key 2.3.0 —
  /// builds through 1006 reached the same function through the solana
  /// package; the golden test pins the bytes).
  static Future<KeyPairResult> deriveKeyPair(List<String> mnemonic) async {
    final mnemonicStr = mnemonic.join(' ');
    final seed = bip39.mnemonicToSeed(mnemonicStr);

    // SLIP-0010 Ed25519 derivation (hardened path only).
    final keyData = await ED25519_HD_KEY.derivePath(_derivationPath, seed);

    // Raw seed bytes for pinenacl Ed25519 usage (signing, X3DH)
    final privateKeySeed = Uint8List.fromList(keyData.key);
    final signingKey = SigningKey(seed: privateKeySeed);
    final publicKeyBytes = Uint8List.fromList(signingKey.verifyKey.toList());

    return KeyPairResult(
      privateKey: privateKeySeed,
      publicKey: publicKeyBytes,
      snowChatId: deriveSnowChatId(publicKeyBytes),
    );
  }

  /// Derive SnowChat ID from public key.
  /// Format: "snow" + first 32 hex chars of public key = 36 chars.
  static String deriveSnowChatId(Uint8List publicKey) {
    final hex = publicKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'snow${hex.substring(0, 32)}';
  }

  /// Validate a SnowChat ID format.
  static bool isValidSnowChatId(String id) {
    if (id.length != 36) return false;
    if (!id.startsWith('snow')) return false;
    final hexPart = id.substring(4);
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(hexPart);
  }

  /// Validate mnemonic phrase (12 or 24 words).
  /// BIP39 supports 12 (128-bit), 15, 18, 21, and 24 (256-bit) words.
  static bool isValidMnemonic(List<String> words) {
    if (words.length != 12 && words.length != 24) return false;
    final mnemonicStr = words.join(' ');
    return bip39.validateMnemonic(mnemonicStr);
  }
}

class KeyPairResult {
  final Uint8List privateKey;
  final Uint8List publicKey;
  final String snowChatId;

  const KeyPairResult({
    required this.privateKey,
    required this.publicKey,
    required this.snowChatId,
  });
}
