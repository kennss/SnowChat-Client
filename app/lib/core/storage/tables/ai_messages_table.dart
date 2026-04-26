/// @file        ai_messages_table.dart
/// @description Drift AI messages table — stores on-device AI conversation history.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-15
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-15)
///
/// @functions
///  - AiMessages: AI conversation messages table class

import 'package:drift/drift.dart';

/// On-device AI conversation messages table.
/// Never sent to the server — fully local.
class AiMessages extends Table {
  /// UUID
  TextColumn get id => text()();

  /// 'user' or 'assistant'
  TextColumn get role => text()();

  /// Message text
  TextColumn get content => text()();

  /// Session ID (for separating conversations)
  TextColumn get sessionId => text().withDefault(const Constant('default'))();

  /// Created at
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
