/// @file        messages_table.dart
/// @description Drift local messages table definition. Signal 3-timestamp pattern + read state column included.
///              Stores decrypted plaintext messages on-device only (21 columns).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-01)
///
/// @functions
///  - LocalMessages: Drift local messages table class (21 columns)

import 'package:drift/drift.dart';

/// Local messages table (decrypted plaintext, exists only on device).
///
/// Schema v2: Expanded from 9 to 21 columns following Signal Android
/// `MessageTable.kt` patterns (02-Signal-Architecture-Reference Section 2.1).
///
/// Key changes from v1:
///  - `timestamp` (DateTime) → 3-timestamp pattern: `dateSent`, `dateReceived`, `dateServer`
///  - `status` (Text) → `outgoingStatus` (Text)
///  - `expiresAt` (DateTime) → `expiresIn` + `expireStarted` (Int)
///  - Added `read` (Bool) — the critical column for unread badge support
///  - Added receipt tracking, notification, remote delete, mention, reply columns
class LocalMessages extends Table {
  // === Basic identity ===
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderSnowchatId => text()();

  // === Timestamps (Signal 3-timestamp pattern) ===
  IntColumn get dateSent => integer()(); // sender-side send time (ms epoch)
  IntColumn get dateReceived => integer()(); // receiver-side receive time (ms epoch)
  IntColumn get dateServer =>
      integer().withDefault(const Constant(-1))(); // server timestamp

  // === Message content ===
  TextColumn get plaintext => text()();
  TextColumn get type =>
      text().withDefault(const Constant('text'))(); // text, file, voice, system

  // === Read state (Signal's core pattern) ===
  BoolColumn get read =>
      boolean().withDefault(const Constant(false))();

  // === Outgoing status (for outgoing messages) ===
  TextColumn get outgoingStatus =>
      text().withDefault(const Constant('sent'))();
  // sending, sent, delivered, read_by_recipient, failed

  // === Receipts ===
  BoolColumn get hasDeliveryReceipt =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get hasReadReceipt =>
      boolean().withDefault(const Constant(false))();

  // === Notification tracking ===
  BoolColumn get notified =>
      boolean().withDefault(const Constant(false))();

  // === Expiring messages ===
  IntColumn get expiresIn =>
      integer().withDefault(const Constant(0))(); // TTL in seconds
  IntColumn get expireStarted =>
      integer().withDefault(const Constant(0))();

  // === Metadata ===
  TextColumn get metadata => text().nullable()(); // JSON blob
  BoolColumn get remoteDeleted =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get mentionsSelf =>
      boolean().withDefault(const Constant(false))();

  // === Reply / quote ===
  TextColumn get replyToId => text().nullable()();

  // === Group chat sender display name ===
  TextColumn get senderDisplayName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
