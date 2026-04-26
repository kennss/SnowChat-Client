/// @file        wallet_lifecycle_manager.dart
/// @description Multi-Wallet memory security policy — auto-evict cached
///              keypairs after a delay when the app enters background.
///              Multi-Wallet-Design-FINAL.md §3.3 + audit P1 A-3 fix.
///
///              Policy:
///                - app paused/inactive → start 10s grace timer
///                - after 10s call onIdle() (e.g. KeypairManager.clearCache)
///                - on resumed → cancel timer
///                - if an in-flight send exists, defer evict (check WalletSendLock)
///
///              Usage:
///                final mgr = WalletLifecycleManager(
///                  onIdle: () => keypairManager.clearCache(),
///                  shouldDefer: () => sendLock.hasAnyActive,
///                );
///                mgr.start();      // on app boot
///                mgr.dispose();    // on app dispose (usually never called)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletLifecycleManager.start(): register observer
///  - WalletLifecycleManager.dispose(): unregister observer
///  - WalletLifecycleManager.didChangeAppLifecycleState: lifecycle hook

library;

import 'dart:async';

import 'package:flutter/widgets.dart';

class WalletLifecycleManager with WidgetsBindingObserver {
  WalletLifecycleManager({
    required this.onIdle,
    required this.shouldDefer,
    Duration? idleGrace,
  }) : idleGrace = idleGrace ?? const Duration(seconds: 10);

  /// Callback invoked on idle — e.g. KeypairManager.clearCache.
  final void Function() onIdle;

  /// When this returns true, evict is deferred (e.g. in-flight send).
  /// Evaluated synchronously at call time — bool, not Future.
  final bool Function() shouldDefer;

  /// Wait time from paused/inactive to onIdle. Default 10s.
  final Duration idleGrace;

  Timer? _idleTimer;
  bool _started = false;

  /// Called once on app boot. Repeated calls are harmless (idempotent).
  void start() {
    if (_started) return;
    WidgetsBinding.instance.addObserver(this);
    _started = true;
  }

  /// Usually never called within app lifetime. Test / hot-restart only.
  void dispose() {
    if (!_started) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _scheduleIdle();
      case AppLifecycleState.resumed:
        _cancelIdle();
      case AppLifecycleState.detached:
        // Just before app termination — timer is meaningless. Evict immediately if possible.
        _cancelIdle();
        if (!shouldDefer()) onIdle();
    }
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleGrace, () {
      // Re-check defer after grace — a send may have started in the meantime
      if (!shouldDefer()) {
        onIdle();
      } else {
        // Currently deferring. Re-evaluate every 1s — evict immediately when send finishes.
        _retryUntilIdle();
      }
    });
  }

  void _retryUntilIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!shouldDefer()) {
        t.cancel();
        onIdle();
      }
    });
  }

  void _cancelIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// For tests. Force-trigger idle without a real lifecycle event.
  @visibleForTesting
  void debugTriggerPaused() {
    didChangeAppLifecycleState(AppLifecycleState.paused);
  }

  /// For tests. Force resume.
  @visibleForTesting
  void debugTriggerResumed() {
    didChangeAppLifecycleState(AppLifecycleState.resumed);
  }

  /// For tests. Whether the idle timer is currently active.
  @visibleForTesting
  bool get hasActiveTimer => _idleTimer?.isActive ?? false;
}
