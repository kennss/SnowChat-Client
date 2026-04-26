/// @file        contacts_table.dart
/// @description Drift contacts table definition. Stores SnowChat ID, display name, public key, and block/trust state.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-29)
///
/// @functions
///  - Contacts: Drift contacts table class

import 'package:drift/drift.dart';

/// Contacts stored locally.
class Contacts extends Table {
  TextColumn get snowChatId => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get publicKeyHex => text().nullable()();
  BoolColumn get isBlocked =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isTrusted =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {snowChatId};
}
