/// @file        gv2_inbox_store.dart
/// @description Group protocol v2 — the only writer of the local inbox tables
///              (gv2_inbox, gv2_seen). Envelopes are stored here before the
///              server row is acknowledged, wait here for whatever they need,
///              and leave a digest behind once handled so that the same
///              envelope is never handled twice (design document §7.4).
///              Ordering, lanes and the handling itself live in
///              gv2_inbox.dart.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (keyWaitsOf(); storeInvite() — an invite from the 1:1 path, kept before it is acknowledged). Earlier 2026-11-21 (hasSyncWaits()). Earlier 2026-11-20
///
/// @functions
///  - Gv2InboxStore.storeNew(): store envelopes not stored or handled before
///  - Gv2InboxStore.unclassified() / classify(): give group envelopes a group
///  - Gv2InboxStore.readyLanes() / ready(): what is waiting its turn
///  - Gv2InboxStore.waitingSyncLanes(): groups with rows waiting for the log
///  - Gv2InboxStore.finish(): a row is handled or dropped
///  - Gv2InboxStore.park(): a row waits for a key or for the change log
///  - Gv2InboxStore.requeue(): a row stays ready (now in a group's lane)
///  - Gv2InboxStore.keepOpened(): a row's payload is what its handler decrypted
///  - Gv2InboxStore.keyWaitsOf(): rows of a group waiting for a sender's key
///  - Gv2InboxStore.wakeKey() / wakeSync() / wakeAllKeys(): waiting rows
///    become ready again
///  - Gv2InboxStore.hasKeyWaits() / hasSyncWaits(): whether rows wait
///  - Gv2InboxStore.storeInvite(): keep an invite that came on the 1:1 path
///  - Gv2InboxStore.failed(): count a failed attempt
///  - Gv2InboxStore.expire() / pruneSeen(): forget what is too old
///  - Gv2InboxStore.markMessage(): a group message is handled (once)
///  - Gv2InboxStore.messageHandled(): whether it was
///  - Gv2InboxStore.conversationOfServerRow(): what a push notification opens
///  - Gv2IncomingEnvelope: an envelope about to be stored
///
/// Notes:
///  - The empty string names the pairwise lane: rows with no group yet.
///  - Nothing here logs: rows hold message content and group ids.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:drift/drift.dart';

import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';

part 'gv2_inbox_store.g.dart';

/// The lane of rows that have no group yet: pairwise envelopes before their
/// handler has looked at them.
const String gv2PairwiseLane = '';

/// An envelope about to be stored.
class Gv2IncomingEnvelope {
  final String serverRowId;

  /// SHA-256 of [envelope].
  final Uint8List digest;
  final Gv2InboxKind kind;
  final Uint8List envelope;

  const Gv2IncomingEnvelope({
    required this.serverRowId,
    required this.digest,
    required this.kind,
    required this.envelope,
  });
}

@DriftAccessor(tables: [Gv2InboxRows, Gv2Seen, Gv2MessageIds])
class Gv2InboxStore extends DatabaseAccessor<SnowDatabase>
    with _$Gv2InboxStoreMixin {
  Gv2InboxStore(super.db);

  /// Store each of [envelopes] that is neither in the inbox nor handled
  /// before, in the given order, in one transaction. Returns how many were
  /// stored. Pairwise envelopes are ready at once; group envelopes wait to
  /// be given their group.
  Future<int> storeNew(
    List<Gv2IncomingEnvelope> envelopes, {
    required int nowMs,
  }) {
    if (envelopes.isEmpty) return Future.value(0);
    return transaction(() async {
      final digests = [for (final e in envelopes) e.digest];
      final known = <String>{
        for (final row in await (select(
          gv2InboxRows,
        )..where((t) => t.digest.isIn(digests))).get())
          _key(row.digest),
        for (final row in await (select(
          gv2Seen,
        )..where((t) => t.digest.isIn(digests))).get())
          _key(row.digest),
      };
      var stored = 0;
      for (final e in envelopes) {
        // Also catches the same envelope twice in one batch.
        if (!known.add(_key(e.digest))) continue;
        await into(gv2InboxRows).insert(
          Gv2InboxRowsCompanion.insert(
            serverRowId: e.serverRowId,
            digest: e.digest,
            kind: e.kind,
            payload: e.envelope,
            state: e.kind == Gv2InboxKind.pairwise
                ? Gv2InboxState.ready
                : Gv2InboxState.received,
            receivedAtMs: nowMs,
          ),
        );
        stored++;
      }
      return stored;
    });
  }

  /// Keep the invite message [invite] that came from [senderSnowId] on the
  /// 1:1 sealed path (in the 1:1 message [serverRowId]) as a ready row of
  /// the pairwise lane, unless the same invite from the same sender is
  /// stored or was handled before. Returns whether it was stored. Needs no
  /// group runtime: the 1:1 queue calls it before it acknowledges.
  Future<bool> storeInvite({
    required String serverRowId,
    required String senderSnowId,
    required Uint8List invite,
    required int nowMs,
  }) {
    final payload = Uint8List.fromList([...ascii.encode(senderSnowId), ...invite]);
    final digest = Uint8List.fromList(hash.sha256.convert(payload).bytes);
    return transaction(() async {
      final inbox = await (select(
        gv2InboxRows,
      )..where((t) => t.digest.equals(digest))).getSingleOrNull();
      final seen = await (select(
        gv2Seen,
      )..where((t) => t.digest.equals(digest))).getSingleOrNull();
      if (inbox != null || seen != null) return false;
      await into(gv2InboxRows).insert(
        Gv2InboxRowsCompanion.insert(
          serverRowId: serverRowId,
          digest: digest,
          kind: Gv2InboxKind.invite,
          payload: payload,
          unsealed: const Value(true),
          state: Gv2InboxState.ready,
          receivedAtMs: nowMs,
        ),
      );
      return true;
    });
  }

  /// Group envelopes whose group is not known yet, oldest first.
  Future<List<Gv2InboxRow>> unclassified({int limit = 200, int after = 0}) =>
      (select(gv2InboxRows)
            ..where(
              (t) =>
                  t.state.equalsValue(Gv2InboxState.received) &
                  t.localId.isBiggerThanValue(after),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.localId)])
            ..limit(limit))
          .get();

  /// [localId] belongs to [groupId] and waits its turn there.
  Future<void> classify(int localId, String groupId) =>
      (update(gv2InboxRows)..where((t) => t.localId.equals(localId))).write(
        Gv2InboxRowsCompanion(
          groupId: Value(groupId),
          state: const Value(Gv2InboxState.ready),
        ),
      );

  /// The lanes that have ready rows: group ids, and [gv2PairwiseLane].
  Future<Set<String>> readyLanes() async {
    final rows =
        await (selectOnly(gv2InboxRows, distinct: true)
              ..addColumns([gv2InboxRows.groupId])
              ..where(gv2InboxRows.state.equalsValue(Gv2InboxState.ready)))
            .get();
    return {for (final r in rows) r.read(gv2InboxRows.groupId) ?? gv2PairwiseLane};
  }

  /// The groups that have rows waiting for their change log.
  Future<Set<String>> waitingSyncLanes() async {
    final rows =
        await (selectOnly(gv2InboxRows, distinct: true)
              ..addColumns([gv2InboxRows.groupId])
              ..where(
                gv2InboxRows.state.equalsValue(Gv2InboxState.waitingSync),
              ))
            .get();
    return {for (final r in rows) ?r.read(gv2InboxRows.groupId)};
  }

  /// Ready rows of [lane], oldest first, leaving out [skip].
  Future<List<Gv2InboxRow>> ready(
    String lane, {
    Set<int> skip = const {},
    int limit = 50,
  }) =>
      (select(gv2InboxRows)
            ..where(
              (t) =>
                  t.state.equalsValue(Gv2InboxState.ready) &
                  (lane == gv2PairwiseLane
                      ? t.groupId.isNull()
                      : t.groupId.equals(lane)) &
                  (skip.isEmpty
                      ? const Constant(true)
                      : t.localId.isNotIn(skip)),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.localId)])
            ..limit(limit))
          .get();

  /// The row of [localId], or null when it is gone.
  Future<Gv2InboxRow?> row(int localId) => (select(
    gv2InboxRows,
  )..where((t) => t.localId.equals(localId))).getSingleOrNull();

  /// Rows of every state, oldest first. For diagnostics and tests.
  Future<List<Gv2InboxRow>> allRows() =>
      (select(gv2InboxRows)..orderBy([(t) => OrderingTerm.asc(t.localId)])).get();

  /// [row] is handled ([conversationId] set: shown there) or dropped. The row
  /// goes; its digest stays in gv2_seen.
  Future<void> finish(
    Gv2InboxRow row, {
    String? conversationId,
    required int day,
  }) async {
    await (delete(gv2InboxRows)..where((t) => t.localId.equals(row.localId))).go();
    await into(gv2Seen).insertOnConflictUpdate(
      Gv2SeenCompanion.insert(
        digest: row.digest,
        serverRowId: row.serverRowId,
        conversationId: Value(conversationId),
        day: day,
      ),
    );
  }

  /// [localId] waits ([state] is waitingKey or waitingSync) in [groupId].
  /// [keep], when given, replaces the payload (it has been decrypted).
  Future<void> park(
    int localId, {
    required Gv2InboxState state,
    required String groupId,
    String? waitFor,
    Uint8List? keep,
  }) {
    assert(
      state == Gv2InboxState.waitingKey || state == Gv2InboxState.waitingSync,
    );
    return (update(gv2InboxRows)..where((t) => t.localId.equals(localId))).write(
      Gv2InboxRowsCompanion(
        state: Value(state),
        groupId: Value(groupId),
        waitFor: Value(waitFor),
        payload: keep == null ? const Value.absent() : Value(keep),
        unsealed: keep == null ? const Value.absent() : const Value(true),
      ),
    );
  }

  /// The payload of [localId] is now [opened] (what its handler decrypted).
  Future<void> keepOpened(int localId, Uint8List opened) =>
      (update(gv2InboxRows)..where((t) => t.localId.equals(localId))).write(
        Gv2InboxRowsCompanion(payload: Value(opened), unsealed: const Value(true)),
      );

  /// [localId] stays ready, now in [groupId]. [keep], when given, replaces
  /// the payload.
  Future<void> requeue(
    int localId, {
    required String groupId,
    Uint8List? keep,
  }) => (update(gv2InboxRows)..where((t) => t.localId.equals(localId))).write(
    Gv2InboxRowsCompanion(
      state: const Value(Gv2InboxState.ready),
      groupId: Value(groupId),
      waitFor: const Value(null),
      payload: keep == null ? const Value.absent() : Value(keep),
      unsealed: keep == null ? const Value.absent() : const Value(true),
    ),
  );

  /// Rows of [groupId] waiting for the Sender Key of [sender] are ready.
  /// Returns their local ids.
  Future<List<int>> wakeKey(String groupId, String sender) => _wake(
    (t) =>
        t.groupId.equals(groupId) &
        t.state.equalsValue(Gv2InboxState.waitingKey) &
        t.waitFor.equals(sender),
  );

  /// Rows of [groupId] waiting for the change log are ready. Returns their
  /// local ids.
  Future<List<int>> wakeSync(String groupId) => _wake(
    (t) =>
        t.groupId.equals(groupId) &
        t.state.equalsValue(Gv2InboxState.waitingSync),
  );

  /// Whether any row waits for the change log (such rows make their group
  /// sync again from time to time).
  Future<bool> hasSyncWaits() async =>
      await (select(gv2InboxRows)
            ..where((t) => t.state.equalsValue(Gv2InboxState.waitingSync))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  /// How many rows of [groupId] wait for a key of [sender] — counted up to
  /// [atMost] (the caller only asks whether a cap is reached).
  Future<int> keyWaitsOf(String groupId, String sender, {required int atMost}) async {
    final rows = await (select(gv2InboxRows)
          ..where(
            (t) =>
                t.state.equalsValue(Gv2InboxState.waitingKey) &
                t.groupId.equals(groupId) &
                t.waitFor.equals(sender),
          )
          ..limit(atMost))
        .get();
    return rows.length;
  }

  /// Whether any row waits for a Sender Key (such rows are looked at again
  /// from time to time).
  Future<bool> hasKeyWaits() async =>
      await (select(gv2InboxRows)
            ..where((t) => t.state.equalsValue(Gv2InboxState.waitingKey))
            ..limit(1))
          .getSingleOrNull() !=
      null;

  /// Every row waiting for a key is ready again (its handler looks whether
  /// the key is there now, and asks for it again when it is not). Returns
  /// how many.
  Future<int> wakeAllKeys() =>
      (update(gv2InboxRows)
            ..where((t) => t.state.equalsValue(Gv2InboxState.waitingKey)))
          .write(
            const Gv2InboxRowsCompanion(
              state: Value(Gv2InboxState.ready),
              waitFor: Value(null),
            ),
          );

  Future<List<int>> _wake(Expression<bool> Function($Gv2InboxRowsTable) where) =>
      transaction(() async {
        final rows = await (select(gv2InboxRows)..where(where)).get();
        if (rows.isEmpty) return const <int>[];
        final ids = [for (final r in rows) r.localId];
        await (update(gv2InboxRows)..where((t) => t.localId.isIn(ids))).write(
          const Gv2InboxRowsCompanion(
            state: Value(Gv2InboxState.ready),
            waitFor: Value(null),
          ),
        );
        return ids;
      });

  /// One more failed attempt at [localId]. Returns the new count.
  Future<int> failed(int localId) => transaction(() async {
    final current = await row(localId);
    if (current == null) return 0;
    final attempts = current.attempts + 1;
    await (update(gv2InboxRows)..where((t) => t.localId.equals(localId))).write(
      Gv2InboxRowsCompanion(attempts: Value(attempts)),
    );
    return attempts;
  });

  /// Drop every row received before [beforeMs], whatever its state. Returns
  /// how many went.
  Future<int> expire({required int beforeMs, required int day}) =>
      transaction(() async {
        final rows = await (select(
          gv2InboxRows,
        )..where((t) => t.receivedAtMs.isSmallerThanValue(beforeMs))).get();
        for (final row in rows) {
          await finish(row, day: day);
        }
        return rows.length;
      });

  /// Forget digests and message ids handled before [beforeDay]. Returns how
  /// many digests went.
  Future<int> pruneSeen({required int beforeDay}) async {
    await (delete(
      gv2MessageIds,
    )..where((t) => t.day.isSmallerThanValue(beforeDay))).go();
    return (delete(
      gv2Seen,
    )..where((t) => t.day.isSmallerThanValue(beforeDay))).go();
  }

  /// Record that the group message [localMessageId] (32 bytes) is handled.
  /// Returns false when it was handled before — the caller then does nothing
  /// more with it. Call inside the transaction that stores the message.
  Future<bool> markMessage(Uint8List localMessageId, {required int day}) =>
      transaction(() async {
        final held =
            await (select(gv2MessageIds)
                  ..where((t) => t.localMessageId.equals(localMessageId)))
                .getSingleOrNull();
        if (held != null) return false;
        await into(gv2MessageIds).insert(
          Gv2MessageIdsCompanion.insert(
            localMessageId: localMessageId,
            day: day,
          ),
        );
        return true;
      });

  /// Whether the group message [localMessageId] (32 bytes) was handled
  /// (shown, or taken back before it arrived).
  Future<bool> messageHandled(Uint8List localMessageId) async =>
      await (select(gv2MessageIds)
            ..where((t) => t.localMessageId.equals(localMessageId)))
          .getSingleOrNull() !=
      null;

  /// The conversation an envelope that came in [serverRowId] is shown in —
  /// or will be, once handled: a group envelope waiting in the inbox belongs
  /// to its group's conversation. Null when it is not known (yet).
  Future<String?> conversationOfServerRow(String serverRowId) async {
    final seen =
        await (select(gv2Seen)
              ..where((t) => t.serverRowId.equals(serverRowId))
              ..limit(1))
            .getSingleOrNull();
    if (seen != null) return seen.conversationId;
    final pending =
        await (select(gv2InboxRows)
              ..where(
                (t) =>
                    t.serverRowId.equals(serverRowId) &
                    t.kind.equalsValue(Gv2InboxKind.group),
              )
              ..limit(1))
            .getSingleOrNull();
    return pending?.groupId;
  }

  static String _key(Uint8List digest) => String.fromCharCodes(digest);
}
