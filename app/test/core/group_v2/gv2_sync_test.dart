/// @file        gv2_sync_test.dart
/// @description Gv2Sync against a scripted server. The log it serves is made
///              of REAL signed entries and real head signatures
///              (gv2_test_support.dart); the server can also be made to do
///              what a dishonest or broken one would: alter an entry, hide
///              the head, roll back, serve another history, or sign something
///              the rules forbid. Checks that the device follows an honest
///              log, keeps what it verified, never takes the server's word,
///              and freezes a group only on the server's own signature. Also
///              the member checks (with real zkgroup ciphertexts).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (the result names the inviter of each member that joined). Earlier 2026-11-20 (an invalid_entry freeze judged again by a later build)
///
/// @functions
///  - main(): the test groups below.
///  - _Server: the scripted transport.
///  - _Keys: credentials stand-in (server keys, presentations).
///  - _Device: database, store and sync of one account.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_credentials.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_payloads.dart';
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/group_v2/gv2_sync.dart';
import 'package:snowchat/core/group_v2/gv2_transport.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';

import 'gv2_test_support.dart';

const _now = 1794528000000;

class _Server extends Fake implements Gv2Transport {
  /// The log the server holds.
  Gv2TestGroup g;
  _Server(this.g);

  int? pageSize;
  final Map<int, Uint8List> entryOverride = {};
  final Map<int, Uint8List> entryHeadSigOverride = {};
  Gv2Head? headOverride;
  Gv2Snapshot Function(Gv2Snapshot honest)? alterSnapshot;

  /// The caller was removed at this revision: later entries are hidden.
  int? removedAt;
  bool moreForEver = false;
  Object? error;
  int presentationRejections = 0;

  int logCalls = 0;
  int snapshotCalls = 0;

  void _gate() {
    if (presentationRejections > 0) {
      presentationRejections--;
      throw const Gv2ApiException(401, 'presentation_invalid');
    }
    if (error != null) throw error!;
  }

  Gv2Head head(int revision) => Gv2Head(
        revision: revision,
        chain: g.states[revision].chain,
        headSig: g.headSig(revision),
      );

  @override
  Future<Gv2LogPage> log({
    required Uint8List groupId,
    required Uint8List presentation,
    required int from,
    int? limit,
  }) async {
    logCalls++;
    _gate();
    final last = removedAt ?? g.state.revision;
    final take = min(limit ?? 200, pageSize ?? 200);
    final entries = [
      for (var r = from; r <= last && r < from + take; r++)
        Gv2LogEntry(
          revision: r,
          entry: entryOverride[r] ?? gv2EncodeEntry(g.log[r]),
          headSig: entryHeadSigOverride[r] ?? g.headSig(r),
        ),
    ];
    return Gv2LogPage(
      head: removedAt != null ? null : (headOverride ?? head(g.state.revision)),
      removed: removedAt != null,
      entries: entries,
      more: moreForEver || from + take <= last,
    );
  }

  @override
  Future<Gv2Snapshot> snapshot({
    required Uint8List groupId,
    required Uint8List presentation,
    required int at,
  }) async {
    snapshotCalls++;
    _gate();
    final honest =
        Gv2Snapshot(state: g.states[at].copy(), headSig: g.headSig(at));
    return alterSnapshot == null ? honest : alterSnapshot!(honest);
  }
}

class _Keys extends Fake implements Gv2Credentials {
  final Gv2TestGroup g;
  int renewals = 0;
  Uint8List? headPublicKey;
  Uint8List serverPublicParams = gv2TestBytes('server params', 673);
  _Keys(this.g);

  @override
  Future<Gv2ServerKeysRow> serverKeys() async => Gv2ServerKeysRow(
        slot: 0,
        serverPublicParams: serverPublicParams,
        headPublicKey: headPublicKey ?? g.headKey.publicKey,
      );

  @override
  Future<Uint8List> presentation(Uint8List masterKey) async =>
      gv2TestBytes('presentation', 64);

  @override
  Future<void> renew() async => renewals++;
}

class _Device {
  final Gv2TestGroup g;
  final _Server server;
  final SnowDatabase db = SnowDatabase(NativeDatabase.memory());
  late final Gv2Store store = db.gv2Store;
  late final _Keys keys = _Keys(g);
  final Map<String, Uint8List> pinned = {};
  int pinnedLookups = 0;

  _Device(this.g, this.server);

  Gv2Sync sync({int? pageLimit, int verifyInIsolateFrom = 8, int checkInIsolateFrom = 16}) =>
      Gv2Sync(
        store: store,
        transport: server,
        credentials: keys,
        pinnedAccountKey: (snowId) async {
          pinnedLookups++;
          return pinned[snowId];
        },
        nowMs: () => _now,
        pageLimit: pageLimit,
        verifyInIsolateFrom: verifyInIsolateFrom,
        checkInIsolateFrom: checkInIsolateFrom,
      );

  /// This device created the group ([who] is its owner) and holds revision 0.
  Future<void> created(Gv2TestPerson who) => store.insertCreated(
        masterKey: g.masterKey,
        myCiphertext: who.ciphertext,
        state: g.states[0],
        headSig: g.headSig(0),
        nowMs: 0,
      );

  /// This device was invited at revision [at] and holds only that anchor.
  Future<bool> invited(Gv2TestPerson who, int at) => store.insertAnchored(
        groupId: g.groupId,
        masterKey: g.masterKey,
        myCiphertext: who.ciphertext,
        protocolVersion: gv2ProtocolVersion,
        revision: at,
        chain: g.states[at].chain,
        stateHash: gv2StateHash(g.states[at]),
        membership: Gv2Membership.invited,
        inviteSeed: g.inviteKeyOf(who).seed,
      );

  Future<Gv2GroupRow> row() async => (await store.group(g.id))!;

  Future<Map<String, Object?>> evidence() async =>
      jsonDecode(utf8.decode((await row()).holdEvidence!)) as Map<String, Object?>;
}

void main() {
  late Gv2TestGroup g;
  late _Server server;
  late _Device d;
  late Gv2TestPerson alice;
  late Gv2TestPerson bob;
  late Gv2TestPerson carol;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  setUp(() {
    g = Gv2TestGroup();
    alice = g.person('alice');
    bob = g.person('bob');
    carol = g.person('carol');
    g.create(alice, invite: [bob, carol]); // 0
    server = _Server(g);
    d = _Device(g, server);
  });
  tearDown(() => d.db.close());

  /// Five more honest revisions: bob joins, carol declines, bob becomes
  /// admin, renames, and invites dave.
  void history() {
    g.accept(bob); // 1
    g.decline(carol); // 2
    g.change(alice, [Gv2SetRole(bob.ciphertext, gv2RoleAdmin)]); // 3
    g.change(bob, const [Gv2SetTitle()], newTitle: 'Winter'); // 4
    g.invite(bob, g.person('dave')); // 5
  }

  group('an honest log', () {
    test('is followed entry by entry to the server\'s head', () async {
      await d.created(alice);
      history();
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.advanced);
      expect(result.fromRevision, 0);
      expect(result.toRevision, 5);
      expect(result.membership, Gv2Membership.active);
      expect(result.applied.map((e) => e.revision), [1, 2, 3, 4, 5]);
      // Bob's ACCEPT took alice's invite (read before the entry removed it).
      expect(result.invitedBy, {bob.key: alice.key});

      final row = await d.row();
      expect(row.revision, 5);
      expect(row.chain, g.state.chain);
      expect(row.headSig, g.headSig(5));
      expect(row.title, 'Winter');
      expect(row.lastSyncAtMs, _now);
      expect(row.lastRemovalRevision, isNull);
      expect(gv2StateHash((await d.store.loadState(g.id))!), gv2StateHash(g.state));
      // Every revision passed is kept as a verified point.
      for (var r = 0; r <= 5; r++) {
        expect((await d.store.head(g.id, r))!.chain, g.states[r].chain,
            reason: '$r');
      }

      final again = await d.sync().sync(g.id);
      expect(again.status, Gv2SyncStatus.upToDate);
      expect(again.applied, isEmpty);
      expect(again.invitedBy, isEmpty);
    });

    test('is followed across pages, inline or in a worker isolate', () async {
      for (final isolateFrom in [100, 1]) {
        final device = _Device(g, server);
        addTearDown(device.db.close);
        await device.created(alice);
        if (g.state.revision == 0) history();
        server.logCalls = 0;
        final result = await device
            .sync(pageLimit: 2, verifyInIsolateFrom: isolateFrom)
            .sync(g.id);
        expect(result.status, Gv2SyncStatus.advanced, reason: 'isolate from $isolateFrom');
        expect(result.toRevision, 5);
        expect(result.invitedBy, {bob.key: alice.key},
            reason: 'isolate from $isolateFrom');
        expect(server.logCalls, 3, reason: '2 + 2 + 1 entries');
        expect((await device.row()).chain, g.state.chain);
        // The last entry of each stored page is signed; the others are not.
        for (var r = 1; r <= 5; r++) {
          final h = (await device.store.head(g.id, r))!;
          expect(h.chain, g.states[r].chain, reason: '$r');
          expect(h.headSig, r.isEven || r == 5 ? g.headSig(r) : isNull,
              reason: '$r');
        }
      }
    });

    test('concurrent syncs of one group share one run', () async {
      await d.created(alice);
      history();
      final sync = d.sync();
      final results = await Future.wait([sync.sync(g.id), sync.sync(g.id)]);
      expect(server.logCalls, 1);
      expect(identical(results[0], results[1]), isTrue);
    });

    test('an unknown group is reported, not fetched', () async {
      final result = await d.sync().sync('ab' * 32);
      expect(result.status, Gv2SyncStatus.unknownGroup);
      expect(server.logCalls + server.snapshotCalls, 0);
    });

    test('a refused presentation is renewed once and the call repeated',
        () async {
      await d.created(alice);
      history();
      server.presentationRejections = 1;
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.advanced);
      expect(d.keys.renewals, 1);

      server.presentationRejections = 2;
      g.change(alice, const [Gv2SetTitle()], newTitle: 'Spring');
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.serverError);
      expect(result.serverCode, 'presentation_invalid');
    });

    test('no answer and error answers leave the group as it is', () async {
      await d.created(alice);
      history();
      for (final (error, status) in [
        (const Gv2NetworkException(), Gv2SyncStatus.offline),
        (const Gv2ApiException(429, 'rate_limited'), Gv2SyncStatus.serverError),
        (const Gv2ApiException(403, 'not_a_member'), Gv2SyncStatus.notReadable),
        (const Gv2ApiException(404, 'group_not_found'), Gv2SyncStatus.notReadable),
        (const Gv2ProtocolException('entries'), Gv2SyncStatus.badData),
      ]) {
        server.error = error;
        final result = await d.sync().sync(g.id);
        expect(result.status, status, reason: '$error');
        expect(result.membership, Gv2Membership.active);
      }
      // "Not readable" is the server's word: nothing was changed on it.
      final row = await d.row();
      expect(row.revision, 0);
      expect(row.membership, Gv2Membership.active);
      expect(row.hold, Gv2Hold.none);
    });
  });

  group('this account\'s standing', () {
    test('an invitee loads the anchor\'s state, then follows the log', () async {
      g.decline(carol); // 1
      expect(await d.invited(bob, 0), isTrue);
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.advanced);
      expect(server.snapshotCalls, 1);
      expect(result.membership, Gv2Membership.invited);
      final row = await d.row();
      expect(row.stateLoaded, isTrue);
      expect(row.revision, 1);
      expect(row.headSig, g.headSig(1));
      expect(row.inviteSeed, isNotNull);

      // The accept shows up in the log (submitted by this account): a member
      // now, but not yet confirmed by another member.
      g.accept(bob); // 2
      final joined = await d.sync().sync(g.id);
      expect(joined.membership, Gv2Membership.awaitingConfirm);
      expect((await d.row()).inviteSeed, isNull);
      expect(server.snapshotCalls, 1, reason: 'the state is not fetched again');
    });

    test('removed: the log ends with the removal and says no more', () async {
      g.accept(bob); // 1
      g.change(alice, [Gv2Remove(bob.ciphertext)]); // 2
      g.change(alice, const [Gv2SetTitle()], newTitle: 'After bob'); // 3
      await d.invited(bob, 0);
      server.removedAt = 2;
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.advanced);
      expect(result.membership, Gv2Membership.removed);
      expect(result.toRevision, 2);
      final row = await d.row();
      expect(row.title, 'Snow', reason: 'what happened afterwards is hidden');
      expect(row.lastRemovalRevision, 2);
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.upToDate);
    });

    test('left, when the leave in the log is this account\'s own', () async {
      g.accept(bob); // 1
      g.change(bob, const [Gv2Leave()]); // 2
      await d.invited(bob, 0);
      server.removedAt = 2;
      expect((await d.sync().sync(g.id)).membership, Gv2Membership.left);
    });

    test('ended, when the owner deletes the group', () async {
      g.accept(bob); // 1
      g.change(alice, const [Gv2DeleteGroup()]); // 2
      await d.invited(bob, 0);
      final result = await d.sync().sync(g.id);
      expect(result.membership, Gv2Membership.ended);
      expect((await d.row()).deleted, isTrue);
    });

    test('a removal of someone else is recorded for the Sender Key', () async {
      await d.created(alice);
      g.accept(bob); // 1
      g.accept(carol); // 2
      g.change(alice, [Gv2Remove(carol.ciphertext)]); // 3
      g.change(alice, const [Gv2SetTitle()], newTitle: 'Two'); // 4
      final result = await d.sync().sync(g.id);
      expect(result.membership, Gv2Membership.active);
      expect((await d.row()).lastRemovalRevision, 3);
    });
  });

  group('the state at the anchor', () {
    setUp(() async {
      g.decline(carol); // 1
      await d.invited(bob, 1);
    });

    test('is refused when it does not hash to the anchor', () async {
      for (final alter in <Gv2Snapshot Function(Gv2Snapshot)>[
        // The inviter is no longer the owner.
        (s) => Gv2Snapshot(
            state: s.state..members[alice.key]!.role = gv2RoleMember,
            headSig: s.headSig),
        // Somebody extra.
        (s) => Gv2Snapshot(
            state: s.state
              ..members[carol.key] = Gv2MemberState(
                role: gv2RoleMember,
                memberPub: carol.memberKey.publicKey,
                joinedRevision: 1,
                memberPayload: g.memberPayload(carol),
              ),
            headSig: s.headSig),
        // Another chain.
        (s) => Gv2Snapshot(
            state: s.state..chain = gv2TestSha('other chain'),
            headSig: s.headSig),
      ]) {
        server.alterSnapshot = alter;
        final result = await d.sync().sync(g.id);
        expect(result.status, Gv2SyncStatus.snapshotMismatch);
        expect((await d.row()).stateLoaded, isFalse);
        expect(await d.store.memberRows(g.id), isEmpty);
      }
    });

    test('is refused without the server\'s signature over that head', () async {
      server.alterSnapshot =
          (s) => Gv2Snapshot(state: s.state, headSig: gv2TestBytes('no', 64));
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.badData);
      expect((await d.row()).stateLoaded, isFalse);
    });

    test('an anchor where this account is not invited is not installed',
        () async {
      // The same group, but the "invite" names someone who is not pending.
      final stranger = _Device(g, server);
      addTearDown(stranger.db.close);
      await stranger.store.insertAnchored(
        groupId: g.groupId,
        masterKey: g.masterKey,
        myCiphertext: g.person('mallory').ciphertext,
        protocolVersion: gv2ProtocolVersion,
        revision: 1,
        chain: g.states[1].chain,
        stateHash: gv2StateHash(g.states[1]),
        membership: Gv2Membership.invited,
        inviteSeed: Uint8List(32),
      );
      expect((await stranger.sync().sync(g.id)).status, Gv2SyncStatus.badData);
      expect((await stranger.row()).stateLoaded, isFalse);
    });
  });

  group('data that does not verify (and proves nothing)', () {
    setUp(() async {
      await d.created(alice);
      history();
    });

    test('an altered entry stops the sync; what was verified before is kept',
        () async {
      final altered = gv2EncodeEntry(g.log[3]);
      altered[altered.length - 70] ^= 0x01; // inside the state hash
      server.entryOverride[3] = altered;
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      expect(result.toRevision, 2);
      final row = await d.row();
      expect(row.revision, 2);
      expect(row.hold, Gv2Hold.none, reason: 'nothing the server signed');
      // Once the server serves the real entry the sync goes on.
      server.entryOverride.clear();
      expect((await d.sync().sync(g.id)).toRevision, 5);
    });

    test('bytes that are no entry at all', () async {
      // The first byte is where the protocol version sits: with the current
      // version there, undecodable bytes are simply bad data.
      server.entryOverride[1] = gv2TestBytes('garbage', 90)
        ..[0] = gv2ProtocolVersion;
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      final row = await d.row();
      expect(row.revision, 0);
      expect(row.hold, Gv2Hold.none);
    });

    test('a head signature that does not verify: nothing after the last signed point',
        () async {
      server.entryHeadSigOverride[5] = gv2TestBytes('unsigned', 64);
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      // Entries 1–4 verify and entry 4's head is signed.
      expect((await d.row()).revision, 4);
    });

    test('a join after the last signed point is not reported with its '
        'inviter', () async {
      g.accept(g.person('dave')); // 6: dave takes bob's invite
      server.entryHeadSigOverride[6] = gv2TestBytes('unsigned', 64);
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      expect(result.toRevision, 5);
      // Bob's join (signed) is reported; dave's (dropped) is not.
      expect(result.invitedBy, {bob.key: alice.key});
    });

    test('a head signed by another key is not the server\'s', () async {
      d.keys.headPublicKey =
          Gv2SigningKey.fromSeed(gv2TestSha('another server')).publicKey;
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      expect((await d.row()).revision, 0);
    });

    test('a head the server claims but did not serve', () async {
      // It serves up to 3 and says that is all, while naming 5 as its head.
      final honest = server.head(5);
      g.states.removeRange(4, 6);
      g.log.removeRange(4, 6);
      server.headOverride = honest;
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      expect((await d.row()).revision, 3, reason: 'the verified part is kept');
    });

    test('"more" without entries does not loop', () async {
      await d.sync().sync(g.id);
      server.moreForEver = true;
      server.logCalls = 0;
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.badData);
      expect(server.logCalls, 1);
    });

    test('a server behind the stored anchor does not take the device back',
        () async {
      await d.sync().sync(g.id);
      final before = await d.row();
      // The server now shows the log only up to revision 3.
      g.states.removeRange(4, 6);
      g.log.removeRange(4, 6);
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.serverBehind);
      final row = await d.row();
      expect(row.revision, 5);
      expect(row.chain, before.chain);
      expect(row.hold, Gv2Hold.none);
    });

    test('an unsigned other head at the same revision is only bad data',
        () async {
      await d.sync().sync(g.id);
      server.headOverride = Gv2Head(
          revision: 5,
          chain: gv2TestSha('other chain'),
          headSig: gv2TestBytes('unsigned', 64));
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.badData);
      expect((await d.row()).hold, Gv2Hold.none);
    });
  });

  group('what the server signed against itself freezes the group', () {
    /// An entry that extends the real chain at [state] but breaks the rules
    /// (bob, a plain member, removes the owner), with a head the server signed.
    void serveInvalidEntry(Gv2GroupState state) {
      final draft = Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: state.revision + 1,
        prevChain: state.chain,
        actor: bob.ciphertext,
        actions: [Gv2Remove(alice.ciphertext)],
        memberPayload: Uint8List(0),
        titlePayload: Uint8List(0),
      );
      final hash = gv2TestSha('claimed state');
      final signed = gv2SignedBytes(g.groupId, draft, hash);
      final sig = bob.memberKey.sign(signed);
      final chain = gv2ChainHash(state.chain, signed, sig);
      server.entryOverride[draft.revision] = gv2EncodeEntry(
          Gv2Entry.complete(draft, stateHashAfter: hash, sig: sig));
      server.entryHeadSigOverride[draft.revision] = g.headKey
          .sign(gv2HeadMessage(g.groupId, draft.revision, chain));
    }

    test('an entry the rules forbid, with the server\'s signature on its head',
        () async {
      await d.created(alice);
      g.accept(bob); // 1
      g.decline(carol); // 2 (replaced below by the invalid entry)
      serveInvalidEntry(g.states[1]);

      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.frozen);
      expect(result.toRevision, 1, reason: 'the valid entry before it is kept');
      final row = await d.row();
      expect(row.hold, Gv2Hold.frozen);
      expect(row.revision, 1);
      final evidence = await d.evidence();
      expect(evidence['kind'], 'invalid_entry');
      expect(evidence['reject'], 'permission');
      expect((evidence['served'] as Map)['revision'], 2);
      expect((evidence['served'] as Map)['entry'], isNotNull);
      expect((evidence['held'] as Map)['revision'], 1);

      // Frozen for good: no request is made, whatever the server serves now.
      server.entryOverride.clear();
      server.entryHeadSigOverride.clear();
      server.logCalls = 0;
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.frozen);
      expect(server.logCalls, 0);
    });

    test('the same entry WITHOUT the server\'s signature is only bad data',
        () async {
      await d.created(alice);
      g.accept(bob); // 1
      g.decline(carol); // 2
      serveInvalidEntry(g.states[1]);
      server.entryHeadSigOverride[2] = gv2TestBytes('unsigned', 64);
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      expect((await d.row()).hold, Gv2Hold.none);
    });

    test('an entry of another history, signed, after a head it also signed',
        () async {
      await d.created(alice);
      g.accept(bob); // 1 (never served)
      // The same group with another first entry.
      final fork = Gv2TestGroup();
      fork.create(fork.person('alice'), invite: [fork.person('bob')]);
      fork.accept(fork.person('bob'));
      expect(fork.states[0].chain, isNot(g.states[0].chain));
      server.entryOverride[1] = gv2EncodeEntry(fork.log[1]);
      server.entryHeadSigOverride[1] = fork.headSig(1);

      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.frozen);
      final evidence = await d.evidence();
      expect(evidence['kind'], 'fork');
      expect((evidence['held'] as Map)['chain'], base64Encode(g.states[0].chain));
      expect((evidence['held'] as Map)['headSig'], base64Encode(g.headSig(0)));
      expect((evidence['served'] as Map)['chain'],
          base64Encode(fork.states[1].chain));
      expect((await d.row()).revision, 0);
    });

    test('the same fork is only bad data when the held head carries no signature',
        () async {
      // An invitee that never got a signed head for its anchor.
      await d.invited(bob, 0);
      await d.store.installState(state: g.states[0]);
      final fork = Gv2TestGroup();
      fork.create(fork.person('alice'), invite: [fork.person('bob')]);
      fork.accept(fork.person('bob'));
      g.accept(bob); // 1 (never served)
      server.entryOverride[1] = gv2EncodeEntry(fork.log[1]);
      server.entryHeadSigOverride[1] = fork.headSig(1);
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.badData);
      expect((await d.row()).hold, Gv2Hold.none);
    });

    test('two signed heads at the same revision', () async {
      await d.created(alice);
      history();
      await d.sync().sync(g.id);
      final other = gv2TestSha('other chain');
      server.headOverride = Gv2Head(
        revision: 5,
        chain: other,
        headSig: g.headKey.sign(gv2HeadMessage(g.groupId, 5, other)),
      );
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.frozen);
      final evidence = await d.evidence();
      expect(evidence['kind'], 'two_heads');
      expect((evidence['held'] as Map)['chain'], base64Encode(g.state.chain));
      expect((evidence['served'] as Map)['chain'], base64Encode(other));
    });
  });

  group('a freeze judged again by a later build', () {
    /// Evidence as an earlier build would have stored it, had its rules
    /// refused entry [revision] of the honest log.
    Uint8List refusedBefore(int revision) => Uint8List.fromList(utf8.encode(
          jsonEncode({
            'kind': 'invalid_entry',
            'reject': 'permission',
            'held': {
              'revision': revision - 1,
              'chain': base64Encode(g.states[revision - 1].chain),
              'headSig': base64Encode(g.headSig(revision - 1)),
            },
            'served': {
              'revision': revision,
              'chain': base64Encode(g.states[revision].chain),
              'headSig': base64Encode(g.headSig(revision)),
              'entry': base64Encode(gv2EncodeEntry(g.log[revision])),
            },
          }),
        ));

    test('an entry the rules of this build accept: the freeze was a '
        'disagreement between builds, so it is lifted and the sync goes on',
        () async {
      await d.created(alice);
      history();
      await d.store.setHold(g.id, Gv2Hold.frozen, evidence: refusedBefore(1));

      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.advanced);
      expect(result.toRevision, 5);
      final row = await d.row();
      expect(row.hold, Gv2Hold.none);
      expect(row.holdEvidence, isNull);
      expect(row.chain, g.state.chain);
    });

    test('an entry this build still refuses keeps the group frozen, and '
        'nothing is fetched', () async {
      await d.created(alice);
      g.accept(bob); // 1
      g.decline(carol); // 2 (replaced by an entry the rules forbid)
      final sync = d.sync();
      // Served by the test group's real entries: replace 2 with bob
      // removing the owner, signed by the server.
      final draft = Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: 2,
        prevChain: g.states[1].chain,
        actor: bob.ciphertext,
        actions: [Gv2Remove(alice.ciphertext)],
        memberPayload: Uint8List(0),
        titlePayload: Uint8List(0),
      );
      final hash = gv2TestSha('claimed state');
      final signed = gv2SignedBytes(g.groupId, draft, hash);
      final sig = bob.memberKey.sign(signed);
      final chain = gv2ChainHash(g.states[1].chain, signed, sig);
      server.entryOverride[2] = gv2EncodeEntry(
          Gv2Entry.complete(draft, stateHashAfter: hash, sig: sig));
      server.entryHeadSigOverride[2] =
          g.headKey.sign(gv2HeadMessage(g.groupId, 2, chain));
      expect((await sync.sync(g.id)).status, Gv2SyncStatus.frozen);
      final frozenOn = (await d.row()).holdEvidence;

      server.logCalls = 0;
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.frozen);
      expect(server.logCalls, 0);
      expect((await d.row()).holdEvidence, frozenOn);
    });

    test('judged once per run: a second sync of the same run does not look '
        'again', () async {
      await d.created(alice);
      history();
      // Evidence about a point this device does not hold: kept.
      await d.store.setHold(g.id, Gv2Hold.frozen, evidence: refusedBefore(3));
      final sync = d.sync();
      expect((await sync.sync(g.id)).status, Gv2SyncStatus.frozen);

      // Now evidence that would be lifted — but not in this run.
      await d.store.setHold(g.id, Gv2Hold.frozen, evidence: refusedBefore(1));
      expect((await sync.sync(g.id)).status, Gv2SyncStatus.frozen);
      expect((await d.row()).hold, Gv2Hold.frozen);

      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.advanced);
    });

    test('evidence that is not about the anchor held here keeps the freeze',
        () async {
      await d.created(alice);
      history();
      // Entry 3 is valid, but this device holds revision 0.
      await d.store.setHold(g.id, Gv2Hold.frozen, evidence: refusedBefore(3));
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.frozen);
      expect((await d.row()).revision, 0);
    });

    test('a fork and two signed heads are not judged again: they are facts '
        'about signatures, not about the rules', () async {
      await d.created(alice);
      history();
      final valid = jsonDecode(utf8.decode(refusedBefore(1))) as Map;
      for (final kind in ['fork', 'two_heads']) {
        await d.store.setHold(
          g.id,
          Gv2Hold.frozen,
          evidence: Uint8List.fromList(
              utf8.encode(jsonEncode({...valid, 'kind': kind}))),
        );
        server.logCalls = 0;
        expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.frozen,
            reason: kind);
        expect(server.logCalls, 0, reason: kind);
      }
    });

    test('unreadable evidence keeps the freeze', () async {
      await d.created(alice);
      history();
      await d.store.setHold(g.id, Gv2Hold.frozen,
          evidence: Uint8List.fromList(utf8.encode('not json')));
      expect((await d.sync().sync(g.id)).status, Gv2SyncStatus.frozen);
    });
  });

  group('an entry of a later protocol version', () {
    test('holds the group until a sync gets through, then releases it',
        () async {
      await d.created(alice);
      history();
      final future = gv2EncodeEntry(g.log[3]);
      future[0] = gv2ProtocolVersion + 1;
      server.entryOverride[3] = future;

      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.updateRequired);
      var row = await d.row();
      expect(row.hold, Gv2Hold.updateRequired);
      expect(row.revision, 2);
      expect(row.holdEvidence, isNull);

      // After the update the same log is readable.
      server.entryOverride.clear();
      final after = await d.sync().sync(g.id);
      expect(after.status, Gv2SyncStatus.advanced);
      row = await d.row();
      expect(row.hold, Gv2Hold.none);
      expect(row.revision, 5);
    });
  });

  group('damaged local rows', () {
    setUp(() async {
      await d.created(alice);
      history();
      await d.sync().sync(g.id);
      await d.db.customStatement(
          'DELETE FROM gv2_members WHERE ciphertext = ?', [bob.key]);
    });

    test('are rebuilt from the anchor and the sync goes on', () async {
      g.change(alice, const [Gv2SetTitle()], newTitle: 'Spring'); // 6
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.advanced);
      expect(result.toRevision, 6);
      expect(server.snapshotCalls, 1);
      final row = await d.row();
      expect(row.hold, Gv2Hold.none, reason: 'not the server\'s fault');
      expect((await d.store.memberRows(g.id)).length, 2);
    });

    test('are reported as local when the server cannot restore them', () async {
      server.alterSnapshot = (s) => Gv2Snapshot(
          state: s.state..chain = gv2TestSha('other chain'), headSig: s.headSig);
      final result = await d.sync().sync(g.id);
      expect(result.status, Gv2SyncStatus.localCorruption);
      final row = await d.row();
      expect(row.hold, Gv2Hold.none);
      expect(row.revision, 5, reason: 'the anchor is kept');
    });
  });

  group('member checks', () {
    late Gv2TestPerson dave;
    late Gv2TestPerson erin;
    late Gv2TestPerson frank;

    setUp(() async {
      dave = g.person('dave');
      erin = g.person('erin');
      frank = g.person('frank');
      await d.created(alice);
      g.accept(bob); // 1: an honest member
      // 2: carol joins with a payload sealed under another key.
      g.accept(carol,
          payload: gv2SealMemberPayload(
              gv2DeriveHintKey(g.masterKey, g.groupId),
              carol.payload(g.groupId, issuedAtMs: _now)));
      g.invite(alice, dave); // 3
      // 4: dave joins with a copy of bob's whole payload.
      g.accept(dave, payload: g.memberPayload(bob));
      g.invite(alice, erin); // 5
      // 6: erin joins with a certificate made for another group.
      g.accept(erin,
          payload: gv2SealMemberPayload(
              g.stateKey,
              erin.payload(Gv2TestGroup('other').groupId, issuedAtMs: _now)));
      g.invite(alice, frank); // 7: still pending
      await d.sync().sync(g.id);
    });

    Future<Map<String, Gv2MemberRow>> rows() async => {
          for (final m in await d.store.memberRows(g.id)) m.ciphertext: m,
        };

    test('confirm exactly the members whose account vouches for them',
        () async {
      final summary = await d.sync().checkMembers(g.id);
      expect(summary.confirmed, 2);
      expect(summary.unconfirmed, 3);
      final r = await rows();

      for (final p in [alice, bob]) {
        expect(r[p.key]!.checkState, Gv2MemberCheckState.confirmed, reason: p.name);
        expect(r[p.key]!.snowId, p.snowId);
        expect(r[p.key]!.accountPublicKey, p.accountPub);
        expect(r[p.key]!.certIssuedAtMs, isNotNull);
      }
      expect(r[carol.key]!.checkState, Gv2MemberCheckState.payload);
      expect(r[dave.key]!.checkState, Gv2MemberCheckState.accountId);
      expect(r[erin.key]!.checkState, Gv2MemberCheckState.certificate);
      // Who the ciphertext belongs to is known even when the check fails...
      expect(r[dave.key]!.snowId, dave.snowId);
      // ...but an unconfirmed member has no account key on record.
      expect(r[dave.key]!.accountPublicKey, isNull);

      expect((await d.store.confirmedMembers(g.id)).map((m) => m.snowId).toSet(),
          {alice.snowId, bob.snowId});
      // The pending invite is named.
      expect((await d.store.pendingInvites(g.id)).single.snowId, frank.snowId);
    });

    test('are made once: a second run checks nobody', () async {
      await d.sync().checkMembers(g.id);
      final lookups = d.pinnedLookups;
      final again = await d.sync().checkMembers(g.id);
      expect(again.confirmed + again.unconfirmed, 0);
      expect(d.pinnedLookups, lookups);
    });

    test('give the same result in a worker isolate', () async {
      final summary = await d.sync(checkInIsolateFrom: 1).checkMembers(g.id);
      expect(summary.confirmed, 2);
      final r = await rows();
      expect(r[bob.key]!.checkState, Gv2MemberCheckState.confirmed);
      expect(r[erin.key]!.checkState, Gv2MemberCheckState.certificate);
    });

    test('refuse an account key that differs from the one already pinned',
        () async {
      d.pinned[bob.snowId] = Uint8List.fromList(bob.accountPub)..[31] ^= 0x01;
      d.pinned[alice.snowId] = alice.accountPub;
      await d.sync().checkMembers(g.id);
      final r = await rows();
      expect(r[bob.key]!.checkState, Gv2MemberCheckState.pinnedKey);
      expect(r[bob.key]!.accountPublicKey, isNull);
      expect(r[alice.key]!.checkState, Gv2MemberCheckState.confirmed);
    });

    test('a member who joins again is checked again', () async {
      await d.sync().checkMembers(g.id);
      g.change(alice, [Gv2Remove(carol.ciphertext)]); // 8
      g.invite(alice, carol); // 9
      g.accept(carol); // 10: this time with a proper payload
      await d.sync().sync(g.id);
      expect((await rows())[carol.key]!.checkState, Gv2MemberCheckState.unchecked);
      final summary = await d.sync().checkMembers(g.id);
      expect(summary.confirmed, 1);
      expect((await rows())[carol.key]!.checkState, Gv2MemberCheckState.confirmed);
    });

    test('nothing is checked before the state is there', () async {
      final fresh = _Device(g, server);
      addTearDown(fresh.db.close);
      await fresh.invited(frank, 7);
      final summary = await fresh.sync().checkMembers(g.id);
      expect(summary.confirmed + summary.unconfirmed, 0);
    });
  });

  group('the title and the server keys', () {
    test('match when the group was created under the keys this device holds',
        () async {
      // The test group's title commits to gv2ServerKeyHash of these values.
      final params = gv2TestBytes('server params', 673);
      final titled = Gv2TestGroup('titled');
      final owner = titled.person('alice');
      titled.create(
        owner,
        titlePayloadBytes: gv2SealTitlePayload(
          titled.stateKey,
          Gv2TitlePayload(
            name: 'Keys',
            serverKeyHash: gv2ServerKeyHash(
              serverPublicParams: params,
              headPublicKey: titled.headKey.publicKey,
            ),
          ),
        ),
      );
      final device = _Device(titled, _Server(titled));
      addTearDown(device.db.close);
      await device.created(owner);
      expect(await device.sync().titleMatchesServerKeys(titled.id), isTrue);

      // The server hands this device other parameters than the creator had.
      device.keys.serverPublicParams = gv2TestBytes('other params', 673);
      expect(await device.sync().titleMatchesServerKeys(titled.id), isFalse);
    });

    test('is unknown when the title does not open', () async {
      final untitled = Gv2TestGroup('untitled');
      final owner = untitled.person('alice');
      untitled.create(owner, titlePayloadBytes: gv2TestBytes('opaque', 332));
      final device = _Device(untitled, _Server(untitled));
      addTearDown(device.db.close);
      await device.created(owner);
      expect(await device.sync().titleMatchesServerKeys(untitled.id), isNull);
      expect(await device.sync().titleMatchesServerKeys('ab' * 32), isNull);
    });
  });

  group('gv2StandingAfter', () {
    test('an invite that was revoked reads as declined', () {
      g.change(alice, [Gv2RevokeInvite(bob.ciphertext)]); // 1
      expect(
        gv2StandingAfter(
          before: Gv2Membership.invited,
          myCiphertext: bob.key,
          entry: g.log[1],
          after: g.states[1],
        ),
        Gv2Membership.declined,
      );
      // Carol is still invited; alice still active.
      expect(
        gv2StandingAfter(
          before: Gv2Membership.invited,
          myCiphertext: carol.key,
          entry: g.log[1],
          after: g.states[1],
        ),
        Gv2Membership.invited,
      );
      expect(
        gv2StandingAfter(
          before: Gv2Membership.active,
          myCiphertext: alice.key,
          entry: g.log[1],
          after: g.states[1],
        ),
        Gv2Membership.active,
      );
    });
  });
}
