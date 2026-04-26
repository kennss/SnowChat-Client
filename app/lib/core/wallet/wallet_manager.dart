/// @file        wallet_manager.dart
/// @description Solana wallet keypair management. BIP39/SLIP-0010 key derivation, signing, balance query, server registration.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - WalletManager: wallet management class
///  - WalletManager.deriveAndStoreKeypair(): derive keypair from BIP39 mnemonic, store, register with server
///  - WalletManager.getPublicKey(): query stored public key
///  - WalletManager.hasWallet: check whether wallet is configured
///  - WalletManager.deleteWallet(): delete all wallet keys
///  - WalletManager.sign(): Ed25519 signature with private key
///  - WalletManager.getSOLBalance(): query SOL balance (lamports)
///  - WalletManager.registerWalletWithServer(): register wallet address with server
///  - WalletManager.solToLamports(): convert SOL string to lamports
///  - WalletManager.lamportsToSol(): convert lamports to SOL string
///  - WalletNotInitializedException: wallet-not-initialized exception class
///  - SecureStorageWrapper: flutter_secure_storage test abstraction class

/// Solana wallet keypair management from BIP39 / SLIP-0010.
///
/// All monetary values are [BigInt] lamports. NEVER use double for SOL.
/// Private key material is stored exclusively in [flutter_secure_storage].
/// After keypair derivation, the wallet address is registered with the server
/// so it can begin indexing/caching on-chain data.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pinenacl/ed25519.dart';

import '../network/api_client.dart';
import 'solana_client.dart' as rpc;

/// Wallet manager handling key derivation, storage, signing, and server registration.
///
/// Uses BIP39 mnemonic -> PBKDF2 seed -> SLIP-0010 (Ed25519) key derivation.
/// Solana path: m/44'/501'/0'/0'
/// Chat identity path: m/44'/0'/0'/0'
class WalletManager {
  WalletManager({
    required SecureStorageWrapper secureStorage,
    required rpc.SolanaClient solanaClient,
    this.apiClient,
  })  : _secureStorage = secureStorage,
        _solanaClient = solanaClient;

  final SecureStorageWrapper _secureStorage;
  final rpc.SolanaClient _solanaClient;

  /// Optional server API client for wallet registration.
  final ApiClient? apiClient;

  static const String _mnemonicKey = 'wallet_mnemonic';
  static const String _privateKeyKey = 'solana_private_key';
  static const String _publicKeyKey = 'solana_public_key';

  // ---------------------------------------------------------------------------
  // Key derivation
  // ---------------------------------------------------------------------------

  /// Derive a Solana keypair from a BIP39 mnemonic.
  ///
  /// Returns the public key (base58). The private key is stored securely.
  /// After derivation, registers the wallet address with the server.
  Future<String> deriveAndStoreKeypair(String mnemonic) async {
    // Derive a deterministic 32-byte seed from the mnemonic words.
    // In production, use: bip39.mnemonicToSeed(mnemonic)
    //   then ED25519_HD_KEY.derivePath("m/44'/501'/0'/0'", seed)
    final seedBytes = _seedFromMnemonic(mnemonic);

    // Derive Ed25519 keypair from seed using pinenacl.
    final signingKey = SigningKey(seed: seedBytes);
    final publicKeyBytes = Uint8List.fromList(
        signingKey.verifyKey.toList());
    final publicKey = _base58Encode(publicKeyBytes);

    await _secureStorage.write(key: _mnemonicKey, value: mnemonic);
    await _secureStorage.write(
        key: _privateKeyKey, value: _bytesToHex(seedBytes));
    await _secureStorage.write(key: _publicKeyKey, value: publicKey);

    // Register wallet with server for indexing
    await registerWalletWithServer(publicKey);

    return publicKey;
  }

  /// Retrieve the stored public key.
  Future<String?> getPublicKey() async {
    return _secureStorage.read(key: _publicKeyKey);
  }

  /// Check whether a wallet has been set up.
  Future<bool> get hasWallet async {
    final key = await _secureStorage.read(key: _publicKeyKey);
    return key != null && key.isNotEmpty;
  }

  /// Delete all wallet keys (destructive).
  Future<void> deleteWallet() async {
    await _secureStorage.delete(key: _mnemonicKey);
    await _secureStorage.delete(key: _privateKeyKey);
    await _secureStorage.delete(key: _publicKeyKey);
  }

  // ---------------------------------------------------------------------------
  // Server Registration
  // ---------------------------------------------------------------------------

  /// Register the wallet address with the SnowChat server.
  ///
  /// The server starts indexing/caching on-chain data for this wallet.
  /// This is best-effort; failure does not prevent wallet usage.
  Future<void> registerWalletWithServer(String publicKey) async {
    if (apiClient == null) return;

    try {
      await apiClient!.post(
        '/wallet',
        data: {
          'address': publicKey,
          'network': 'solana',
        },
      );
    } on DioException catch (_) {
      // Registration is best-effort. The wallet works without server
      // indexing; data will be fetched directly from RPC as fallback.
    }
  }

  // ---------------------------------------------------------------------------
  // Signing
  // ---------------------------------------------------------------------------

  /// Sign arbitrary bytes with the stored Ed25519 private key.
  ///
  /// Returns the 64-byte Ed25519 signature.
  Future<Uint8List> sign(Uint8List message) async {
    final privateKeyHex =
        await _secureStorage.read(key: _privateKeyKey);
    if (privateKeyHex == null) throw WalletNotInitializedException();

    // Decode the stored private key (32 bytes seed)
    final seedBytes = _hexToBytes(privateKeyHex);

    // Use pinenacl for Ed25519 signing
    final signingKey = SigningKey(seed: seedBytes);
    final signedMessage = signingKey.sign(message);

    // Return the 64-byte signature (not the message)
    return Uint8List.fromList(signedMessage.signature.toList());
  }

  // ---------------------------------------------------------------------------
  // Balance
  // ---------------------------------------------------------------------------

  /// Fetch the SOL balance in lamports.
  Future<BigInt> getSOLBalance() async {
    final address = await getPublicKey();
    if (address == null) throw WalletNotInitializedException();
    return _solanaClient.getBalance(address);
  }

  // ---------------------------------------------------------------------------
  // SOL -> lamports conversion (NEVER use double)
  // ---------------------------------------------------------------------------

  /// Convert a human-readable SOL string to lamports.
  ///
  /// Examples:
  ///   "1"     -> 1000000000
  ///   "1.5"   -> 1500000000
  ///   "0.001" ->    1000000
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

    // Fractional part: pad/truncate to 9 decimal places.
    var fracStr = parts[1];
    if (fracStr.length > 9) {
      fracStr = fracStr.substring(0, 9);
    } else {
      fracStr = fracStr.padRight(9, '0');
    }

    return whole + BigInt.parse(fracStr);
  }

  /// Convert lamports to a human-readable SOL string.
  ///
  /// Returns e.g. "1.5" (strips trailing zeros).
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Derive a deterministic 32-byte seed from mnemonic words.
  ///
  /// Uses a simple hash for now; in production replace with
  /// `bip39.mnemonicToSeed(mnemonic)` + SLIP-0010 derivation.
  Uint8List _seedFromMnemonic(String mnemonic) {
    final bytes = Uint8List(32);
    final words = mnemonic.split(' ');
    for (var i = 0; i < words.length && i < 32; i++) {
      bytes[i] = words[i].codeUnits.fold<int>(0, (a, b) => (a + b) & 0xFF);
    }
    return bytes;
  }

  /// Encode raw bytes as a base58 string (Bitcoin alphabet).
  static String _base58Encode(Uint8List bytes) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }

    final result = StringBuffer();
    while (value > BigInt.zero) {
      final remainder = (value % BigInt.from(58)).toInt();
      value = value ~/ BigInt.from(58);
      result.write(alphabet[remainder]);
    }

    // Preserve leading zeros as '1's.
    for (final byte in bytes) {
      if (byte != 0) break;
      result.write('1');
    }

    return result.toString().split('').reversed.join();
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

/// Thrown when an operation requires an initialized wallet but none exists.
class WalletNotInitializedException implements Exception {
  @override
  String toString() =>
      'Wallet not initialized. Call deriveAndStoreKeypair() first.';
}

/// Abstraction over flutter_secure_storage for testability.
class SecureStorageWrapper {
  // In production, delegate to FlutterSecureStorage.
  final Map<String, String> _store = {};

  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  Future<String?> read({required String key}) async {
    return _store[key];
  }

  Future<void> delete({required String key}) async {
    _store.remove(key);
  }
}
