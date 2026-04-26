/// @file        balance_provider.dart
/// @description SOL/SPL token balance Riverpod Provider — uses solana
///              package RPC.
///              Multi-Wallet Phase 2.5 (2026-04-25) — fixed H-3 single-source
///              violation. Removed local definitions of
///              secureWalletStorageProvider / keypairManagerProvider
///              (re-export only). walletAddressProvider is now a thin
///              wrapper that follows the active wallet.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation; Multi-Wallet Phase 2.5 H-3 single-source fix)
///
/// @functions
///  - solBalanceProvider: SOL balance (BigInt lamports)
///  - tokenBalancesProvider: SPL token balance list
///  - walletAddressProvider: active wallet address (wallet_list_provider wrapper)
///  - TokenBalance: SPL token balance data class

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/dto.dart';
import 'package:solana/solana.dart';

import '../core/keypair_manager.dart';
import '../rpc/rpc_client_provider.dart';
import 'wallet_list_provider.dart';

// Re-export the canonical providers (single source — wallet_provider.dart).
// External callers (transfer_provider, tensor_providers, etc.) keep their
// existing import path (`providers/balance_provider.dart`) yet still receive
// the single instance — preventing separate-instance bugs from duplicate
// definitions.
export '../wallet_provider.dart'
    show secureWalletStorageProvider, keypairManagerProvider;

// ---------------------------------------------------------------------------
// Active wallet address — single source via wallet_list_provider
// ---------------------------------------------------------------------------

/// Active wallet's Solana address (Base58). null = wallet not initialized
/// OR active id missing from index.
///
/// **History**: Pre-Multi-Wallet this read SecureWalletStorage directly.
/// Since Phase 2.5 it wraps `activeWalletAddressProvider` (sync). Callers
/// can still use `await ref.watch(walletAddressProvider.future)` as before.
final walletAddressProvider = FutureProvider<String?>((ref) async {
  return ref.watch(activeWalletAddressProvider);
});

// ---------------------------------------------------------------------------
// SOL balance
// ---------------------------------------------------------------------------

/// SOL balance in lamports (BigInt). Auto-refreshes when invalidated.
final solBalanceProvider = FutureProvider<BigInt>((ref) async {
  final address = await ref.watch(walletAddressProvider.future);
  if (address == null) return BigInt.zero;

  try {
    final rpc = ref.read(rpcClientProvider);
    final result = await rpc.getBalance(address);
    return BigInt.from(result.value);
  } catch (e) {
    debugPrint('[BalanceProvider] SOL balance fetch failed: $e');
    return BigInt.zero;
  }
});

// ---------------------------------------------------------------------------
// SPL token balances
// ---------------------------------------------------------------------------

/// SPL token balance data.
class TokenBalance {
  final String mint;
  final BigInt rawAmount;
  final int decimals;
  final String symbol;
  final String name;
  final String? logoUrl;

  const TokenBalance({
    required this.mint,
    required this.rawAmount,
    required this.decimals,
    this.symbol = '',
    this.name = '',
    this.logoUrl,
  });

  /// Display-friendly amount string.
  String get displayAmount {
    return KeypairManager.smallestUnitToDisplay(rawAmount, decimals);
  }

  /// Whether balance is zero.
  bool get isZero => rawAmount == BigInt.zero;
}

/// SPL token balances for the current wallet.
final tokenBalancesProvider = FutureProvider<List<TokenBalance>>((ref) async {
  final address = await ref.watch(walletAddressProvider.future);
  if (address == null) return [];

  try {
    final rpc = ref.read(rpcClientProvider);
    final result = await rpc.getTokenAccountsByOwner(
      address,
      const TokenAccountsFilter.byProgramId(TokenProgram.programId),
      encoding: Encoding.jsonParsed,
    );

    final balances = <TokenBalance>[];
    for (final account in result.value) {
      final data = account.account.data;
      if (data is ParsedSplTokenProgramAccountData) {
        final parsed = data.parsed;
        if (parsed is TokenAccountData) {
          final info = parsed.info;
          balances.add(TokenBalance(
            mint: info.mint,
            rawAmount:
                BigInt.tryParse(info.tokenAmount.amount) ?? BigInt.zero,
            decimals: info.tokenAmount.decimals,
          ));
        }
      }
    }

    return balances.where((t) => !t.isZero).toList();
  } catch (e) {
    debugPrint('[BalanceProvider] Token balances fetch failed: $e');
    return [];
  }
});
