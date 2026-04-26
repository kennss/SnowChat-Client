/// @file        wallet_send_lock.dart
/// @description Multi-Wallet in-flight transaction lock — protects the same
///              wallet's keypair from being evicted / deleted by other code
///              paths during the biometric prompt (several to ~30 seconds).
///              Multi-Wallet-Design-FINAL.md §3.2 + audit P1 A-5 fix.
///
///              Usage:
///                final lock = WalletSendLock();
///                lock.acquire(walletId);
///                try {
///                  await signAndBroadcast(...);
///                } finally {
///                  lock.release(walletId);
///                }
///
///              `removeWallet` flow / KeypairManager.clearCache check the lock:
///                if (lock.isLocked(walletId)) throw InFlightTransactionException();
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletSendLock.acquire(walletId)
///  - WalletSendLock.release(walletId)
///  - WalletSendLock.isLocked(walletId)
///  - WalletSendLock.hasAnyActive
///  - WalletSendLock.activeWalletIds (debug)

library;

/// Per-wallet in-flight transaction reference counter.
/// When sends overlap on the same wallet, release must match acquire counts.
class WalletSendLock {
  final Map<String, int> _refCounts = {};

  /// Begin a wallet send — increment refCount. The same wallet may be
  /// acquired twice (e.g. in-app transfer + marketplace buy in parallel) —
  /// isLocked == false only after every release.
  void acquire(String walletId) {
    _refCounts[walletId] = (_refCounts[walletId] ?? 0) + 1;
  }

  /// End a wallet send. Lock releases when refCount reaches 0.
  /// More releases than acquires → ArgumentError (enforces balanced calls).
  void release(String walletId) {
    final current = _refCounts[walletId];
    if (current == null || current <= 0) {
      throw ArgumentError(
        'release($walletId) without matching acquire — call balance violation',
      );
    }
    if (current == 1) {
      _refCounts.remove(walletId);
    } else {
      _refCounts[walletId] = current - 1;
    }
  }

  /// Whether this wallet has an in-flight send.
  /// Checked by `removeWallet` / `clearCache` before invocation.
  bool isLocked(String walletId) =>
      (_refCounts[walletId] ?? 0) > 0;

  /// True if any wallet has work in flight.
  /// Used by `WalletLifecycleManager` to decide whether to defer idle eviction.
  bool get hasAnyActive => _refCounts.isNotEmpty;

  /// For debugging. Do not log in production — not key material, but user
  /// behavior can be tracked through it (against the spirit of Zero-Knowledge).
  Iterable<String> get activeWalletIds => _refCounts.keys;
}
