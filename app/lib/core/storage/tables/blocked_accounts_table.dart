/// @file        blocked_accounts_table.dart
/// @description The accounts this user blocked, kept on this device (X1). What a blocked account
///              sends is dropped where it arrives — sealed messages and controls, the non-sealed
///              1:1, call signals, group invites — before anything is stored or shown. The
///              server drops it too (it knows the sender at the moment it relays); this list is
///              the device's own: it decides also for what was queued before a block reached the
///              server, and while the server cannot be asked.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - BlockedAccounts: one row per account this user blocked, or unblocked while the server
///    did not know yet (data class BlockedAccountRow)
library;

import 'package:drift/drift.dart';

@DataClassName('BlockedAccountRow')
class BlockedAccounts extends Table {
  @override
  String get tableName => 'blocked_accounts';

  /// The account ("snow" + 32 hex).
  TextColumn get snowId => text().withLength(min: 36, max: 36)();

  /// True: blocked. False: unblocked here while the server still has the
  /// block (the row goes once the server took the unblock).
  BoolColumn get blocked => boolean()();

  /// Whether the server holds what this row says.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  /// When this device last changed the row (local clock, ms).
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {snowId};
}
