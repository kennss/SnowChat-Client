/// @file        wallet_address_book_dao.dart
/// @description Drift DAO for WalletAddressBook — Phase 6.1 §3.5.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-08)
///
/// @functions
///  - WalletAddressBookDao.add(): add new entry (update on duplicate)
///  - WalletAddressBookDao.list(): fetch owner's entries ordered by last_used desc
///  - WalletAddressBookDao.touch(): update last_used
///  - WalletAddressBookDao.remove(): delete by id

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/wallet_address_book_table.dart';

part 'wallet_address_book_dao.g.dart';

@DriftAccessor(tables: [WalletAddressBook])
class WalletAddressBookDao extends DatabaseAccessor<SnowDatabase>
    with _$WalletAddressBookDaoMixin {
  WalletAddressBookDao(super.db);

  Future<int> add(WalletAddressBookCompanion entry) {
    return into(walletAddressBook).insert(
      entry,
      onConflict: DoUpdate(
        (old) => entry,
        target: [walletAddressBook.ownerAddress, walletAddressBook.address],
      ),
    );
  }

  Future<List<WalletAddressBookData>> list(String ownerAddress) {
    return (select(walletAddressBook)
          ..where((t) => t.ownerAddress.equals(ownerAddress))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.lastUsedMs,
                  mode: OrderingMode.desc,
                ),
            (t) => OrderingTerm(
                  expression: t.createdAtMs,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
  }

  Future<void> touch(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (update(walletAddressBook)..where((t) => t.id.equals(id))).write(
      WalletAddressBookCompanion(lastUsedMs: Value(now)),
    );
  }

  Future<int> remove(int id) {
    return (delete(walletAddressBook)..where((t) => t.id.equals(id))).go();
  }
}
