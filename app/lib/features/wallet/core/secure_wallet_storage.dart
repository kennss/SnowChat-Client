/// @file        secure_wallet_storage.dart
/// @description Wallet key secure storage — flutter_secure_storage wrapper.
///              Stores mnemonic, private key, and Solana address in OS
///              keychain/keystore.
///              Multi-Wallet Phase 1 (2026-04-25) — added new key schema:
///              wallet_index_v1, wallet_active_id, `wallet_secret/{id}`.
///              Legacy keys (wallet_mnemonic, solana_private_key,
///              solana_public_key) are retained as-is in v2.0.0 — F-6
///              deferred policy (orphan-prune in v2.1.0).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation; Multi-Wallet Phase 1 v2 key schema; legacy keys retained per F-6 deferred policy)
///
/// @functions
///  - SecureWalletStorage: secure-storage wrapper for wallet
///  - [Legacy] saveMnemonic / readMnemonic / savePrivateKey / readPrivateKey
///  - [Legacy] saveSolanaAddress / readSolanaAddress / hasWallet / clearWallet
///  - [Legacy] hasLegacyKeys / deleteLegacyKeys (for Migration F-6 cleanup)
///  - [v2] readWalletIndexJson / writeWalletIndexJson / deleteWalletIndex
///  - [v2] readActiveWalletId / writeActiveWalletId / deleteActiveWalletId
///  - [v2] readImportedSecret / writeImportedSecret / deleteImportedSecret
///  - [v2] listAllImportedSecretIds (for orphan tracking)

library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper over flutter_secure_storage for wallet key material.
///
/// Keys are stored encrypted via iOS Keychain / Android Keystore.
/// This class manages the storage key names and serialization format.
///
/// Phase 6.1 §4.2.1 Stage 1 applied:
///   - iOS:     KeychainAccessibility.first_unlock_this_device
///              (no off-device replication, excluded from iCloud Keychain sync)
///   - Android: encryptedSharedPreferences (Keystore-backed AES)
///
/// Stage 2 (biometric binding + setUserAuthenticationRequired) requires
/// native channel work and is run as a separate spike.
class SecureWalletStorage {
  SecureWalletStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? _defaultStorage();

  final FlutterSecureStorage _storage;

  /// Phase 6.1 Stage 1 security options — the strongest policy directly
  /// exposed by flutter_secure_storage. Applicable without a native channel.
  static FlutterSecureStorage _defaultStorage() {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Storage key constants
  // ---------------------------------------------------------------------------
  //
  // Legacy (pre-Phase 1) — kept in v2.0.0; orphan-prune in v2.1.0 (F-6).
  static const _mnemonicKey = 'wallet_mnemonic';
  static const _privateKeyKey = 'solana_private_key';
  static const _publicKeyKey = 'solana_public_key';

  // Multi-Wallet (v2 schema) — wallet_index_v1 is the single source of truth.
  // wallet_secret/<id> is for imported wallets only (derived re-derives on
  // the fly from mnemonic). Never write wallet_secret/<primaryId> — primary
  // derives from identity_mnemonic (owned by IdentityManager).
  static const _walletIndexKey = 'wallet_index_v1';
  static const _activeWalletIdKey = 'wallet_active_id';
  static const _importedSecretPrefix = 'wallet_secret/';

  // ---------------------------------------------------------------------------
  // Mnemonic
  // ---------------------------------------------------------------------------

  /// Save BIP39 mnemonic (24 words, space-separated).
  Future<void> saveMnemonic(String mnemonic) =>
      _storage.write(key: _mnemonicKey, value: mnemonic);

  /// Read stored mnemonic.
  Future<String?> readMnemonic() => _storage.read(key: _mnemonicKey);

  // ---------------------------------------------------------------------------
  // Private key (Ed25519 seed, 32 bytes)
  // ---------------------------------------------------------------------------

  /// Save Ed25519 private key seed as base64.
  Future<void> savePrivateKey(Uint8List privateKey) =>
      _storage.write(key: _privateKeyKey, value: base64Encode(privateKey));

  /// Read Ed25519 private key seed.
  Future<Uint8List?> readPrivateKey() async {
    final encoded = await _storage.read(key: _privateKeyKey);
    if (encoded == null) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }

  // ---------------------------------------------------------------------------
  // Solana address (Base58 public key)
  // ---------------------------------------------------------------------------

  /// Save Solana wallet address (Base58 encoded public key).
  Future<void> saveSolanaAddress(String address) =>
      _storage.write(key: _publicKeyKey, value: address);

  /// Read stored Solana wallet address.
  Future<String?> readSolanaAddress() => _storage.read(key: _publicKeyKey);

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  /// Check whether a wallet has been set up.
  Future<bool> hasWallet() async {
    final key = await _storage.read(key: _publicKeyKey);
    return key != null && key.isNotEmpty;
  }

  /// Delete all wallet key material (destructive).
  /// **Deletes both legacy and v2 keys.** clearWallet is called only from
  /// onboarding reset / account deletion flows. Distinct from removeWallet
  /// (which removes only one sub).
  Future<void> clearWallet() async {
    // Legacy
    await _storage.delete(key: _mnemonicKey);
    await _storage.delete(key: _privateKeyKey);
    await _storage.delete(key: _publicKeyKey);
    // v2 keys
    await _storage.delete(key: _walletIndexKey);
    await _storage.delete(key: _activeWalletIdKey);
    // All imported secrets
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_importedSecretPrefix)) {
        await _storage.delete(key: key);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // [Legacy] Migration helpers (F-6 deferred to v2.1.0)
  // ---------------------------------------------------------------------------

  /// Returns true if any legacy key (`wallet_mnemonic`, `solana_private_key`,
  /// `solana_public_key`) exists. Used in Migration bootstrap step 1 to
  /// branch between "already v2 schema" vs "v1 user first boot".
  Future<bool> hasLegacyKeys() async {
    final mnemonic = await _storage.read(key: _mnemonicKey);
    if (mnemonic != null) return true;
    final privKey = await _storage.read(key: _privateKeyKey);
    if (privKey != null) return true;
    final pubKey = await _storage.read(key: _publicKeyKey);
    return pubKey != null;
  }

  /// Delete all legacy keys. F-6 deferred — must NOT be called in v2.0.0
  /// (rollback safety). Only called at v2.1.0 orphan-prune.
  /// F-5 fix: each delete is wrapped in try-catch so a single failure does
  /// not block deletion of the others.
  Future<void> deleteLegacyKeys() async {
    try {
      await _storage.delete(key: _mnemonicKey);
    } catch (_) {/* swallow — orphan-prune retries on next boot */}
    try {
      await _storage.delete(key: _privateKeyKey);
    } catch (_) {/* swallow */}
    try {
      await _storage.delete(key: _publicKeyKey);
    } catch (_) {/* swallow */}
  }

  // ---------------------------------------------------------------------------
  // [v2] Wallet Index — single source of truth (JSON serialized)
  // ---------------------------------------------------------------------------

  /// Read the `wallet_index_v1` JSON string. Parsing is the caller's
  /// responsibility (typically WalletIndexNotifier).
  Future<String?> readWalletIndexJson() =>
      _storage.read(key: _walletIndexKey);

  /// Write the `wallet_index_v1` JSON string. Serialization is the caller's job.
  Future<void> writeWalletIndexJson(String json) =>
      _storage.write(key: _walletIndexKey, value: json);

  Future<void> deleteWalletIndex() => _storage.delete(key: _walletIndexKey);

  // ---------------------------------------------------------------------------
  // [v2] Active wallet pointer — id of the wallet last viewed by UI
  // ---------------------------------------------------------------------------

  Future<String?> readActiveWalletId() =>
      _storage.read(key: _activeWalletIdKey);

  Future<void> writeActiveWalletId(String walletId) =>
      _storage.write(key: _activeWalletIdKey, value: walletId);

  Future<void> deleteActiveWalletId() =>
      _storage.delete(key: _activeWalletIdKey);

  // ---------------------------------------------------------------------------
  // [v2] Imported wallet secrets — Plain Keystore (P0 A-1)
  // ---------------------------------------------------------------------------
  //
  // Policy: never use pinenacl wrap (wallet/CLAUDE.md §3.3 compliance).
  // Rely solely on OS-level protection of flutter_secure_storage (iOS
  // Keychain first_unlock_this_device + Android Keystore-backed AES).
  // Stores the 32-byte Ed25519 seed as Base64.

  /// Save the 32-byte Ed25519 seed of an imported wallet.
  /// Do NOT call for derived — derived secrets re-derive on the fly from mnemonic.
  Future<void> writeImportedSecret(String walletId, Uint8List secret) {
    if (secret.length != 32) {
      throw ArgumentError(
        'Imported secret must be exactly 32 bytes (Ed25519 seed)',
      );
    }
    return _storage.write(
      key: _importedSecretKey(walletId),
      value: base64Encode(secret),
    );
  }

  /// Read the imported wallet's secret. null = key missing (corruption / I-5).
  Future<Uint8List?> readImportedSecret(String walletId) async {
    final encoded = await _storage.read(key: _importedSecretKey(walletId));
    if (encoded == null) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }

  /// Permanently delete the imported wallet's secret (removeWallet flow).
  Future<void> deleteImportedSecret(String walletId) =>
      _storage.delete(key: _importedSecretKey(walletId));

  /// Return all imported-secret walletIds. For orphan tracking / migration
  /// verification / clearWallet auxiliary use. Detects corruption cases
  /// where a secret persists without an entry in wallet_index_v1.
  Future<List<String>> listAllImportedSecretIds() async {
    final all = await _storage.readAll();
    return all.keys
        .where((k) => k.startsWith(_importedSecretPrefix))
        .map((k) => k.substring(_importedSecretPrefix.length))
        .toList();
  }

  /// Exact storage key for a per-wallet secret.
  static String _importedSecretKey(String walletId) =>
      '$_importedSecretPrefix$walletId';
}
