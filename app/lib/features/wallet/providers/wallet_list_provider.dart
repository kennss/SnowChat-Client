/// @file        wallet_list_provider.dart
/// @description Multi-Wallet single-source-of-truth provider bundle.
///              Per Multi-Wallet-Design-FINAL.md §2.1.
///
///              Components:
///                - WalletIndexNotifier: loads storage's wallet_index_v1 into
///                  memory and persists immediately on every mutator call.
///                - walletIndexProvider: AsyncNotifierProvider — every UI /
///                  Service should read only this provider.
///                - activeWalletIdProvider: wallet id that the current
///                  selector is showing. last-seen is loaded from storage's
///                  wallet_active_id. Changes persist immediately via
///                  _persistActiveId.
///                - defaultWalletIdProvider: derived read-only of
///                  index.defaultId.
///                - activeWalletAddressProvider /
///                  defaultWalletAddressProvider: address lookup. Both are
///                  valid only when walletIndexProvider is ready.
///
///              Caller guide:
///                - read-only: watch the 5 providers above directly
///                - write: must go through WalletNotifier (Phase 2B). Direct
///                  mutator calls are forbidden — H-3 single-source violation.
///
///              Note: when walletIndexProvider builds and wallet_index_v1
///              is missing, it throws WalletIndexCorruptedException
///              ("bootstrap incomplete"). The normal flow is for the F-1
///              routing barrier to block this at splash.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletIndexNotifier.build / setDefault / addEntry / removeEntry /
///    rename / hideDerived / unhideDerived / markLegacyKeysCleaned
///  - walletIndexProvider
///  - activeWalletIdProvider
///  - defaultWalletIdProvider / defaultWalletAddressProvider
///  - activeWalletAddressProvider

library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/secure_wallet_storage.dart';
import '../models/wallet_account_model.dart';
import '../models/wallet_index.dart';
import '../models/wallet_index_exceptions.dart';
import '../wallet_provider.dart' show secureWalletStorageProvider;

// ---------------------------------------------------------------------------
// WalletIndexNotifier — memory model + storage persist
// ---------------------------------------------------------------------------

class WalletIndexNotifier extends AsyncNotifier<WalletIndex> {
  late SecureWalletStorage _storage;

  @override
  Future<WalletIndex> build() async {
    _storage = ref.read(secureWalletStorageProvider);
    final json = await _storage.readWalletIndexJson();
    if (json == null) {
      // Bootstrap incomplete. Normally the F-1 routing barrier blocks this
      // at splash — reaching here implies a race / migration not executed
      // / external storage cleared.
      throw const WalletIndexCorruptedException(
        'wallet_index_v1 missing — bootstrap incomplete.',
      );
    }
    return WalletIndex.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  // Internal helper — common mutator pattern.
  Future<void> _persistAndUpdate(WalletIndex next) async {
    await _storage.writeWalletIndexJson(jsonEncode(next.toJson()));
    state = AsyncData(next);
  }

  WalletIndex _require() {
    final value = state.valueOrNull;
    if (value == null) {
      throw const WalletIndexCorruptedException(
        'WalletIndex not loaded. Call after walletIndexProvider is ready.',
      );
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Mutators
  // ---------------------------------------------------------------------------

  /// Change Default. P1 A-4 biometric verification is the caller's responsibility (WalletNotifier).
  Future<void> setDefault(String walletId) async {
    final cur = _require();
    final next = cur.withDefault(walletId);
    await _persistAndUpdate(next);
  }

  /// Add a new derived/imported entry. WalletEntry invariants are checked
  /// by withEntry (id/address duplicates, primary-add rejected).
  Future<void> addEntry(WalletEntry entry) async {
    final cur = _require();
    final next = cur.withEntry(entry);
    await _persistAndUpdate(next);
  }

  /// Permanent removal of an imported wallet — cleans up entry + secret together.
  /// - role==primary → CannotRemovePrimaryException
  /// - imported → also deletes `wallet_secret/{id}`
  /// - if it was default → falls back to primary (handled inside withoutEntry)
  Future<void> removeEntry(String walletId) async {
    final cur = _require();
    final entry = cur.findById(walletId);
    if (entry == null) {
      throw WalletNotFoundException(walletId);
    }
    final next = cur.withoutEntry(walletId);
    // 1) persist index first — orphan entry is more dangerous than orphan
    //    secret (UI may reference an invalid id). Secret leftovers are
    //    handled safely by v2.1.0 orphan-prune.
    await _persistAndUpdate(next);
    // 2) Only clean secret for imported. derived re-derives from mnemonic
    //    so it has no separate secret.
    if (entry.kind == WalletKind.imported) {
      await _storage.deleteImportedSecret(walletId);
    }
  }

  /// Rename label. Noop if empty after trim or unchanged.
  Future<void> rename(String walletId, String newLabel) async {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty) return;
    final cur = _require();
    final entry = cur.findById(walletId);
    if (entry == null) throw WalletNotFoundException(walletId);
    if (entry.label == trimmed) return;
    final next = cur.updateEntry(walletId, (e) => e.copyWith(label: trimmed));
    await _persistAndUpdate(next);
  }

  /// Set derived sub hidden=true. Disappears from the UI selector.
  /// address / derivationAccountIndex are preserved — same address restorable
  /// on unhide. Forbidden for imported (which uses permanent delete only).
  Future<void> hideDerived(String walletId) async {
    final cur = _require();
    final entry = cur.findById(walletId);
    if (entry == null) throw WalletNotFoundException(walletId);
    if (entry.kind != WalletKind.derived) {
      throw const WalletIndexCorruptedException(
        'hideDerived called on non-derived wallet.',
      );
    }
    if (entry.role == WalletRole.primary) {
      throw const CannotRemovePrimaryException();
    }
    if (entry.hidden) return;
    final next =
        cur.updateEntry(walletId, (e) => e.copyWith(hidden: true));
    await _persistAndUpdate(next);
  }

  /// Restore derived sub to hidden=false. Found by derivationAccountIndex match.
  Future<void> unhideDerived(int derivationAccountIndex) async {
    final cur = _require();
    final entry = cur.derivedEntries.firstWhere(
      (e) => e.derivationAccountIndex == derivationAccountIndex && e.hidden,
      orElse: () => throw WalletNotFoundException(
        'derived@$derivationAccountIndex',
      ),
    );
    final next =
        cur.updateEntry(entry.id, (e) => e.copyWith(hidden: false));
    await _persistAndUpdate(next);
  }

  /// Called only on v2.1.0 boot, after F-6 deferred orphan-prune completes.
  Future<void> markLegacyKeysCleaned() async {
    final cur = _require();
    if (!cur.metadata.legacyKeysPendingCleanup) return;
    await _persistAndUpdate(cur.markLegacyKeysCleaned());
  }
}

final walletIndexProvider =
    AsyncNotifierProvider<WalletIndexNotifier, WalletIndex>(
  WalletIndexNotifier.new,
);

// ---------------------------------------------------------------------------
// Active wallet (UI selector pointer)
// ---------------------------------------------------------------------------

/// Wallet id the selector currently shows. Initial value is storage's
/// wallet_active_id, or (when missing) primary. WalletNotifier.initialize()
/// sets it right after the first load.
///
/// Direct changes must go through ActiveWalletController (below) — storage
/// persist is its responsibility. External code should only watch read-only.
final activeWalletIdProvider = StateProvider<String?>((ref) => null);

/// Controller that couples activeWalletIdProvider change with storage persist.
/// Used by WalletNotifier (Phase 2B). UI must not call directly.
class ActiveWalletController {
  ActiveWalletController(this._ref);

  final Ref _ref;

  /// Updates memory + storage at the same time. If they diverge, the next
  /// boot shows a stale active wallet on screen.
  Future<void> set(String walletId) async {
    final storage = _ref.read(secureWalletStorageProvider);
    await storage.writeActiveWalletId(walletId);
    _ref.read(activeWalletIdProvider.notifier).state = walletId;
  }

  /// Load last-seen from storage. Falls back to primary when missing.
  /// Note: primary fallback requires walletIndexProvider to be ready.
  Future<void> hydrate() async {
    final storage = _ref.read(secureWalletStorageProvider);
    final stored = await storage.readActiveWalletId();
    if (stored != null) {
      _ref.read(activeWalletIdProvider.notifier).state = stored;
      return;
    }
    final indexAsync = _ref.read(walletIndexProvider);
    final idx = indexAsync.valueOrNull;
    if (idx != null) {
      await set(idx.primaryId);
    }
  }
}

final activeWalletControllerProvider = Provider<ActiveWalletController>(
  (ref) => ActiveWalletController(ref),
);

// ---------------------------------------------------------------------------
// Default wallet (receive QR / friend transfer / marketplace default)
// ---------------------------------------------------------------------------

/// Watches only index.defaultId — auto-refreshes on index change. Mutate
/// solely via WalletIndexNotifier.setDefault.
final defaultWalletIdProvider = Provider<String?>((ref) {
  final indexAsync = ref.watch(walletIndexProvider);
  return indexAsync.valueOrNull?.defaultId;
});

final defaultWalletAddressProvider = Provider<String?>((ref) {
  final indexAsync = ref.watch(walletIndexProvider);
  final idx = indexAsync.valueOrNull;
  if (idx == null) return null;
  return idx.defaultEntry.address;
});

final defaultWalletEntryProvider = Provider<WalletEntry?>((ref) {
  final indexAsync = ref.watch(walletIndexProvider);
  return indexAsync.valueOrNull?.defaultEntry;
});

// ---------------------------------------------------------------------------
// Active wallet derived providers (lookup by id)
// ---------------------------------------------------------------------------

final activeWalletEntryProvider = Provider<WalletEntry?>((ref) {
  final activeId = ref.watch(activeWalletIdProvider);
  final indexAsync = ref.watch(walletIndexProvider);
  final idx = indexAsync.valueOrNull;
  if (activeId == null || idx == null) return null;
  return idx.findById(activeId);
});

final activeWalletAddressProvider = Provider<String?>((ref) {
  final entry = ref.watch(activeWalletEntryProvider);
  return entry?.address;
});

// ---------------------------------------------------------------------------
// Convenience aggregate — selector list (visible only)
// ---------------------------------------------------------------------------

/// Watched by UI selector / dropdown. Excludes hidden. Always includes primary.
final visibleWalletEntriesProvider = Provider<List<WalletEntry>>((ref) {
  final indexAsync = ref.watch(walletIndexProvider);
  return indexAsync.valueOrNull?.visibleEntries ?? const <WalletEntry>[];
});

@visibleForTesting
WalletIndexNotifier debugReadWalletIndexNotifier(Ref ref) {
  return ref.read(walletIndexProvider.notifier);
}
