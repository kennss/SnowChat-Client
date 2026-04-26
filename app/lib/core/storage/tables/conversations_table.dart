/// @file        conversations_table.dart
/// @description Drift conversations table definition. Signal ThreadTable pattern applied.
///              Stores 1:1 and group conversations, snippet, read state, archive/pin state (20 columns).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-19)
///
/// @functions
///  - Conversations: Drift conversations table class (20 columns)

import 'package:drift/drift.dart';

/// Conversations (1:1 and group) stored locally.
///
/// Schema v2: Expanded from 12 to 20 columns following Signal Android
/// `ThreadTable.kt` patterns (02-Signal-Architecture-Reference Section 3.1).
///
/// Key changes from v1:
///  - `lastMessageTime`, `createdAt`, `updatedAt` changed from DateTime to IntColumn (ms epoch)
///  - Added `isRead` (Bool) — thread-level forced unread support
///  - Added `lastSeen`, `lastScrolled` for scroll position tracking
///  - Added `lastMessageId` for quick snippet message lookup
///  - Added `unreadSelfMentionCount` for @mention badge
///  - Added `isArchived`, `isActive`, `pinnedOrder`, `groupId`
class Conversations extends Table {
  // === Basic identity ===
  TextColumn get id => text()();
  TextColumn get type =>
      text().withDefault(const Constant('direct'))(); // direct, group
  TextColumn get title => text().nullable()(); // Group name or null for 1:1
  TextColumn get participantIds => text()(); // JSON array of SnowChat IDs
  TextColumn get groupId => text().nullable()(); // server group ID

  // === Snippet (Signal pattern: denormalize the last message) ===
  TextColumn get lastMessageText => text().nullable()();
  IntColumn get lastMessageTime => integer().nullable()(); // ms epoch
  TextColumn get lastMessageSenderId => text().nullable()();
  TextColumn get lastMessageId => text().nullable()(); // reference to original message

  // === Denormalized Unread Count (Signal's core pattern) ===
  IntColumn get unreadCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get unreadSelfMentionCount =>
      integer().withDefault(const Constant(0))();

  // === Read state (thread-level) ===
  BoolColumn get isRead =>
      boolean().withDefault(const Constant(true))();
  IntColumn get lastSeen =>
      integer().withDefault(const Constant(0))(); // ms epoch
  IntColumn get lastScrolled =>
      integer().withDefault(const Constant(0))();

  // === Conversation attributes ===
  BoolColumn get isPinned =>
      boolean().withDefault(const Constant(false))();
  IntColumn get pinnedOrder => integer().nullable()();
  BoolColumn get isMuted =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isActive =>
      boolean().withDefault(const Constant(true))();

  // === Expiring message setting ===
  IntColumn get disappearingTtl => integer().nullable()(); // seconds

  // === AI auto-translate ===
  BoolColumn get autoTranslateEnabled =>
      boolean().withDefault(const Constant(false))();
  /// Per-conversation translation target language (null falls back to settings.preferredLanguage).
  /// Value: name from SupportedLanguages — 'Korean', 'English', ...
  TextColumn get autoTranslateTargetLang => text().nullable()();

  // === Timestamps ===
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
