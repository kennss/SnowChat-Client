/// @file        wallet_provider.dart
/// @description Wallet state management Riverpod Provider — based on the
///              solana package (Phase 6 rebuild).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - walletProvider: WalletNotifier StateNotifierProvider
///  - WalletState: wallet state data class
///  - WalletNotifier: wallet state management (init, balance, SOL transfer, SPL transfer, airdrop)
///  - transactionHistoryProvider: transaction history Provider
///  - selectedTokenProvider: selected-token state Provider

import 'dart:async';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/dto.dart' hide TransactionStatus;
import 'package:solana/solana.dart' as sol;

import '../../app/providers.dart';
import '../../core/network/socket_manager.dart';
import '../../core/wallet/solana_client.dart' as legacy;
import '../../core/wallet/solana_config.dart' as legacy_config;
import '../../core/wallet/token_service.dart';
import '../../core/wallet/transaction_builder.dart';
import '../../core/wallet/wallet_manager.dart' show WalletManager, SecureStorageWrapper;
import '../../shared/models/wallet_models.dart';
import 'address_book/address_book_repository.dart';
import 'cache/wallet_balance_cache.dart';
import 'core/derivation_service.dart';
import 'core/keypair_manager.dart';
import 'core/secure_wallet_storage.dart';
import 'core/wallet_id_generator.dart';
import 'core/wallet_send_lock.dart';
import 'core/wallet_v2_migration.dart';
import 'models/wallet_account_model.dart';
import 'models/wallet_index.dart';
import 'models/wallet_index_exceptions.dart';
import 'naming/sns_resolver.dart';
import 'providers/wallet_list_provider.dart';
import 'rpc/rpc_client_provider.dart' hide solanaNetworkProvider;
import 'rpc/rpc_config.dart';
import 'price/price_service.dart';
import 'token/token_list_service.dart';
import 'transaction/compute_budget_helper.dart';
import 'transaction/fee_estimator.dart';
import 'transaction/priority_fee_estimator.dart';
import 'transaction/transaction_parser.dart';
import 'transaction/transaction_simulator.dart';
import 'transaction/v0_send_helper.dart';
import 'transaction/sol_transfer_service.dart';
import 'transaction/spl_transfer_service.dart';

// ---------------------------------------------------------------------------
// Core service providers
// ---------------------------------------------------------------------------

final secureWalletStorageProvider = Provider<SecureWalletStorage>((ref) {
  return SecureWalletStorage();
});

final keypairManagerProvider = Provider<KeypairManager>((ref) {
  return KeypairManager(
    storage: ref.read(secureWalletStorageProvider),
    apiClient: ref.read(apiClientProvider),
  );
});

/// Multi-Wallet Phase 1.5 — per-wallet send lock (protects in-flight tx).
/// Checked by removeWallet / clearCache. WalletLifecycleManager's
/// shouldDefer callback uses `hasAnyActive` to decide whether to block idle evict.
final walletSendLockProvider = Provider<WalletSendLock>((ref) {
  return WalletSendLock();
});

/// Multi-Wallet Phase 3A — v1 → v2 schema migration orchestrator.
/// Called by `WalletNotifier.initialize()` / `createFromMnemonic()`.
/// Idempotent — every call after the first returns the cached future
/// immediately. Force-rerun via `ref.invalidate` (pattern right after
/// createFromMnemonic).
///
/// **Phase 3 fix**: identityReader reads via IdentityManager.getMnemonic
/// from the `identity_mnemonic` key (the canonical single source).
/// SecureWalletStorage.readMnemonic uses a separate `wallet_mnemonic`
/// key, so existing users (right after V1 onboarding) had it empty,
/// causing a false-positive mismatch branch.
final walletV2MigrationProvider = Provider<WalletV2Migration>((ref) {
  final storage = ref.read(secureWalletStorageProvider);
  final identityManager = ref.read(identityManagerProvider);
  return WalletV2Migration(
    storage: storage,
    identityReader: () async {
      final words = await identityManager.getMnemonic();
      if (words == null || words.isEmpty) return null;
      return words.join(' ');
    },
  );
});

// Legacy providers (kept for NFT module compatibility until NFT migration)
final secureStorageProvider = Provider<SecureStorageWrapper>((ref) {
  return SecureStorageWrapper();
});

final solanaClientProvider = Provider<legacy.SolanaClient>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  legacy_config.SolanaConfig.currentNetwork =
      network == SolanaNetwork.devnet
          ? legacy_config.SolanaNetwork.devnet
          : legacy_config.SolanaNetwork.mainnet;
  return legacy.SolanaClient();
});

final walletManagerProvider = Provider<WalletManager>((ref) {
  final client = ref.read(solanaClientProvider);
  return WalletManager(
    secureStorage: ref.read(secureStorageProvider),
    solanaClient: client,
  );
});

final tokenServiceProvider = Provider<TokenService>((ref) {
  final client = ref.read(solanaClientProvider);
  return TokenService(solanaClient: client);
});

final transactionBuilderProvider = Provider<TransactionBuilder>((ref) {
  final client = ref.read(solanaClientProvider);
  return TransactionBuilder(
    solanaClient: client,
    walletManager: ref.read(walletManagerProvider),
  );
});

// New Phase 6 providers
final newSolanaClientProvider = Provider<sol.SolanaClient>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  return sol.SolanaClient(
    rpcUrl: Uri.parse(network.rpcUrl),
    websocketUrl: Uri.parse(network.wsUrl),
  );
});

// ---------------------------------------------------------------------------
// Phase 6.1 transaction pipeline providers
// ---------------------------------------------------------------------------

final priorityFeeEstimatorProvider = Provider<PriorityFeeEstimator>((ref) {
  final network = ref.watch(solanaNetworkProvider);
  return PriorityFeeEstimator(rpcUrl: network.rpcUrl);
});

final feeEstimatorProvider = Provider<FeeEstimator>((ref) {
  return FeeEstimator(
    rpcClient: ref.read(rpcClientProvider),
    priorityEstimator: ref.read(priorityFeeEstimatorProvider),
  );
});

final transactionSimulatorProvider = Provider<TransactionSimulator>((ref) {
  return TransactionSimulator(rpcClient: ref.read(rpcClientProvider));
});

final v0SendHelperProvider = Provider<V0SendHelper>((ref) {
  return V0SendHelper(solanaClient: ref.read(newSolanaClientProvider));
});

/// Step 2 — drift `wallet_balances` persistent cache + in-memory L1.
final walletBalanceCacheProvider = Provider<WalletBalanceCache>((ref) {
  return DriftWalletBalanceCache(database: ref.read(snowDatabaseProvider));
});

/// Step 2 — transaction classifier (drift `wallet_tx_cache` + in-memory 200 entries).
final transactionParserProvider = Provider<TransactionParser>((ref) {
  return TransactionParser(
    rpcClient: ref.read(rpcClientProvider),
    txCacheDao: ref.read(snowDatabaseProvider).walletTxCacheDao,
  );
});

/// Step 2 — Bonfida `.sol` domain resolver (1-hour in-memory cache).
final snsResolverProvider = Provider<SnsResolver>((ref) {
  final r = SnsResolver();
  ref.onDispose(r.close);
  return r;
});

/// Step 2 — Address book Repository (drift `wallet_address_book`).
final addressBookRepositoryProvider = Provider<AddressBookRepository>((ref) {
  return AddressBookRepository(
    ref.read(snowDatabaseProvider).walletAddressBookDao,
  );
});

final solTransferServiceProvider = Provider<SolTransferService>((ref) {
  return SolTransferService(
    keypairManager: ref.read(keypairManagerProvider),
    feeEstimator: ref.read(feeEstimatorProvider),
    simulator: ref.read(transactionSimulatorProvider),
    v0Sender: ref.read(v0SendHelperProvider),
  );
});

final splTransferServiceProvider = Provider<SplTransferService>((ref) {
  return SplTransferService(
    solanaClient: ref.read(newSolanaClientProvider),
    keypairManager: ref.read(keypairManagerProvider),
    feeEstimator: ref.read(feeEstimatorProvider),
    simulator: ref.read(transactionSimulatorProvider),
    v0Sender: ref.read(v0SendHelperProvider),
  );
});

// ---------------------------------------------------------------------------
// Wallet state
// ---------------------------------------------------------------------------

@immutable
class WalletState {
  const WalletState({
    this.balance,
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.publicKey,
    this.lastTxSignature,
  });

  final WalletBalance? balance;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final String? publicKey;
  final String? lastTxSignature;

  bool get hasWallet => publicKey != null;

  WalletState copyWith({
    WalletBalance? balance,
    bool? isLoading,
    bool? isSending,
    String? error,
    String? publicKey,
    String? lastTxSignature,
  }) {
    return WalletState(
      balance: balance ?? this.balance,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
      publicKey: publicKey ?? this.publicKey,
      lastTxSignature: lastTxSignature ?? this.lastTxSignature,
    );
  }
}

// ---------------------------------------------------------------------------
// Wallet notifier
// ---------------------------------------------------------------------------

class WalletNotifier extends StateNotifier<WalletState> {
  WalletNotifier(
    this._keypairManager,
    this._rpc,
    this._solTransfer,
    this._splTransfer,
    this._priceService,
    this._tokenListService,
    this._balanceCache,
    this._txParser,
    this._ref,
  ) : super(const WalletState()) {
    _listenToWalletUpdates();
  }

  final KeypairManager _keypairManager;
  final sol.RpcClient _rpc;
  final SplTransferService _splTransfer;
  final PriceService _priceService;
  final TokenListService _tokenListService;
  final SolTransferService _solTransfer;
  final WalletBalanceCache _balanceCache;
  final TransactionParser _txParser;
  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _walletUpdateSub;

  /// Phase 6.1 §3.1 — cache TTL. RPC call is skipped when re-entered within 30s.
  static const _balanceCacheTtl = Duration(seconds: 30);

  // -------------------------------------------------------------------------
  // Initialization
  // -------------------------------------------------------------------------

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);
    try {
      // Phase 3A — Multi-Wallet bootstrap. fresh install / pre-onboarding
      // users pass through as freshInstall without issue (publicKey stays null).
      BootstrapOutcome? outcome;
      try {
        outcome =
            await _ref.read(walletV2MigrationProvider).bootstrap();
      } catch (e, st) {
        // bootstrap itself threw — at least show legacy publicKey (fix C safety net).
        debugPrint('[Wallet] bootstrap threw: $e\n$st');
      }

      if (outcome == BootstrapOutcome.freshInstall) {
        state = state.copyWith(isLoading: false);
        return;
      }
      if (outcome == BootstrapOutcome.primaryIntegrityViolated) {
        // Fall back to legacy publicKey — at least balance can be checked
        final legacy = await _keypairManager.getAddress();
        state = state.copyWith(
          publicKey: legacy,
          isLoading: false,
          error: 'Main Wallet integrity check failed. '
              'Restore your recovery phrase from Settings.',
        );
        if (legacy != null) {
          await refreshBalance();
        }
        return;
      }

      // walletIndex + active hydrate — legacy fallback on failure (safety net)
      String? address;
      try {
        final idx = await _ref.read(walletIndexProvider.future);
        await _ref.read(activeWalletControllerProvider).hydrate();
        final activeId = _ref.read(activeWalletIdProvider) ?? idx.primaryId;
        final entry = idx.findById(activeId) ?? idx.primaryEntry;
        // Phase 5 critical fix — make keypair sign based on the entry
        _keypairManager.setActive(entry);
        address = entry.address;
      } catch (e, st) {
        debugPrint('[Wallet] walletIndex load failed → legacy fallback: '
            '$e\n$st');
        _keypairManager.setActive(null);
        address = await _keypairManager.getAddress();
      }

      if (address == null) {
        // bootstrap incomplete + no legacy address — must go to onboarding
        state = state.copyWith(isLoading: false);
        return;
      }

      state = state.copyWith(publicKey: address, isLoading: false);

      await _keypairManager.ensureRegistered();
      await refreshBalance();
    } catch (e) {
      // Final safety net — try legacy publicKey at least
      try {
        final legacy = await _keypairManager.getAddress();
        if (legacy != null) {
          state = state.copyWith(publicKey: legacy, isLoading: false);
          await refreshBalance();
          return;
        }
      } catch (_) {/* swallow */}
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> createFromMnemonic(String mnemonic) async {
    state = state.copyWith(isLoading: true);
    try {
      final address = await _keypairManager.createWallet(mnemonic);

      // Phase 3A — force v2 schema migration immediately after saving the new mnemonic.
      // initialize() may have a cached freshInstall, so invalidate.
      _ref.invalidate(walletV2MigrationProvider);
      await _ref.read(walletV2MigrationProvider).bootstrap();
      _ref.invalidate(walletIndexProvider);
      final idx = await _ref.read(walletIndexProvider.future);
      await _ref.read(activeWalletControllerProvider).hydrate();

      // Phase 5 critical fix — decide keypair active entry (usually primary)
      final activeId = _ref.read(activeWalletIdProvider) ?? idx.primaryId;
      final entry = idx.findById(activeId) ?? idx.primaryEntry;
      _keypairManager.setActive(entry);

      state = state.copyWith(publicKey: address, isLoading: false);
      // Non-blocking balance refresh — don't block onboarding if RPC is slow
      refreshBalance().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[Wallet] Balance refresh timed out (non-fatal)');
        },
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // -------------------------------------------------------------------------
  // Balance refresh (real RPC via solana package)
  // -------------------------------------------------------------------------

  Future<void> refreshBalance({bool force = false}) async {
    final pubKey = state.publicKey;
    if (pubKey == null) return;

    // Phase 6.1 §3.1 — cache hit (force=false)
    if (!force) {
      final cached = await _balanceCache.read(pubKey);
      if (cached != null && cached.isNotEmpty && cached.first.isFresh(_balanceCacheTtl)) {
        // Cache hit — show immediately in UI (skip RPC)
        state = state.copyWith(
          balance: _walletBalanceFromCache(cached),
          isLoading: false,
        );
        return;
      }
      // Even stale cache: paint first
      if (cached != null && cached.isNotEmpty) {
        state = state.copyWith(
          balance: _walletBalanceFromCache(cached),
          isLoading: true,
        );
      } else {
        state = state.copyWith(isLoading: true);
      }
    } else {
      state = state.copyWith(isLoading: true);
    }
    try {
      // SOL balance
      final solResult = await _rpc.getBalance(pubKey);
      final solLamports = BigInt.from(solResult.value);

      // SPL token balances
      final splTokens = await _fetchSplTokens(pubKey);

      // Fetch prices for all tokens
      final allMints = [
        'So11111111111111111111111111111111', // SOL native mint
        ...splTokens.map((t) => t.mint),
      ];
      final prices = await _priceService.getTokenPrices(allMints);
      final solPrice = prices['So11111111111111111111111111111111'] ?? 0.0;

      // Build SOL token info with USD value
      final solUsdCents = _calcUsdCents(solLamports, 9, solPrice);
      final solToken = TokenInfo(
        mint: 'SOL',
        symbol: 'SOL',
        name: 'Solana',
        decimals: 9,
        balanceLamports: solLamports,
        usdValueCents: solUsdCents,
      );

      // Enrich SPL tokens with metadata + prices
      final tokenMeta = await _tokenListService.getTokenInfoBatch(
          splTokens.map((t) => t.mint).toList());
      final enrichedTokens = splTokens.map((t) {
        final meta = tokenMeta[t.mint];
        final price = prices[t.mint] ?? 0.0;
        return TokenInfo(
          mint: t.mint,
          symbol: meta?.symbol ?? t.symbol,
          name: meta?.name ?? t.name,
          decimals: t.decimals,
          balanceLamports: t.balanceLamports,
          usdValueCents: _calcUsdCents(t.balanceLamports, t.decimals, price),
          logoUrl: meta?.logoUrl,
        );
      }).toList();

      final allTokens = [solToken, ...enrichedTokens];
      final totalUsd = allTokens.fold<BigInt>(
          BigInt.zero, (sum, t) => sum + t.usdValueCents);

      final newBalance = WalletBalance(
        totalUsdValue: totalUsd,
        changePercent24h: 0,
        tokens: allTokens,
      );
      state = state.copyWith(balance: newBalance, isLoading: false);

      // Phase 6.1 §3.1 — persist RPC result to drift cache
      try {
        await _balanceCache.write(
          pubKey,
          DriftWalletBalanceCache.fromWalletBalance(newBalance),
        );
      } catch (e) {
        debugPrint('[Wallet] balance cache write failed: $e');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Phase 6.1.1 — apply WS-push SOL lamports to state immediately.
  /// Espresso Cash pattern: treat the accountSubscribe push's Account.lamports as authoritative.
  /// No extra RPC call → race-free.
  void applyLiveSolBalance(BigInt newLamports) {
    final bal = state.balance;
    if (bal == null) return;
    final tokens = [...bal.tokens];
    final idx = tokens.indexWhere((t) => t.mint == 'SOL');
    if (idx < 0) return;
    final old = tokens[idx];
    if (old.balanceLamports == newLamports) return;
    final newUsd = old.balanceLamports == BigInt.zero
        ? old.usdValueCents
        : (old.usdValueCents * newLamports) ~/ old.balanceLamports;
    tokens[idx] = TokenInfo(
      mint: old.mint,
      symbol: old.symbol,
      name: old.name,
      decimals: old.decimals,
      balanceLamports: newLamports,
      usdValueCents: newUsd,
      logoUrl: old.logoUrl,
      changePercent24h: old.changePercent24h,
    );
    final newTotal =
        tokens.fold<BigInt>(BigInt.zero, (s, t) => s + t.usdValueCents);
    state = state.copyWith(
      balance: bal.copyWith(tokens: tokens, totalUsdValue: newTotal),
    );
    debugPrint('[Wallet] applyLiveSolBalance: $newLamports lamports');
  }

  /// Apply SPL token amount push. Patches per-mint directly.
  void applyLiveSplBalance(String mint, BigInt newRawAmount) {
    final bal = state.balance;
    if (bal == null) return;
    final tokens = [...bal.tokens];
    final idx = tokens.indexWhere((t) => t.mint == mint);
    if (idx < 0) {
      // New token (first deposit) — needs full refresh to also fetch metadata
      refreshBalance(force: true);
      return;
    }
    final old = tokens[idx];
    if (old.balanceLamports == newRawAmount) return;
    final newUsd = old.balanceLamports == BigInt.zero
        ? old.usdValueCents
        : (old.usdValueCents * newRawAmount) ~/ old.balanceLamports;
    tokens[idx] = TokenInfo(
      mint: old.mint,
      symbol: old.symbol,
      name: old.name,
      decimals: old.decimals,
      balanceLamports: newRawAmount,
      usdValueCents: newUsd,
      logoUrl: old.logoUrl,
      changePercent24h: old.changePercent24h,
    );
    final newTotal =
        tokens.fold<BigInt>(BigInt.zero, (s, t) => s + t.usdValueCents);
    state = state.copyWith(
      balance: bal.copyWith(tokens: tokens, totalUsdValue: newTotal),
    );
    debugPrint('[Wallet] applyLiveSplBalance: $mint=$newRawAmount');
  }

  /// Cache entry → WalletBalance UI model (no USD/price info; show balance immediately).
  WalletBalance _walletBalanceFromCache(List<CachedBalanceEntry> entries) {
    final tokens = entries.map((e) {
      final mint = e.mintAddress == 'native' ? 'SOL' : e.mintAddress;
      return TokenInfo(
        mint: mint,
        symbol: e.symbol,
        name: e.name ?? e.symbol,
        decimals: e.decimals,
        balanceLamports: e.rawAmount,
        usdValueCents: BigInt.zero,
        logoUrl: e.logoUrl,
      );
    }).toList();
    return WalletBalance(
      totalUsdValue: BigInt.zero,
      changePercent24h: 0,
      tokens: tokens,
    );
  }

  Future<List<TokenInfo>> _fetchSplTokens(String pubKey) async {
    try {
      final result = await _rpc.getTokenAccountsByOwner(
        pubKey,
        const TokenAccountsFilter.byProgramId(sol.TokenProgram.programId),
        encoding: Encoding.jsonParsed,
      );

      final tokens = <TokenInfo>[];
      for (final account in result.value) {
        final data = account.account.data;
        if (data is ParsedSplTokenProgramAccountData) {
          final parsed = data.parsed;
          if (parsed is TokenAccountData) {
            final info = parsed.info;
            final rawAmount =
                BigInt.tryParse(info.tokenAmount.amount) ?? BigInt.zero;
            if (rawAmount > BigInt.zero) {
              tokens.add(TokenInfo(
                mint: info.mint,
                symbol: '', // Token list lookup in future phase
                name: info.mint.substring(0, 8),
                decimals: info.tokenAmount.decimals,
                balanceLamports: rawAmount,
                usdValueCents: BigInt.zero,
              ));
            }
          }
        }
      }
      return tokens;
    } catch (e) {
      debugPrint('[Wallet] SPL token fetch failed: $e');
      return [];
    }
  }

  /// Calculate USD value in cents from raw amount + price.
  /// Uses double ONLY for this display calculation — never for amount arithmetic.
  static BigInt _calcUsdCents(BigInt rawAmount, int decimals, double priceUsd) {
    if (priceUsd <= 0) return BigInt.zero;
    final divisor = BigInt.from(10).pow(decimals);
    final whole = rawAmount ~/ divisor;
    final frac = rawAmount % divisor;
    // Convert to USD cents: (whole + frac/divisor) * price * 100
    final wholeCents = (whole.toDouble() * priceUsd * 100).round();
    final fracCents =
        (frac.toDouble() / divisor.toDouble() * priceUsd * 100).round();
    return BigInt.from(wholeCents + fracCents);
  }

  // -------------------------------------------------------------------------
  // Send SOL
  // -------------------------------------------------------------------------

  Future<String> sendSOL({
    required String toAddress,
    required BigInt lamports,
    PriorityLevel level = PriorityLevel.normal,
    bool forceSendOnTransientSimError = false,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final sig = await _solTransfer.transferSol(
        recipientAddress: toAddress,
        lamports: lamports,
        level: level,
        forceSendOnTransientSimError: forceSendOnTransientSimError,
      );
      state = state.copyWith(isSending: false, lastTxSignature: sig);
      await refreshBalance();
      return sig;
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
      rethrow;
    }
  }

  /// Fee preview for SOL transfer (called from the UI preview sheet).
  Future<FeeEstimate> previewSolFee({
    required String toAddress,
    required BigInt lamports,
    PriorityLevel level = PriorityLevel.normal,
  }) {
    return _solTransfer.estimateFee(
      recipientAddress: toAddress,
      lamports: lamports,
      level: level,
    );
  }

  // -------------------------------------------------------------------------
  // Send SPL Token (placeholder — Day 8-9)
  // -------------------------------------------------------------------------

  Future<String> sendSPLToken({
    required String toAddress,
    required String tokenMint,
    required BigInt amount,
    required int decimals,
    PriorityLevel level = PriorityLevel.normal,
    bool forceSendOnTransientSimError = false,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final sig = await _splTransfer.transferToken(
        recipientAddress: toAddress,
        mintAddress: tokenMint,
        amount: amount,
        level: level,
        forceSendOnTransientSimError: forceSendOnTransientSimError,
      );
      state = state.copyWith(isSending: false, lastTxSignature: sig);
      await refreshBalance();
      return sig;
    } catch (e) {
      state = state.copyWith(isSending: false, error: e.toString());
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Airdrop (Devnet only)
  // -------------------------------------------------------------------------

  Future<String> requestAirdrop({BigInt? lamports}) async {
    final network = _ref.read(solanaNetworkProvider);
    if (network != SolanaNetwork.devnet) {
      throw StateError('Airdrop is only available on Devnet');
    }

    final pubKey = state.publicKey;
    if (pubKey == null) throw WalletNotInitializedException();

    state = state.copyWith(isLoading: true);
    try {
      // Public api.devnet.solana.com requestAirdrop has very tight IP
      // rate-limits, so direct client calls almost always fail.
      // The server proxy handles it reliably via Helius devnet RPC.
      final api = _ref.read(apiClientProvider);
      final amount = lamports ?? BigInt.from(1000000000);
      final solAmount = amount.toDouble() / 1000000000;
      final response = await api.post(
        '/wallet/airdrop',
        data: {'address': pubKey, 'sol': solAmount},
      );

      final data = response.data;
      final sig = data is Map ? data['signature'] as String? : null;
      if (sig == null || sig.isEmpty) {
        throw StateError('Airdrop response missing signature');
      }

      state = state.copyWith(isLoading: false, lastTxSignature: sig);
      await Future<void>.delayed(const Duration(seconds: 2));
      await refreshBalance();
      return sig;
    } on DioException catch (e) {
      final body = e.response?.data;
      String msg;
      if (body is Map && body['error'] is Map) {
        final code = (body['error'] as Map)['code'];
        final message = (body['error'] as Map)['message'];
        if (code == 'RATE_LIMITED') {
          msg = '$message';
        } else if (code == 'FAUCET_BUSY') {
          msg = 'Faucet busy upstream. Please retry in a moment.';
        } else {
          msg = message?.toString() ?? 'Airdrop failed';
        }
      } else {
        msg = 'Airdrop failed: ${e.message ?? e.toString()}';
      }
      state = state.copyWith(isLoading: false, error: msg);
      throw StateError(msg);
    } catch (e) {
      final msg = 'Airdrop failed: $e';
      state = state.copyWith(isLoading: false, error: msg);
      throw StateError(msg);
    }
  }

  // -------------------------------------------------------------------------
  // Transaction History
  // -------------------------------------------------------------------------

  Future<List<TransactionInfo>> getTransactionHistory({int limit = 20}) async {
    final pubKey = state.publicKey;
    if (pubKey == null) return [];

    try {
      final sigs = await _rpc.getSignaturesForAddress(
        pubKey,
        limit: limit,
      );

      // Phase 6.1 §3.2 — classify in parallel batches of 5 (parser cache hits considered)
      const concurrency = 5;
      final out = <TransactionInfo>[];
      for (var i = 0; i < sigs.length; i += concurrency) {
        final batch = sigs.sublist(
          i,
          (i + concurrency).clamp(0, sigs.length),
        );
        final results = await Future.wait(batch.map((s) async {
          ParsedTxResult? parsed;
          if (s.err == null) {
            parsed = await _txParser.classify(
              signature: s.signature,
              ownerAddress: pubKey,
            );
          }
          return TransactionInfo(
            signature: s.signature,
            type: _mapTxType(parsed?.type),
            timestamp: s.blockTime != null
                ? DateTime.fromMillisecondsSinceEpoch(s.blockTime! * 1000)
                : DateTime.now(),
            status: s.err != null
                ? TransactionStatus.failed
                : TransactionStatus.confirmed,
            fee: parsed?.feeLamports ?? BigInt.from(5000),
            amountLamports: parsed?.amountLamports,
            tokenMint: parsed?.tokenMint,
            fromAddress: parsed?.type == ParsedTxType.solReceive ||
                    parsed?.type == ParsedTxType.splReceive
                ? parsed?.counterparty
                : null,
            toAddress: parsed?.type == ParsedTxType.solSend ||
                    parsed?.type == ParsedTxType.splSend
                ? parsed?.counterparty
                : null,
          );
        }));
        out.addAll(results);
      }
      return out;
    } catch (e) {
      debugPrint('[Wallet] Failed to fetch tx history: $e');
      return [];
    }
  }

  static TransactionType _mapTxType(ParsedTxType? t) {
    switch (t) {
      case ParsedTxType.solSend:
      case ParsedTxType.splSend:
        return TransactionType.send;
      case ParsedTxType.solReceive:
      case ParsedTxType.splReceive:
        return TransactionType.receive;
      case ParsedTxType.unknown:
      case null:
        return TransactionType.unknown;
    }
  }

  // -------------------------------------------------------------------------
  // Socket.IO wallet updates
  // -------------------------------------------------------------------------

  void _listenToWalletUpdates() {
    try {
      final socketManager = _ref.read(socketManagerProvider);
      _walletUpdateSub = socketManager.onMessage.listen((data) {
        final type = data['type'] as String?;
        if (type == 'wallet_update' || type == 'transaction_confirmed') {
          refreshBalance();
        }
      });
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // Delete
  // -------------------------------------------------------------------------

  Future<void> deleteWallet() async {
    await _keypairManager.deleteWallet();
    state = const WalletState();
  }

  // -------------------------------------------------------------------------
  // Phase 2B-2: Multi-Wallet API
  // -------------------------------------------------------------------------

  /// Change active wallet — UI selector / programmatic switch.
  /// Sync storage + activeWalletIdProvider + state.publicKey + reload balance.
  /// switch alone does NOT pre-load the new wallet's keypair (lazy —
  /// loadWalletFor at send time).
  Future<void> switchActive(String walletId) async {
    final idx = _ref.read(walletIndexProvider).valueOrNull;
    if (idx == null) {
      throw const WalletIndexCorruptedException(
        'walletIndex not loaded — bootstrap incomplete?',
      );
    }
    final entry = idx.findById(walletId);
    if (entry == null) throw WalletNotFoundException(walletId);

    await _ref.read(activeWalletControllerProvider).set(walletId);
    // Phase 5 critical fix — switch keypair source as well. Previously
    // missed, causing the bug where active=B but signing used A's
    // (primary) keypair when broadcasting.
    _keypairManager.setActive(entry);
    state = state.copyWith(publicKey: entry.address);
    await refreshBalance();
  }

  /// Add a derived sub-wallet. account index = nextDerivationAccountIndex
  /// (C-2 monotonic). On success, returns the new wallet id + auto-switches active.
  /// label null/empty → `WalletLabels.derivedAccount(index)`.
  Future<String> addDerivedWallet({String? label}) async {
    final idx = _ref.read(walletIndexProvider).valueOrNull;
    if (idx == null) {
      throw const WalletIndexCorruptedException(
        'walletIndex not loaded',
      );
    }
    if (!idx.canAddDerived) {
      throw const DerivedLimitExceededException(WalletIndexLimits.maxDerived);
    }

    final mnemonic =
        await _ref.read(secureWalletStorageProvider).readMnemonic();
    if (mnemonic == null) {
      throw const IdentityMnemonicMissingException();
    }

    final accountIndex = idx.nextDerivationAccountIndex();
    final keyPair =
        await DerivationService.deriveWalletKeyPairAt(mnemonic, accountIndex);
    final address = keyPair.publicKey.toBase58();

    final id = WalletIdGenerator.generate();
    final entry = WalletEntry(
      id: id,
      address: address,
      kind: WalletKind.derived,
      role: WalletRole.sub,
      label: _resolveLabel(label, WalletLabels.derivedAccount(accountIndex)),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      derivationAccountIndex: accountIndex,
    );

    await _ref.read(walletIndexProvider.notifier).addEntry(entry);
    await switchActive(id);
    return id;
  }

  /// Import external mnemonic — kind=imported, account 0 derive.
  /// C-1: throws SelfImportRejectedException when matching identity_mnemonic.
  /// Cleans up orphan secret on failure.
  Future<String> importWalletFromMnemonic(
    String mnemonic, {
    String? label,
  }) async {
    final idx = _ref.read(walletIndexProvider).valueOrNull;
    if (idx == null) {
      throw const WalletIndexCorruptedException(
        'walletIndex not loaded',
      );
    }
    if (!idx.canAddImported) {
      throw const ImportLimitExceededException(WalletIndexLimits.maxImported);
    }

    // C-1: reject self mnemonic (compare after case / whitespace normalization)
    final identityMnemonic =
        await _ref.read(secureWalletStorageProvider).readMnemonic();
    if (identityMnemonic != null &&
        _normalizeMnemonic(mnemonic) ==
            _normalizeMnemonic(identityMnemonic)) {
      throw const SelfImportRejectedException();
    }

    // External mnemonic account 0 → extract 32-byte seed then discard
    final keyPair = await DerivationService.deriveWalletKeyPairAt(mnemonic, 0);
    final address = keyPair.publicKey.toBase58();

    if (idx.findByAddress(address) != null) {
      throw DuplicateWalletException(address);
    }

    final keyPairData = await keyPair.extract();
    final secret =
        Uint8List.fromList(keyPairData.bytes.sublist(0, 32));
    final id = WalletIdGenerator.generate();

    await _ref
        .read(secureWalletStorageProvider)
        .writeImportedSecret(id, secret);

    final entry = WalletEntry(
      id: id,
      address: address,
      kind: WalletKind.imported,
      role: WalletRole.sub,
      label: _resolveLabel(label, WalletLabels.importedDefault),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      await _ref.read(walletIndexProvider.notifier).addEntry(entry);
    } catch (e) {
      // index add failed → clean up orphan secret immediately
      await _ref
          .read(secureWalletStorageProvider)
          .deleteImportedSecret(id);
      rethrow;
    }

    await switchActive(id);
    return id;
  }

  /// Import a 32-byte Ed25519 seed.
  /// I-2: length validation. C-1 variant: throws SelfImportRejected when matching primary address.
  Future<String> importWalletFromPrivateKey(
    Uint8List secret32, {
    String? label,
  }) async {
    if (secret32.length != 32) {
      throw const InvalidPrivateKeyException(
        'Private key must be exactly 32 bytes (Ed25519 seed).',
      );
    }
    final idx = _ref.read(walletIndexProvider).valueOrNull;
    if (idx == null) {
      throw const WalletIndexCorruptedException(
        'walletIndex not loaded',
      );
    }
    if (!idx.canAddImported) {
      throw const ImportLimitExceededException(WalletIndexLimits.maxImported);
    }

    final keyPair = await DerivationService.keyPairFromSecret(secret32);
    final address = keyPair.publicKey.toBase58();

    // C-1 variant: reject primary address (user's own main wallet)
    if (address == idx.primaryEntry.address) {
      throw const SelfImportRejectedException();
    }
    if (idx.findByAddress(address) != null) {
      throw DuplicateWalletException(address);
    }

    final id = WalletIdGenerator.generate();
    await _ref
        .read(secureWalletStorageProvider)
        .writeImportedSecret(id, secret32);

    final entry = WalletEntry(
      id: id,
      address: address,
      kind: WalletKind.imported,
      role: WalletRole.sub,
      label: _resolveLabel(label, WalletLabels.importedDefault),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    try {
      await _ref.read(walletIndexProvider.notifier).addEntry(entry);
    } catch (e) {
      await _ref
          .read(secureWalletStorageProvider)
          .deleteImportedSecret(id);
      rethrow;
    }

    await switchActive(id);
    return id;
  }

  /// removeWallet — blocks primary (C-3), blocks sendlock (A-5).
  /// NFT/listing checks are delegated externally via the [preCheck] callback
  /// (Phase 5 integration point). preCheck throws propagate as-is. On
  /// success, removes the index entry + (imported) deletes secret + evicts
  /// keypair cache.
  Future<void> removeWallet(
    String walletId, {
    Future<void> Function(WalletEntry entry)? preCheck,
  }) async {
    final idx = _ref.read(walletIndexProvider).valueOrNull;
    if (idx == null) {
      throw const WalletIndexCorruptedException(
        'walletIndex not loaded',
      );
    }
    final entry = idx.findById(walletId);
    if (entry == null) throw WalletNotFoundException(walletId);

    // C-3: check both (id match OR role==primary)
    if (entry.role == WalletRole.primary || walletId == idx.primaryId) {
      throw const CannotRemovePrimaryException();
    }

    // A-5: in-flight tx
    final sendLock = _ref.read(walletSendLockProvider);
    if (sendLock.isLocked(walletId)) {
      throw const InFlightTransactionException();
    }

    // D-1 / D-2: external checks (NFT holdings / active listings)
    if (preCheck != null) {
      await preCheck(entry);
    }

    await _ref.read(walletIndexProvider.notifier).removeEntry(walletId);
    _keypairManager.evictWallet(walletId);

    // If it was active, fall back to primary
    final activeId = _ref.read(activeWalletIdProvider);
    if (activeId == walletId) {
      await switchActive(idx.primaryId);
    }
  }

  /// Change Default — A-4: biometric gate.
  /// Throws StateError when `biometricOk=false` — caller (UI) passes the
  /// local_auth result.
  Future<void> setDefault(
    String walletId, {
    required bool biometricOk,
  }) async {
    if (!biometricOk) {
      throw StateError('biometric authentication required for setDefault');
    }
    await _ref.read(walletIndexProvider.notifier).setDefault(walletId);
  }

  /// Rename label. Noop when empty after trim. Server sync follows §11.8
  /// opt-in policy — this method updates local only. Server sync is a
  /// separate entry point (Phase 5.5).
  Future<void> renameWallet(String walletId, String newLabel) async {
    await _ref.read(walletIndexProvider.notifier).rename(walletId, newLabel);
  }

  /// Mark derived sub as hidden=true. Disappears from selector. If it was
  /// active, fall back to primary.
  Future<void> hideDerivedWallet(String walletId) async {
    final activeId = _ref.read(activeWalletIdProvider);
    await _ref
        .read(walletIndexProvider.notifier)
        .hideDerived(walletId);
    if (activeId == walletId) {
      final idx = _ref.read(walletIndexProvider).valueOrNull;
      if (idx != null) await switchActive(idx.primaryId);
    }
  }

  /// Restore hidden derived — match by derivation account index.
  Future<void> unhideWallet(int derivationAccountIndex) async {
    await _ref
        .read(walletIndexProvider.notifier)
        .unhideDerived(derivationAccountIndex);
  }

  // ---------------------------------------------------------------------------
  // Helpers (Phase 2B)
  // ---------------------------------------------------------------------------

  String _resolveLabel(String? input, String fallback) {
    final trimmed = input?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  /// Normalize for BIP39 mnemonic comparison — unify case + multi-whitespace.
  static String _normalizeMnemonic(String m) {
    return m.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
  }

  @override
  void dispose() {
    _walletUpdateSub?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Provider definitions
// ---------------------------------------------------------------------------

final walletProvider =
    StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  return WalletNotifier(
    ref.read(keypairManagerProvider),
    ref.read(rpcClientProvider),
    ref.read(solTransferServiceProvider),
    ref.read(splTransferServiceProvider),
    ref.read(priceServiceProvider),
    ref.read(tokenListServiceProvider),
    ref.read(walletBalanceCacheProvider),
    ref.read(transactionParserProvider),
    ref,
  );
});

final transactionHistoryProvider =
    FutureProvider<List<TransactionInfo>>((ref) async {
  final notifier = ref.read(walletProvider.notifier);
  return notifier.getTransactionHistory();
});

final selectedTokenProvider = StateProvider<TokenInfo?>((ref) => null);

/// Get Solana Explorer URL for a transaction signature.
String getSolanaExplorerUrl(String signature, SolanaNetwork network) {
  return network.explorerTxUrl(signature);
}
