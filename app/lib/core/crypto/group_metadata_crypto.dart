/// @file        group_metadata_crypto.dart
/// @description Group metadata E2EE — GMK generation, group name encrypt/decrypt, GMK sign/verify, local storage
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - GroupMetadataCrypto.generateGMK(): Generate a random 32-byte GMK
///  - GroupMetadataCrypto.encryptGroupName(): Encrypt group name with GMK
///  - GroupMetadataCrypto.decryptGroupName(): Decrypt group name with GMK
///  - GroupMetadataCrypto.signGMK(): Generate coordinator Ed25519 signature
///  - GroupMetadataCrypto.verifyGMKSignature(): Verify GMK signature
///  - GroupMetadataCrypto.storeGMK(): Store GMK in flutter_secure_storage
///  - GroupMetadataCrypto.loadGMK(): Load GMK from flutter_secure_storage
///  - GroupMetadataCrypto.deleteGMK(): Delete GMK

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/x25519.dart' as nacl_api;
import 'package:pinenacl/ed25519.dart' as ed;

/// Group Metadata Key (GMK) based encryption for group names.
/// Uses random 32-byte key + XSalsa20-Poly1305 AEAD.
/// GMK is distributed via 1:1 E2EE (Double Ratchet) sessions.
class GroupMetadataCrypto {
  static final _rng = Random.secure();
  static const _storage = FlutterSecureStorage();
  static const _keyPrefix = 'gmk_';

  // ---------------------------------------------------------------------------
  // GMK Generation
  // ---------------------------------------------------------------------------

  /// Generate a random 32-byte Group Metadata Key.
  static Uint8List generateGMK() {
    return _randomBytes(32);
  }

  // ---------------------------------------------------------------------------
  // Group Name Encryption / Decryption
  // ---------------------------------------------------------------------------

  /// Encrypt group name with GMK.
  /// Returns base64-encoded ciphertext (nonce || ciphertext+tag).
  static String encryptGroupName(Uint8List gmk, String plaintext) {
    final box = nacl_api.SecretBox(gmk);
    final nonce = _randomBytes(nacl_api.EncryptedMessage.nonceLength);
    final encrypted = box.encrypt(
      Uint8List.fromList(utf8.encode(plaintext)),
      nonce: nonce,
    );
    return base64Encode(Uint8List.fromList(encrypted.toList()));
  }

  /// Decrypt group name with GMK.
  /// [base64Ciphertext] is base64-encoded (nonce || ciphertext+tag).
  /// Returns null on decryption failure (wrong key, corrupted data).
  static String? decryptGroupName(Uint8List gmk, String base64Ciphertext) {
    try {
      final encrypted = Uint8List.fromList(base64Decode(base64Ciphertext));
      final nonceLen = nacl_api.EncryptedMessage.nonceLength;
      if (encrypted.length <= nonceLen) return null;

      final box = nacl_api.SecretBox(gmk);
      final decrypted = box.decrypt(
        nacl_api.EncryptedMessage(
          nonce: encrypted.sublist(0, nonceLen),
          cipherText: encrypted.sublist(nonceLen),
        ),
      );
      return utf8.decode(decrypted);
    } catch (e) {
      debugPrint('[GroupMetadataCrypto] Decrypt failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // GMK Signing (Authenticity Proof)
  // ---------------------------------------------------------------------------

  /// Sign GMK with coordinator's Ed25519 signing key.
  /// signedPayload = utf8(groupId) || gmk(32B) || epoch(4B big-endian)
  static Uint8List signGMK({
    required Uint8List signingKeySeed,
    required String groupId,
    required Uint8List gmk,
    required int epoch,
  }) {
    final payload = _buildSignPayload(groupId, gmk, epoch);
    final signingKey = ed.SigningKey(seed: signingKeySeed);
    final signedMessage = signingKey.sign(payload);
    return Uint8List.fromList(signedMessage.signature.toList());
  }

  /// Verify GMK signature with coordinator's Ed25519 verify key.
  static bool verifyGMKSignature({
    required Uint8List verifyKey,
    required String groupId,
    required Uint8List gmk,
    required int epoch,
    required Uint8List signature,
  }) {
    try {
      final payload = _buildSignPayload(groupId, gmk, epoch);
      final vk = ed.VerifyKey(verifyKey);
      vk.verify(
        signature: ed.Signature(signature),
        message: payload,
      );
      return true;
    } catch (e) {
      debugPrint('[GroupMetadataCrypto] Signature verification failed: $e');
      return false;
    }
  }

  static Uint8List _buildSignPayload(
      String groupId, Uint8List gmk, int epoch) {
    final groupIdBytes = utf8.encode(groupId);
    final epochBytes = ByteData(4)..setUint32(0, epoch, Endian.big);
    return Uint8List.fromList([
      ...groupIdBytes,
      ...gmk,
      ...epochBytes.buffer.asUint8List(),
    ]);
  }

  // ---------------------------------------------------------------------------
  // GMK Local Storage (flutter_secure_storage)
  // ---------------------------------------------------------------------------

  /// Store GMK in flutter_secure_storage.
  /// Key: "gmk_{groupId}", Value: "base64(gmk):epoch"
  static Future<void> storeGMK(
      String groupId, Uint8List gmk, int epoch) async {
    final value = '${base64Encode(gmk)}:$epoch';
    await _storage.write(key: '$_keyPrefix$groupId', value: value);
  }

  /// Load GMK from flutter_secure_storage.
  /// Returns (gmk, epoch) or (null, -1) if not found.
  static Future<(Uint8List?, int)> loadGMK(String groupId) async {
    final value = await _storage.read(key: '$_keyPrefix$groupId');
    if (value == null) return (null, -1);
    final parts = value.split(':');
    if (parts.length != 2) return (null, -1);
    try {
      final gmk = base64Decode(parts[0]);
      final epoch = int.parse(parts[1]);
      return (Uint8List.fromList(gmk), epoch);
    } catch (e) {
      debugPrint('[GroupMetadataCrypto] Failed to parse stored GMK: $e');
      return (null, -1);
    }
  }

  /// Delete GMK from flutter_secure_storage.
  static Future<void> deleteGMK(String groupId) async {
    await _storage.delete(key: '$_keyPrefix$groupId');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _rng.nextInt(256)),
    );
  }
}
