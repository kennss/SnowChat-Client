/// @file        pending_transfer_dao.dart
/// @description Wallet V2 Phase 1 — PendingTransfers DAO. CRUD + state transitions + recovery queries.
///              Tracks in-flight transfers (sender broadcast -> recipient accept -> tx confirm).
///              On app restart, recoverPending() looks up RPC results for status='sent' rows.
///              Supports replay verification (isProcessed) + per-peer pending lock (findActiveForPeer).
///              Phase J P1-B follow-up: added findActiveRecipientPending — used by recoverPendingDialogs
///              after a dialog mount-fail when foreground is resumed.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-20
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-20 Phase J P1-B: added findActiveRecipientPending)
///
/// @functions
///  - upsert(): insert new or replace existing row (insertOrReplace)
///  - findByRequestId(): single-row lookup
///  - updateStatus(): status transition + updatedAt refresh
///  - updateSignature(): set signature + status='sent' after broadcast
///  - findInFlight(): recovery candidates (sender role + status='sent' && signature != null)
///  - findActiveRecipientPending(): Phase J P1-B — recipient role + status='pending'
///                                   (re-shown after dialog mount-fail when foreground returns)
///  - findActiveForPeer(): per-peer lock — rows currently pending/sent
///  - isProcessed(): replay verification (terminal status)
///  - deleteOldFinalized(): clean up old terminal rows (24h retention)

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/pending_transfers_table.dart';

part 'pending_transfer_dao.g.dart';

/// PendingTransfers table accessor.
@DriftAccessor(tables: [PendingTransfers])
class PendingTransferDao extends DatabaseAccessor<SnowDatabase>
    with _$PendingTransferDaoMixin {
  PendingTransferDao(super.db);

  /// Insert new or replace existing row. Called when sender sends transfer_request,
  /// and when recipient receives transfer_request.
  Future<int> upsert(PendingTransfersCompanion entry) {
    return into(pendingTransfers).insert(
      entry,
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Single-row lookup. Null if absent.
  Future<PendingTransfer?> findByRequestId(String requestId) {
    return (select(pendingTransfers)
          ..where((t) => t.requestId.equals(requestId)))
        .getSingleOrNull();
  }

  /// Status transition + updatedAt refresh.
  /// The caller is responsible for the correctness of the status value
  /// (`pending` / `sent` / `completed` / `failed` / `timeout`). (Recommend converting from an enum at the service layer.)
  Future<int> updateStatus(String requestId, String status) {
    return (update(pendingTransfers)
          ..where((t) => t.requestId.equals(requestId)))
        .write(PendingTransfersCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// After broadcast, set signature + status='sent' together.
  Future<int> updateSignature({
    required String requestId,
    required String signature,
  }) {
    return (update(pendingTransfers)
          ..where((t) => t.requestId.equals(requestId)))
        .write(PendingTransfersCompanion(
      signature: Value(signature),
      status: const Value('sent'),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// recoverPending(): rows to look up via RPC getSignatureStatus on app restart.
  /// Sender-role rows with status='sent' && signature != null.
  Future<List<PendingTransfer>> findInFlight() {
    return (select(pendingTransfers)
          ..where((t) =>
              t.role.equals('sender') &
              t.status.equals('sent') &
              t.signature.isNotNull()))
        .get();
  }

  /// Phase J P1-B: recipient-role + status='pending' rows.
  ///
  /// **Used by**: TransferService.recoverPendingDialogs() — on foreground resume,
  /// reconstructs the rows retained from a dialog mount-fail and re-shows the dialog.
  ///
  /// **note**: expiry (10 min) check is the caller's responsibility (compare createdAt). This query
  /// only filters by 'pending' status.
  Future<List<PendingTransfer>> findActiveRecipientPending() {
    return (select(pendingTransfers)
          ..where((t) =>
              t.role.equals('recipient') & t.status.equals('pending')))
        .get();
  }

  /// Per-peer pending lock (P1-8): check whether an in-flight transfer is in progress to the same peer.
  /// Rows with sender role + status in (pending, sent).
  /// If present, block new transfers and show a "Previous transfer pending" toast.
  Future<PendingTransfer?> findActiveForPeer(String peerSnowchatId) {
    return (select(pendingTransfers)
          ..where((t) =>
              t.role.equals('sender') &
              t.peerSnowchatId.equals(peerSnowchatId) &
              t.status.isIn(['pending', 'sent'])))
        .getSingleOrNull();
  }

  /// Replay verification (P0-2): whether the requestId is already processed (terminal).
  /// True if status is one of completed / failed / timeout → ignore the second handling.
  Future<bool> isProcessed(String requestId) async {
    final existing = await findByRequestId(requestId);
    if (existing == null) return false;
    return const ['completed', 'failed', 'timeout'].contains(existing.status);
  }

  /// Clean up old terminal rows. Default 24h retention.
  /// Call after recoverPending() or while idle. Prevents drift bloat.
  Future<int> deleteOldFinalized({
    Duration retain = const Duration(hours: 24),
  }) {
    final cutoff =
        DateTime.now().subtract(retain).millisecondsSinceEpoch;
    return (delete(pendingTransfers)
          ..where((t) =>
              t.updatedAt.isSmallerThanValue(cutoff) &
              t.status.isIn(['completed', 'failed', 'timeout'])))
        .go();
  }

  /// Diagnostic / debug — total row count.
  Future<int> count() async {
    final query = selectOnly(pendingTransfers)
      ..addColumns([pendingTransfers.requestId.count()]);
    final row = await query.getSingle();
    return row.read(pendingTransfers.requestId.count()) ?? 0;
  }
}
