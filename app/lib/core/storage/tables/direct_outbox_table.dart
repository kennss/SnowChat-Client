/// @file        direct_outbox_table.dart
/// @description The 1:1 outbox (schema v17): one row per outgoing 1:1 message that has not been
///              taken by the server yet. The message itself is a local_messages row shown as
///              `sending`; this row is the job that sends it — DirectOutbox drains it whenever
///              the socket is connected, oldest first per peer, and removes it on the server's
///              ack. Design: Documentation/TO-DO/2026-11-21-direct-outbox-design.md.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (a `control` job — a contact notice — has no local_messages row: its
///              id is a random UUID and its payload is the inner JSON itself). Earlier 2026-11-21
///
/// @functions
///  - DirectOutboxJobs: one send job per outgoing 1:1 message (data class DirectOutboxRow)
///  - DirectOutboxPhase: what the job does next — upload the attachment, or send
library;

import 'package:drift/drift.dart';

/// What a job does next.
abstract final class DirectOutboxPhase {
  /// The attachment (file / voice) is not on the server yet: encrypt the kept
  /// local copy, upload it, then send.
  static const String upload = 'upload';

  /// Everything is ready: encrypt the message for the peer and send it.
  static const String send = 'send';
}

@DataClassName('DirectOutboxRow')
@TableIndex(name: 'idx_direct_outbox_peer', columns: {#peer, #createdAtMs})
class DirectOutboxJobs extends Table {
  @override
  String get tableName => 'direct_outbox';

  /// The local message id (`msg_…`) — also the `cid` the peer deduplicates
  /// by. A control job (kind `control`): a random UUID of its own.
  TextColumn get messageId => text()();

  /// The peer ("snow" + 32 hex). A 1:1 room's id is the peer's snowId.
  TextColumn get peer => text().withLength(min: 36, max: 36)();

  /// `text`, `file` or `voice` (MessageType name), or `control` (a contact
  /// notice — DirectOutbox.controlKind).
  TextColumn get kind => text()();

  /// DirectOutboxPhase.upload or DirectOutboxPhase.send.
  TextColumn get phase => text()();

  /// What the job needs to send without the screen that started it (JSON):
  /// text, ttl, reply fields; for an attachment the kept copy's relative
  /// path, file name, MIME type, size, voice duration, and — once uploaded —
  /// the E2EE metadata (file id and key); for a control job the inner JSON,
  /// whether it travels as a control row and whether it carries the name
  /// certificate. Encrypted at rest with the rest of the database; never
  /// sent anywhere as it is.
  TextColumn get payload => text()();

  /// When the message was written (local clock, ms). Orders a peer's jobs;
  /// a job older than DirectOutbox.maxAge fails.
  IntColumn get createdAtMs => integer()();

  /// Sends tried and not acknowledged (backoff grows with it).
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Not before this time (local clock, ms); 0 = now.
  IntColumn get nextAttemptAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {messageId};
}
