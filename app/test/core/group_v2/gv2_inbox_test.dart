/// @file        gv2_inbox_test.dart
/// @description Group protocol v2 local inbox: rows are stored before they
///              are acknowledged, a lost acknowledgement or a replay is one
///              row, each group's envelopes are handled one at a time in
///              arrival order while groups run side by side, waiting rows
///              wake when their key arrives or their group syncs (including
///              a wake-up that happens while the row is being handled), a
///              group drains its ready rows before it syncs (and syncs for a
///              pairwise row that waits for its log), what a handler
///              writes commits with its outcome (and its after-commit hook
///              runs only then), what a handler decrypted survives its
///              failure, and old rows expire.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (before the backup was looked at, a row of no held group stays — groupsKnown). Earlier 2026-11-21 (a row holding its lane — holdsLane). Earlier 2026-11-21 (no Gv2InboxItem.afterSync: the stand-in handler counts syncs that ended; invite rows kept by the 1:1 queue). Earlier 2026-11-13
///
/// @functions
///  - main(): the test groups below.
///  - _Fixture: an in-memory database with groups, the inbox and its fakes.
///  - _Handler: a handler scripted per test that records what it sees.
///
/// Notes:
///  - Group envelopes are real change notices sealed with the real keys of
///    real test groups (gv2_test_support.dart); the notice's revision serves
///    as the envelope's label. Pairwise envelopes are opaque bytes starting
///    with 0x01 — the inbox does not look inside them.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_envelope.dart';
import 'package:snowchat/core/group_v2/gv2_inbox.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';

import 'gv2_test_support.dart';

const _t0 = 1794528000000;
const _device = '0b8f6c1e-5a52-4f0e-9a43-6d2c8f1b7e10';
const _bob = 'snow00000000000000000000000000000b0b';

String _rowId(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

/// A change notice of [g] labelled [label].
Uint8List _notice(Gv2TestGroup g, int label) => gv2SealChangeNoticeEnvelope(
      keys: Gv2EnvelopeKeys.derive(g.masterKey, g.groupId),
      stamp: Gv2EnvelopeStamp(
        senderAccountId: Uint8List(16),
        senderDeviceId: _device,
        messageId: gv2NewMessageId(),
        revision: label,
        chain: Uint8List(32),
        timestampMs: 1,
      ),
    );

/// An opaque pairwise envelope labelled [label].
Uint8List _pairwise(int label) => Uint8List.fromList(
    [0x01, ...gv2TestBytes('pairwise $label', 300)]);

int? _pairwiseLabel(Uint8List payload) {
  for (var label = 0; label < 1000; label++) {
    if (_same(payload, _pairwise(label))) return label;
  }
  return null;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

typedef _OnGroup = FutureOr<Gv2InboxOutcome> Function(
    String groupId, int label, Gv2InboxItem item);
typedef _OnPairwise = FutureOr<Gv2InboxOutcome> Function(Gv2InboxItem item);

class _Handler implements Gv2InboxHandler {
  _OnGroup onGroup = (groupId, label, item) =>
      Gv2Handled(conversationId: groupId);
  _OnPairwise onPairwise = (item) => const Gv2Handled();
  FutureOr<void> Function(String groupId) onSync = (_) {};

  /// "groupId-prefix:label" / "p:label" in the order handled.
  final List<String> log = [];
  final List<String> syncs = [];
  final Map<String, int> running = {};
  final Map<String, int> maxRunning = {};
  int totalRunning = 0;
  int maxTotalRunning = 0;
  Duration delay = Duration.zero;

  String short(String groupId) => groupId.substring(0, 6);

  Future<T> _track<T>(String lane, Future<T> Function() body) async {
    running.update(lane, (n) => n + 1, ifAbsent: () => 1);
    totalRunning++;
    maxRunning.update(lane, (n) => n < running[lane]! ? running[lane]! : n,
        ifAbsent: () => running[lane]!);
    if (totalRunning > maxTotalRunning) maxTotalRunning = totalRunning;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return await body();
    } finally {
      running.update(lane, (n) => n - 1);
      totalRunning--;
    }
  }

  @override
  Future<Gv2InboxOutcome> handleGroupEnvelope(
    String groupId,
    Gv2OpenedEnvelope envelope,
    Gv2InboxItem item,
  ) =>
      _track(groupId, () async {
        final label = gv2ChangeNoticeRevision(envelope)!;
        log.add('${short(groupId)}:$label');
        return onGroup(groupId, label, item);
      });

  @override
  Future<Gv2InboxOutcome> handlePairwise(Gv2InboxItem item) =>
      _track(item.groupId ?? 'pairwise', () async {
        final label = item.unsealed
            ? int.parse(utf8.decode(item.payload).split(':').last)
            : _pairwiseLabel(item.payload);
        log.add('p:$label');
        return onPairwise(item);
      });

  @override
  Future<void> syncGroup(String groupId) async {
    syncs.add(short(groupId));
    await onSync(groupId);
    synced++;
  }

  /// Invites handed over, as (sender, invite bytes).
  final List<(String, Uint8List)> invites = [];
  Gv2InboxOutcome Function(String sender, Uint8List invite) onInvite =
      (_, _) => const Gv2Handled();

  @override
  Future<Gv2InboxOutcome> handleInvite(
    String senderSnowId,
    Uint8List invite,
  ) async {
    invites.add((senderSnowId, invite));
    log.add('i:${invite.length}');
    return onInvite(senderSnowId, invite);
  }

  /// Syncs that ended without throwing (a stand-in for "reached the head":
  /// a real handler reads Gv2GroupRow.lastSyncAtMs).
  int synced = 0;
}

class _Fixture {
  final SnowDatabase db = SnowDatabase(NativeDatabase.memory());
  final _Handler handler = _Handler();
  final List<List<String>> acks = [];
  bool ackFails = false;
  int now = _t0;
  int _nextRow = 1;

  /// What the inbox held each time it acknowledged.
  final List<int> storedAtAck = [];

  late final Gv2Inbox inbox = Gv2Inbox(
    store: db.gv2InboxStore,
    groups: db.gv2Store,
    handler: handler,
    ack: (ids) async {
      storedAtAck.add((await db.gv2InboxStore.allRows()).length);
      if (ackFails) throw StateError('offline');
      acks.add(ids);
    },
    nowMs: () => now,
    groupsKnown: () => groupsKnown,
  );

  /// Whether the inbox may take a row of no held group for one of no group
  /// at all (false: a new install that has not looked at its backup yet).
  bool groupsKnown = true;

  Future<Gv2TestGroup> group(String label, {bool store = true}) async {
    final g = Gv2TestGroup('inbox $label');
    final alice = g.person('alice');
    g.create(alice);
    if (store) await add(g);
    return g;
  }

  Future<void> add(Gv2TestGroup g) async {
    await db.gv2Store.insertCreated(
      masterKey: g.masterKey,
      myCiphertext: g.person('alice').ciphertext,
      state: g.state,
      headSig: g.headSig(0),
      nowMs: now,
    );
    inbox.groupsChanged();
  }

  Gv2QueueRow row(Uint8List envelope, {String? id, int? seq}) {
    final n = _nextRow++;
    return Gv2QueueRow(id: id ?? _rowId(n), seq: seq ?? n, envelope: envelope);
  }

  Future<Gv2ReceiveResult> receive(List<Uint8List> envelopes) =>
      inbox.receive([for (final e in envelopes) row(e)]);

  Future<List<Gv2InboxRow>> rows() => db.gv2InboxStore.allRows();

  Future<int> seenCount() async =>
      (await db.select(db.gv2Seen).get()).length;

  Future<void> close() => db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() => f.close());

  group('queue rows', () {
    test('a row from the server is parsed strictly', () {
      final envelope = _pairwise(1);
      final good = {
        'id': _rowId(7),
        'seq': '12',
        'envelope': base64Encode(envelope),
        'silent': false,
      };
      final row = Gv2QueueRow.tryParse(good)!;
      expect(row.id, _rowId(7));
      expect(row.seq, 12);
      expect(row.envelope, envelope);

      // No usable id: cannot even be acknowledged.
      for (final id in [null, 7, 'x', '${_rowId(7)}0', _rowId(7).substring(1)]) {
        expect(Gv2QueueRow.tryParse({...good, 'id': id}), isNull,
            reason: '$id');
      }
      // Either case: the server acknowledges either.
      expect(
          Gv2QueueRow.tryParse({...good, 'id': _rowId(0xabc).toUpperCase()})!
              .id,
          _rowId(0xabc).toUpperCase());
      expect(Gv2QueueRow.tryParse('not a map'), isNull);

      // A usable id but no usable envelope: acknowledged and dropped.
      for (final bad in [null, 5, 'not base64!', '${base64Encode(envelope)}\n']) {
        final parsed = Gv2QueueRow.tryParse({...good, 'envelope': bad})!;
        expect(parsed.envelope, isEmpty, reason: '$bad');
      }
      // Base64 with a non-canonical tail bit decodes but is not what the
      // server writes.
      final canonical = base64Encode([0xff]); // "/w=="
      expect(Gv2QueueRow.tryParse({...good, 'envelope': canonical})!.envelope,
          [0xff]);
      expect(Gv2QueueRow.tryParse({...good, 'envelope': '/x=='})!.envelope,
          isEmpty);
      for (final seq in [null, 12, '-1', '012', '1e3']) {
        expect(Gv2QueueRow.tryParse({...good, 'seq': seq})!.seq, 0,
            reason: '$seq');
      }
    });
  });

  group('receiving', () {
    test('rows are stored first and acknowledged after', () async {
      final g = await f.group('a');
      final result = await f.receive([_notice(g, 1), _pairwise(2)]);

      expect(result.stored, 2);
      expect(result.acknowledged, isTrue);
      expect(f.storedAtAck, [2]);
      expect(f.acks, [
        [_rowId(1), _rowId(2)]
      ]);
      final rows = await f.rows();
      expect(rows.map((r) => r.kind),
          [Gv2InboxKind.group, Gv2InboxKind.pairwise]);
      expect(rows.map((r) => r.state),
          [Gv2InboxState.received, Gv2InboxState.ready]);
      expect(rows.every((r) => r.receivedAtMs == _t0), isTrue);
    });

    test('nothing is acknowledged when storing fails', () async {
      final g = await f.group('a');
      await f.db.customStatement('''
        CREATE TRIGGER no_inbox BEFORE INSERT ON gv2_inbox
        BEGIN SELECT RAISE(ABORT, 'disk full'); END''');

      await expectLater(f.receive([_notice(g, 1)]), throwsA(anything));
      expect(f.acks, isEmpty);
      expect(f.storedAtAck, isEmpty);
    });

    test('a lost acknowledgement: the row comes again and is one row',
        () async {
      final g = await f.group('a');
      final envelope = _notice(g, 1);
      f.ackFails = true;
      final first = await f.inbox.receive([f.row(envelope, id: _rowId(50))]);
      expect(first.stored, 1);
      expect(first.acknowledged, isFalse);

      // The server still has it and hands it out again.
      f.ackFails = false;
      final again = await f.inbox.receive([f.row(envelope, id: _rowId(50))]);
      expect(again.stored, 0);
      expect(again.acknowledged, isTrue);
      expect(f.acks, [
        [_rowId(50)]
      ]);

      await f.inbox.drain();
      expect(f.handler.log, ['${f.handler.short(g.id)}:1']);
    });

    test('rows left unacknowledged go with the next acknowledgement', () async {
      final g = await f.group('a');
      f.ackFails = true;
      await f.receive([_notice(g, 1)]);
      f.ackFails = false;
      await f.receive([_notice(g, 2)]);

      expect(f.acks.single.toSet(), {_rowId(1), _rowId(2)});
      expect(await f.inbox.flushAcks(), isTrue);
      expect(f.acks, hasLength(1));
    });

    test('an envelope handled before is not handled again', () async {
      final g = await f.group('a');
      final envelope = _notice(g, 1);
      await f.receive([envelope]);
      await f.inbox.drain();

      // Replayed under a new row id (or redelivered after the row was
      // handled).
      final again = await f.receive([envelope]);
      expect(again.stored, 0);
      expect(f.acks.last, [_rowId(2)]);
      await f.inbox.drain();
      expect(f.handler.log, hasLength(1));
    });

    test('the same envelope twice in one fetch is one row', () async {
      final g = await f.group('a');
      final envelope = _notice(g, 1);
      final result = await f.receive([envelope, envelope]);

      expect(result.stored, 1);
      expect(f.acks.single, [_rowId(1), _rowId(2)]);
    });

    test('what is not an envelope is acknowledged and forgotten', () async {
      final result = await f.receive([
        Uint8List(0),
        Uint8List.fromList([0x03, ...gv2TestBytes('x', 600)]),
        Uint8List.fromList([0x02, 1, 2, 3]), // too short to be a group envelope
        Uint8List(gv2MaxEnvelopeBytes + 1)..[0] = 0x01,
      ]);

      expect(result.stored, 0);
      expect(f.acks.single, hasLength(4));
      expect(await f.rows(), isEmpty);
    });

    test('rows of one fetch are stored in sequence order', () async {
      final g = await f.group('a');
      await f.inbox.receive([
        f.row(_notice(g, 3), seq: 3),
        f.row(_notice(g, 1), seq: 1),
        f.row(_notice(g, 2), seq: 2),
      ]);
      await f.inbox.drain();

      final s = f.handler.short(g.id);
      expect(f.handler.log, ['$s:1', '$s:2', '$s:3']);
    });
  });

  group('lanes', () {
    test('an envelope goes to its group, one of no group is dropped',
        () async {
      final a = await f.group('a');
      final b = await f.group('b');
      final stranger = await f.group('stranger', store: false);
      await f.receive([_notice(a, 1), _notice(stranger, 2), _notice(b, 3)]);
      await f.inbox.drain();

      expect(f.handler.log.toSet(),
          {'${f.handler.short(a.id)}:1', '${f.handler.short(b.id)}:3'});
      expect(await f.rows(), isEmpty);
      expect(await f.seenCount(), 3);
    });

    test('a group stored after the envelope is still found', () async {
      final late = await f.group('late', store: false);
      // The key map is read before the group exists...
      await f.receive([_notice(await f.group('a'), 1)]);
      await f.inbox.drain();
      // ...and the group is stored without telling the inbox.
      await f.db.gv2Store.insertCreated(
        masterKey: late.masterKey,
        myCiphertext: late.person('alice').ciphertext,
        state: late.state,
        headSig: late.headSig(0),
        nowMs: _t0,
      );
      await f.receive([_notice(late, 7)]);
      await f.inbox.drain();

      expect(f.handler.log.last, '${f.handler.short(late.id)}:7');
    });

    test('one group at a time in arrival order, groups side by side, '
        'pairwise envelopes first', () async {
      final a = await f.group('a');
      final b = await f.group('b');
      f.handler.delay = const Duration(milliseconds: 5);
      await f.receive([
        for (var i = 0; i < 5; i++) ...[_notice(a, i), _notice(b, 10 + i)],
        _pairwise(20),
        _pairwise(21),
      ]);
      await f.inbox.drain();

      final sa = f.handler.short(a.id);
      final sb = f.handler.short(b.id);
      expect(f.handler.log.where((e) => e.startsWith(sa)),
          [for (var i = 0; i < 5; i++) '$sa:$i']);
      expect(f.handler.log.where((e) => e.startsWith(sb)),
          [for (var i = 0; i < 5; i++) '$sb:${10 + i}']);
      expect(f.handler.log.where((e) => e.startsWith('p:')), ['p:20', 'p:21']);
      expect(f.handler.maxRunning.values.every((n) => n == 1), isTrue);
      // The two groups side by side...
      expect(f.handler.maxTotalRunning, 2);
      // ...after the pairwise envelopes of this drain: a Sender Key that is
      // already here is installed before the messages it opens are read.
      expect(f.handler.log.sublist(0, 2), ['p:20', 'p:21']);
    });

    test('rows arriving while a lane runs are handled by the same drain',
        () async {
      final a = await f.group('a');
      var injected = false;
      f.handler.onGroup = (groupId, label, item) async {
        if (!injected) {
          injected = true;
          await f.receive([_notice(a, 2)]);
          // A second drain while the first runs joins it.
          unawaited(f.inbox.drain());
        }
        return const Gv2Handled();
      };
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();
      await f.inbox.drain();

      final s = f.handler.short(a.id);
      expect(f.handler.log, ['$s:1', '$s:2']);
    });
  });

  group('waiting', () {
    test('a row waits for its key and is handled when it arrives', () async {
      final a = await f.group('a');
      final s = f.handler.short(a.id);
      var keyHere = false;
      f.handler.onGroup = (groupId, label, item) =>
          keyHere ? const Gv2Handled() : const Gv2WaitForKey(sender: _bob);
      await f.receive([_notice(a, 1), _notice(a, 2)]);
      await f.inbox.drain();

      final parked = await f.rows();
      expect(parked.map((r) => r.state),
          everyElement(Gv2InboxState.waitingKey));
      expect(parked.map((r) => r.waitFor), everyElement(_bob));

      // Another sender's key does not wake them.
      await f.inbox.keyArrived(a.id, 'snow00000000000000000000000000000ca1');
      expect(f.handler.log, ['$s:1', '$s:2']);

      keyHere = true;
      await f.inbox.keyArrived(a.id, _bob);
      expect(f.handler.log, ['$s:1', '$s:2', '$s:1', '$s:2']);
      expect(await f.rows(), isEmpty);
    });

    test('a pairwise key that is installed wakes the rows waiting for it',
        () async {
      final a = await f.group('a');
      final s = f.handler.short(a.id);
      var installed = false;
      f.handler.onGroup = (groupId, label, item) => installed
          ? Gv2Handled(conversationId: groupId)
          : const Gv2WaitForKey(sender: _bob);
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();

      f.handler.onPairwise = (item) {
        installed = true;
        return Gv2Handled(wake: [Gv2Wake.key(a.id, _bob)]);
      };
      await f.receive([_pairwise(5)]);
      await f.inbox.drain();
      // The group lane runs on its own once woken.
      await pumpEventQueue();
      await f.inbox.drain();

      expect(f.handler.log, ['$s:1', 'p:5', '$s:1']);
      expect(await f.rows(), isEmpty);
    });

    test('a key that arrives while the row is being handled is not missed',
        () async {
      final a = await f.group('a');
      var attempts = 0;
      f.handler.onGroup = (groupId, label, item) async {
        attempts++;
        if (attempts == 1) {
          // Installed by another lane after this handler looked for it.
          await f.inbox.keyArrived(groupId, _bob);
          return const Gv2WaitForKey(sender: _bob);
        }
        return const Gv2Handled();
      };
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();

      expect(attempts, 2);
      expect(await f.rows(), isEmpty);
    });

    test('a group handles what it has, then syncs once, then the rest',
        () async {
      final a = await f.group('a');
      final s = f.handler.short(a.id);
      var synced = false;
      f.handler.onGroup = (groupId, label, item) {
        if (label.isOdd && !synced) return const Gv2WaitForSync();
        return const Gv2Handled();
      };
      f.handler.onSync = (groupId) {
        // Everything ready was handled before the sync.
        expect(f.handler.log, ['$s:1', '$s:2', '$s:3', '$s:4']);
        synced = true;
      };
      await f.receive([for (var i = 1; i <= 4; i++) _notice(a, i)]);
      await f.inbox.drain();

      expect(f.handler.syncs, [s]);
      expect(f.handler.log, ['$s:1', '$s:2', '$s:3', '$s:4', '$s:1', '$s:3']);
      expect(await f.rows(), isEmpty);
    });

    test('before the backup was looked at, a row of no held group stays; it '
        'is taken when its group comes back, or dropped once the groups are '
        'known', () async {
      final back = await f.group('back', store: false);
      final never = await f.group('never', store: false);
      f.groupsKnown = false;
      await f.receive([_notice(back, 1), _notice(never, 1)]);
      await f.inbox.drain();
      expect((await f.rows()).map((r) => r.state).toSet(),
          {Gv2InboxState.received}, reason: 'kept');
      expect(f.handler.log, isEmpty);

      // The backup brings one group back.
      await f.add(back);
      f.inbox.groupsChanged();
      f.groupsKnown = true;
      await f.inbox.drain();
      expect(f.handler.log, ['${f.handler.short(back.id)}:1']);
      expect(await f.rows(), isEmpty, reason: 'the other one is dropped now');
    });

    test('a row that says the log moved past this device holds the lane: the '
        'rows after it are handled after the sync', () async {
      final a = await f.group('a');
      final s = f.handler.short(a.id);
      f.handler.onGroup = (groupId, label, item) =>
          label == 2 && f.handler.synced == 0
              ? const Gv2WaitForSync(holdsLane: true)
              : const Gv2Handled();
      f.handler.onSync = (_) => f.handler.log.add('sync');
      await f.receive([for (var i = 1; i <= 4; i++) _notice(a, i)]);
      await f.inbox.drain();
      expect(f.handler.log, ['$s:1', '$s:2', 'sync', '$s:2', '$s:3', '$s:4']);
      expect(await f.rows(), isEmpty);
    });

    test('a sync that does not help leaves the rows waiting, without a loop',
        () async {
      final a = await f.group('a');
      f.handler.onGroup =
          (groupId, label, item) => const Gv2WaitForSync();
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();

      expect(f.handler.syncs, hasLength(1));
      expect(f.handler.log, hasLength(2));
      expect((await f.rows()).single.state, Gv2InboxState.waitingSync);

      // A sync run elsewhere wakes it.
      f.handler.onGroup = (groupId, label, item) => const Gv2Handled();
      await f.inbox.synced(a.id);
      expect(await f.rows(), isEmpty);
    });

    test('a failing sync leaves the rows for the next drain', () async {
      final a = await f.group('a');
      var fail = true;
      f.handler.onGroup = (groupId, label, item) => f.handler.synced > 0
          ? const Gv2Handled()
          : const Gv2WaitForSync();
      f.handler.onSync = (groupId) {
        if (fail) throw StateError('database');
      };
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();
      expect((await f.rows()).single.state, Gv2InboxState.waitingSync);

      fail = false;
      await f.receive([_notice(a, 2)]);
      await f.inbox.drain();
      expect(await f.rows(), isEmpty);
    });

    test('a pairwise row keeps what it decrypted and waits in its group',
        () async {
      final a = await f.group('a');
      final s = f.handler.short(a.id);
      final seen = <Gv2InboxItem>[];
      f.handler.onPairwise = (item) {
        seen.add(item);
        if (!item.unsealed) {
          return Gv2WaitForKey(
            sender: _bob,
            groupId: a.id,
            keep: Uint8List.fromList(utf8.encode('opened:9')),
          );
        }
        return const Gv2Handled();
      };
      await f.receive([_pairwise(9)]);
      await f.inbox.drain();

      final parked = (await f.rows()).single;
      expect(parked.groupId, a.id);
      expect(parked.unsealed, isTrue);
      expect(utf8.decode(parked.payload), 'opened:9');
      expect(parked.state, Gv2InboxState.waitingKey);
      // The digest is still that of the envelope received.
      expect(parked.digest, hash.sha256.convert(_pairwise(9)).bytes);

      await f.inbox.keyArrived(a.id, _bob);
      expect(f.handler.log, ['p:9', 'p:9']);
      expect(seen.last.unsealed, isTrue);
      expect(seen.last.groupId, a.id);
      expect(await f.rows(), isEmpty);
      expect(f.handler.log.where((e) => e.startsWith(s)), isEmpty);
    });

    test('a pairwise row that waits for the log makes its group sync, and '
        'drain returns when that is done', () async {
      final a = await f.group('a');
      f.handler.onPairwise = (item) => f.handler.synced > 0
          ? const Gv2Handled()
          : Gv2WaitForSync(groupId: a.id);
      await f.receive([_pairwise(9)]);
      await f.inbox.drain();

      expect(f.handler.syncs, [f.handler.short(a.id)]);
      expect(f.handler.log, ['p:9', 'p:9']);
      expect(await f.rows(), isEmpty);
    });

    test('every drain gives a group with rows waiting for its log one sync',
        () async {
      final a = await f.group('a');
      f.handler.onGroup = (groupId, label, item) => const Gv2WaitForSync();
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();
      expect(f.handler.syncs, hasLength(1));

      // Nothing new arrived (or the app started again): one more attempt.
      await f.inbox.drain();
      expect(f.handler.syncs, hasLength(2));
      expect((await f.rows()).single.state, Gv2InboxState.waitingSync);
    });

    test('what a handler decrypted is kept even when it then fails', () async {
      final seen = <Gv2InboxItem>[];
      f.handler.onPairwise = (item) async {
        seen.add(item);
        if (!item.unsealed) {
          await item.keepOpened(Uint8List.fromList(utf8.encode('opened:3')));
          throw StateError('died after decrypting');
        }
        return const Gv2Handled();
      };
      await f.receive([_pairwise(3)]);
      await f.inbox.drain();
      final kept = (await f.rows()).single;
      expect(kept.unsealed, isTrue);
      expect(utf8.decode(kept.payload), 'opened:3');
      expect(kept.attempts, 1);
      expect(kept.digest, hash.sha256.convert(_pairwise(3)).bytes);

      await f.inbox.drain();
      expect(seen.map((i) => i.unsealed), [false, true]);
      expect(await f.rows(), isEmpty);
    });

    test('after-commit runs once the outcome is committed, never when it fails',
        () async {
      var committed = 0;
      f.handler.onPairwise = (item) =>
          Gv2Handled(afterCommit: () => committed++);
      await f.receive([_pairwise(1)]);
      await f.inbox.drain();
      expect(committed, 1);

      f.handler.onPairwise = (item) => Gv2Handled(
            write: () async => throw StateError('rolled back'),
            afterCommit: () => committed++,
          );
      await f.receive([_pairwise(2)]);
      await f.inbox.drain();
      expect(committed, 1);
      expect((await f.rows()).single.attempts, 1);

      // A hook that throws does not undo or repeat the outcome.
      f.handler.onPairwise = (item) =>
          Gv2Handled(afterCommit: () => throw StateError('hook'));
      await f.inbox.drain();
      expect(await f.rows(), isEmpty);
    });

    test('a handler cannot move a row to another group or park it nowhere',
        () async {
      final a = await f.group('a');
      final b = await f.group('b');
      f.handler.onGroup =
          (groupId, label, item) => Gv2WaitForSync(groupId: b.id);
      f.handler.onPairwise = (item) => const Gv2WaitForSync();
      await f.receive([_notice(a, 1), _pairwise(2)]);
      await f.inbox.drain();

      final rows = await f.rows();
      expect(rows.map((r) => r.state), everyElement(Gv2InboxState.ready));
      expect(rows.map((r) => r.attempts), everyElement(1));
    });
  });

  group('failures', () {
    test('a handler that throws is retried, then the row is dropped',
        () async {
      final a = await f.group('a');
      f.handler.onGroup = (groupId, label, item) =>
          label == 1 ? throw StateError('bug') : const Gv2Handled();
      await f.receive([_notice(a, 1), _notice(a, 2)]);

      await f.inbox.drain();
      // The failing row does not hold up the next one.
      expect(f.handler.log, hasLength(2));
      expect((await f.rows()).single.attempts, 1);

      for (var i = 2; i <= gv2InboxMaxAttempts; i++) {
        await f.inbox.drain();
      }
      expect(await f.rows(), isEmpty);
      expect(await f.seenCount(), 2);
    });

    test('what the handler writes commits with the outcome, or not at all',
        () async {
      final a = await f.group('a');
      Future<void> write() => f.db.gv2Store.saveServerKeys(
            serverPublicParams: gv2TestBytes('params', 97),
            headPublicKey: gv2TestBytes('head', 32),
          );
      f.handler.onGroup =
          (groupId, label, item) => Gv2Handled(write: write);
      await f.db.customStatement('''
        CREATE TRIGGER no_seen BEFORE INSERT ON gv2_seen
        BEGIN SELECT RAISE(ABORT, 'disk full'); END''');
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();

      expect(await f.db.gv2Store.serverKeys(), isNull);
      final row = (await f.rows()).single;
      expect(row.state, Gv2InboxState.ready);
      expect(row.attempts, 1);

      await f.db.customStatement('DROP TRIGGER no_seen');
      await f.inbox.drain();
      expect(await f.db.gv2Store.serverKeys(), isNotNull);
      expect(await f.rows(), isEmpty);
    });
  });

  group('time', () {
    test('a row waiting for 30 days is dropped, digests go after 30 days',
        () async {
      final a = await f.group('a');
      f.handler.onGroup =
          (groupId, label, item) => const Gv2WaitForKey(sender: _bob);
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();
      expect(await f.rows(), hasLength(1));

      f.now = _t0 + const Duration(days: 30).inMilliseconds - 1;
      await f.inbox.drain();
      expect(await f.rows(), hasLength(1));

      f.now = _t0 + const Duration(days: 30).inMilliseconds + 1;
      await f.inbox.drain();
      expect(await f.rows(), isEmpty);
      expect(await f.seenCount(), 1);

      f.now += const Duration(days: 31).inMilliseconds;
      await f.inbox.drain();
      expect(await f.seenCount(), 0);
    });
  });

  group('notifications', () {
    test('a server row leads to its conversation', () async {
      final a = await f.group('a');
      f.handler.onGroup = (groupId, label, item) => label == 1
          ? Gv2Handled(conversationId: 'conversation-$label')
          : const Gv2WaitForKey(sender: _bob);
      f.handler.onPairwise = (item) => const Gv2Handled();
      await f.receive([_notice(a, 1), _notice(a, 2), _pairwise(3)]);

      // Not handled yet: a group envelope already belongs to its group.
      expect(await f.inbox.conversationOfServerRow(_rowId(1)), isNull);
      await f.inbox.drain();
      expect(await f.inbox.conversationOfServerRow(_rowId(1)), 'conversation-1');
      expect(await f.inbox.conversationOfServerRow(_rowId(2)), a.id);
      expect(await f.inbox.conversationOfServerRow(_rowId(3)), isNull);
      expect(await f.inbox.conversationOfServerRow(_rowId(99)), isNull);
    });
  });

  group('added for the messaging layer', () {
    test('a group message id is marked once, and forgotten with the digests',
        () async {
      final store = f.db.gv2InboxStore;
      final id = gv2TestSha('a local message id');
      final other = gv2TestSha('another local message id');
      expect(await store.markMessage(id, day: 100), isTrue);
      expect(await store.markMessage(id, day: 101), isFalse);
      expect(await store.markMessage(other, day: 140), isTrue);

      await store.pruneSeen(beforeDay: 120);
      expect(await store.markMessage(id, day: 141), isTrue);
      expect(await store.markMessage(other, day: 141), isFalse);
    });

    test('a waiting outcome runs its afterCommit hook once committed',
        () async {
      final a = await f.group('a');
      var hooks = 0;
      f.handler.onGroup = (groupId, label, item) => f.handler.synced > 0
          ? const Gv2Handled()
          : Gv2WaitForSync(afterCommit: () => hooks++);
      f.handler.onPairwise = (item) => Gv2WaitForKey(
            sender: 'snow-sender',
            groupId: a.id,
            afterCommit: () => hooks += 10,
          );
      await f.receive([_notice(a, 1), _pairwise(2)]);
      await f.inbox.drain();
      expect(hooks, 11);
    });

    test('requestSync handles what the group has ready, then syncs, then '
        'handles what waited for it', () async {
      final a = await f.group('a');
      f.handler.onGroup = (groupId, label, item) =>
          label == 2 && f.handler.synced == 0
              ? const Gv2WaitForSync()
              : const Gv2Handled();
      f.handler.onSync = (_) => f.handler.log.add('sync');
      // Stored, not yet given their group: still "what arrived before".
      await f.receive([_notice(a, 1), _notice(a, 2), _notice(a, 3)]);
      await f.inbox.requestSync(a.id);
      final sa = f.handler.short(a.id);
      expect(f.handler.log, ['$sa:1', '$sa:2', '$sa:3', 'sync', '$sa:2']);
      expect(await f.rows(), isEmpty);

      // With nothing in the lane it still syncs.
      f.handler.log.clear();
      await f.inbox.requestSync(a.id);
      expect(f.handler.log, ['sync']);
    });

    test('rows waiting for a key are looked at again on the first drain and '
        'then every ten minutes', () async {
      final a = await f.group('a');
      f.handler.onGroup = (groupId, label, item) =>
          const Gv2WaitForKey(sender: 'snow-sender');
      await f.receive([_notice(a, 1)]);
      await f.inbox.drain();
      expect(f.handler.log, hasLength(1));

      await f.inbox.drain();
      expect(f.handler.log, hasLength(1));
      f.now += gv2KeyWaitRetry.inMilliseconds;
      await f.inbox.drain();
      expect(f.handler.log, hasLength(2));
      expect((await f.rows()).single.state, Gv2InboxState.waitingKey);

      // After a restart (a new inbox) the first drain looks again.
      final restarted = Gv2Inbox(
        store: f.db.gv2InboxStore,
        groups: f.db.gv2Store,
        handler: f.handler,
        ack: (_) async {},
        nowMs: () => f.now,
      );
      await restarted.drain();
      expect(f.handler.log, hasLength(3));
    });
  });

  group('invites kept by the 1:1 queue', () {
    const sender = 'snow0123456789abcdef0123456789abcdef';
    final invite = Uint8List.fromList(List.generate(166, (i) => i));

    test('stored once, before any runtime runs; handed over on the next '
        'drain; the same invite again is not stored again', () async {
      final store = f.db.gv2InboxStore;
      expect(
        await store.storeInvite(
          serverRowId: 'm1',
          senderSnowId: sender,
          invite: invite,
          nowMs: f.now + 1,
        ),
        isTrue,
      );
      expect(
        await store.storeInvite(
          serverRowId: 'm2',
          senderSnowId: sender,
          invite: invite,
          nowMs: f.now + 2,
        ),
        isFalse,
      );
      expect((await f.rows()).single.kind, Gv2InboxKind.invite);

      await f.inbox.drain();
      expect(f.handler.invites.single.$1, sender);
      expect(f.handler.invites.single.$2, invite);
      expect(await f.rows(), isEmpty);
      // Handled: the same invite (redelivered) is not taken in again.
      expect(
        await store.storeInvite(
          serverRowId: 'm3',
          senderSnowId: sender,
          invite: invite,
          nowMs: f.now + 3,
        ),
        isFalse,
      );
    });

    test('a handler that fails leaves the invite for the next drain',
        () async {
      await f.db.gv2InboxStore.storeInvite(
        serverRowId: 'm1',
        senderSnowId: sender,
        invite: invite,
        nowMs: f.now + 1,
      );
      var fail = true;
      f.handler.onInvite = (_, _) {
        if (fail) throw StateError('database');
        return const Gv2Handled();
      };
      await f.inbox.drain();
      expect(await f.rows(), hasLength(1));
      fail = false;
      await f.inbox.drain();
      expect(await f.rows(), isEmpty);
      expect(f.handler.invites, hasLength(2));
    });
  });
}
