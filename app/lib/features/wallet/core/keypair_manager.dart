/// @file        keypair_manager.dart
/// @description Solana wallet keypair lifecycle management. Create, store,
///              load, delete, server registration.
///              Multi-Wallet Phase 1.5 (2026-04-25) — added clearCache()
///              (called by lifecycle observer on idle). Phase 2B-1
///              (2026-04-25) — added `_multiCache: Map<id, KeyPair>` +
///              `loadWalletFor(entry)` for multi-wallet keypair load/cache.
///              Existing `loadWallet()` / `getAddress()` kept for primary
///              compatibility.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation; Multi-Wallet Phase 1.5 clearCache + Phase 2B-1 multi-wallet cache/load)
///
/// @functions
///  - KeypairManager: wallet keypair management class
///  - createWallet(): create keypair from mnemonic + save to secure storage + register on server
///  - loadWallet(): restore keypair from secure storage (primary-compatible)
///  - loadWalletFor(entry): multi-wallet load based on WalletEntry (Phase 2B)
///  - evictWallet(walletId): clear cache for a single entry
///  - hasWallet(): whether a wallet exists
///  - getAddress(): return stored Solana address
///  - deleteWallet(): delete all keys
///  - clearCache(): clear in-memory cache (lifecycle idle / security best practice)
///  - solToLamports(): SOL string → BigInt lamports (no Float)
///  - lamportsToSol(): BigInt lamports → SOL string (no Float)

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:solana/solana.dart';

import '../../../core/network/api_client.dart';
import '../models/wallet_account_model.dart';
import '../models/wallet_index_exceptions.dart';
import 'derivation_service.dart';
import 'secure_wallet_storage.dart';

/// Manages the Solana wallet keypair lifecycle.
///
/// Creates, stores, loads, and deletes Ed25519HDKeyPair.
/// All monetary values are BigInt lamports — Float/double NEVER used.
class KeypairManager {
  KeypairManager({
    required SecureWalletStorage storage,
    this.apiClient,
  }) : _storage = storage;

  final SecureWalletStorage _storage;
  final ApiClient? apiClient;

  /// Cached keypair (in-memory, loaded from secure storage on demand).
  /// **Legacy single-wallet path** — for primary compatibility. The Phase 2B
  /// multi-wallet entry point is `_multiCache`.
  Ed25519HDKeyPair? _cachedKeyPair;

  /// Multi-Wallet keypair cache — walletId → keypair. Stores both derived and
  /// imported in one place. `clearCache()` empties it entirely on lifecycle
  /// idle. Per-id evict goes through `evictWallet(walletId)`.
  final Map<String, Ed25519HDKeyPair> _multiCache = {};

  /// Phase 5 critical fix — current active wallet entry. All send / buy /
  /// marketplace signing uses this entry's keypair.
  ///
  /// When unset, `loadWallet()` falls back to the legacy single-wallet path
  /// (= primary). `WalletNotifier.switchActive` calls `setActive(entry)`
  /// every time.
  WalletEntry? _activeEntry;

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Create wallet from mnemonic: derive keypair, save to secure storage,
  /// register with server.
  ///
  /// Returns the Solana wallet address (Base58).
  Future<String> createWallet(String mnemonic) async {
    final keyPair = await DerivationService.deriveWalletKeyPair(mnemonic);
    final address = keyPair.publicKey.toBase58();

    // Extract private key seed for storage
    final keyPairData = await keyPair.extract();
    final privateKeySeed = Uint8List.fromList(
        keyPairData.bytes.sublist(0, 32));

    // Save to secure storage
    await _storage.saveMnemonic(mnemonic);
    await _storage.savePrivateKey(privateKeySeed);
    await _storage.saveSolanaAddress(address);

    _cachedKeyPair = keyPair;

    // Register with server (best-effort)
    await _registerWithServer(address);

    return address;
  }

  // ---------------------------------------------------------------------------
  // Load
  // ---------------------------------------------------------------------------

  /// Load wallet keypair from secure storage.
  ///
  /// Phase 5 fix: when `_activeEntry` is set, return that entry's keypair
  /// (multi-wallet active wallet). When unset, fall back to the legacy
  /// single-wallet path (mnemonic → account 0 = primary).
  Future<Ed25519HDKeyPair> loadWallet() async {
    // Multi-Wallet first — keypair of the active entry
    final active = _activeEntry;
    if (active != null) {
      return loadWalletFor(active);
    }

    // Legacy single-wallet path
    if (_cachedKeyPair != null) return _cachedKeyPair!;

    final mnemonic = await _storage.readMnemonic();
    if (mnemonic != null) {
      _cachedKeyPair = await DerivationService.deriveWalletKeyPair(mnemonic);
      return _cachedKeyPair!;
    }

    final privateKey = await _storage.readPrivateKey();
    if (privateKey != null) {
      _cachedKeyPair = await Ed25519HDKeyPair.fromPrivateKeyBytes(
        privateKey: privateKey,
      );
      return _cachedKeyPair!;
    }

    throw WalletNotInitializedException();
  }

  /// Set the Multi-Wallet active entry — called by
  /// `WalletNotifier.switchActive` / `initialize`. All subsequent send / buy
  /// / marketplace signing uses this entry's keypair. Passing null falls
  /// back to the legacy single-wallet path.
  void setActive(WalletEntry? entry) {
    _activeEntry = entry;
  }

  /// Current active entry — for debugging / verification.
  WalletEntry? get activeEntry => _activeEntry;

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Check if a wallet exists in secure storage.
  Future<bool> hasWallet() => _storage.hasWallet();

  /// Get the stored Solana wallet address (Base58).
  /// Phase 5 fix: if an active entry exists, return its address first.
  Future<String?> getAddress() async {
    final active = _activeEntry;
    if (active != null) return active.address;
    return _storage.readSolanaAddress();
  }

  /// Ensure wallet is registered on server.
  /// If server returns 409 (duplicate), wallet is already registered — OK.
  /// If server returns 201, wallet was missing and is now registered.
  /// Best-effort: failures are silently ignored.
  Future<void> ensureRegistered() async {
    if (apiClient == null) return;
    final address = await _storage.readSolanaAddress();
    if (address == null) return;
    try {
      await apiClient!.post('/wallet', data: {
        'chain': 'solana',
        'address': address,
        'label': 'Main Wallet',
      });
      debugPrint('[KeypairManager] Wallet registered on server');
    } catch (e) {
      // 409 = already registered (OK), other errors = best-effort
      debugPrint('[KeypairManager] ensureRegistered: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  /// Delete all wallet keys from secure storage (destructive).
  Future<void> deleteWallet() async {
    _cachedKeyPair = null;
    await _storage.clearWallet();
  }

  /// Clear in-memory keypair cache without touching secure storage.
  /// Called by `WalletLifecycleManager` after idle grace following
  /// app paused/inactive — shrinks the memory-dump attack surface. The next
  /// load call re-reads from secure storage. Phase 2B-1 — empties both
  /// single and multi caches.
  void clearCache() {
    _cachedKeyPair = null;
    _multiCache.clear();
  }

  /// Evict a single multi-wallet entry from cache. Called in the removeWallet
  /// flow — ensures keypairs of permanently removed wallets do not linger in
  /// memory.
  void evictWallet(String walletId) {
    _multiCache.remove(walletId);
  }

  // ---------------------------------------------------------------------------
  // Multi-wallet load (Phase 2B-1)
  // ---------------------------------------------------------------------------

  /// Load a keypair based on a `WalletEntry`.
  ///   - derived: derive on the fly from a BIP44 account index of identity_mnemonic
  ///   - imported: restore from the 32-byte seed at `wallet_secret/<id>`
  ///
  /// After loading, verifies the derive/restore result address matches
  /// `entry.address` (early detection of storage corruption / mnemonic
  /// mismatch). On mismatch, throws [PrimaryIntegrityViolationException] —
  /// guides user through recovery.
  ///
  /// On cache hit, storage is not touched. Evict via `evictWallet(id)` /
  /// `clearCache()`.
  Future<Ed25519HDKeyPair> loadWalletFor(WalletEntry entry) async {
    final cached = _multiCache[entry.id];
    if (cached != null) return cached;

    final keyPair = await _deriveOrRestore(entry);

    final actualAddress = keyPair.publicKey.toBase58();
    if (actualAddress != entry.address) {
      throw PrimaryIntegrityViolationException(
        expectedAddress: entry.address,
        actualAddress: actualAddress,
      );
    }

    _multiCache[entry.id] = keyPair;
    return keyPair;
  }

  Future<Ed25519HDKeyPair> _deriveOrRestore(WalletEntry entry) async {
    if (entry.kind == WalletKind.derived) {
      final mnemonic = await _storage.readMnemonic();
      if (mnemonic == null) {
        throw const IdentityMnemonicMissingException();
      }
      final idx = entry.derivationAccountIndex;
      if (idx == null) {
        // The assertion blocks this case but storage corruption is still possible
        throw const WalletIndexCorruptedException(
          'derived entry missing derivationAccountIndex',
        );
      }
      return DerivationService.deriveWalletKeyPairAt(mnemonic, idx);
    }

    // imported
    final secret = await _storage.readImportedSecret(entry.id);
    if (secret == null) {
      throw WalletSecretMissingException(entry.id, entry.label);
    }
    return DerivationService.keyPairFromSecret(secret);
  }

  // ---------------------------------------------------------------------------
  // Amount conversion (BigInt only — Float/double NEVER)
  // ---------------------------------------------------------------------------

  /// Convert SOL display string to lamports (BigInt).
  /// "1.5" → BigInt(1500000000)
  static BigInt solToLamports(String solAmount) {
    final trimmed = solAmount.trim();
    if (trimmed.isEmpty) return BigInt.zero;

    final parts = trimmed.split('.');
    if (parts.length > 2) {
      throw FormatException('Invalid SOL amount: $solAmount');
    }

    final wholePart =
        parts[0].isEmpty ? BigInt.zero : BigInt.parse(parts[0]);
    final whole = wholePart * BigInt.from(1000000000);

    if (parts.length == 1) return whole;

    var fracStr = parts[1];
    if (fracStr.length > 9) {
      fracStr = fracStr.substring(0, 9);
    } else {
      fracStr = fracStr.padRight(9, '0');
    }

    return whole + BigInt.parse(fracStr);
  }

  /// Convert lamports (BigInt) to SOL display string.
  /// BigInt(1500000000) → "1.5"
  static String lamportsToSol(BigInt lamports) {
    final isNegative = lamports < BigInt.zero;
    final abs = lamports.abs();
    final whole = abs ~/ BigInt.from(1000000000);
    final frac = abs % BigInt.from(1000000000);

    if (frac == BigInt.zero) {
      return '${isNegative ? '-' : ''}$whole';
    }

    var fracStr = frac.toString().padLeft(9, '0');
    fracStr = fracStr.replaceAll(RegExp(r'0+$'), '');
    return '${isNegative ? '-' : ''}$whole.$fracStr';
  }

  /// Convert token display amount to smallest unit (BigInt).
  static BigInt tokenToSmallestUnit(String displayAmount, int decimals) {
    final parts = displayAmount.split('.');
    final integerPart = BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals);
    if (parts.length == 1) return integerPart;

    final decimalStr =
        parts[1].padRight(decimals, '0').substring(0, decimals);
    return integerPart + BigInt.parse(decimalStr);
  }

  /// Convert smallest unit (BigInt) to display string.
  static String smallestUnitToDisplay(BigInt amount, int decimals) {
    final divisor = BigInt.from(10).pow(decimals);
    final integerPart = amount ~/ divisor;
    final remainder = amount % divisor;
    final decimalStr = remainder.toString().padLeft(decimals, '0');
    final trimmed = decimalStr.replaceAll(RegExp(r'0+$'), '');
    if (trimmed.isEmpty) return integerPart.toString();
    return '$integerPart.$trimmed';
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /// Register wallet address with SnowChat server (best-effort).
  Future<void> _registerWithServer(String address) async {
    if (apiClient == null) return;
    try {
      await apiClient!.post('/wallet', data: {
        'chain': 'solana',
        'address': address,
        'label': 'Main Wallet',
      });
    } catch (e) {
      debugPrint('[KeypairManager] Server registration failed: $e');
    }
  }
}

/// Thrown when wallet operations are attempted without initialization.
class WalletNotInitializedException implements Exception {
  @override
  String toString() =>
      'Wallet not initialized. Call createWallet() first.';
}
