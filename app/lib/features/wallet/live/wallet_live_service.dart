/// @file        wallet_live_service.dart
/// @description Solana wallet real-time sync service — accountSubscribe (WS)
///              first, with 15s polling fallback on disconnect, polling
///              halted on recovery. SPL uses N accountSubscribes per ATA
///              (programSubscribe memcmp is not supported).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletLiveService.start(): start service → attempt WS connection (serialized)
///  - WalletLiveService.stop(): tear down all subscriptions/timers (serialized)
///  - WalletLiveService.restart(): re-init on network/wallet change
///  - WalletLiveService.pause()/resume(): handle app background/foreground
///  - WalletLiveService.dispose(): called on Provider dispose
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/dto.dart';
import 'package:solana/solana.dart';

import '../providers/balance_provider.dart';
import '../wallet_provider.dart'
    show transactionHistoryProvider, walletProvider;
import 'reconnect_policy.dart';
import 'wallet_live_mode.dart';

final walletLiveModeProvider =
    StateProvider<WalletLiveMode>((ref) => WalletLiveMode.initial);

class WalletLiveService {
  WalletLiveService({
    required this.ref,
    required this.wsUri,
    required this.rpcClient,
    required this.walletPubkey,
  });

  final Ref ref;
  final Uri wsUri;
  final RpcClient rpcClient;
  final String walletPubkey;

  // ── State ────────────────────────────────────────────────────────────
  SubscriptionClient? _client;
  StreamSubscription? _solSub;
  final Map<String, StreamSubscription> _ataSubs = {};
  Timer? _ataRefreshTimer;
  Timer? _pollingTimer;
  Timer? _reconnectTimer;
  Timer? _invalidateDebounce;
  int _reconnectAttempt = 0;
  WalletLiveMode _mode = WalletLiveMode.initial;
  bool _disposed = false;
  bool _reconnecting = false;
  Future<void>? _opLock;

  // ── Public API ───────────────────────────────────────────────────────
  Future<void> start() => _serialize(_start);
  Future<void> stop() => _serialize(_stop);
  Future<void> restart() => _serialize(() async {
        await _stop();
        await _start();
      });

  Future<void> pause() async {
    _reconnectTimer?.cancel();
    _stopPolling();
  }

  Future<void> resume() async {
    if (_disposed) return;
    if (_mode == WalletLiveMode.websocket) {
      _scheduleInvalidate();
    } else {
      await start();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _serialize(_stop);
    _setMode(WalletLiveMode.disposed);
  }

  // ── Serialization ────────────────────────────────────────────────────
  Future<void> _serialize(Future<void> Function() op) async {
    final prev = _opLock;
    final completer = Completer<void>();
    _opLock = completer.future;
    try {
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      if (_disposed && op != _stop) return;
      await op();
    } finally {
      completer.complete();
    }
  }

  Future<void> _start() async {
    if (_disposed) return;
    // Ignore duplicate start when already active
    if (_mode == WalletLiveMode.connecting ||
        _mode == WalletLiveMode.websocket ||
        _mode == WalletLiveMode.polling) {
      return;
    }
    debugPrint('[WalletLive] start() pubkey=$walletPubkey ws=$wsUri');
    _setMode(WalletLiveMode.connecting);
    await _openWebSocket();
  }

  Future<void> _stop() async {
    await _closeAllStreams();
    _reconnectTimer?.cancel();
    _stopPolling();
    _ataRefreshTimer?.cancel();
    _invalidateDebounce?.cancel();
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _reconnectAttempt = 0;
    _reconnecting = false;
    if (!_disposed) _setMode(WalletLiveMode.initial);
  }

  Future<void> _openWebSocket() async {
    // Wrap with runZonedGuarded to absorb SubscriptionClient internal
    // unhandled async errors (e.g. DNS failure throwing during sync stage).
    final completer = Completer<bool>();
    runZonedGuarded(() async {
      try {
        try {
          _client?.close();
        } catch (_) {}
        _client = SubscriptionClient(
          wsUri,
          pingInterval: const Duration(seconds: 20),
        );

        _solSub = _client!
            .accountSubscribe(walletPubkey, commitment: Commitment.confirmed)
            .listen(
              _onSolPush,
              onError: (_) => _onDisconnect(),
              onDone: _onDisconnect,
              cancelOnError: true,
            );

        await _refreshAtaSubscriptions();
        _ataRefreshTimer?.cancel();
        _ataRefreshTimer = Timer.periodic(
          const Duration(minutes: 1),
          (_) => _refreshAtaSubscriptions(),
        );

        if (!completer.isCompleted) completer.complete(true);
      } catch (_) {
        if (!completer.isCompleted) completer.complete(false);
      }
    }, (error, stack) {
      if (!completer.isCompleted) completer.complete(false);
      // Treat zone error as a disconnect when already connected
      if (_mode == WalletLiveMode.websocket) _onDisconnect();
    });

    final ok = await completer.future;
    if (ok) {
      debugPrint('[WalletLive] WS connected, ATA subs=${_ataSubs.length}');
      _reconnectAttempt = 0;
      _reconnecting = false;
      _stopPolling();
      _setMode(WalletLiveMode.websocket);
      _scheduleInvalidate();
    } else {
      debugPrint('[WalletLive] WS open failed → polling fallback');
      _onDisconnect();
    }
  }

  Future<void> _refreshAtaSubscriptions() async {
    if (_disposed || _client == null) return;
    try {
      final result = await rpcClient.getTokenAccountsByOwner(
        walletPubkey,
        const TokenAccountsFilter.byProgramId(TokenProgram.programId),
        encoding: Encoding.jsonParsed,
      );
      final currentAtas = <String>{
        for (final acc in result.value) acc.pubkey,
      };
      // Add
      for (final ata in currentAtas.difference(_ataSubs.keys.toSet())) {
        if (_client == null) break;
        _ataSubs[ata] = _client!
            .accountSubscribe(ata, commitment: Commitment.confirmed)
            .listen(
              _onAtaPush,
              onError: (_) => _onDisconnect(),
              onDone: _onDisconnect,
              cancelOnError: true,
            );
      }
      // Remove
      final removed = _ataSubs.keys.toSet().difference(currentAtas);
      for (final ata in removed) {
        await _safeCancel(_ataSubs.remove(ata));
      }
    } catch (_) {
      // ATA lookup failure is not treated as a disconnect
    }
  }

  /// SOL native account push — apply Account.lamports directly to state (race-free).
  void _onSolPush(Account account) {
    if (_disposed) return;
    final lamports = BigInt.from(account.lamports);
    debugPrint('[WalletLive] SOL push: $lamports lamports');
    try {
      ref.read(walletProvider.notifier).applyLiveSolBalance(lamports);
    } catch (e) {
      debugPrint('[WalletLive] applyLiveSolBalance failed: $e');
    }
    // History is invalidated separately
    _scheduleHistoryInvalidate();
  }

  /// SPL ATA push — when data is jsonParsed, extract mint+amount directly.
  /// Other encodings lack an ATA→mint mapping, so fall back to
  /// walletProvider.refreshBalance.
  void _onAtaPush(Account account) {
    if (_disposed) return;
    final data = account.data;
    if (data is ParsedSplTokenProgramAccountData) {
      final parsed = data.parsed;
      if (parsed is TokenAccountData) {
        final info = parsed.info;
        final mint = info.mint;
        final amount = BigInt.tryParse(info.tokenAmount.amount) ?? BigInt.zero;
        debugPrint('[WalletLive] SPL push: $mint=$amount');
        try {
          ref
              .read(walletProvider.notifier)
              .applyLiveSplBalance(mint, amount);
        } catch (e) {
          debugPrint('[WalletLive] applyLiveSplBalance failed: $e');
        }
        _scheduleHistoryInvalidate();
        return;
      }
    }
    // Fallback: full refresh on parse failure
    debugPrint('[WalletLive] SPL push (unparsed) → full refresh');
    _scheduleFullRefresh();
  }

  void _scheduleHistoryInvalidate() {
    _invalidateDebounce?.cancel();
    _invalidateDebounce = Timer(const Duration(milliseconds: 500), () {
      if (_disposed) return;
      ref.invalidate(transactionHistoryProvider);
      ref.invalidate(solBalanceProvider);
      ref.invalidate(tokenBalancesProvider);
    });
  }

  void _scheduleFullRefresh() {
    _invalidateDebounce?.cancel();
    _invalidateDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (_disposed) return;
      try {
        await ref.read(walletProvider.notifier).refreshBalance(force: true);
      } catch (_) {}
      ref.invalidate(transactionHistoryProvider);
      ref.invalidate(solBalanceProvider);
      ref.invalidate(tokenBalancesProvider);
    });
  }

  /// Catch-up for consistency right after (re)connect. The push model can
  /// hold a stale balance, so do a full walletProvider refresh on the first
  /// pass.
  void _scheduleInvalidate() => _scheduleFullRefresh();

  void _onDisconnect() {
    if (_disposed) return;
    if (_reconnecting) return;
    if (_mode == WalletLiveMode.polling) return;
    _reconnecting = true;

    _closeAllStreams();
    try {
      _client?.close();
    } catch (_) {}
    _client = null;

    _setMode(WalletLiveMode.polling);
    _startPolling();
    _scheduleReconnect();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _scheduleInvalidate();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _scheduleInvalidate();
    });
  }

  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = ReconnectPolicy.delayFor(_reconnectAttempt++);
    _reconnectTimer = Timer(delay, () async {
      if (_disposed) return;
      await _openWebSocket();
      if (_mode != WalletLiveMode.websocket) {
        _reconnecting = false;
      }
    });
  }

  Future<void> _closeAllStreams() async {
    await _safeCancel(_solSub);
    _solSub = null;
    for (final sub in _ataSubs.values) {
      await _safeCancel(sub);
    }
    _ataSubs.clear();
    _ataRefreshTimer?.cancel();
  }

  Future<void> _safeCancel(StreamSubscription? sub) async {
    if (sub == null) return;
    try {
      await sub.cancel();
    } catch (_) {}
  }

  void _setMode(WalletLiveMode m) {
    if (_mode == m) return;
    _mode = m;
    if (_disposed && m != WalletLiveMode.disposed) return;
    Future.microtask(() {
      if (_disposed && m != WalletLiveMode.disposed) return;
      ref.read(walletLiveModeProvider.notifier).state = m;
    });
  }
}
