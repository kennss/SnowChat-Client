/// @file        direct_outbox_dao.dart
/// @description The rows of the 1:1 outbox (DirectOutboxJobs) — written only through
///              DirectOutbox (core/messaging/direct_outbox.dart).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - DirectOutboxDao.put(): add a job (or replace the job of the same message)
///  - DirectOutboxDao.allJobs(): every job, oldest first
///  - DirectOutboxDao.job(): the job of one message
///  - DirectOutboxDao.toSend(): an uploaded attachment's job moves to the send phase
///  - DirectOutboxDao.postpone(): a send that did not go through — one more attempt, retry later
///  - DirectOutboxDao.retryAllNow(): every job may go at once (the socket came back)
///  - DirectOutboxDao.remove(): the job is done (sent, failed or its message is gone)
library;

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/direct_outbox_table.dart';

part 'direct_outbox_dao.g.dart';

@DriftAccessor(tables: [DirectOutboxJobs])
class DirectOutboxDao extends DatabaseAccessor<SnowDatabase>
    with _$DirectOutboxDaoMixin {
  DirectOutboxDao(super.db);

  /// Add the job of [row]'s message; a job already there for it is replaced
  /// (a failed message sent again starts over).
  Future<void> put(DirectOutboxJobsCompanion row) =>
      into(directOutboxJobs).insertOnConflictUpdate(row);

  /// Every job, oldest first (ties by message id, for a stable order).
  Future<List<DirectOutboxRow>> allJobs() => (select(directOutboxJobs)
        ..orderBy([
          (j) => OrderingTerm.asc(j.createdAtMs),
          (j) => OrderingTerm.asc(j.messageId),
        ]))
      .get();

  Future<DirectOutboxRow?> job(String messageId) => (select(directOutboxJobs)
        ..where((j) => j.messageId.equals(messageId)))
      .getSingleOrNull();

  /// The attachment of [messageId] is uploaded: the job sends next, with
  /// [payload] (now holding the E2EE metadata).
  Future<void> toSend(String messageId, String payload) =>
      (update(directOutboxJobs)..where((j) => j.messageId.equals(messageId)))
          .write(DirectOutboxJobsCompanion(
        phase: const Value(DirectOutboxPhase.send),
        payload: Value(payload),
      ));

  /// The job of [messageId] did not go through: [attempts] tries so far, not
  /// again before [nextAttemptAtMs].
  Future<void> postpone(String messageId,
          {required int attempts, required int nextAttemptAtMs}) =>
      (update(directOutboxJobs)..where((j) => j.messageId.equals(messageId)))
          .write(DirectOutboxJobsCompanion(
        attempts: Value(attempts),
        nextAttemptAtMs: Value(nextAttemptAtMs),
      ));

  /// Every waiting job may go now (the attempt counts stay).
  Future<void> retryAllNow() => update(directOutboxJobs)
      .write(const DirectOutboxJobsCompanion(nextAttemptAtMs: Value(0)));

  Future<int> remove(String messageId) =>
      (delete(directOutboxJobs)..where((j) => j.messageId.equals(messageId)))
          .go();
}
