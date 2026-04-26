/// @file        wallet_balance_cache.dart
/// @description Wallet balance cache — in-memory L1 + drift `wallet_balances`
///              L2. Phase 6.1 §3.1. raw_amount is BigInt → String (drift TEXT).
///              The 30s TTL is decided by the caller via
///              [CachedBalanceEntry.isFresh].
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletBalanceCache: cache interface
///  - DriftWalletBalanceCache: drift + in-memory hybrid implementation
///  - CachedBalanceEntry: single-entry model (BigInt rawAmount)
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../../core/storage/database.dart' as db;
import '../../../shared/models/wallet_models.dart';

/// Cached balance entry — single token or native SOL.
class CachedBalanceEntry {
  const CachedBalanceEntry({
    required this.mintAddress,
    required this.rawAmount,
    required this.decimals,
    required this.symbol,
    required this.lastUpdatedMs,
    this.name,
    this.logoUrl,
  });

  /// 'native' = SOL; otherwise SPL token mint Base58.
  final String mintAddress;
  final BigInt rawAmount;
  final int decimals;
  final String symbol;
  final int lastUpdatedMs;
  final String? name;
  final String? logoUrl;

  bool isFresh(Duration ttl) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - lastUpdatedMs < ttl.inMilliseconds;
  }
}

abstract class WalletBalanceCache {
  Future<List<CachedBalanceEntry>?> read(String walletAddress);
  Future<void> write(String walletAddress, List<CachedBalanceEntry> entries);
  Future<void> invalidate(String walletAddress);
}

/// In-memory L1 + drift L2 hybrid cache.
class DriftWalletBalanceCache implements WalletBalanceCache {
  DriftWalletBalanceCache({required db.SnowDatabase database})
      : _db = database;

  final db.SnowDatabase _db;
  final Map<String, List<CachedBalanceEntry>> _memory = {};

  @override
  Future<List<CachedBalanceEntry>?> read(String walletAddress) async {
    final mem = _memory[walletAddress];
    if (mem != null) return mem;

    try {
      final rows = await _db.walletBalanceDao.read(walletAddress);
      if (rows.isEmpty) return null;
      final entries = rows.map(_rowToEntry).toList();
      _memory[walletAddress] = entries;
      return entries;
    } catch (e) {
      debugPrint('[BalanceCache] drift read failed: $e');
      return null;
    }
  }

  @override
  Future<void> write(
    String walletAddress,
    List<CachedBalanceEntry> entries,
  ) async {
    _memory[walletAddress] = entries;
    try {
      final companions = entries
          .map((e) => db.WalletBalancesCompanion.insert(
                ownerAddress: walletAddress,
                mintAddress: e.mintAddress,
                rawAmount: e.rawAmount.toString(),
                decimals: e.decimals,
                symbol: e.symbol,
                lastUpdatedMs: e.lastUpdatedMs,
                name: Value(e.name),
                logoUrl: Value(e.logoUrl),
              ))
          .toList();
      await _db.walletBalanceDao.upsertAll(walletAddress, companions);
    } catch (e) {
      debugPrint('[BalanceCache] drift write failed: $e');
    }
  }

  @override
  Future<void> invalidate(String walletAddress) async {
    _memory.remove(walletAddress);
    try {
      await _db.walletBalanceDao.deleteOwner(walletAddress);
    } catch (_) {}
  }

  CachedBalanceEntry _rowToEntry(db.WalletBalance row) {
    return CachedBalanceEntry(
      mintAddress: row.mintAddress,
      rawAmount: BigInt.parse(row.rawAmount),
      decimals: row.decimals,
      symbol: row.symbol,
      name: row.name,
      logoUrl: row.logoUrl,
      lastUpdatedMs: row.lastUpdatedMs,
    );
  }

  /// Convert [WalletBalance] (UI model) to a list of cache entries.
  /// 'SOL' / wrapped SOL mint is normalized to 'native'.
  static List<CachedBalanceEntry> fromWalletBalance(WalletBalance balance) {
    final tokens = balance.tokens;
    final now = DateTime.now().millisecondsSinceEpoch;
    return tokens.map((t) {
      final mint = t.isNativeSOL ? 'native' : t.mint;
      return CachedBalanceEntry(
        mintAddress: mint,
        rawAmount: t.balanceLamports,
        decimals: t.decimals,
        symbol: t.symbol,
        name: t.name,
        logoUrl: t.logoUrl,
        lastUpdatedMs: now,
      );
    }).toList();
  }
}
