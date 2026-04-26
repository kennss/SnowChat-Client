/// @file        wallet_balance_dao.dart
/// @description Drift DAO for the WalletBalances table — Phase 6.1 §3.1.
///              CRUD for per-owner balance entries. All raw_amount values are converted BigInt -> String.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-08)
///
/// @functions
///  - WalletBalanceDao.upsertAll(): batch replace an owner's entries
///  - WalletBalanceDao.read(): fetch all entries for an owner
///  - WalletBalanceDao.deleteOwner(): delete all entries for an owner

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/wallet_balances_table.dart';

part 'wallet_balance_dao.g.dart';

@DriftAccessor(tables: [WalletBalances])
class WalletBalanceDao extends DatabaseAccessor<SnowDatabase>
    with _$WalletBalanceDaoMixin {
  WalletBalanceDao(super.db);

  /// Replace all of owner's entries (delete + insertAll).
  Future<void> upsertAll(
    String ownerAddress,
    List<WalletBalancesCompanion> entries,
  ) async {
    await transaction(() async {
      await (delete(walletBalances)
            ..where((t) => t.ownerAddress.equals(ownerAddress)))
          .go();
      await batch((b) {
        b.insertAll(walletBalances, entries);
      });
    });
  }

  /// Fetch all balance entries for owner.
  Future<List<WalletBalance>> read(String ownerAddress) {
    return (select(walletBalances)
          ..where((t) => t.ownerAddress.equals(ownerAddress)))
        .get();
  }

  Future<void> deleteOwner(String ownerAddress) {
    return (delete(walletBalances)
          ..where((t) => t.ownerAddress.equals(ownerAddress)))
        .go();
  }
}
