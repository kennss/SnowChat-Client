/// @file        identity_manager.dart
/// @description User Ed25519 ID keypair management. Creation, restore, signing, and integrated Signal Protocol key management
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - IdentityManager: User ID keypair and Signal key management class
///  - IdentityManager.setSignalService(): Wire up SignalProtocolService
///  - IdentityManager.hasIdentity(): Check whether an identity exists on this device
///  - IdentityManager.createIdentity(): Create a new identity, return mnemonic
///  - IdentityManager.restoreIdentity(): Restore identity from mnemonic
///  - IdentityManager.getSnowChatId(): Get the current SnowChat ID
///  - IdentityManager.getMnemonic(): Get the stored mnemonic
///  - IdentityManager.getPublicKey(): Get public key bytes
///  - IdentityManager.getPublicKeyHex(): Get public key as hex string
///  - IdentityManager.getPrivateKey(): Get private key bytes
///  - IdentityManager.sign(): Sign data with the ID key (Ed25519 detached)
///  - IdentityManager.signString(): Sign string data and return hex
///  - IdentityManager.generateSignalIdentityKey(): Generate and store Signal Curve25519 keypair
///  - IdentityManager.getSignalPublicKey(): Get Signal public key
///  - IdentityManager.hasSignalIdentity(): Check whether Signal keypair exists
///  - IdentityManager.deleteIdentity(): Delete all identity data

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pinenacl/ed25519.dart';

import '../storage/secure_storage.dart';
import 'key_derivation.dart';
import 'signal_protocol_service.dart';

/// Manages the user's Ed25519 identity keypair.
/// Private keys are stored in flutter_secure_storage (Keychain / Android Keystore).
///
/// Also coordinates with [SignalProtocolService] to generate and store the
/// Curve25519 identity key pair used by the Signal Protocol (separate from the
/// Ed25519 key used for SnowChat ID derivation).
class IdentityManager {
  final SecureStorageService _secureStorage;
  SignalProtocolService? _signalService;

  static const _mnemonicKey = 'identity_mnemonic';
  static const _privateKeyKey = 'identity_private_key';
  static const _publicKeyKey = 'identity_public_key';
  static const _snowIdKey = 'snow_chat_id';
  static const _signalIdentityPublicKey = 'signal_identity_public_key';
  static const _signalIdentityPrivateKey = 'signal_identity_private_key';
  static const _signalSigningSeedKey = 'signal_signing_seed';
  static const _signalVerifyKeyKey = 'signal_verify_key';
  static const _signalRegistrationIdKey = 'signal_registration_id';

  /// Attach a [SignalProtocolService] instance for Signal key management.
  /// This is optional -- if not set, Signal-related operations are skipped.
  void setSignalService(SignalProtocolService service) {
    _signalService = service;
  }

  IdentityManager(this._secureStorage);

  /// Check if identity already exists on this device.
  Future<bool> hasIdentity() async {
    final id = await _secureStorage.read(_snowIdKey);
    return id != null && id.isNotEmpty;
  }

  /// Create a new identity. Returns the mnemonic for backup.
  Future<List<String>> createIdentity() async {
    final mnemonic = KeyDerivation.generateMnemonic();
    final keyPair = await KeyDerivation.deriveKeyPair(mnemonic);

    await _secureStorage.write(_mnemonicKey, mnemonic.join(' '));
    await _secureStorage.write(
        _privateKeyKey, _bytesToHex(keyPair.privateKey));
    await _secureStorage.write(
        _publicKeyKey, _bytesToHex(keyPair.publicKey));
    await _secureStorage.write(_snowIdKey, keyPair.snowChatId);

    return mnemonic;
  }

  /// Restore identity from mnemonic.
  Future<String> restoreIdentity(List<String> mnemonic) async {
    if (!KeyDerivation.isValidMnemonic(mnemonic)) {
      throw ArgumentError('Invalid mnemonic: must be 12 or 24 valid BIP39 words');
    }

    final _sw = Stopwatch()..start();
    final keyPair = await KeyDerivation.deriveKeyPair(mnemonic);
    debugPrint('[Perf]   BIP39 + SLIP-0010 deriveKeyPair: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(_mnemonicKey, mnemonic.join(' '));
    debugPrint('[Perf]   write mnemonic: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(
        _privateKeyKey, _bytesToHex(keyPair.privateKey));
    debugPrint('[Perf]   write privateKey: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(
        _publicKeyKey, _bytesToHex(keyPair.publicKey));
    debugPrint('[Perf]   write publicKey: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(_snowIdKey, keyPair.snowChatId);
    debugPrint('[Perf]   write snowId: ${_sw.elapsedMilliseconds}ms');

    return keyPair.snowChatId;
  }

  /// Get the current SnowChat ID.
  Future<String?> getSnowChatId() async {
    return _secureStorage.read(_snowIdKey);
  }

  /// Get the stored mnemonic (for backup display).
  Future<List<String>?> getMnemonic() async {
    final stored = await _secureStorage.read(_mnemonicKey);
    if (stored == null) return null;
    return stored.split(' ');
  }

  /// Get the public key bytes.
  Future<Uint8List?> getPublicKey() async {
    final hex = await _secureStorage.read(_publicKeyKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the public key as hex string (for server registration).
  Future<String?> getPublicKeyHex() async {
    return _secureStorage.read(_publicKeyKey);
  }

  /// Get the private key bytes (use with caution).
  Future<Uint8List?> getPrivateKey() async {
    final hex = await _secureStorage.read(_privateKeyKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Sign data with the identity key using Ed25519 detached signature.
  /// Returns a 64-byte signature compatible with tweetnacl verification.
  Future<Uint8List> sign(Uint8List data) async {
    final privateKeySeed = await getPrivateKey();
    if (privateKeySeed == null) {
      throw StateError('No identity key available');
    }

    // pinenacl SigningKey from 32-byte seed produces tweetnacl-compatible signatures
    final signingKey = SigningKey(seed: privateKeySeed);
    final signedMessage = signingKey.sign(data);
    // signedMessage.signature is the 64-byte detached signature
    return Uint8List.fromList(signedMessage.signature.toList());
  }

  /// Sign a UTF-8 string and return the signature as hex string.
  /// Used for challenge-response authentication.
  Future<String> signString(String message) async {
    final messageBytes = Uint8List.fromList(utf8.encode(message));
    final signature = await sign(messageBytes);
    return _bytesToHex(signature);
  }

  // ---------------------------------------------------------------------------
  // Signal Protocol Identity Key (Curve25519)
  // ---------------------------------------------------------------------------

  /// Generate and store the Signal Protocol identity key pair (Curve25519).
  /// This is separate from the Ed25519 key used for SnowChat ID.
  /// Called once during initial setup or identity creation.
  Future<Map<String, dynamic>> generateSignalIdentityKey() async {
    final signal = _signalService;
    if (signal == null) {
      throw StateError('SignalProtocolService not attached to IdentityManager');
    }

    final keyPair = await signal.generateIdentityKeyPair();
    final publicKey = keyPair['publicKey'] as Uint8List;
    final privateKey = keyPair['privateKey'] as Uint8List;

    // Store X25519 identity key pair
    await _secureStorage.write(
        _signalIdentityPublicKey, _bytesToHex(publicKey));
    await _secureStorage.write(
        _signalIdentityPrivateKey, _bytesToHex(privateKey));

    // Store Ed25519 signing seed + verify key + registration ID
    // (generated inside generateIdentityKeyPair)
    if (signal.signingKeySeed != null) {
      await _secureStorage.write(
          _signalSigningSeedKey, _bytesToHex(signal.signingKeySeed!));
    }
    if (signal.verifyKey != null) {
      await _secureStorage.write(
          _signalVerifyKeyKey, _bytesToHex(signal.verifyKey!));
    }
    if (signal.registrationId != null) {
      await _secureStorage.write(
          _signalRegistrationIdKey, signal.registrationId.toString());
    }

    return keyPair;
  }

  /// Get the stored Signal identity public key.
  Future<Uint8List?> getSignalPublicKey() async {
    final hex = await _secureStorage.read(_signalIdentityPublicKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Signal identity private key.
  Future<Uint8List?> getSignalPrivateKey() async {
    final hex = await _secureStorage.read(_signalIdentityPrivateKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Ed25519 signing seed.
  Future<Uint8List?> getSignalSigningSeed() async {
    final hex = await _secureStorage.read(_signalSigningSeedKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Ed25519 verify key.
  Future<Uint8List?> getSignalVerifyKey() async {
    final hex = await _secureStorage.read(_signalVerifyKeyKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Signal registration ID.
  Future<int?> getSignalRegistrationId() async {
    final str = await _secureStorage.read(_signalRegistrationIdKey);
    if (str == null) return null;
    return int.tryParse(str);
  }

  /// Save Ed25519 signing seed + verify key to secure storage.
  Future<void> saveSigningSeed(Uint8List seed, Uint8List verifyKey) async {
    await _secureStorage.write(_signalSigningSeedKey, _bytesToHex(seed));
    await _secureStorage.write(_signalVerifyKeyKey, _bytesToHex(verifyKey));
  }

  /// Check if a Signal identity key pair exists.
  Future<bool> hasSignalIdentity() async {
    final key = await _secureStorage.read(_signalIdentityPublicKey);
    return key != null && key.isNotEmpty;
  }

  /// Delete all identity data (dangerous!).
  Future<void> deleteIdentity() async {
    await _secureStorage.delete(_mnemonicKey);
    await _secureStorage.delete(_privateKeyKey);
    await _secureStorage.delete(_publicKeyKey);
    await _secureStorage.delete(_snowIdKey);
    await _secureStorage.delete(_signalIdentityPublicKey);
    await _secureStorage.delete(_signalIdentityPrivateKey);
  }

  // --- Hex helpers ---

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
