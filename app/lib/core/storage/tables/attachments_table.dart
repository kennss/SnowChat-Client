/// @file        attachments_table.dart
/// @description Attachments table definition — Signal AttachmentTable pattern. N attachments per message (1:N).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-01
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-01)
///
/// @functions
///  - LocalAttachments: drift table class (attachment metadata + transfer state)
///  - TransferState: transfer state constants (matches Signal)

import 'package:drift/drift.dart';

/// Signal's AttachmentTable converted to drift.
/// Supports one or more attachments per message (1:N relationship).
class LocalAttachments extends Table {
  // === Identifiers ===
  TextColumn get id => text()(); // UUID (client-generated)
  TextColumn get messageId => text()(); // FK → local_messages.id
  IntColumn get displayOrder =>
      integer().withDefault(const Constant(0))();

  // === File metadata ===
  TextColumn get contentType => text()(); // MIME type
  TextColumn get fileName => text().nullable()();
  IntColumn get fileSize =>
      integer().withDefault(const Constant(0))();
  IntColumn get width =>
      integer().withDefault(const Constant(0))();
  IntColumn get height =>
      integer().withDefault(const Constant(0))();

  // === Server (remote) ===
  TextColumn get remoteFileId => text().nullable()(); // server fileId
  TextColumn get remoteKey => text().nullable()(); // E2EE decryption key (Phase 4)
  TextColumn get remoteDigest => text().nullable()(); // SHA-256 of ciphertext

  // === Local ===
  TextColumn get localPath => text().nullable()(); // download / original file path
  IntColumn get transferState =>
      integer().withDefault(const Constant(2))();
  // 0=done, 1=started, 2=pending, 3=failed

  // === Thumbnail ===
  TextColumn get blurHash => text().nullable()();
  TextColumn get thumbnailPath => text().nullable()();

  // === Flags ===
  BoolColumn get isVoiceNote =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Transfer state constants (matches Signal's TRANSFER_STATE values).
class TransferState {
  static const int done = 0;
  static const int started = 1;
  static const int pending = 2;
  static const int failed = 3;
}
