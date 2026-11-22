/// @file        gv2_store_test.dart
/// @description Gv2Store on a real (in-memory) database, with states produced
///              by real signed entries: a state and its anchor move together
///              or not at all, an older view cannot overwrite a newer one, an
///              invite cannot replace a stored anchor, per-member results
///              survive unrelated changes and are reset when a member joins
///              again, damaged rows are reported as local corruption and can
///              be repaired from the anchor, credentials and endorsements
///              do not outlive the server keys or the member they belong to,
///              and every verified point of the log is kept unchanged.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: pruneOld, shedding a group no longer this account's, forgetGone). Earlier 2026-11-13
///
/// @functions
///  - main(): the test groups below.
///  - _Fixture: a database, its store and a test group with three people.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise.dart' show Gv2SenderKeyBody;
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';

import 'gv2_test_support.dart';

const _now = 1794528000000;

class _Fixture {
  final SnowDatabase db = SnowDatabase(NativeDatabase.memory());
  final Gv2TestGroup g = Gv2TestGroup();
  late final Gv2Store store = db.gv2Store;
  late final Gv2TestPerson alice = g.person('alice');
  late final Gv2TestPerson bob = g.person('bob');
  late final Gv2TestPerson carol = g.person('carol');

  /// Alice creates the group (inviting bob and carol) and stores it.
  Future<void> createdByAlice() async {
    g.create(alice, invite: [bob, carol]);
    await store.insertCreated(
      masterKey: g.masterKey,
      myCiphertext: alice.ciphertext,
      state: g.states[0],
      headSig: g.headSig(0),
      nowMs: _now,
    );
  }

  /// Move alice's stored group from revision [from] to the latest state.
  Future<void> advanceFrom(int from, {Gv2Membership? membership, int? removal}) =>
      store.advance(
        from: g.states[from],
        to: g.state,
        headSig: g.headSig(g.state.revision),
        membership: membership,
        removalRevision: removal,
      );

  Future<Gv2GroupRow> row() async => (await store.group(g.id))!;

  Future<Gv2MemberRow> member(Gv2TestPerson p) async =>
      (await store.memberRows(g.id)).singleWhere((m) => m.ciphertext == p.key);

  Gv2MemberCheckResult confirmed(Gv2TestPerson p, int joinedRevision) =>
      Gv2MemberCheckResult(
        ciphertext: p.key,
        joinedRevision: joinedRevision,
        state: Gv2MemberCheckState.confirmed,
        snowId: p.snowId,
        accountPublicKey: p.accountPub,
        certIssuedAtMs: _now,
      );
}

void main() {
  late _Fixture f;
  setUp(() => f = _Fixture());
  tearDown(() => f.db.close());

  group('a group this device created', () {
    test('is stored with its anchor, state and decoded name', () async {
      await f.createdByAlice();
      final row = await f.row();
      expect(row.membership, Gv2Membership.active);
      expect(row.hold, Gv2Hold.none);
      expect(row.revision, 0);
      expect(row.chain, f.g.states[0].chain);
      expect(row.stateHash, gv2StateHash(f.g.states[0]));
      expect(row.headSig, f.g.headSig(0));
      expect(row.stateLoaded, isTrue);
      expect(row.title, 'Snow');
      expect(row.masterKey, f.g.masterKey);
      expect(row.myCiphertext, f.alice.key);
      expect(row.lastSyncAtMs, _now);
      expect(await f.store.myRole(f.g.id), gv2RoleOwner);

      final members = await f.store.memberRows(f.g.id);
      expect(members.map((m) => m.ciphertext), [f.alice.key]);
      expect(members.single.checkState, Gv2MemberCheckState.unchecked);
      final pending = await f.store.pendingInvites(f.g.id);
      expect(pending.map((p) => p.ciphertext).toSet(), {f.bob.key, f.carol.key});
      expect(pending.every((p) => p.invitedBy == f.alice.key), isTrue);
    });

    test('loads back to exactly the same state', () async {
      await f.createdByAlice();
      final loaded = (await f.store.loadState(f.g.id))!;
      expect(gv2StateHash(loaded), gv2StateHash(f.g.states[0]));
      expect(loaded.chain, f.g.states[0].chain);
      expect(loaded.revision, 0);
      expect(loaded.members.keys, f.g.states[0].members.keys);
      expect(loaded.pending.keys, f.g.states[0].pending.keys);
    });

    test('cannot be stored twice, nor from a state that is not a creation',
        () async {
      await f.createdByAlice();
      await expectLater(
        f.store.insertCreated(
          masterKey: f.g.masterKey,
          myCiphertext: f.alice.ciphertext,
          state: f.g.states[0],
          headSig: f.g.headSig(0),
          nowMs: _now,
        ),
        throwsA(isA<Gv2StoreConflict>()),
      );
      final other = Gv2TestGroup('other');
      final dave = other.person('dave');
      final erin = other.person('erin');
      other.create(dave, invite: [erin]);
      // Erin is not the owner of that group.
      expect(
        () => f.store.insertCreated(
          masterKey: other.masterKey,
          myCiphertext: erin.ciphertext,
          state: other.states[0],
          headSig: other.headSig(0),
          nowMs: _now,
        ),
        throwsArgumentError,
      );
      other.accept(erin);
      expect(
        () => f.store.insertCreated(
          masterKey: other.masterKey,
          myCiphertext: dave.ciphertext,
          state: other.states[1],
          headSig: other.headSig(1),
          nowMs: _now,
        ),
        throwsArgumentError,
      );
      expect(await f.store.group(other.id), isNull);
    });

    test('a name that does not open is stored as unknown', () async {
      f.g.create(f.alice,
          titlePayloadBytes: f.g.titlePayload('Snow',
              key: gv2DeriveHintKey(f.g.masterKey, f.g.groupId)));
      await f.store.insertCreated(
        masterKey: f.g.masterKey,
        myCiphertext: f.alice.ciphertext,
        state: f.g.states[0],
        headSig: f.g.headSig(0),
        nowMs: _now,
      );
      expect((await f.row()).title, isNull);
      // The state itself is intact.
      expect(await f.store.loadState(f.g.id), isNotNull);
    });
  });

  group('advance', () {
    setUp(() => f.createdByAlice());

    test('moves the anchor and writes only what changed', () async {
      await f.store.saveMemberChecks(f.g.id, [f.confirmed(f.alice, 0)]);
      f.g.accept(f.bob); // revision 1
      await f.advanceFrom(0);

      final row = await f.row();
      expect(row.revision, 1);
      expect(row.chain, f.g.states[1].chain);
      expect(row.stateHash, gv2StateHash(f.g.states[1]));
      expect(row.headSig, f.g.headSig(1));
      expect((await f.store.memberRows(f.g.id)).length, 2);
      expect((await f.store.pendingInvites(f.g.id)).single.ciphertext, f.carol.key);
      // Alice's check result survived bob joining.
      expect((await f.member(f.alice)).checkState, Gv2MemberCheckState.confirmed);
      expect((await f.member(f.bob)).checkState, Gv2MemberCheckState.unchecked);
      expect((await f.member(f.bob)).joinedRevision, 1);
      expect(gv2StateHash((await f.store.loadState(f.g.id))!),
          gv2StateHash(f.g.states[1]));
    });

    test('can skip over several revisions at once', () async {
      f.g.accept(f.bob); // 1
      f.g.decline(f.carol); // 2
      f.g.change(f.alice, [Gv2SetRole(f.bob.ciphertext, gv2RoleAdmin)]); // 3
      f.g.change(f.bob, const [Gv2SetTitle()], newTitle: 'Winter'); // 4
      await f.advanceFrom(0);

      final row = await f.row();
      expect(row.revision, 4);
      expect(row.title, 'Winter');
      expect(await f.store.pendingInvites(f.g.id), isEmpty);
      expect((await f.member(f.bob)).role, gv2RoleAdmin);
      expect(gv2StateHash((await f.store.loadState(f.g.id))!),
          gv2StateHash(f.g.state));
    });

    test('a role change keeps what this device worked out about the member',
        () async {
      f.g.accept(f.bob);
      await f.advanceFrom(0);
      await f.store.saveMemberChecks(f.g.id, [f.confirmed(f.bob, 1)]);
      await f.store.setReach(f.g.id, f.bob.key, Gv2Reach.unreachable);

      f.g.change(f.alice, [Gv2SetRole(f.bob.ciphertext, gv2RoleAdmin)]);
      await f.advanceFrom(1);
      final bob = await f.member(f.bob);
      expect(bob.role, gv2RoleAdmin);
      expect(bob.checkState, Gv2MemberCheckState.confirmed);
      expect(bob.snowId, f.bob.snowId);
      expect(bob.accountPublicKey, f.bob.accountPub);
      expect(bob.reach, Gv2Reach.unreachable);
    });

    test('a member who left and joined again starts unchecked', () async {
      f.g.accept(f.bob); // 1
      await f.advanceFrom(0);
      await f.store.saveMemberChecks(f.g.id, [f.confirmed(f.bob, 1)]);
      await f.store.setReach(f.g.id, f.bob.key, Gv2Reach.deleted);

      f.g.change(f.alice, [Gv2Remove(f.bob.ciphertext)]); // 2
      await f.advanceFrom(1);
      expect((await f.store.memberRows(f.g.id)).map((m) => m.ciphertext),
          [f.alice.key]);

      f.g.invite(f.alice, f.bob); // 3
      f.g.accept(f.bob, issuedAtMs: _now + 5000); // 4
      await f.advanceFrom(2);
      final bob = await f.member(f.bob);
      expect(bob.joinedRevision, 4);
      expect(bob.checkState, Gv2MemberCheckState.unchecked);
      expect(bob.snowId, isNull);
      expect(bob.accountPublicKey, isNull);
      expect(bob.reach, Gv2Reach.ok);

      // Removed and re-added inside ONE advance: still a fresh row.
      await f.store.saveMemberChecks(f.g.id, [f.confirmed(f.bob, 4)]);
      f.g.change(f.alice, [Gv2Remove(f.bob.ciphertext)]); // 5
      f.g.invite(f.alice, f.bob); // 6
      f.g.accept(f.bob, issuedAtMs: _now + 9000); // 7
      await f.advanceFrom(4);
      final again = await f.member(f.bob);
      expect(again.joinedRevision, 7);
      expect(again.checkState, Gv2MemberCheckState.unchecked);
      expect(gv2StateHash((await f.store.loadState(f.g.id))!),
          gv2StateHash(f.g.state));
    });

    test('an invite that was revoked and made again is replaced', () async {
      f.g.change(f.alice, [Gv2RevokeInvite(f.bob.ciphertext)]); // 1
      f.g.invite(f.alice, f.bob); // 2
      await f.advanceFrom(0);
      final invite = (await f.store.pendingInvites(f.g.id))
          .singleWhere((p) => p.ciphertext == f.bob.key);
      expect(invite.revision, 2);
      expect(invite.invitePub, f.g.inviteKeyOf(f.bob).publicKey);
      expect(await f.store.loadState(f.g.id), isNotNull);
    });

    test('from an older view of the group: refused, nothing written', () async {
      f.g.accept(f.bob); // 1
      await f.advanceFrom(0);
      f.g.decline(f.carol); // 2
      // A second writer still working from revision 0.
      await expectLater(f.advanceFrom(0), throwsA(isA<Gv2StoreConflict>()));
      final row = await f.row();
      expect(row.revision, 1);
      expect((await f.store.pendingInvites(f.g.id)).length, 1);
      // From the right starting point it goes through.
      await f.advanceFrom(1);
      expect((await f.row()).revision, 2);
    });

    test('from another chain at the same revision: refused', () async {
      // A different history that also has a revision 0.
      final fork = Gv2TestGroup();
      fork.create(fork.person('alice'), invite: [fork.person('bob')]);
      fork.accept(fork.person('bob'));
      expect(fork.states[0].chain, isNot(f.g.states[0].chain));
      await expectLater(
        f.store.advance(
            from: fork.states[0], to: fork.states[1], headSig: fork.headSig(1)),
        throwsA(isA<Gv2StoreConflict>()),
      );
      expect((await f.row()).revision, 0);
    });

    test('backwards, sideways or to another group is not an advance', () async {
      f.g.accept(f.bob);
      await f.advanceFrom(0);
      expect(
          () => f.store.advance(
              from: f.g.states[1], to: f.g.states[0], headSig: f.g.headSig(0)),
          throwsArgumentError);
      expect(
          () => f.store.advance(
              from: f.g.states[1], to: f.g.states[1], headSig: f.g.headSig(1)),
          throwsArgumentError);
      final other = Gv2TestGroup('other')..create(Gv2TestGroup('other').person('x'));
      expect(
          () => f.store.advance(
              from: f.g.states[1], to: other.states[0], headSig: other.headSig(0)),
          throwsArgumentError);
    });

    test('a standing that contradicts the new state: refused, nothing written',
        () async {
      f.g.accept(f.bob); // 1
      await f.advanceFrom(0);
      f.g.change(f.alice, [Gv2TransferOwner(f.bob.ciphertext)]); // 2
      f.g.change(f.bob, [Gv2Remove(f.alice.ciphertext)]); // 3
      // Alice is no longer a member at revision 3 but the caller says nothing.
      await expectLater(f.advanceFrom(1), throwsStateError);
      expect((await f.row()).revision, 1);
      expect((await f.store.memberRows(f.g.id)).length, 2);
      // Saying "active" is just as wrong.
      await expectLater(
          f.advanceFrom(1, membership: Gv2Membership.active), throwsStateError);
      // With the right standing the whole move goes through.
      await f.advanceFrom(1, membership: Gv2Membership.removed);
      final row = await f.row();
      expect(row.revision, 3);
      expect(row.membership, Gv2Membership.removed);
      expect(await f.store.myRole(f.g.id), isNull);
    });

    test('a failure in the middle leaves the stored group untouched', () async {
      f.g.accept(f.bob); // 1
      final broken = f.g.states[1].copy();
      // A member row that cannot be written (member key of the wrong length).
      broken.members[f.carol.key] = Gv2MemberState(
        role: gv2RoleMember,
        memberPub: Uint8List(31),
        joinedRevision: 1,
        memberPayload: Uint8List(0),
      );
      await expectLater(
        f.store.advance(
            from: f.g.states[0], to: broken, headSig: f.g.headSig(1)),
        throwsArgumentError,
      );
      final row = await f.row();
      expect(row.revision, 0);
      expect(row.headSig, f.g.headSig(0));
      expect((await f.store.memberRows(f.g.id)).length, 1);
      expect((await f.store.pendingInvites(f.g.id)).length, 2);
      expect(gv2StateHash((await f.store.loadState(f.g.id))!),
          gv2StateHash(f.g.states[0]));
    });

    test('a database error after the rows were written rolls everything back',
        () async {
      f.g.accept(f.bob); // 1
      // The member and pending rows are written first, the group row last:
      // make that last statement fail inside the database.
      await f.db.customStatement(
        'CREATE TRIGGER gv2_test_fail BEFORE UPDATE ON gv2_groups '
        "BEGIN SELECT RAISE(ABORT, 'test failure'); END",
      );
      await expectLater(f.advanceFrom(0), throwsA(anything));
      await f.db.customStatement('DROP TRIGGER gv2_test_fail');

      final row = await f.row();
      expect(row.revision, 0);
      expect((await f.store.memberRows(f.g.id)).map((m) => m.ciphertext),
          [f.alice.key]);
      expect((await f.store.pendingInvites(f.g.id)).length, 2);
      expect(gv2StateHash((await f.store.loadState(f.g.id))!),
          gv2StateHash(f.g.states[0]));
      // And the same move succeeds afterwards.
      await f.advanceFrom(0);
      expect((await f.row()).revision, 1);
    });

    test('the latest removal is recorded with the state', () async {
      f.g.accept(f.bob); // 1
      f.g.accept(f.carol); // 2
      await f.advanceFrom(0);
      expect((await f.row()).lastRemovalRevision, isNull);
      f.g.change(f.alice, [Gv2Remove(f.bob.ciphertext)]); // 3
      f.g.change(f.alice, const [Gv2SetTitle()], newTitle: 'Winter'); // 4
      expect(() => f.advanceFrom(2, removal: 2), throwsArgumentError);
      expect(() => f.advanceFrom(2, removal: 5), throwsArgumentError);
      await f.advanceFrom(2, removal: 3);
      expect((await f.row()).lastRemovalRevision, 3);
      // A later advance without a removal keeps it.
      f.g.change(f.alice, const [Gv2SetTitle()], newTitle: 'Spring'); // 5
      await f.advanceFrom(4);
      expect((await f.row()).lastRemovalRevision, 3);
    });

    test('the end of the group needs the ended standing', () async {
      f.g.change(f.alice, const [Gv2DeleteGroup()]); // 1
      await expectLater(f.advanceFrom(0), throwsStateError);
      await f.advanceFrom(0, membership: Gv2Membership.ended);
      final row = await f.row();
      expect(row.deleted, isTrue);
      expect(row.membership, Gv2Membership.ended);
    });
  });

  group('a group known from an invite', () {
    late Gv2TestGroup g;
    late Gv2TestPerson bob;

    /// Alice's group at revision 1 (bob and carol invited, carol declined);
    /// this device is bob's and has just received the invite.
    Future<bool> invited({Uint8List? chain}) {
      return f.store.insertAnchored(
        groupId: g.groupId,
        masterKey: g.masterKey,
        myCiphertext: bob.ciphertext,
        protocolVersion: gv2ProtocolVersion,
        revision: 1,
        chain: chain ?? g.states[1].chain,
        stateHash: gv2StateHash(g.states[1]),
        membership: Gv2Membership.invited,
        inviteSeed: g.inviteKeyOf(bob).seed,
        invitedBySnowId: g.person('alice').snowId,
      );
    }

    setUp(() {
      g = f.g;
      bob = f.bob;
      g.create(f.alice, invite: [f.bob, f.carol]);
      g.decline(f.carol);
    });

    test('holds only the anchor until the state is installed', () async {
      expect(await invited(), isTrue);
      final row = await f.row();
      expect(row.membership, Gv2Membership.invited);
      expect(row.stateLoaded, isFalse);
      expect(row.headSig, isNull);
      expect(row.inviteSeed, g.inviteKeyOf(bob).seed);
      expect(row.invitedBySnowId, g.person('alice').snowId);
      expect(await f.store.loadState(g.id), isNull);
      expect(await f.store.memberRows(g.id), isEmpty);
    });

    test('a second invite for the same group does not replace the anchor',
        () async {
      expect(await invited(), isTrue);
      expect(await invited(chain: gv2TestSha('another chain')), isFalse);
      expect((await f.row()).chain, g.states[1].chain);
    });

    test('only the state the anchor commits to can be installed', () async {
      await invited();
      // The state of another revision.
      await expectLater(f.store.installState(state: g.states[0]),
          throwsA(isA<Gv2StoreConflict>()));
      // The right revision with one role changed.
      final altered = g.states[1].copy();
      altered.members[f.alice.key]!.role = gv2RoleAdmin;
      await expectLater(f.store.installState(state: altered),
          throwsA(isA<Gv2StoreConflict>()));
      // The right state under another chain.
      final rechained = g.states[1].copy()..chain = gv2TestSha('another chain');
      await expectLater(f.store.installState(state: rechained),
          throwsA(isA<Gv2StoreConflict>()));
      expect(await f.store.memberRows(g.id), isEmpty);
      expect((await f.row()).stateLoaded, isFalse);

      await f.store.installState(state: g.states[1], headSig: g.headSig(1));
      final row = await f.row();
      expect(row.stateLoaded, isTrue);
      expect(row.headSig, g.headSig(1));
      expect(row.title, 'Snow');
      expect(gv2StateHash((await f.store.loadState(g.id))!),
          gv2StateHash(g.states[1]));
      // And only once.
      await expectLater(f.store.installState(state: g.states[1]),
          throwsA(isA<Gv2StoreConflict>()));
    });

    test('accepting moves the standing and erases the invite key', () async {
      await invited();
      await f.store.installState(state: g.states[1], headSig: g.headSig(1));
      g.accept(bob); // 2
      // Still "invited" would contradict the state.
      await expectLater(
        f.store.advance(from: g.states[1], to: g.state, headSig: g.headSig(2)),
        throwsStateError,
      );
      await f.store.advance(
        from: g.states[1],
        to: g.state,
        headSig: g.headSig(2),
        membership: Gv2Membership.awaitingConfirm,
      );
      var row = await f.row();
      expect(row.membership, Gv2Membership.awaitingConfirm);
      expect(row.inviteSeed, isNull);
      expect(await f.store.myRole(g.id), gv2RoleMember);

      await f.store.setMembership(g.id, Gv2Membership.active);
      row = await f.row();
      expect(row.membership, Gv2Membership.active);
      // A standing the state contradicts is refused.
      await expectLater(
          f.store.setMembership(g.id, Gv2Membership.left), throwsStateError);
      expect((await f.row()).membership, Gv2Membership.active);
    });

    test('the anchor must be invited or restored, with the right key material',
        () {
      Future<bool> insert(Gv2Membership membership, {Uint8List? seed}) =>
          f.store.insertAnchored(
            groupId: g.groupId,
            masterKey: g.masterKey,
            myCiphertext: bob.ciphertext,
            protocolVersion: gv2ProtocolVersion,
            revision: 1,
            chain: g.states[1].chain,
            stateHash: gv2StateHash(g.states[1]),
            membership: membership,
            inviteSeed: seed,
          );
      expect(() => insert(Gv2Membership.invited), throwsArgumentError);
      expect(() => insert(Gv2Membership.active, seed: Uint8List(32)),
          throwsArgumentError);
      expect(() => insert(Gv2Membership.awaitingConfirm, seed: Uint8List(32)),
          throwsArgumentError);
    });

    test('a restored group waits for confirmation', () async {
      g.accept(bob); // 2: bob is a member in the backup's anchor
      expect(
        await f.store.insertAnchored(
          groupId: g.groupId,
          masterKey: g.masterKey,
          myCiphertext: bob.ciphertext,
          protocolVersion: gv2ProtocolVersion,
          revision: 2,
          chain: g.states[2].chain,
          stateHash: gv2StateHash(g.states[2]),
          membership: Gv2Membership.awaitingConfirm,
        ),
        isTrue,
      );
      // Before the state is there, the standing cannot be changed.
      await expectLater(
          f.store.setMembership(g.id, Gv2Membership.active), throwsStateError);
      await f.store.installState(state: g.states[2], headSig: g.headSig(2));
      await f.store.setMembership(g.id, Gv2Membership.active);
      expect((await f.row()).membership, Gv2Membership.active);
    });

    test('a state in which this account is not invited cannot be installed',
        () async {
      // The anchor claims revision 0 of a group where bob is not invited.
      final other = Gv2TestGroup('other');
      other.create(other.person('dave'));
      await f.store.insertAnchored(
        groupId: other.groupId,
        masterKey: other.masterKey,
        myCiphertext: other.person('bob').ciphertext,
        protocolVersion: gv2ProtocolVersion,
        revision: 0,
        chain: other.states[0].chain,
        stateHash: gv2StateHash(other.states[0]),
        membership: Gv2Membership.invited,
        inviteSeed: Uint8List(32),
      );
      await expectLater(
          f.store.installState(state: other.states[0]), throwsStateError);
      expect((await f.store.group(other.id))!.stateLoaded, isFalse);
      expect(await f.store.memberRows(other.id), isEmpty);
    });
  });

  group('what only grows', () {
    setUp(() => f.createdByAlice());

    Gv2SenderKeyBody key(int chainId) => Gv2SenderKeyBody(
      chainId: chainId,
      iteration: 0,
      chainKey: gv2TestSha('chain $chainId'),
      signingKey: Uint8List(32),
    );

    test('log points older than an envelope can be are pruned — never the '
        'current one; so are the records of keys given long ago', () async {
      f.g.accept(f.bob); // 1
      await f.advanceFrom(0);
      final keys = f.db.gv2SenderKeyStore;
      await keys.recordDelivery(f.g.id, f.bob.snowId, key(1), nowMs: 1000);
      await keys.recordDelivery(f.g.id, f.bob.snowId, key(2), nowMs: 9000);

      final later = DateTime.now().millisecondsSinceEpoch + 60000;
      await f.store.pruneOld(headsBeforeMs: later, deliveriesBeforeMs: 5000);
      expect(await f.store.head(f.g.id, 0), isNull);
      expect(await f.store.head(f.g.id, 1), isNotNull, reason: 'the anchor');
      expect(await keys.delivered(f.g.id, f.bob.snowId, 1), isNull);
      expect(await keys.delivered(f.g.id, f.bob.snowId, 2), isNotNull);

      // Points stored just now stay.
      f.g.decline(f.carol); // 2
      await f.advanceFrom(1);
      await f.store.pruneOld(
        headsBeforeMs: DateTime.now().millisecondsSinceEpoch - 60000,
        deliveriesBeforeMs: 0,
      );
      expect(await f.store.head(f.g.id, 1), isNotNull);
      expect(await f.store.head(f.g.id, 2), isNotNull);
    });

    test('a group that is no longer this account\'s sheds its keys, the '
        'records of keys given, its endorsements and its older points; '
        'removing its chat erases it — one this account is in, never',
        () async {
      f.g.accept(f.bob); // 1
      await f.advanceFrom(0);
      final keys = f.db.gv2SenderKeyStore;
      await keys.createOwn(f.g.id, f.alice.snowId);
      await keys.recordDelivery(f.g.id, f.bob.snowId, key(1), nowMs: _now);
      await f.store.replaceEndorsements(
        groupId: f.g.id,
        revision: 1,
        expiration: 0,
        byCiphertext: {
          for (final m in await f.store.memberRows(f.g.id))
            m.ciphertext: Uint8List(8),
        },
      );
      expect(await f.store.forgetGone(f.g.id), isFalse, reason: 'a member');

      f.g.change(f.alice, [Gv2TransferOwner(f.bob.ciphertext)]); // 2
      f.g.change(f.alice, const [Gv2Leave()]); // 3
      await f.advanceFrom(1, membership: Gv2Membership.left);
      expect(await keys.ownCurrent(f.g.id, f.alice.snowId), isNull);
      expect(await keys.delivered(f.g.id, f.bob.snowId, 1), isNull);
      expect(await f.store.endorsements(f.g.id), isEmpty);
      expect(await f.store.head(f.g.id, 1), isNull);
      expect(await f.store.head(f.g.id, 3), isNotNull);
      // Its state stays readable (the chat shows it as left).
      expect(gv2StateHash((await f.store.loadState(f.g.id))!),
          gv2StateHash(f.g.state));

      expect(await f.store.forgetGone(f.g.id), isTrue);
      expect(await f.store.group(f.g.id), isNull);
    });
  });

  group('reinvite', () {
    setUp(() async {
      await f.createdByAlice();
      f.g.accept(f.bob); // 1
      f.g.change(f.alice, [Gv2TransferOwner(f.bob.ciphertext)]); // 2
      f.g.change(f.alice, const [Gv2Leave()]); // 3
    });

    /// A later invite of alice by bob, as her device hears of it over 1:1.
    Future<bool> reinvited({int? revision, Uint8List? seed}) {
      final at = revision ?? f.g.state.revision;
      return f.store.reinvite(
        groupId: f.g.id,
        protocolVersion: gv2ProtocolVersion,
        revision: at,
        chain: f.g.states[at].chain,
        stateHash: gv2StateHash(f.g.states[at]),
        inviteSeed: seed ?? gv2TestSha('second invite'),
        invitedBySnowId: f.bob.snowId,
      );
    }

    test('takes the later anchor of the new invite and waits for its state',
        () async {
      await f.store.setMyKeyRevision(f.g.id, 0);
      await f.advanceFrom(0, membership: Gv2Membership.left, removal: 3);
      expect((await f.row()).lastRemovalRevision, 3);
      f.g.invite(f.bob, f.alice); // 4

      expect(await reinvited(), isTrue);
      final row = await f.row();
      expect(row.membership, Gv2Membership.invited);
      expect(row.inviteSeed, gv2TestSha('second invite'));
      expect(row.invitedBySnowId, f.bob.snowId);
      expect(row.revision, 4);
      expect(row.chain, f.g.states[4].chain);
      expect(row.stateHash, gv2StateHash(f.g.states[4]));
      expect(row.headSig, isNull);
      expect(row.stateLoaded, isFalse);
      expect(row.myKeyRevision, isNull);
      expect(row.lastRemovalRevision, isNull);
      expect(await f.store.memberRows(f.g.id), isEmpty);

      await f.store.installState(state: f.g.states[4], headSig: f.g.headSig(4));
      expect((await f.store.pendingInvites(f.g.id)).map((p) => p.ciphertext),
          contains(f.alice.key));
      // Already invited: a further invite changes nothing.
      expect(await reinvited(seed: Uint8List(32)), isFalse);
      expect((await f.row()).inviteSeed, gv2TestSha('second invite'));
    });

    test('never goes back to an earlier point of the group', () async {
      await f.advanceFrom(0, membership: Gv2Membership.left);
      // The stored anchor is revision 3; an "invite" at 3 or below is refused.
      expect(await reinvited(revision: 3), isFalse);
      expect(await reinvited(revision: 1), isFalse);
      final row = await f.row();
      expect(row.membership, Gv2Membership.left);
      expect(row.revision, 3);
      expect(row.stateLoaded, isTrue);
    });

    test('is refused while still a member, and for an unknown or frozen group',
        () async {
      f.g.invite(f.bob, f.alice); // 4
      // Alice's device has not followed the log yet: it still holds revision 0
      // as an active member.
      expect(await reinvited(), isFalse);
      expect((await f.row()).revision, 0);
      expect(
          await f.store.reinvite(
            groupId: 'ab' * 32,
            protocolVersion: gv2ProtocolVersion,
            revision: 9,
            chain: Uint8List(32),
            stateHash: Uint8List(32),
            inviteSeed: Uint8List(32),
          ),
          isFalse);
      await f.store.advance(
          from: f.g.states[0],
          to: f.g.states[3],
          headSig: f.g.headSig(3),
          membership: Gv2Membership.left);
      await f.store.setHold(f.g.id, Gv2Hold.frozen);
      expect(await reinvited(), isFalse);
    });
  });

  group('verified log points', () {
    test('every point the anchor passes is kept, signed where it was signed',
        () async {
      await f.createdByAlice();
      final h0 = (await f.store.head(f.g.id, 0))!;
      expect(h0.chain, f.g.states[0].chain);
      expect(h0.headSig, f.g.headSig(0));

      f.g.accept(f.bob); // 1
      f.g.accept(f.carol); // 2
      f.g.change(f.alice, const [Gv2SetTitle()], newTitle: 'x'); // 3
      await f.store.advance(
        from: f.g.states[0],
        to: f.g.states[3],
        headSig: f.g.headSig(3),
        points: [
          for (var r = 1; r <= 3; r++) Gv2LogPoint(r, f.g.states[r].chain),
        ],
      );
      for (var r = 1; r <= 3; r++) {
        final h = (await f.store.head(f.g.id, r))!;
        expect(h.chain, f.g.states[r].chain, reason: '$r');
        expect(h.headSig, r == 3 ? f.g.headSig(3) : isNull, reason: '$r');
      }
      expect(await f.store.head(f.g.id, 4), isNull);
    });

    test('a point outside the advance, or a last point that is not the new '
        'head, is refused with nothing written', () async {
      await f.createdByAlice();
      f.g.accept(f.bob); // 1
      f.g.accept(f.carol); // 2
      Future<void> advanceWith(List<Gv2LogPoint> points) => f.store.advance(
            from: f.g.states[0],
            to: f.g.states[2],
            headSig: f.g.headSig(2),
            points: points,
          );
      expect(() => advanceWith([Gv2LogPoint(0, f.g.states[0].chain)]),
          throwsArgumentError);
      expect(() => advanceWith([Gv2LogPoint(3, f.g.states[2].chain)]),
          throwsArgumentError);
      expect(() => advanceWith([Gv2LogPoint(2, f.g.states[1].chain)]),
          throwsArgumentError);
      expect(() => advanceWith([Gv2LogPoint(1, Uint8List(31))]),
          throwsArgumentError);
      expect((await f.row()).revision, 0);
      expect(await f.store.head(f.g.id, 1), isNull);
    });

    test('an installed anchor is a point; a re-invite forgets the earlier ones',
        () async {
      await f.createdByAlice();
      f.g.accept(f.bob); // 1
      f.g.change(f.alice, [Gv2TransferOwner(f.bob.ciphertext)]); // 2
      f.g.change(f.alice, const [Gv2Leave()]); // 3
      await f.advanceFrom(0, membership: Gv2Membership.left);
      // Leaving kept only the current point (the older ones were shed).
      expect(await f.store.head(f.g.id, 0), isNull);
      expect(await f.store.head(f.g.id, 3), isNotNull);
      f.g.invite(f.bob, f.alice); // 4
      expect(
        await f.store.reinvite(
          groupId: f.g.id,
          protocolVersion: gv2ProtocolVersion,
          revision: 4,
          chain: f.g.states[4].chain,
          stateHash: gv2StateHash(f.g.states[4]),
          inviteSeed: gv2TestSha('again'),
        ),
        isTrue,
      );
      for (var r = 0; r <= 4; r++) {
        expect(await f.store.head(f.g.id, r), isNull, reason: '$r');
      }
      await f.store.installState(state: f.g.states[4], headSig: f.g.headSig(4));
      expect((await f.store.head(f.g.id, 4))!.headSig, f.g.headSig(4));
    });

    test('a point is never changed once held', () async {
      await f.createdByAlice();
      // Damage the stored anchor's chain the way a forked log would arrive:
      // a different chain at a revision already held.
      await f.db.customStatement(
          "UPDATE gv2_heads SET chain = x'${'00' * 32}' WHERE revision = 0");
      await f.store.dropState(f.g.id);
      await expectLater(
        f.store.installState(state: f.g.states[0], headSig: f.g.headSig(0)),
        throwsA(isA<Gv2StoreConflict>()),
      );
      expect((await f.row()).stateLoaded, isFalse, reason: 'rolled back');
    });

    test('deleting the group deletes its points, keys, deliveries and outbox',
        () async {
      await f.createdByAlice();
      await f.db.gv2SenderKeyStore.createOwn(f.g.id, f.alice.snowId);
      await f.db.customStatement(
          "INSERT INTO gv2_key_deliveries (group_id, member, chain_id, key, "
          "delivered_at_ms) VALUES ('${f.g.id}', '${f.bob.snowId}', 1, x'00', 0)");
      await f.db.customStatement(
          "INSERT INTO gv2_outbox (group_id, kind, recipient, payload, "
          "created_at_ms) VALUES ('${f.g.id}', 'pairwise', '${f.bob.snowId}', "
          "x'00', 0)");
      await f.store.deleteGroup(f.g.id);
      for (final table in [
        'gv2_heads',
        'gv2_sender_keys',
        'gv2_key_deliveries',
        'gv2_outbox',
      ]) {
        final n = await f.db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        expect(n.read<int>('n'), 0, reason: table);
      }
    });
  });

  group('member checks', () {
    setUp(() async {
      await f.createdByAlice();
      f.g.accept(f.bob); // 1
      f.g.accept(f.carol); // 2
      await f.advanceFrom(0);
    });

    test('are recorded per member and select who may receive', () async {
      expect((await f.store.membersToCheck(f.g.id)).length, 3);
      expect((await f.store.membersToCheck(f.g.id, limit: 2)).length, 2);
      expect(await f.store.confirmedMembers(f.g.id), isEmpty);

      final applied = await f.store.saveMemberChecks(f.g.id, [
        f.confirmed(f.alice, 0),
        f.confirmed(f.bob, 1),
        Gv2MemberCheckResult(
          ciphertext: f.carol.key,
          joinedRevision: 2,
          state: Gv2MemberCheckState.certificate,
          snowId: f.carol.snowId,
          // Not stored for a member that is not confirmed.
          accountPublicKey: f.carol.accountPub,
          certIssuedAtMs: _now,
        ),
      ]);
      expect(applied, 3);
      expect(await f.store.membersToCheck(f.g.id), isEmpty);
      expect(
          (await f.store.confirmedMembers(f.g.id)).map((m) => m.snowId).toSet(),
          {f.alice.snowId, f.bob.snowId});

      final carol = (await f.store.memberBySnowId(f.g.id, f.carol.snowId))!;
      expect(carol.checkState, Gv2MemberCheckState.certificate);
      expect(carol.accountPublicKey, isNull);
      expect(carol.certIssuedAtMs, isNull);
      final bob = (await f.store.memberBySnowId(f.g.id, f.bob.snowId))!;
      expect(bob.accountPublicKey, f.bob.accountPub);
      expect(bob.certIssuedAtMs, _now);
      expect(await f.store.memberBySnowId(f.g.id, 'snow${'0' * 32}'), isNull);
    });

    test('a result for an earlier membership is dropped', () async {
      f.g.change(f.alice, [Gv2Remove(f.bob.ciphertext)]); // 3
      f.g.invite(f.alice, f.bob); // 4
      f.g.accept(f.bob); // 5
      await f.advanceFrom(2);
      // The check ran against the membership of revision 1.
      expect(await f.store.saveMemberChecks(f.g.id, [f.confirmed(f.bob, 1)]), 0);
      expect((await f.member(f.bob)).checkState, Gv2MemberCheckState.unchecked);
      expect(await f.store.saveMemberChecks(f.g.id, [f.confirmed(f.bob, 5)]), 1);
    });

    test('a confirmed result without its account is refused, all or nothing',
        () async {
      await expectLater(
        f.store.saveMemberChecks(f.g.id, [
          f.confirmed(f.alice, 0),
          Gv2MemberCheckResult(
            ciphertext: f.bob.key,
            joinedRevision: 1,
            state: Gv2MemberCheckState.confirmed,
            snowId: f.bob.snowId,
          ),
        ]),
        throwsArgumentError,
      );
      expect(await f.store.confirmedMembers(f.g.id), isEmpty);
    });

    test('accounts of pending invites are recorded', () async {
      f.g.invite(f.alice, f.g.person('dave')); // 3
      await f.advanceFrom(2);
      final dave = f.g.person('dave');
      await f.store.savePendingAccounts(f.g.id, {dave.key: dave.snowId});
      expect((await f.store.pendingInvites(f.g.id)).single.snowId, dave.snowId);
    });
  });

  group('damaged rows', () {
    setUp(() async {
      await f.createdByAlice();
      f.g.accept(f.bob);
      await f.advanceFrom(0);
    });

    test('are reported as local corruption, not as a state', () async {
      await f.db.customStatement(
        'UPDATE gv2_members SET role = ? WHERE ciphertext = ?',
        [gv2RoleOwner, f.bob.key],
      );
      await expectLater(
          f.store.loadState(f.g.id), throwsA(isA<Gv2StoreCorruption>()));
    });

    test('a missing row is corruption too', () async {
      await f.db.customStatement('DELETE FROM gv2_pending');
      await expectLater(
          f.store.loadState(f.g.id), throwsA(isA<Gv2StoreCorruption>()));
    });

    test('can be repaired from the anchor', () async {
      await f.db.customStatement('DELETE FROM gv2_members WHERE ciphertext = ?',
          [f.bob.key]);
      await expectLater(
          f.store.loadState(f.g.id), throwsA(isA<Gv2StoreCorruption>()));

      await f.store.dropState(f.g.id);
      var row = await f.row();
      expect(row.stateLoaded, isFalse);
      expect(row.revision, 1);
      expect(row.chain, f.g.states[1].chain);
      expect(row.stateHash, gv2StateHash(f.g.states[1]));
      expect(row.headSig, f.g.headSig(1));
      expect(row.masterKey, f.g.masterKey);
      expect(await f.store.loadState(f.g.id), isNull);
      // Nothing can be advanced while the state is missing.
      f.g.decline(f.carol);
      await expectLater(f.advanceFrom(1), throwsA(isA<Gv2StoreConflict>()));

      // Only the state of the anchor is taken back.
      await expectLater(f.store.installState(state: f.g.states[2]),
          throwsA(isA<Gv2StoreConflict>()));
      await f.store.installState(state: f.g.states[1]);
      row = await f.row();
      expect(row.stateLoaded, isTrue);
      expect(row.headSig, f.g.headSig(1), reason: 'the stored signature stays');
      expect(row.title, 'Snow');
      await f.advanceFrom(1);
      expect((await f.row()).revision, 2);
    });
  });

  group('server keys, credentials, endorsements', () {
    const day = 86400;
    final params = gv2TestBytes('server params', 673);
    final headKey = gv2TestSha('head key');
    const me = 'snow00000000000000000000000000000001';

    Map<String, Uint8List> endorsementsFor(Iterable<Gv2TestPerson> people) =>
        {for (final p in people) p.key: gv2TestBytes('endorsement ${p.name}', 33)};

    test('the first keys are stored; the same keys again change nothing',
        () async {
      expect(await f.store.serverKeys(), isNull);
      expect(
          await f.store
              .saveServerKeys(serverPublicParams: params, headPublicKey: headKey),
          isFalse);
      await f.store.saveAuthCredentials(me, {day: Uint8List(8)}, pruneBefore: 0);
      expect(
          await f.store
              .saveServerKeys(serverPublicParams: params, headPublicKey: headKey),
          isFalse);
      expect(await f.store.authCredential(me, day), isNotNull);
      final keys = (await f.store.serverKeys())!;
      expect(keys.serverPublicParams, params);
      expect(keys.headPublicKey, headKey);
    });

    test('different keys replace the old ones and erase what was issued under them',
        () async {
      await f.createdByAlice();
      await f.store
          .saveServerKeys(serverPublicParams: params, headPublicKey: headKey);
      await f.store.saveAuthCredentials(me, {day: Uint8List(8)}, pruneBefore: 0);
      await f.store.replaceEndorsements(
        groupId: f.g.id,
        revision: 0,
        expiration: 3 * day,
        byCiphertext: endorsementsFor([f.alice]),
      );

      expect(
          await f.store.saveServerKeys(
              serverPublicParams: gv2TestBytes('new params', 673),
              headPublicKey: headKey),
          isTrue);
      expect(await f.store.authCredential(me, day), isNull);
      expect(await f.store.endorsements(f.g.id), isEmpty);
      // The group itself is untouched.
      expect(await f.store.loadState(f.g.id), isNotNull);

      // A new head key alone counts as a change too.
      expect(
          await f.store.saveServerKeys(
              serverPublicParams: gv2TestBytes('new params', 673),
              headPublicKey: gv2TestSha('new head key')),
          isTrue);
      expect(
          () => f.store.saveServerKeys(
              serverPublicParams: params, headPublicKey: Uint8List(31)),
          throwsArgumentError);
    });

    test('credentials are kept per day, pruned, and never shared between accounts',
        () async {
      const other = 'snow00000000000000000000000000000002';
      await f.store.saveAuthCredentials(
          other, {5 * day: Uint8List.fromList([9])}, pruneBefore: 0);
      await f.store.saveAuthCredentials(
        me,
        {for (var d = 1; d <= 7; d++) d * day: Uint8List.fromList([d])},
        pruneBefore: 3 * day,
      );
      expect(await f.store.authCredential(me, 2 * day), isNull, reason: 'pruned');
      expect((await f.store.authCredential(me, 3 * day))!.credential, [3]);
      expect(await f.store.lastAuthCredentialTime(me), 7 * day);
      // The other account's row is gone and was never readable as mine.
      expect(await f.store.authCredential(other, 5 * day), isNull);
      expect(await f.store.lastAuthCredentialTime(other), isNull);
      expect((await f.store.authCredential(me, 5 * day))!.credential, [5]);

      // A later store keeps the days still ahead and drops the past ones.
      await f.store.saveAuthCredentials(
          me, {8 * day: Uint8List.fromList([8])}, pruneBefore: 6 * day);
      expect(await f.store.authCredential(me, 5 * day), isNull);
      expect(await f.store.authCredential(me, 7 * day), isNotNull);
      expect(await f.store.lastAuthCredentialTime(me), 8 * day);
    });

    test('endorsements must cover exactly the members of the stored revision',
        () async {
      await f.createdByAlice();
      f.g.accept(f.bob); // 1
      await f.advanceFrom(0);

      Future<void> replace(int revision, Iterable<Gv2TestPerson> people) =>
          f.store.replaceEndorsements(
            groupId: f.g.id,
            revision: revision,
            expiration: 3 * day,
            byCiphertext: endorsementsFor(people),
          );

      await expectLater(replace(0, [f.alice, f.bob]),
          throwsA(isA<Gv2StoreConflict>()),
          reason: 'verified against an older revision');
      await expectLater(
          replace(1, [f.alice]), throwsA(isA<Gv2StoreConflict>()),
          reason: 'a member is missing');
      await expectLater(replace(1, [f.alice, f.bob, f.carol]),
          throwsA(isA<Gv2StoreConflict>()),
          reason: 'carol is only invited');
      await expectLater(replace(1, [f.alice, f.carol]),
          throwsA(isA<Gv2StoreConflict>()));
      expect(await f.store.endorsements(f.g.id), isEmpty);

      await replace(1, [f.alice, f.bob]);
      final rows = await f.store.endorsements(f.g.id);
      expect(rows.map((e) => e.ciphertext).toSet(), {f.alice.key, f.bob.key});
      expect(rows.every((e) => e.expiration == 3 * day), isTrue);
    });

    test('an endorsement goes with its member, and with the group', () async {
      await f.createdByAlice();
      f.g.accept(f.bob); // 1
      f.g.accept(f.carol); // 2
      await f.advanceFrom(0);
      await f.store.replaceEndorsements(
        groupId: f.g.id,
        revision: 2,
        expiration: 3 * day,
        byCiphertext: endorsementsFor([f.alice, f.bob, f.carol]),
      );

      f.g.change(f.alice, [Gv2Remove(f.bob.ciphertext)]); // 3
      await f.advanceFrom(2);
      expect((await f.store.endorsements(f.g.id)).map((e) => e.ciphertext).toSet(),
          {f.alice.key, f.carol.key});

      await f.store.dropState(f.g.id);
      expect(await f.store.endorsements(f.g.id), isEmpty);

      await f.store.installState(state: f.g.states[3]);
      await f.store.replaceEndorsements(
        groupId: f.g.id,
        revision: 3,
        expiration: 3 * day,
        byCiphertext: endorsementsFor([f.alice, f.carol]),
      );
      await f.store.deleteGroup(f.g.id);
      expect(await f.store.endorsements(f.g.id), isEmpty);
    });
  });

  group('single-field changes', () {
    setUp(() => f.createdByAlice());

    test('a frozen group stays frozen and keeps its evidence', () async {
      final evidence = gv2TestBytes('two heads', 200);
      await f.store.setHold(f.g.id, Gv2Hold.updateRequired);
      expect((await f.row()).hold, Gv2Hold.updateRequired);
      await f.store.setHold(f.g.id, Gv2Hold.none);
      expect((await f.row()).hold, Gv2Hold.none);

      await f.store.setHold(f.g.id, Gv2Hold.frozen, evidence: evidence);
      await expectLater(
          f.store.setHold(f.g.id, Gv2Hold.none), throwsStateError);
      await expectLater(
          f.store.setHold(f.g.id, Gv2Hold.updateRequired), throwsStateError);
      await f.store.setHold(f.g.id, Gv2Hold.frozen);
      final row = await f.row();
      expect(row.hold, Gv2Hold.frozen);
      expect(row.holdEvidence, evidence);
    });

    test('a withheld hold keeps its evidence, is not turned into '
        'updateRequired, and ends released or frozen', () async {
      final shown = gv2TestBytes('the head the server does not serve', 120);
      await f.store.setHold(f.g.id, Gv2Hold.withheld, evidence: shown);
      var row = await f.row();
      expect(row.hold, Gv2Hold.withheld);
      expect(row.holdEvidence, shown);

      // A sync that meets an unknown version does not replace it.
      await f.store.setHold(f.g.id, Gv2Hold.updateRequired);
      row = await f.row();
      expect(row.hold, Gv2Hold.withheld);
      expect(row.holdEvidence, shown);

      await f.store.setHold(f.g.id, Gv2Hold.none);
      row = await f.row();
      expect(row.hold, Gv2Hold.none);
      expect(row.holdEvidence, isNull);

      final twoHeads = gv2TestBytes('two heads', 200);
      await f.store.setHold(f.g.id, Gv2Hold.withheld, evidence: shown);
      await f.store.setHold(f.g.id, Gv2Hold.frozen, evidence: twoHeads);
      row = await f.row();
      expect(row.hold, Gv2Hold.frozen);
      expect(row.holdEvidence, twoHeads);
      await expectLater(
          f.store.setHold(f.g.id, Gv2Hold.withheld, evidence: shown),
          throwsStateError);
    });

    test('key revision and sync time are recorded', () async {
      expect((await f.row()).myKeyRevision, isNull);
      await f.store.setMyKeyRevision(f.g.id, 0);
      await f.store.markSynced(f.g.id, _now + 60000);
      final row = await f.row();
      expect(row.myKeyRevision, 0);
      expect(row.lastSyncAtMs, _now + 60000);
      await f.store.setMyKeyRevision(f.g.id, null);
      expect((await f.row()).myKeyRevision, isNull);
    });

    test('changes to an unknown group are refused', () async {
      final unknown = 'cd' * 32;
      await expectLater(f.store.setMyKeyRevision(unknown, 1),
          throwsA(isA<Gv2StoreConflict>()));
      await expectLater(f.store.setHold(unknown, Gv2Hold.frozen),
          throwsA(isA<Gv2StoreConflict>()));
      await expectLater(f.store.setMembership(unknown, Gv2Membership.left),
          throwsA(isA<Gv2StoreConflict>()));
      await expectLater(
          f.store.dropState(unknown), throwsA(isA<Gv2StoreConflict>()));
      expect(await f.store.loadState(unknown), isNull);
      expect(await f.store.myRole(unknown), isNull);
    });

    test('deleting a group removes every row of it and no other', () async {
      final other = Gv2TestGroup('other');
      final dave = other.person('dave');
      other.create(dave, invite: [other.person('erin')]);
      await f.store.insertCreated(
        masterKey: other.masterKey,
        myCiphertext: dave.ciphertext,
        state: other.states[0],
        headSig: other.headSig(0),
        nowMs: _now,
      );
      expect((await f.store.groups()).length, 2);

      await f.store.deleteGroup(f.g.id);
      expect(await f.store.group(f.g.id), isNull);
      expect(await f.store.memberRows(f.g.id), isEmpty);
      expect(await f.store.pendingInvites(f.g.id), isEmpty);
      expect((await f.store.groups()).single.groupId, other.id);
      expect((await f.store.memberRows(other.id)).length, 1);
      expect((await f.store.pendingInvites(other.id)).length, 1);
      final left = await f.db
          .customSelect('SELECT COUNT(*) AS n FROM gv2_members WHERE group_id = ?',
              variables: [Variable.withString(f.g.id)])
          .getSingle();
      expect(left.read<int>('n'), 0);
    });

    test('the list of groups is a live stream', () async {
      final seen = <int>[];
      final sub = f.store.watchGroups().listen((rows) => seen.add(rows.length));
      await pumpEventQueue();
      await f.store.deleteGroup(f.g.id);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, 1);
      expect(seen.last, 0);
    });
  });
}
