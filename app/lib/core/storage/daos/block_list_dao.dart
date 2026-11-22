/// @file        block_list_dao.dart
/// @description The rows of the accounts this user blocked (BlockedAccounts) — written only
///              through BlockList (core/blocking/block_list.dart).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - BlockListDao.allRows(): every row
///  - BlockListDao.setBlocked(): this device blocked or unblocked an account (not synced yet)
///  - BlockListDao.markSynced(): the server took what a row says (an unblock row goes)
///  - BlockListDao.adoptServerBlocks(): blocks the server knows of and this device does not
library;

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/blocked_accounts_table.dart';

part 'block_list_dao.g.dart';

@DriftAccessor(tables: [BlockedAccounts])
class BlockListDao extends DatabaseAccessor<SnowDatabase>
    with _$BlockListDaoMixin {
  BlockListDao(super.db);

  Future<List<BlockedAccountRow>> allRows() => select(blockedAccounts).get();

  /// This device blocked ([blocked]) or unblocked [snowId]: recorded, for
  /// the server to take next.
  Future<void> setBlocked(String snowId, bool blocked, int nowMs) =>
      into(blockedAccounts).insertOnConflictUpdate(
        BlockedAccountsCompanion.insert(
          snowId: snowId,
          blocked: blocked,
          synced: const Value(false),
          updatedAtMs: nowMs,
        ),
      );

  /// The server took what the row of [snowId] said at [updatedAtMs]: a
  /// block is marked synced, an unblock row goes. A row changed meanwhile
  /// (another block / unblock after the request left) is not touched.
  Future<void> markSynced(String snowId, int updatedAtMs) =>
      transaction(() async {
        final row = await (select(blockedAccounts)
              ..where((b) => b.snowId.equals(snowId)))
            .getSingleOrNull();
        if (row == null || row.updatedAtMs != updatedAtMs) return;
        if (row.blocked) {
          await (update(blockedAccounts)
                ..where((b) => b.snowId.equals(snowId)))
              .write(const BlockedAccountsCompanion(synced: Value(true)));
        } else {
          await (delete(blockedAccounts)
                ..where((b) => b.snowId.equals(snowId)))
              .go();
        }
      });

  /// Blocks the server holds that this device has no row of (a new install,
  /// or a block made before this list existed): taken in as synced. A row
  /// this device has — blocked or an unblock not yet taken — is never
  /// overridden. Returns the accounts taken in.
  Future<List<String>> adoptServerBlocks(List<String> snowIds, int nowMs) =>
      transaction(() async {
        final held = {
          for (final r in await select(blockedAccounts).get()) r.snowId,
        };
        final taken = <String>[];
        for (final id in snowIds.toSet()) {
          if (held.contains(id)) continue;
          await into(blockedAccounts).insert(
            BlockedAccountsCompanion.insert(
              snowId: id,
              blocked: true,
              synced: const Value(true),
              updatedAtMs: nowMs,
            ),
          );
          taken.add(id);
        }
        return taken;
      });
}
