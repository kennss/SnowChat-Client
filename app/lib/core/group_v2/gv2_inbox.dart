/// @file        gv2_inbox.dart
/// @description Group protocol v2 — the local inbox. Rows of the server's
///              group queue are stored here and acknowledged at once (the
///              server deletes them), then handled on this device: each
///              group's envelopes one at a time in arrival order, pairwise
///              envelopes in a lane of their own, so that a group waiting
///              for a key or for its change log holds up nothing else
///              (design document §7.4).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (the daily pruning of log points and own key records; drainGroup(): a group's lane before a removal of this device; P5.6: a group envelope that matches no group stays (unclassified) until this install has looked at the backup of its groups — groupsKnown; a reinstall whose backup fetch failed dropped them). Earlier 2026-11-21 (P5.6: a row that says the log moved past this device (Gv2WaitForSync.holdsLane) holds its lane — the rows after it are judged after the sync, so a member removed meanwhile cannot post under the old roster). Earlier 2026-11-21 (invite rows (Gv2InboxKind.invite) handled through Gv2InboxHandler.handleInvite). Earlier 2026-11-21 (no afterSync: a handler decides from Gv2InboxItem.syncReachedSince(lastSyncAtMs) — a sync that was only tried says nothing; gv2SyncWaitRetry). Earlier 2026-11-20
///
/// @functions
///  - Gv2QueueRow.tryParse(): a server queue row (REST `gv2` list or socket
///    `gv2_message`)
///  - Gv2Inbox.receive(): store rows, then acknowledge them
///  - Gv2Inbox.flushAcks(): acknowledge what could not be acknowledged before
///  - Gv2Inbox.drain(): handle everything that is ready
///  - Gv2Inbox.requestSync(): catch a group up, after what it has ready
///  - Gv2Inbox.drainGroup(): handle what a group's lane holds now
///  - Gv2Inbox.keyArrived() / synced(): what waiting rows wait for happened
///  - Gv2Inbox.groupsChanged(): the set of groups changed
///  - Gv2Inbox.conversationOfServerRow(): what a push notification opens
///  - Gv2Inbox.classify(): give stored rows their group, handling nothing
///  - (invite rows: an invite that came on the 1:1 path, stored by the 1:1
///    queue before it acknowledged the message — handled in the pairwise
///    lane through Gv2InboxHandler.handleInvite)
///  - Gv2InboxHandler: what handles an envelope (implemented by the
///    messaging layer)
///  - Gv2InboxItem / Gv2InboxOutcome / Gv2Wake: what a handler sees and says
///  - Gv2InboxItem.syncReachedSince() / gv2NotAMember(): when a row that
///    waited for the log may be given up
///
/// Notes:
///  - Acknowledge after store, never before: a row is deleted on the server
///    only once it is in this database. A crash between the two makes the
///    server hand the row out again, and the digest makes it one row here.
///  - Order: rows are handled in the order they were stored. The server's
///    sequence number orders the rows of one fetch (and is used for that)
///    but restarts when the queue empties, so it cannot order rows across
///    fetches. Nothing needs a stricter order: a message whose key has not
///    come yet waits for it, a message from ahead in the change log waits
///    for the log.
///  - Before a group catches up with its change log, its ready rows are
///    handled first: a message sent before a removal is judged by the roster
///    it was sent under (design §7.4). Up to a row that says the log moved
///    past this device (a change notice or a header ahead — holdsLane): the
///    group syncs there, and the rows after it are judged after the sync —
///    they may have been sent after a removal this device had not applied.
///  - A group with rows waiting for its log gets a sync attempt on every
///    drain, and when a pairwise row starts waiting there: no row waits for a
///    sync that nothing would start. While rows wait, the runtime drains
///    again every [gv2SyncWaitRetry]. A handler gives up on what the log
///    does not show only when a sync that started after the row arrived
///    reached the server's head (Gv2InboxItem.syncReachedSince) — never
///    because a sync was merely tried.
///  - A waiting row is dropped 30 days after it arrived — no sender keeps
///    what it sent for longer (and the server keeps an undelivered row at
///    most that long). Digests of handled rows are kept as long.
///  - A pairwise envelope can be decrypted once. Its handler stores what it
///    decrypted (Gv2InboxItem.keepOpened) before acting on it, so a failure
///    afterwards retries from the stored plaintext, never by decrypting
///    again.
///  - Nothing here logs: envelopes, group ids and senders are what this
///    file handles.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_envelope.dart';
import 'gv2_inbox_store.dart';
import 'gv2_outbox.dart' show gv2OwnKeyMaxAge;
import 'gv2_store.dart';

/// How long an envelope may wait on this device, and how long the digest of
/// a handled one is kept.
const Duration gv2InboxRetention = Duration(days: 30);

/// Rows waiting for a Sender Key are handled again this often, so that a
/// key request that went missing is made again.
const Duration gv2KeyWaitRetry = Duration(minutes: 10);

/// Length of a snowId ("snow" + 32 hex) at the head of an invite row.
const int _snowIdLength = 36;

/// Rows waiting for the change log are looked at again this often while
/// they wait (each look syncs their group): a sync that failed — offline,
/// rate limited, a server error — is tried again without waiting for the
/// next envelope or connect.
const Duration gv2SyncWaitRetry = Duration(minutes: 2);

/// A handler that throws this many times on one row has the row dropped.
const int gv2InboxMaxAttempts = 5;

/// Acknowledgements per request (the server takes up to 1,000).
const int _ackChunk = 500;

/// Rows handled per query of a lane.
const int _laneBatch = 50;

/// The server's acknowledgement takes the id in either case
/// (GroupV2QueueService.ack), so the inbox does too: a row whose id it
/// refused could never be acknowledged.
final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _decimal = RegExp(r'^(0|[1-9][0-9]{0,18})$');

/// One row of the server's group queue, as the REST fetch (`gv2` list) and
/// the socket (`gv2_message`) deliver it.
class Gv2QueueRow {
  /// The row id (a UUID); acknowledging it deletes the row.
  final String id;

  /// Per-recipient sequence number: orders the rows of one fetch.
  final int seq;

  /// The envelope: may be anything — the inbox decides.
  final Uint8List envelope;

  const Gv2QueueRow({
    required this.id,
    required this.seq,
    required this.envelope,
  });

  /// The row in [json], or null when it is not one: an id that is not a
  /// UUID cannot be acknowledged, so such a row is ignored. A row
  /// with a usable id but unusable envelope comes back with an empty
  /// envelope — it is acknowledged and dropped. Never throws.
  static Gv2QueueRow? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || !_uuid.hasMatch(id)) return null;
    final seqText = json['seq'];
    final seq = seqText is String && _decimal.hasMatch(seqText)
        ? int.tryParse(seqText)
        : null;
    final encoded = json['envelope'];
    Uint8List? envelope;
    if (encoded is String) {
      try {
        envelope = base64Decode(encoded);
        // One encoding only: the server writes canonical base64.
        if (base64Encode(envelope) != encoded) envelope = null;
      } on FormatException {
        envelope = null;
      }
    }
    return Gv2QueueRow(
      id: id,
      seq: seq ?? 0,
      envelope: envelope ?? Uint8List(0),
    );
  }
}

/// Acknowledges server queue rows (deletes them). Throws when it could not.
typedef Gv2Ack = Future<void> Function(List<String> serverRowIds);

/// What a handler is given.
class Gv2InboxItem {
  final String serverRowId;
  final Gv2InboxKind kind;

  /// The envelope as received; or, when [unsealed], what the handler kept
  /// of it the last time.
  final Uint8List payload;
  final bool unsealed;

  /// The group the row belongs to, when known: always for a group envelope,
  /// for a pairwise envelope once its handler named one.
  final String? groupId;

  /// This device's clock, milliseconds.
  final int receivedAtMs;

  /// Earlier attempts that threw.
  final int attempts;


  /// Replace the stored payload with [opened] at once, in its own
  /// transaction, and mark the row unsealed. A handler that decrypts
  /// something that can be decrypted only once (a pairwise envelope: the
  /// 1:1 session moves on) calls this before anything else can fail: if it
  /// then throws, or the app dies, the row is handled again from [opened].
  final Future<void> Function(Uint8List opened) keepOpened;

  const Gv2InboxItem({
    required this.serverRowId,
    required this.kind,
    required this.payload,
    required this.unsealed,
    required this.groupId,
    required this.receivedAtMs,
    required this.attempts,
    required this.keepOpened,
  });

  /// Whether a sync that STARTED after this row arrived reached the
  /// server's head ([lastSyncAtMs]: the start of the last sync of the group
  /// that did — Gv2GroupRow.lastSyncAtMs). Only then does "the log does not
  /// have it" mean anything: a sync that failed (offline, rate limited, a
  /// server error) or started earlier says nothing, and the row waits.
  bool syncReachedSince(int lastSyncAtMs) => lastSyncAtMs >= receivedAtMs;
}

/// Whether the sender of [item] is known not to be a confirmed member of
/// [group]: a sync that started after the row arrived reached the head, and
/// the sender ([member]; null when the log does not name it) is not in the
/// log or failed its account check. A member not checked yet is not known
/// either way — the next sync checks it — and its row waits.
bool gv2NotAMember(Gv2GroupRow group, Gv2MemberRow? member, Gv2InboxItem item) =>
    item.syncReachedSince(group.lastSyncAtMs) &&
    member?.checkState != Gv2MemberCheckState.unchecked;

/// Waiting rows to make ready again, in the same transaction as the outcome
/// that names them.
sealed class Gv2Wake {
  const Gv2Wake();

  /// The Sender Key of [sender] in [groupId] has been installed.
  const factory Gv2Wake.key(String groupId, String sender) = Gv2KeyWake;

  /// [groupId] has caught up with its change log.
  const factory Gv2Wake.sync(String groupId) = Gv2SyncWake;
}

final class Gv2KeyWake extends Gv2Wake {
  final String groupId;
  final String sender;
  const Gv2KeyWake(this.groupId, this.sender);
}

final class Gv2SyncWake extends Gv2Wake {
  final String groupId;
  const Gv2SyncWake(this.groupId);
}

/// Database writes a handler wants committed together with its outcome: in
/// the same transaction as the inbox row leaving or parking. Must touch only
/// the database.
typedef Gv2InboxWrite = Future<void> Function();

/// What a handler decided about an envelope.
sealed class Gv2InboxOutcome {
  const Gv2InboxOutcome();
}

/// Handled. [conversationId]: where it is shown, when it is shown.
/// [afterCommit] runs once [write] and the row's removal are committed (for
/// example to send what [write] queued); not when they fail.
final class Gv2Handled extends Gv2InboxOutcome {
  final String? conversationId;
  final Gv2InboxWrite? write;
  final List<Gv2Wake> wake;
  final void Function()? afterCommit;

  const Gv2Handled({
    this.conversationId,
    this.write,
    this.wake = const [],
    this.afterCommit,
  });
}

/// Not something to handle: forged, for a group this device is not in,
/// too old, of a kind this build does not know, ...
final class Gv2Dropped extends Gv2InboxOutcome {
  const Gv2Dropped();
}

/// Waits for the Sender Key of [sender]. [groupId] is required when the row
/// has no group yet (a pairwise envelope); [keep] replaces the payload when
/// it can be read only once. [afterCommit] as in [Gv2Handled] (for example
/// to send the key request [write] queued).
final class Gv2WaitForKey extends Gv2InboxOutcome {
  final String sender;
  final String? groupId;
  final Uint8List? keep;
  final Gv2InboxWrite? write;
  final void Function()? afterCommit;

  const Gv2WaitForKey({
    required this.sender,
    this.groupId,
    this.keep,
    this.write,
    this.afterCommit,
  });
}

/// Waits for this device to catch up with the change log. The inbox syncs
/// the group once its other ready rows are handled — or at once, before any
/// row after this one, when [holdsLane]: the row says the log has moved past
/// this device (a change notice, or a header ahead of it), so what came after
/// it may have been sent after a change — a removal — this device has not
/// applied, and is judged after the sync (design §7.4).
final class Gv2WaitForSync extends Gv2InboxOutcome {
  final String? groupId;
  final Uint8List? keep;
  final Gv2InboxWrite? write;
  final void Function()? afterCommit;
  final bool holdsLane;

  const Gv2WaitForSync({
    this.groupId,
    this.keep,
    this.write,
    this.afterCommit,
    this.holdsLane = false,
  });
}

/// Handles what comes through the inbox: the messaging layer.
abstract interface class Gv2InboxHandler {
  /// A group envelope of [groupId] (lowercase hex), opened. Nothing in it is
  /// believed yet — see gv2_envelope.dart.
  Future<Gv2InboxOutcome> handleGroupEnvelope(
    String groupId,
    Gv2OpenedEnvelope envelope,
    Gv2InboxItem item,
  );

  /// A pairwise envelope (or what was kept of it).
  Future<Gv2InboxOutcome> handlePairwise(Gv2InboxItem item);

  /// Catch [groupId] up with its change log. Returns normally whatever the
  /// result; throws only on a failure of this device.
  Future<void> syncGroup(String groupId);

  /// An invite message that came from [senderSnowId] on the 1:1 sealed path
  /// (Gv2InboxKind.invite): keep it in the group store.
  Future<Gv2InboxOutcome> handleInvite(String senderSnowId, Uint8List invite);
}

/// What [Gv2Inbox.receive] did.
class Gv2ReceiveResult {
  /// Rows stored now (not stored or handled before).
  final int stored;

  /// Whether every row given — and every one left over from before — is
  /// acknowledged.
  final bool acknowledged;

  const Gv2ReceiveResult({required this.stored, required this.acknowledged});
}

/// What became of a row in one attempt (Gv2Inbox._handle).
enum _Step {
  /// Left the inbox, or parked waiting for a key.
  settled,

  /// Parked waiting for the change log.
  waitsForSync,

  /// Parked waiting for the change log, and the rows after it wait for the
  /// sync too (Gv2WaitForSync.holdsLane).
  holdsForSync,

  /// Still ready: tried again in this pass.
  again,

  /// The handler threw: tried again in a later pass.
  later,
}

class _Lane {
  Future<void>? running;
  bool again = false;

  /// A row waits for this group's log without having been handled in this
  /// lane (it came from the pairwise lane, or waited across a restart): the
  /// lane syncs even when it has nothing ready.
  bool syncWanted = false;
}

/// The local inbox. One per signed-in account.
class Gv2Inbox {
  final Gv2InboxStore _store;
  final Gv2Store _groups;
  final Gv2InboxHandler _handler;
  final Gv2Ack _ack;
  final int Function() _nowMs;

  Gv2Inbox({
    required Gv2InboxStore store,
    required Gv2Store groups,
    required Gv2InboxHandler handler,
    required Gv2Ack ack,
    int Function()? nowMs,
    bool Function()? groupsKnown,
  }) : _store = store,
       _groups = groups,
       _handler = handler,
       _ack = ack,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _groupsKnown = groupsKnown ?? (() => true);

  /// Whether this device knows every group it is in. False on a new install
  /// until it has looked at the backup of its groups: an envelope of a group
  /// the backup is about to bring back waits for it instead of being dropped.
  final bool Function() _groupsKnown;

  /// Rows stored (or ignored) but not acknowledged yet.
  final Set<String> _unacked = {};
  Future<bool>? _acking;

  final Map<String, _Lane> _lanes = {};
  Future<void>? _classifying;

  /// Envelope keys of the groups this device holds, by group id.
  Map<String, Gv2EnvelopeKeys>? _keys;

  /// When rows waiting for a key were last made ready again (local clock).
  int _keyWaitsRetriedAtMs = 0;

  /// Counts of keys installed and syncs run: a row that decides to wait
  /// while one of these happened is tried again instead of parked (no lost
  /// wake-up). Counted for all groups together — at worst a row is tried
  /// once more than it had to be.
  int _keyEventCount = 0;
  int _syncEventCount = 0;

  int _day() => _nowMs() ~/ Duration.millisecondsPerDay;

  // ---------------------------------------------------------------------------
  // Receiving
  // ---------------------------------------------------------------------------

  /// Store [rows] (those not stored or handled before), then acknowledge
  /// them. Rows of one fetch are stored in sequence order. Does not handle
  /// anything: call [drain] for that.
  ///
  /// Throws only when storing fails — then nothing is acknowledged, and the
  /// server hands the rows out again.
  Future<Gv2ReceiveResult> receive(List<Gv2QueueRow> rows) async {
    final ordered = [...rows]..sort((a, b) => a.seq.compareTo(b.seq));
    final incoming = <Gv2IncomingEnvelope>[];
    for (final row in ordered) {
      final kind = _kindOf(row.envelope);
      if (kind == null) continue; // Acknowledged below and forgotten.
      incoming.add(
        Gv2IncomingEnvelope(
          serverRowId: row.id,
          digest: Uint8List.fromList(hash.sha256.convert(row.envelope).bytes),
          kind: kind,
          envelope: row.envelope,
        ),
      );
    }
    final stored = await _store.storeNew(incoming, nowMs: _nowMs());
    _unacked.addAll(ordered.map((r) => r.id));
    return Gv2ReceiveResult(stored: stored, acknowledged: await flushAcks());
  }

  static Gv2InboxKind? _kindOf(Uint8List envelope) {
    if (envelope.isEmpty || envelope.length > gv2MaxEnvelopeBytes) return null;
    if (gv2IsGroupEnvelope(envelope)) return Gv2InboxKind.group;
    // A sealed sender envelope: version byte 0x01 (sealed_sender.dart).
    if (envelope[0] == 0x01) return Gv2InboxKind.pairwise;
    return null;
  }

  /// Acknowledge every stored row not acknowledged yet. Returns true when
  /// none is left. Never throws.
  Future<bool> flushAcks() {
    final running = _acking;
    if (running != null) {
      // Rows added meanwhile are sent by one more round afterwards.
      return running.then((_) => flushAcks());
    }
    final round = _flush();
    _acking = round;
    return round.whenComplete(() => _acking = null);
  }

  Future<bool> _flush() async {
    while (_unacked.isNotEmpty) {
      final chunk = _unacked.take(_ackChunk).toList();
      try {
        await _ack(chunk);
      } catch (_) {
        // The server keeps the rows and hands them out again; the digests
        // make them no-ops here. Tried again with the next receive.
        return false;
      }
      _unacked.removeAll(chunk);
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Handling
  // ---------------------------------------------------------------------------

  /// Handle everything that is ready, and return when that is done: expire
  /// what is too old, give group envelopes their group, run every lane —
  /// including lanes that rows handled meanwhile were moved to or woke.
  /// Rows waiting for a key are looked at again every [gv2KeyWaitRetry] (and
  /// on the first drain after a start): their handler asks for the key
  /// again when the first request, or its answer, was lost.
  Future<void> drain() async {
    await _expire();
    await _classify();
    final now = _nowMs();
    if (now - _keyWaitsRetriedAtMs >= gv2KeyWaitRetry.inMilliseconds) {
      _keyWaitsRetriedAtMs = now;
      await _store.wakeAllKeys();
    }
    final lanes = await _store.readyLanes();
    final waiting = await _store.waitingSyncLanes();
    // Pairwise envelopes first: a Sender Key that is already here is
    // installed before the messages it opens are looked at, so those are
    // read now — not parked, to be judged later by a roster that a sync in
    // between may have changed.
    if (lanes.remove(gv2PairwiseLane)) await _kick(gv2PairwiseLane);
    await Future.wait([
      for (final lane in {...lanes, ...waiting})
        _kick(lane, sync: waiting.contains(lane)),
    ]);
    await _settled();
  }

  /// Returns once no lane is running.
  Future<void> _settled() async {
    while (true) {
      final running = [for (final l in _lanes.values) ?l.running];
      if (running.isEmpty) return;
      await Future.wait(running);
    }
  }

  /// Handle what [groupId] has ready, then catch it up with its change log
  /// (through the handler) and handle what waited for that. Returns when the
  /// group's lane is done. For whoever needs the group's log fresh — a
  /// message about to be sent, a change about to be made — without jumping
  /// the envelopes that arrived before (design §7.4).
  Future<void> requestSync(String groupId) async {
    // Envelopes stored but not given their group yet belong to "what
    // arrived before".
    await _classify();
    await _kick(groupId, sync: true);
  }

  /// Handle what [groupId]'s lane holds now — pairwise envelopes first (a
  /// Sender Key they bring opens the group's rows) — and return when that
  /// is done. Before a change of this device that removes a member: what
  /// that member sent before it, and is here already, is read under the
  /// roster it was sent to (design §7.4), not dropped by the new one.
  Future<void> drainGroup(String groupId) async {
    await _classify();
    await _kick(gv2PairwiseLane);
    await _kick(groupId);
  }

  /// The Sender Key of [sender] in [groupId] has been installed: rows
  /// waiting for it are handled.
  Future<void> keyArrived(String groupId, String sender) async {
    _keyEventCount++;
    if ((await _store.wakeKey(groupId, sender)).isNotEmpty) {
      await _kick(groupId);
    }
  }

  /// [groupId] has caught up with its change log (by anyone's doing): rows
  /// waiting for that are handled.
  Future<void> synced(String groupId) async {
    _syncEventCount++;
    if ((await _store.wakeSync(groupId)).isNotEmpty) await _kick(groupId);
  }

  /// A group was added or removed: group envelopes are matched against the
  /// current set from now on.
  void groupsChanged() => _keys = null;

  /// The conversation the envelope of server row [serverRowId] is shown in,
  /// or will be. Null when not known (yet).
  Future<String?> conversationOfServerRow(String serverRowId) =>
      _store.conversationOfServerRow(serverRowId);

  Future<void> _expire() async {
    final now = _nowMs();
    final day = _day();
    await _store.expire(
      beforeMs: now - gv2InboxRetention.inMilliseconds,
      day: day,
    );
    if (_prunedDay == day) return;
    _prunedDay = day;
    await _store.pruneSeen(beforeDay: day - gv2InboxRetention.inDays);
    // Once a day: the points of the logs no envelope can name any more, and
    // the records of own keys given that long ago.
    await _groups.pruneOld(
      headsBeforeMs: now - gv2InboxRetention.inMilliseconds,
      deliveriesBeforeMs:
          now - (gv2InboxRetention + gv2OwnKeyMaxAge).inMilliseconds,
    );
  }

  /// The local day of the last daily pruning.
  int? _prunedDay;

  /// Give the stored rows that have no group yet their group (rows of a
  /// group this device holds), without handling anything. For a caller that
  /// only needs to know where a row belongs (a tapped push).
  Future<void> classify() => _classify();

  Future<void> _classify() =>
      _classifying ??= _classifyAll().whenComplete(() => _classifying = null);

  Future<void> _classifyAll() async {
    var reloaded = false;
    var after = 0;
    while (true) {
      final rows = await _store.unclassified(after: after);
      if (rows.isEmpty) return;
      after = rows.last.localId;
      for (final row in rows) {
        var match = gv2OpenEnvelopeAmong(row.payload, (await _keyMap()).values);
        if (match == null && !reloaded) {
          // A group added since the keys were read.
          reloaded = true;
          _keys = null;
          match = gv2OpenEnvelopeAmong(row.payload, (await _keyMap()).values);
        }
        if (match == null) {
          // No group of this device: one it never had, or one whose keys it
          // no longer has — nothing can open it later either. Unless this
          // install has not looked at its backup yet: the group may come
          // back from it, and the row stays.
          if (_groupsKnown()) await _store.finish(row, day: _day());
        } else {
          await _store.classify(row.localId, gv2Hex(match.keys.groupId));
        }
      }
    }
  }

  Future<Map<String, Gv2EnvelopeKeys>> _keyMap() async {
    final cached = _keys;
    if (cached != null) return cached;
    final keys = <String, Gv2EnvelopeKeys>{
      for (final g in await _groups.groups())
        g.groupId: Gv2EnvelopeKeys.derive(g.masterKey, gv2Unhex(g.groupId)),
    };
    _keys = keys;
    return keys;
  }

  /// Run [lane] until it has nothing ready. A lane runs one row at a time;
  /// kicking a running lane makes it look again when it is done. [sync]: the
  /// group has rows waiting for its log that this lane has not seen.
  Future<void> _kick(String lane, {bool sync = false}) {
    final state = _lanes.putIfAbsent(lane, _Lane.new)..again = true;
    if (sync) state.syncWanted = true;
    return state.running ??= _runLane(
      lane,
      state,
    ).whenComplete(() => state.running = null);
  }

  Future<void> _runLane(String lane, _Lane state) async {
    while (state.again) {
      state.again = false;
      await _pass(lane, state);
    }
  }

  Future<void> _pass(String lane, _Lane state) async {
    final isGroup = lane != gv2PairwiseLane;
    final skip = <int>{};
    var needSync = false;
    var synced = false;
    /// Catch the group up; false when this device failed (the rows keep
    /// waiting, the next drain tries again).
    Future<bool> catchUp() async {
      synced = true;
      needSync = false;
      try {
        await _handler.syncGroup(lane);
      } catch (_) {
        return false;
      }
      _syncEventCount++;
      await _store.wakeSync(lane);
      return true;
    }

    while (true) {
      final rows = await _store.ready(lane, skip: skip, limit: _laneBatch);
      if (rows.isEmpty) {
        if (isGroup && !synced && state.syncWanted) {
          state.syncWanted = false;
          needSync = true;
        }
        if (!isGroup || !needSync || synced) return;
        // Everything this group had ready is handled: now catch up.
        if (!await catchUp()) return;
        continue;
      }
      var hold = false;
      for (final row in rows) {
        switch (await _handle(row)) {
          case _Step.later:
            skip.add(row.localId);
          case _Step.waitsForSync:
            if (!synced) needSync = true;
          case _Step.holdsForSync:
            // The log moved past this device: the rows after this one are
            // judged after the sync (what came before was judged under the
            // roster it was sent under).
            if (!synced) hold = true;
          case _Step.settled:
          case _Step.again:
            break;
        }
        if (hold) break;
      }
      if (hold && !await catchUp()) return;
    }
  }

  /// Handle [row] and apply the outcome.
  Future<_Step> _handle(Gv2InboxRow row) async {
    final keyEvents = _keyEventCount;
    final syncEvents = _syncEventCount;
    final groupId = row.groupId;
    final item = Gv2InboxItem(
      serverRowId: row.serverRowId,
      kind: row.kind,
      payload: row.payload,
      unsealed: row.unsealed,
      groupId: groupId,
      receivedAtMs: row.receivedAtMs,
      attempts: row.attempts,
      keepOpened: (opened) => _store.keepOpened(row.localId, opened),
    );

    Gv2InboxOutcome outcome;
    try {
      if (row.kind == Gv2InboxKind.group) {
        final keys = groupId == null ? null : (await _keyMap())[groupId];
        final opened = keys == null
            ? null
            : gv2OpenEnvelope(keys: keys, envelope: row.payload);
        outcome = opened == null
            ? const Gv2Dropped()
            : await _handler.handleGroupEnvelope(groupId!, opened, item);
      } else if (row.kind == Gv2InboxKind.invite) {
        final payload = row.payload;
        outcome = payload.length <= _snowIdLength
            ? const Gv2Dropped()
            : await _handler.handleInvite(
                ascii.decode(payload.sublist(0, _snowIdLength),
                    allowInvalid: true),
                Uint8List.sublistView(payload, _snowIdLength),
              );
      } else {
        outcome = await _handler.handlePairwise(item);
      }
      _check(outcome, row);
    } catch (_) {
      return _failed(row);
    }

    final target = switch (outcome) {
      Gv2WaitForKey(groupId: final named) => groupId ?? named,
      Gv2WaitForSync(groupId: final named) => groupId ?? named,
      _ => groupId,
    };
    // Counted before the wake-ups are written, so that a row of another lane
    // parking at the same time either sees the count or is woken.
    for (final w in switch (outcome) {
      Gv2Handled(:final wake) => wake,
      _ => const <Gv2Wake>[],
    }) {
      switch (w) {
        case Gv2KeyWake():
          _keyEventCount++;
        case Gv2SyncWake():
          _syncEventCount++;
      }
    }

    // What the row would wait for may have happened while it was handled
    // (a key installed by the pairwise lane, a sync run elsewhere). Parked
    // now, it would miss that wake-up: it stays ready and is tried again.
    // Decided inside the transaction: transactions run one at a time.
    var missed = false;
    final kicks = <String>{};
    try {
      await _store.transaction(() async {
        missed =
            (outcome is Gv2WaitForKey && _keyEventCount != keyEvents) ||
            (outcome is Gv2WaitForSync && _syncEventCount != syncEvents);
        switch (outcome) {
          case Gv2Handled(:final conversationId, :final write, :final wake):
            await write?.call();
            await _store.finish(
              row,
              conversationId: conversationId,
              day: _day(),
            );
            for (final w in wake) {
              final woken = switch (w) {
                Gv2KeyWake(:final groupId, :final sender) =>
                  await _store.wakeKey(groupId, sender),
                Gv2SyncWake(:final groupId) => await _store.wakeSync(groupId),
              };
              final lane = switch (w) {
                Gv2KeyWake(:final groupId) => groupId,
                Gv2SyncWake(:final groupId) => groupId,
              };
              if (woken.isNotEmpty) kicks.add(lane);
            }
          case Gv2Dropped():
            await _store.finish(row, day: _day());
          case Gv2WaitForKey(:final sender, :final keep, :final write):
            await write?.call();
            if (missed) {
              await _store.requeue(row.localId, groupId: target!, keep: keep);
            } else {
              await _store.park(
                row.localId,
                state: Gv2InboxState.waitingKey,
                groupId: target!,
                waitFor: sender,
                keep: keep,
              );
            }
          case Gv2WaitForSync(:final keep, :final write):
            await write?.call();
            if (missed) {
              await _store.requeue(row.localId, groupId: target!, keep: keep);
            } else {
              await _store.park(
                row.localId,
                state: Gv2InboxState.waitingSync,
                groupId: target!,
                keep: keep,
              );
            }
        }
      });
    } catch (_) {
      // The outcome's writes (or the inbox's) failed and were rolled back.
      return _failed(row);
    }
    final afterCommit = switch (outcome) {
      Gv2Handled(:final afterCommit) => afterCommit,
      Gv2WaitForKey(:final afterCommit) => afterCommit,
      Gv2WaitForSync(:final afterCommit) => afterCommit,
      Gv2Dropped() => null,
    };
    if (afterCommit != null) {
      try {
        afterCommit();
      } catch (_) {
        // The outcome is committed; a failing hook cannot undo it, and the
        // row must not be handled again.
      }
    }
    // A pairwise row that named its group now belongs to that lane; one
    // that waits for the log there asks that lane to sync.
    if (target != null && target != groupId) {
      if (missed) {
        kicks.add(target);
      } else if (outcome is Gv2WaitForSync) {
        unawaited(_kick(target, sync: true));
      }
    }
    for (final lane in kicks) {
      if (lane != (groupId ?? gv2PairwiseLane)) unawaited(_kick(lane));
    }
    if (missed) return _Step.again;
    return switch (outcome) {
      // Only in a group's own lane: a pairwise row moves to its group first.
      Gv2WaitForSync(holdsLane: true) when groupId != null => _Step.holdsForSync,
      Gv2WaitForSync() => _Step.waitsForSync,
      _ => _Step.settled,
    };
  }

  /// The handler threw, or what it decided could not be written: one more
  /// attempt counted, the row dropped after [gv2InboxMaxAttempts].
  Future<_Step> _failed(Gv2InboxRow row) async {
    if (await _store.failed(row.localId) >= gv2InboxMaxAttempts) {
      await _store.finish(row, day: _day());
      return _Step.settled;
    }
    return _Step.later;
  }

  /// A row never changes group, and a waiting row has one.
  static void _check(Gv2InboxOutcome outcome, Gv2InboxRow row) {
    final named = switch (outcome) {
      Gv2WaitForKey(:final groupId) => groupId,
      Gv2WaitForSync(:final groupId) => groupId,
      _ => null,
    };
    if (named != null && named.length != 2 * gv2GroupIdLen) {
      throw ArgumentError('gv2 inbox: a group id is 64 hex characters');
    }
    if (named != null && row.groupId != null && named != row.groupId) {
      throw ArgumentError('gv2 inbox: a row cannot change group');
    }
    if ((outcome is Gv2WaitForKey || outcome is Gv2WaitForSync) &&
        row.groupId == null &&
        named == null) {
      throw ArgumentError('gv2 inbox: a waiting row needs a group');
    }
    if (outcome is Gv2WaitForKey && outcome.sender.isEmpty) {
      throw ArgumentError('gv2 inbox: a key wait needs a sender');
    }
  }
}
