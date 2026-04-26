/// @file        attachment_dao.dart
/// @description Attachments data access object — Signal AttachmentTable pattern applied.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-01
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-03)
///
/// @functions
///  - AttachmentDao: attachments DAO
///  - watchForMessage(): per-message reactive attachment stream
///  - insertAttachment(): insert a single attachment
///  - insertAttachments(): batch insert multiple attachments
///  - finalizeDownload(): download completed -> DONE + localPath
///  - markStarted(): download started
///  - markFailed(): download failed
///  - getPendingDownloads(): query unfinished downloads (on app restart)
///  - getForMessage(): query attachments for a message

import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/attachments_table.dart';

part 'attachment_dao.g.dart';

@DriftAccessor(tables: [LocalAttachments])
class AttachmentDao extends DatabaseAccessor<SnowDatabase>
    with _$AttachmentDaoMixin {
  AttachmentDao(super.db);

  /// Watch attachments for a specific message (reactive stream).
  /// Fires when any attachment's transferState or localPath changes.
  Stream<List<LocalAttachment>> watchForMessage(String messageId) {
    return (select(localAttachments)
          ..where((a) => a.messageId.equals(messageId))
          ..orderBy([
            (a) => OrderingTerm(
                expression: a.displayOrder, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  /// Get attachments for a message (one-shot).
  Future<List<LocalAttachment>> getForMessage(String messageId) {
    return (select(localAttachments)
          ..where((a) => a.messageId.equals(messageId))
          ..orderBy([
            (a) => OrderingTerm(
                expression: a.displayOrder, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Insert a single attachment.
  Future<void> insertAttachment(LocalAttachmentsCompanion attachment) {
    return into(localAttachments).insertOnConflictUpdate(attachment);
  }

  /// Insert multiple attachments (batch).
  Future<void> insertAttachments(
      List<LocalAttachmentsCompanion> attachments) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(localAttachments, attachments);
    });
  }

  /// Mark download as started.
  Future<void> markStarted(String attachmentId) {
    return (update(localAttachments)
          ..where((a) => a.id.equals(attachmentId)))
        .write(const LocalAttachmentsCompanion(
      transferState: Value(TransferState.started),
    ));
  }

  /// Finalize download: set localPath and transferState = DONE.
  Future<void> finalizeDownload(String attachmentId, String localPath) {
    return (update(localAttachments)
          ..where((a) => a.id.equals(attachmentId)))
        .write(LocalAttachmentsCompanion(
      localPath: Value(localPath),
      transferState: const Value(TransferState.done),
    ));
  }

  /// Mark download as failed.
  Future<void> markFailed(String attachmentId) {
    return (update(localAttachments)
          ..where((a) => a.id.equals(attachmentId)))
        .write(const LocalAttachmentsCompanion(
      transferState: Value(TransferState.failed),
    ));
  }

  /// Update messageId on all attachments (when server assigns new message ID).
  Future<void> updateMessageId(String oldMessageId, String newMessageId) {
    return (update(localAttachments)
          ..where((a) => a.messageId.equals(oldMessageId)))
        .write(LocalAttachmentsCompanion(
      messageId: Value(newMessageId),
    ));
  }

  /// Delete all attachments for a message (cascade delete for expiring messages).
  Future<int> deleteForMessage(String messageId) {
    return (delete(localAttachments)
          ..where((a) => a.messageId.equals(messageId)))
        .go();
  }

  /// Get all attachments with incomplete download (for restart resume).
  /// Includes failed state — transient errors (network, auth) should be retried.
  Future<List<LocalAttachment>> getPendingDownloads() {
    return (select(localAttachments)
          ..where((a) =>
              a.transferState.equals(TransferState.pending) |
              a.transferState.equals(TransferState.started) |
              a.transferState.equals(TransferState.failed)))
        .get();
  }

  /// Get all completed attachments (for missing-file detection on startup).
  Future<List<LocalAttachment>> getDoneAttachments() {
    return (select(localAttachments)
          ..where((a) => a.transferState.equals(TransferState.done)))
        .get();
  }
}
