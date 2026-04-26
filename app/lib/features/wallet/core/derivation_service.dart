/// @file        derivation_service.dart
/// @description SLIP-0010 key derivation service — uses Ed25519HDKeyPair from
///              the solana package. Phantom-compatible BIP44 path
///              `m/44'/501'/{account}'/0'`.
///              Multi-Wallet Phase 1 (2026-04-25) — extended from fixed
///              account 0 to arbitrary account index. Also supports deriving
///              a keypair from an imported wallet's raw seed.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation; Multi-Wallet Phase 1 extended fixed account 0 to arbitrary account index, plus imported raw-seed support)
///
/// @functions
///  - DerivationService.walletDerivationPath: default (account 0) path constant
///  - DerivationService.walletDerivationPathFor(account): per-account path
///  - DerivationService.deriveWalletKeyPair(mnemonic): account 0 keypair (legacy)
///  - DerivationService.deriveWalletKeyPairAt(mnemonic, account): arbitrary account
///  - DerivationService.deriveWalletAddress(mnemonic): account 0 address (legacy)
///  - DerivationService.deriveWalletAddressAt(mnemonic, account): arbitrary account
///  - DerivationService.keyPairFromSecret(seed32): imported 32-byte seed → keypair

library;

import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:solana/solana.dart';

/// SLIP-0010 key derivation for Solana wallets.
///
/// Phantom-compatible derivation path: `m/44'/501'/{account}'/0'` where
/// account index 0 = Primary, 1+ = derived sub-wallets.
class DerivationService {
  /// Phantom/Solflare compatible HD path for the Primary (account 0).
  /// Even after Multi-Wallet, Primary is always account 0 — never change.
  static const walletDerivationPath = "m/44'/501'/0'/0'";

  /// Phantom-compatible path at an arbitrary account index.
  /// e.g. 0 → `m/44'/501'/0'/0'` (Primary), 1 → `m/44'/501'/1'/0'`.
  static String walletDerivationPathFor(int accountIndex) {
    if (accountIndex < 0) {
      throw ArgumentError('accountIndex must be >= 0 (got $accountIndex)');
    }
    return "m/44'/501'/$accountIndex'/0'";
  }

  // ---------------------------------------------------------------------------
  // Legacy single-account API (Primary only)
  // ---------------------------------------------------------------------------

  /// Derive Solana wallet keypair at account 0 (Primary).
  ///
  /// Post-Multi-Wallet, new code should use [deriveWalletKeyPairAt].
  /// This method is preserved for backward compat.
  static Future<Ed25519HDKeyPair> deriveWalletKeyPair(String mnemonic) =>
      deriveWalletKeyPairAt(mnemonic, 0);

  /// Get the Solana wallet address (Base58) at account 0.
  /// Also for backward compat. New code should use [deriveWalletAddressAt].
  static Future<String> deriveWalletAddress(String mnemonic) =>
      deriveWalletAddressAt(mnemonic, 0);

  // ---------------------------------------------------------------------------
  // Multi-Wallet API (account index parameterized)
  // ---------------------------------------------------------------------------

  /// Derive a Solana wallet keypair at the given BIP44 account index.
  ///
  /// account 0 = Primary (first wallet of the same mnemonic as SnowChat identity).
  /// account 1+ = derived sub-wallets.
  ///
  /// Same (mnemonic, accountIndex) always returns the same keypair — which is
  /// why derived wallet secrets don't need separate storage.
  static Future<Ed25519HDKeyPair> deriveWalletKeyPairAt(
    String mnemonic,
    int accountIndex,
  ) async {
    if (accountIndex < 0) {
      throw ArgumentError('accountIndex must be >= 0 (got $accountIndex)');
    }
    final seed = bip39.mnemonicToSeed(mnemonic);
    return Ed25519HDKeyPair.fromSeedWithHdPath(
      seed: seed,
      hdPath: walletDerivationPathFor(accountIndex),
    );
  }

  /// Get the Solana wallet address (Base58) at the given account index.
  /// Called by Migration / WalletIndexNotifier when adding a new derived sub.
  static Future<String> deriveWalletAddressAt(
    String mnemonic,
    int accountIndex,
  ) async {
    final keyPair = await deriveWalletKeyPairAt(mnemonic, accountIndex);
    return keyPair.publicKey.toBase58();
  }

  // ---------------------------------------------------------------------------
  // Imported wallet (raw seed) — no derivation, direct construction
  // ---------------------------------------------------------------------------

  /// Build an [Ed25519HDKeyPair] from a raw 32-byte seed.
  /// Used in the imported-wallet flow — the secret is an externally imported
  /// key, not the result of mnemonic derivation.
  ///
  /// [seed] must be exactly 32 bytes. For 64-byte form (Solana CLI's
  /// concatenated private+public key), use only the first 32 bytes (caller
  /// should trim ahead of time — this method is strict 32-byte).
  static Future<Ed25519HDKeyPair> keyPairFromSecret(Uint8List seed) {
    if (seed.length != 32) {
      throw ArgumentError(
        'seed must be exactly 32 bytes (got ${seed.length})',
      );
    }
    return Ed25519HDKeyPair.fromPrivateKeyBytes(privateKey: seed);
  }
}
