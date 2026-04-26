/// @file        wallet_tx_cache_dao.dart
/// @description Drift DAO for WalletTxCache — Phase 6.1 §3.2.
///              Persists only finalized transaction classification results. Stale entries are
///              identified via parser_version comparison when the parser changes.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-08)
///
/// @functions
///  - WalletTxCacheDao.upsert(): store a single classification result
///  - WalletTxCacheDao.lookup(): fetch by signature (single)
///  - WalletTxCacheDao.lookupBatch(): batch fetch
///  - WalletTxCacheDao.deleteOldVersion(): remove entries below parser_version

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/wallet_tx_cache_table.dart';

part 'wallet_tx_cache_dao.g.dart';

@DriftAccessor(tables: [WalletTxCache])
class WalletTxCacheDao extends DatabaseAccessor<SnowDatabase>
    with _$WalletTxCacheDaoMixin {
  WalletTxCacheDao(super.db);

  Future<void> upsert(WalletTxCacheCompanion entry) {
    return into(walletTxCache).insertOnConflictUpdate(entry);
  }

  Future<WalletTxCacheData?> lookup({
    required String signature,
    required String ownerAddress,
  }) {
    return (select(walletTxCache)
          ..where((t) =>
              t.signature.equals(signature) &
              t.ownerAddress.equals(ownerAddress)))
        .getSingleOrNull();
  }

  Future<Map<String, WalletTxCacheData>> lookupBatch({
    required List<String> signatures,
    required String ownerAddress,
  }) async {
    if (signatures.isEmpty) return {};
    final rows = await (select(walletTxCache)
          ..where((t) =>
              t.ownerAddress.equals(ownerAddress) &
              t.signature.isIn(signatures)))
        .get();
    return {for (final r in rows) r.signature: r};
  }

  /// Remove entries below parser_version. Call after the parser algorithm changes.
  Future<int> deleteOldVersion(int currentVersion) {
    return (delete(walletTxCache)
          ..where((t) => t.parserVersion.isSmallerThanValue(currentVersion)))
        .go();
  }
}
