/// @file        block_list_dao.dart
/// @description The rows of the accounts this user blocked (BlockedAccounts) — written only
///              through BlockList (core/blocking/block_list.dart).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (mergeRestored takes in at most `limit` new blocks — the list's cap).
///              Earlier 2026-11-22 (this device's list is the source of truth: no adoption of the
///              server's list — adoptServerBlocks is gone; setBlocked keeps a nickname;
///              markAllSynced() after the server's tags were replaced; mergeRestored() for the
///              contact backup). Earlier 2026-11-21
///
/// @functions
///  - BlockListDao.allRows(): every row
///  - BlockListDao.setBlocked(): this device blocked or unblocked an account (not synced yet)
///  - BlockListDao.markSynced(): the server took what a row says (an unblock row goes)
///  - BlockListDao.markAllSynced(): the server's tags were replaced by the blocked rows
///    (blocked rows synced, unblock rows gone)
///  - BlockListDao.mergeRestored(): blocks from the contact backup this device has no row of
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
  /// the server to take next. [nickname] is kept with a block (null keeps
  /// none).
  Future<void> setBlocked(
    String snowId,
    bool blocked,
    int nowMs, {
    String? nickname,
  }) =>
      into(blockedAccounts).insertOnConflictUpdate(
        BlockedAccountsCompanion.insert(
          snowId: snowId,
          blocked: blocked,
          synced: const Value(false),
          updatedAtMs: nowMs,
          nickname: Value(nickname),
        ),
      );

  /// The server's tags now hold exactly the rows that were blocked at
  /// [snapshotMs] or before: those are marked synced and unblock rows of
  /// that time go. A row changed after [snapshotMs] is not touched (it is
  /// sent by itself).
  Future<void> markAllSynced(int snapshotMs) => transaction(() async {
        for (final row in await select(blockedAccounts).get()) {
          if (row.updatedAtMs > snapshotMs) continue;
          if (row.blocked) {
            await (update(blockedAccounts)
                  ..where((b) => b.snowId.equals(row.snowId)))
                .write(const BlockedAccountsCompanion(synced: Value(true)));
          } else {
            await (delete(blockedAccounts)
                  ..where((b) => b.snowId.equals(row.snowId)))
                .go();
          }
        }
      });

  /// Blocks of the contact backup ([blocks]: snowId → nickname) that this
  /// device has no row of: taken in as blocked, not synced (the server's
  /// tags are replaced after a restore). A row this device has — a block or
  /// an unblock it made — is never overridden. Returns the accounts taken in.
  /// At most [limit] are taken in (the list's cap).
  Future<List<String>> mergeRestored(
    Map<String, String?> blocks,
    int nowMs, {
    required int limit,
  }) =>
      transaction(() async {
        final held = {
          for (final r in await select(blockedAccounts).get()) r.snowId,
        };
        final taken = <String>[];
        for (final e in blocks.entries) {
          if (taken.length >= limit) break;
          if (held.contains(e.key)) continue;
          await into(blockedAccounts).insert(
            BlockedAccountsCompanion.insert(
              snowId: e.key,
              blocked: true,
              synced: const Value(false),
              updatedAtMs: nowMs,
              nickname: Value(e.value),
            ),
          );
          taken.add(e.key);
        }
        return taken;
      });

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
}
