/// @file        gv2_store.dart
/// @description Group protocol v2 — the only writer of the gv2_* tables. It
///              keeps, per group, the master key, the last verified point of
///              the change log (the anchor) and the state at that point, and
///              moves all of them together in one transaction: a crash never
///              leaves a revision that does not match the member rows, and a
///              caller working from an older view of the group cannot
///              overwrite a newer one (design document §5.5, §11.2).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (forgetGone(); P5.6: pruneOld() — log points and key records that only grew; a group no longer this account's sheds its keys, key records, endorsements and old points; setMyKeyRevision records when the own key was made; saveBackupState: writeDueAtMs — the delayed backup write). Earlier 2026-11-20 (liftFreeze(); markChangeSent() / clearChangeSent(); markSynced() settles a change sent before the sync started)
///
/// @functions
///  - Gv2Store.group() / groups() / watchGroups() / watchGroup(): group rows
///  - Gv2Store.insertCreated(): a group this device just created
///  - Gv2Store.insertAnchored(): a group known from an invite or the backup
///  - Gv2Store.reinvite(): a new invite to a group this account was once in
///  - Gv2Store.installState(): store the state the anchor commits to
///  - Gv2Store.advance(): move the anchor forward with the state
///  - Gv2Store.loadState(): rebuild the state and check it against the anchor
///  - Gv2Store.head(): the chain this device verified at a revision
///  - Gv2Store.insertCreating() / finishCreate(): a group this device is
///    creating, before and after the server accepted it
///  - Gv2Store.dropState(): forget the rows after a failed check (repair)
///  - Gv2Store.memberRows() / pendingInvites() / membersToCheck() /
///    confirmedMembers() / member() / memberBySnowId() / myRole() /
///    watchMemberRows() / watchPendingInvites(): member and invite rows
///  - Gv2Store.saveMemberChecks(): record who stands behind which member
///  - Gv2Store.savePendingAccounts(): record whom the pending invites are for
///  - Gv2Store.forgetGone(): erase a group that is no longer this account's
///  - Gv2Store.pruneOld(): the points of logs and the key records that
///    only grew
///  - Gv2Store.setMembership() / setHold() / setMyKeyRevision() /
///    setReach() / markSynced() / deleteGroup(): single-field changes
///  - Gv2Store.markChangeSent() / clearChangeSent(): a change of this device
///    whose answer has not come (markSynced() settles it as well)
///  - Gv2Store.liftFreeze(): end an invalid_entry freeze that a later
///    build's rules accept (on exactly that evidence)
///  - Gv2Store.saveNicknames(): the display names looked up for members
///  - Gv2Store.backupState() / saveBackupState() / setResetPending(): the
///    backup of the group keys (gv2_backup.dart)
///  - Gv2Store.serverKeys() / saveServerKeys(): the server's public keys
///  - Gv2Store.authCredential() / lastAuthCredentialTime() /
///    saveAuthCredentials(): this account's daily credentials
///  - Gv2Store.endorsements() / replaceEndorsements(): send endorsements
///  - Gv2StoreConflict / Gv2StoreCorruption: why a write or a read was refused
///
/// Notes:
///  - This class does not verify signatures or rules. Callers pass states that
///    gv2_state_machine.dart produced from verified entries. What the store
///    does enforce is consistency with what it already holds:
///      * the anchor only moves forward, and only from the exact
///        (revision, chain) the caller started from;
///      * an anchor is never replaced by an invite while this account is in
///        the group or invited to it; a returning account takes a new
///        invite's anchor only when it is later than the stored one;
///      * a state is stored only when it hashes to the anchor's state hash;
///      * the membership recorded for this account agrees with the state.
///  - Every point the anchor passes is recorded (gv2_heads) with the chain at
///    that revision, so that what a member says about an earlier revision
///    can be compared with what this device verified there.
///  - advance() writes only what changed between the two states it is given,
///    so the per-member results of this device (checks, reach, nickname)
///    survive. A member who left and joined again is a new row.
///  - loadState() recomputes the state hash from the rows. A mismatch means
///    the LOCAL rows are damaged — it must not be mistaken for a server that
///    misbehaves — and is reported as Gv2StoreCorruption; dropState() then
///    lets the sync fetch the state at the anchor again and check it against
///    the stored hash.
///  - Credentials and endorsements are issued under the server's public
///    parameters: when those are replaced by different ones, both are erased
///    in the same transaction. An endorsement is erased with its member.
///  - Group ids, ciphertexts and keys are never put into exception messages
///    or logs.
library;

import 'dart:collection';

import 'package:drift/drift.dart';

import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_keys.dart';
import 'gv2_payloads.dart';

part 'gv2_store.g.dart';

/// The stored anchor is not the one the caller worked from, or the state does
/// not match it. Nothing was written; the caller reloads and decides again.
class Gv2StoreConflict implements Exception {
  final String reason;
  const Gv2StoreConflict(this.reason);

  @override
  String toString() => 'Gv2StoreConflict: $reason';
}

/// The stored rows of a group do not hash to its stored state hash.
class Gv2StoreCorruption implements Exception {
  const Gv2StoreCorruption();

  @override
  String toString() => 'Gv2StoreCorruption: stored group state does not match its hash';
}

/// A point of a log between two stored anchors: the chain after the entry of
/// [revision]. Passed to [Gv2Store.advance] for every entry applied.
class Gv2LogPoint {
  final int revision;
  final Uint8List chain;
  const Gv2LogPoint(this.revision, this.chain);
}

/// What this device worked out about one member (see gv2_member_check.dart).
class Gv2MemberCheckResult {
  /// Member ciphertext, lowercase hex.
  final String ciphertext;

  /// joinedRevision of the membership that was checked: the result is dropped
  /// when the member has left and joined again in the meantime.
  final int joinedRevision;

  final Gv2MemberCheckState state;

  /// The account the ciphertext decrypts to, when it decrypts.
  final String? snowId;

  /// Set only for [Gv2MemberCheckState.confirmed].
  final Uint8List? accountPublicKey;
  final int? certIssuedAtMs;

  const Gv2MemberCheckResult({
    required this.ciphertext,
    required this.joinedRevision,
    required this.state,
    this.snowId,
    this.accountPublicKey,
    this.certIssuedAtMs,
  });
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _exact(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw ArgumentError('gv2 store: $what must be $length bytes');
  }
  return bytes;
}

@DriftAccessor(tables: [
  Gv2Groups,
  Gv2Members,
  Gv2Pending,
  Gv2Heads,
  Gv2ServerKeys,
  Gv2AuthCredentials,
  Gv2Endorsements,
  Gv2SenderKeys,
  Gv2KeyDeliveries,
  Gv2OutboxRows,
  Gv2BackupStates,
])
class Gv2Store extends DatabaseAccessor<SnowDatabase> with _$Gv2StoreMixin {
  Gv2Store(super.db);

  // ---------------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------------

  /// The row of [groupId] (lowercase hex), or null.
  Future<Gv2GroupRow?> group(String groupId) =>
      (select(gv2Groups)..where((g) => g.groupId.equals(groupId)))
          .getSingleOrNull();

  Future<List<Gv2GroupRow>> groups() => select(gv2Groups).get();

  Stream<List<Gv2GroupRow>> watchGroups() => select(gv2Groups).watch();

  /// The row of [groupId] as it changes (null while there is none).
  Stream<Gv2GroupRow?> watchGroup(String groupId) =>
      (select(gv2Groups)..where((g) => g.groupId.equals(groupId)))
          .watchSingleOrNull();

  /// Store a group this device created: [state] is the state after its own
  /// CREATE entry, which the server accepted and signed with [headSig]. This
  /// account is the owner. Throws [Gv2StoreConflict] when the group is
  /// already stored.
  Future<void> insertCreated({
    required Uint8List masterKey,
    required Uint8List myCiphertext,
    required Gv2GroupState state,
    required Uint8List headSig,
    required int nowMs,
  }) {
    final groupId = gv2Hex(state.groupId);
    final mine = gv2Hex(_exact(myCiphertext, gv2CiphertextLen, 'myCiphertext'));
    _exact(masterKey, gv2MasterKeyLen, 'masterKey');
    _exact(headSig, gv2SignatureLen, 'headSig');
    if (state.revision != 0 || state.members[mine]?.role != gv2RoleOwner) {
      throw ArgumentError('gv2 store: not the state of a group just created');
    }
    _checkMembership(Gv2Membership.active, mine, state);
    return transaction(() async {
      if (await group(groupId) != null) {
        throw const Gv2StoreConflict('group already stored');
      }
      await into(gv2Groups).insert(Gv2GroupsCompanion.insert(
        groupId: groupId,
        masterKey: masterKey,
        myCiphertext: mine,
        protocolVersion: state.version,
        membership: Gv2Membership.active,
        revision: state.revision,
        chain: _exact(state.chain, gv2HashLen, 'chain'),
        stateHash: gv2StateHash(state),
        headSig: Value(headSig),
        stateLoaded: true,
        deleted: Value(state.deleted),
        titlePayload: state.titlePayload,
        title: Value(_titleOf(masterKey, state)),
        lastSyncAtMs: Value(nowMs),
      ));
      await _writeAllRows(groupId, state);
      await _recordHead(groupId, state.revision, state.chain, headSig);
    });
  }

  /// Store a group this device is creating: [state] is the state its own
  /// revision-0 entry gives. The server has not accepted the entry yet (the
  /// outbox submits it); the row waits in the creating standing, without a
  /// head signature, until [finishCreate]. Throws [Gv2StoreConflict] when
  /// the group is already stored.
  Future<void> insertCreating({
    required Uint8List masterKey,
    required Uint8List myCiphertext,
    required Gv2GroupState state,
  }) {
    final groupId = gv2Hex(state.groupId);
    final mine = gv2Hex(_exact(myCiphertext, gv2CiphertextLen, 'myCiphertext'));
    _exact(masterKey, gv2MasterKeyLen, 'masterKey');
    if (state.revision != 0 || state.members[mine]?.role != gv2RoleOwner) {
      throw ArgumentError('gv2 store: not the state of a group just created');
    }
    _checkMembership(Gv2Membership.creating, mine, state);
    return transaction(() async {
      if (await group(groupId) != null) {
        throw const Gv2StoreConflict('group already stored');
      }
      await into(gv2Groups).insert(Gv2GroupsCompanion.insert(
        groupId: groupId,
        masterKey: masterKey,
        myCiphertext: mine,
        protocolVersion: state.version,
        membership: Gv2Membership.creating,
        revision: state.revision,
        chain: _exact(state.chain, gv2HashLen, 'chain'),
        stateHash: gv2StateHash(state),
        stateLoaded: true,
        deleted: Value(state.deleted),
        titlePayload: state.titlePayload,
        title: Value(_titleOf(masterKey, state)),
      ));
      await _writeAllRows(groupId, state);
    });
  }

  /// The server accepted the revision-0 entry of a group this device was
  /// creating and signed its head with [headSig] (verified by the caller
  /// over the stored revision and chain): the group is active. Returns
  /// false and writes nothing when the group is not in the creating
  /// standing (any more).
  Future<bool> finishCreate({
    required String groupId,
    required Uint8List headSig,
    required int nowMs,
  }) {
    _exact(headSig, gv2SignatureLen, 'headSig');
    return transaction(() async {
      final row = await group(groupId);
      if (row == null || row.membership != Gv2Membership.creating) {
        return false;
      }
      await _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          membership: const Value(Gv2Membership.active),
          headSig: Value(headSig),
          lastSyncAtMs: Value(nowMs),
        ),
      );
      await _recordHead(groupId, row.revision, row.chain, headSig);
      return true;
    });
  }

  /// Store a group this device learned about from a 1:1 invite
  /// ([membership] = invited, with the one-time [inviteSeed]) or from the
  /// backup ([membership] = awaitingConfirm). Only the anchor is known; the
  /// state is fetched later and stored with [installState]. [resetPending]
  /// marks a group taken from the backup that still has to announce that
  /// its Sender Keys are gone.
  ///
  /// Returns false and writes nothing when the group is already stored: an
  /// anchor this device holds is never replaced by what a later message
  /// claims (see [reinvite] for a group this account has left).
  Future<bool> insertAnchored({
    required Uint8List groupId,
    required Uint8List masterKey,
    required Uint8List myCiphertext,
    required int protocolVersion,
    required int revision,
    required Uint8List chain,
    required Uint8List stateHash,
    required Gv2Membership membership,
    Uint8List? inviteSeed,
    String? invitedBySnowId,
    bool resetPending = false,
  }) {
    final id = gv2Hex(_exact(groupId, gv2GroupIdLen, 'groupId'));
    final mine = gv2Hex(_exact(myCiphertext, gv2CiphertextLen, 'myCiphertext'));
    _exact(masterKey, gv2MasterKeyLen, 'masterKey');
    _exact(chain, gv2HashLen, 'chain');
    _exact(stateHash, gv2HashLen, 'stateHash');
    if (revision < 0) throw ArgumentError('gv2 store: revision must be >= 0');
    switch (membership) {
      case Gv2Membership.invited:
        _exact(inviteSeed ?? Uint8List(0), gv2SeedLen, 'inviteSeed');
      case Gv2Membership.awaitingConfirm:
        if (inviteSeed != null) {
          throw ArgumentError('gv2 store: a restored group has no invite key');
        }
      default:
        throw ArgumentError(
            'gv2 store: an anchored group is invited or awaiting confirmation');
    }
    return transaction(() async {
      if (await group(id) != null) return false;
      await into(gv2Groups).insert(Gv2GroupsCompanion.insert(
        groupId: id,
        masterKey: masterKey,
        myCiphertext: mine,
        protocolVersion: protocolVersion,
        membership: membership,
        revision: revision,
        chain: chain,
        stateHash: stateHash,
        stateLoaded: false,
        titlePayload: Uint8List(0),
        inviteSeed: Value(inviteSeed),
        invitedBySnowId: Value(invitedBySnowId),
        resetPending: Value(resetPending),
      ));
      return true;
    });
  }

  /// A new invite to a group this account left, was removed from or declined.
  ///
  /// The server shows a returning account the log only from its new invite
  /// on (what happened while it was away is not its business), so the stored
  /// chain cannot be followed up to the invite. The invite's own anchor is
  /// taken instead — as for a first invite — on one condition this device can
  /// check: its revision is HIGHER than the stored one. The device never goes
  /// back to an earlier point of a group it has seen.
  ///
  /// The old member and pending rows are dropped; the state at the new anchor
  /// is fetched and stored with [installState]. Returns false and writes
  /// nothing when the group is unknown, on hold, ended, still joined or
  /// invited, or when the anchor is not later than the stored one.
  Future<bool> reinvite({
    required String groupId,
    required int protocolVersion,
    required int revision,
    required Uint8List chain,
    required Uint8List stateHash,
    required Uint8List inviteSeed,
    String? invitedBySnowId,
  }) {
    _exact(chain, gv2HashLen, 'chain');
    _exact(stateHash, gv2HashLen, 'stateHash');
    _exact(inviteSeed, gv2SeedLen, 'inviteSeed');
    return transaction(() async {
      final row = await group(groupId);
      if (row == null || row.hold != Gv2Hold.none || row.deleted) return false;
      const rejoinable = {
        Gv2Membership.left,
        Gv2Membership.removed,
        Gv2Membership.declined,
      };
      if (!rejoinable.contains(row.membership)) return false;
      if (revision <= row.revision) return false;
      await _deleteRows(groupId);
      // The new anchor is taken without following the log to it, so the
      // points of the earlier membership are not known to be on its chain.
      await (delete(gv2Heads)..where((h) => h.groupId.equals(groupId))).go();
      await _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          membership: const Value(Gv2Membership.invited),
          protocolVersion: Value(protocolVersion),
          revision: Value(revision),
          chain: Value(chain),
          stateHash: Value(stateHash),
          headSig: const Value(null),
          stateLoaded: const Value(false),
          titlePayload: Value(Uint8List(0)),
          title: const Value(null),
          inviteSeed: Value(inviteSeed),
          invitedBySnowId: Value(invitedBySnowId),
          myKeyRevision: const Value(null),
          lastRemovalRevision: const Value(null),
        ),
      );
      return true;
    });
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Store [state] as the state at the anchor of its group. Accepted only
  /// when the group is waiting for it (never loaded, or dropped for repair)
  /// and [state] is at the anchor's revision and chain and hashes to the
  /// anchor's state hash; otherwise throws [Gv2StoreConflict]. Every member
  /// starts unchecked.
  Future<void> installState({
    required Gv2GroupState state,
    Uint8List? headSig,
  }) {
    final groupId = gv2Hex(state.groupId);
    if (headSig != null) _exact(headSig, gv2SignatureLen, 'headSig');
    return transaction(() async {
      final row = await _require(groupId);
      if (row.stateLoaded) {
        throw const Gv2StoreConflict('state already loaded');
      }
      if (row.revision != state.revision ||
          !_same(row.chain, state.chain) ||
          row.protocolVersion != state.version ||
          !_same(row.stateHash, gv2StateHash(state))) {
        throw const Gv2StoreConflict('state does not match the anchor');
      }
      _checkMembership(row.membership, row.myCiphertext, state);
      await _deleteRows(groupId);
      await _writeAllRows(groupId, state);
      await _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          stateLoaded: const Value(true),
          deleted: Value(state.deleted),
          titlePayload: Value(state.titlePayload),
          title: Value(_titleOf(row.masterKey, state)),
          headSig: headSig == null ? const Value.absent() : Value(headSig),
        ),
      );
      await _recordHead(groupId, state.revision, state.chain, headSig);
    });
  }

  /// Move a group from the state [from] to the later state [to], which the
  /// server signed with [headSig]. [from] must be exactly what is stored
  /// (same revision and chain), else [Gv2StoreConflict] and nothing is
  /// written. [membership] is this account's standing after the move; when
  /// omitted the stored one is kept. It must agree with [to] (StateError).
  /// [removalRevision] is the revision of the latest entry between the two
  /// states that took a member out, when there is one. [points] are the
  /// chains after the entries between the two (the last one is [to]'s own);
  /// each is recorded as a verified point of the log.
  Future<void> advance({
    required Gv2GroupState from,
    required Gv2GroupState to,
    required Uint8List headSig,
    Gv2Membership? membership,
    int? removalRevision,
    int? syncedAtMs,
    List<Gv2LogPoint> points = const [],
  }) {
    final groupId = gv2Hex(from.groupId);
    _exact(headSig, gv2SignatureLen, 'headSig');
    _exact(to.chain, gv2HashLen, 'chain');
    if (!_same(from.groupId, to.groupId) || to.revision <= from.revision) {
      throw ArgumentError('gv2 store: advance needs a later state of the same group');
    }
    if (removalRevision != null &&
        (removalRevision <= from.revision || removalRevision > to.revision)) {
      throw ArgumentError('gv2 store: removalRevision outside the advance');
    }
    for (final p in points) {
      _exact(p.chain, gv2HashLen, 'chain');
      if (p.revision <= from.revision || p.revision > to.revision) {
        throw ArgumentError('gv2 store: a log point outside the advance');
      }
      if (p.revision == to.revision && !_same(p.chain, to.chain)) {
        throw ArgumentError('gv2 store: the last log point is not the new head');
      }
    }
    return transaction(() async {
      final row = await _require(groupId);
      if (!row.stateLoaded) {
        throw const Gv2StoreConflict('state not loaded');
      }
      if (row.revision != from.revision || !_same(row.chain, from.chain)) {
        throw const Gv2StoreConflict('stored anchor differs from the starting state');
      }
      final standing = membership ?? row.membership;
      _checkMembership(standing, row.myCiphertext, to);

      await batch((b) {
        for (final e in to.members.entries) {
          final old = from.members[e.key];
          final now = e.value;
          if (old == null ||
              old.joinedRevision != now.joinedRevision ||
              !_same(old.memberPub, now.memberPub) ||
              !_same(old.memberPayload, now.memberPayload)) {
            // New, or left and joined again: a fresh row, nothing carried over.
            b.insert(gv2Members, _memberRow(groupId, e.key, now),
                mode: InsertMode.insertOrReplace);
          } else if (old.role != now.role) {
            b.update(
              gv2Members,
              Gv2MembersCompanion(role: Value(now.role)),
              where: (m) =>
                  m.groupId.equals(groupId) & m.ciphertext.equals(e.key),
            );
          }
        }
        for (final key in from.members.keys) {
          if (!to.members.containsKey(key)) {
            b.deleteWhere(gv2Members,
                (m) => m.groupId.equals(groupId) & m.ciphertext.equals(key));
            // Still valid at the server for up to two days, but never to be
            // used again by this device.
            b.deleteWhere(gv2Endorsements,
                (e) => e.groupId.equals(groupId) & e.ciphertext.equals(key));
          }
        }
        for (final e in to.pending.entries) {
          final old = from.pending[e.key];
          final now = e.value;
          if (old == null ||
              old.revision != now.revision ||
              !_same(old.invitedBy, now.invitedBy) ||
              !_same(old.invitePub, now.invitePub)) {
            b.insert(gv2Pending, _pendingRow(groupId, e.key, now),
                mode: InsertMode.insertOrReplace);
          }
        }
        for (final key in from.pending.keys) {
          if (!to.pending.containsKey(key)) {
            b.deleteWhere(gv2Pending,
                (p) => p.groupId.equals(groupId) & p.ciphertext.equals(key));
          }
        }
      });

      final titleChanged = !_same(row.titlePayload, to.titlePayload);
      await _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          protocolVersion: Value(to.version),
          revision: Value(to.revision),
          chain: Value(to.chain),
          stateHash: Value(gv2StateHash(to)),
          headSig: Value(headSig),
          deleted: Value(to.deleted),
          titlePayload:
              titleChanged ? Value(to.titlePayload) : const Value.absent(),
          title: titleChanged
              ? Value(_titleOf(row.masterKey, to))
              : const Value.absent(),
          membership: Value(standing),
          inviteSeed: standing == Gv2Membership.invited
              ? const Value.absent()
              : const Value(null),
          lastRemovalRevision: removalRevision == null
              ? const Value.absent()
              : Value(removalRevision),
          lastSyncAtMs:
              syncedAtMs == null ? const Value.absent() : Value(syncedAtMs),
        ),
      );
      for (final p in points) {
        if (p.revision != to.revision) {
          await _recordHead(groupId, p.revision, p.chain, null);
        }
      }
      await _recordHead(groupId, to.revision, to.chain, headSig);
      if (_gone(standing) && !_gone(row.membership)) {
        await _shed(groupId, to.revision);
      }
    });
  }

  static bool _gone(Gv2Membership m) =>
      m == Gv2Membership.left ||
      m == Gv2Membership.removed ||
      m == Gv2Membership.declined ||
      m == Gv2Membership.ended;

  /// [groupId] is no longer this account's: what was kept to read and send
  /// in it goes — the Sender Keys (received and own), the records of keys
  /// given, the endorsements, the points of the log other than the one at
  /// [revision]. The group row, its members and its pending invites stay
  /// (they are its state; the chat shows the group as left until it is
  /// removed — Gv2GroupActions.forget).
  Future<void> _shed(String groupId, int revision) async {
    await (delete(gv2SenderKeys)..where((k) => k.groupId.equals(groupId))).go();
    await (delete(gv2KeyDeliveries)..where((k) => k.groupId.equals(groupId)))
        .go();
    await (delete(gv2Endorsements)..where((e) => e.groupId.equals(groupId)))
        .go();
    await (delete(gv2Heads)
          ..where(
            (h) => h.groupId.equals(groupId) & h.revision.equals(revision).not(),
          ))
        .go();
  }

  /// The chain of [groupId] at [revision] as this device verified it, or
  /// null when it never held that point.
  Future<Gv2HeadRow?> head(String groupId, int revision) =>
      (select(gv2Heads)
            ..where((h) => h.groupId.equals(groupId) & h.revision.equals(revision)))
          .getSingleOrNull();

  /// The state of [groupId] at its anchor, rebuilt from the rows; null when
  /// the group is unknown or its state has not been loaded. Throws
  /// [Gv2StoreCorruption] when the rows do not hash to the stored state hash.
  Future<Gv2GroupState?> loadState(String groupId) {
    return transaction(() async {
      final row = await group(groupId);
      if (row == null || !row.stateLoaded) return null;
      final members = SplayTreeMap<String, Gv2MemberState>();
      for (final m in await memberRows(groupId)) {
        members[m.ciphertext] = Gv2MemberState(
          role: m.role,
          memberPub: m.memberPub,
          joinedRevision: m.joinedRevision,
          memberPayload: m.memberPayload,
        );
      }
      final pending = SplayTreeMap<String, Gv2PendingState>();
      for (final p in await pendingInvites(groupId)) {
        pending[p.ciphertext] = Gv2PendingState(
          invitedBy: gv2Unhex(p.invitedBy),
          invitePub: p.invitePub,
          revision: p.revision,
        );
      }
      final state = Gv2GroupState(
        version: row.protocolVersion,
        groupId: gv2Unhex(groupId),
        revision: row.revision,
        chain: row.chain,
        deleted: row.deleted,
        members: members,
        pending: pending,
        titlePayload: row.titlePayload,
      );
      if (!_same(gv2StateHash(state), row.stateHash)) {
        throw const Gv2StoreCorruption();
      }
      return state;
    });
  }

  /// Forget the member and pending rows of [groupId] and mark its state as
  /// not loaded. The anchor (revision, chain, state hash, head signature) and
  /// the master key stay, so the state can be fetched again and checked
  /// against the same hash with [installState].
  Future<void> dropState(String groupId) {
    return transaction(() async {
      await _require(groupId);
      await _deleteRows(groupId);
      await _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          stateLoaded: const Value(false),
          titlePayload: Value(Uint8List(0)),
          title: const Value(null),
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Members and pending invites
  // ---------------------------------------------------------------------------

  /// All members of [groupId], in ciphertext order.
  Future<List<Gv2MemberRow>> memberRows(String groupId) =>
      (select(gv2Members)
            ..where((m) => m.groupId.equals(groupId))
            ..orderBy([(m) => OrderingTerm.asc(m.ciphertext)]))
          .get();

  /// All pending invites of [groupId], in ciphertext order.
  Future<List<Gv2PendingRow>> pendingInvites(String groupId) =>
      (select(gv2Pending)
            ..where((p) => p.groupId.equals(groupId))
            ..orderBy([(p) => OrderingTerm.asc(p.ciphertext)]))
          .get();

  /// [memberRows] as they change.
  Stream<List<Gv2MemberRow>> watchMemberRows(String groupId) =>
      (select(gv2Members)
            ..where((m) => m.groupId.equals(groupId))
            ..orderBy([(m) => OrderingTerm.asc(m.ciphertext)]))
          .watch();

  /// [pendingInvites] as they change.
  Stream<List<Gv2PendingRow>> watchPendingInvites(String groupId) =>
      (select(gv2Pending)
            ..where((p) => p.groupId.equals(groupId))
            ..orderBy([(p) => OrderingTerm.asc(p.ciphertext)]))
          .watch();

  /// Up to [limit] members whose account has not been checked yet.
  Future<List<Gv2MemberRow>> membersToCheck(String groupId, {int limit = 64}) =>
      (select(gv2Members)
            ..where((m) =>
                m.groupId.equals(groupId) &
                m.checkState.equalsValue(Gv2MemberCheckState.unchecked))
            ..orderBy([(m) => OrderingTerm.asc(m.ciphertext)])
            ..limit(limit))
          .get();

  /// The members whose account is confirmed: the only ones a Sender Key or a
  /// message may go to.
  Future<List<Gv2MemberRow>> confirmedMembers(String groupId) =>
      (select(gv2Members)
            ..where((m) =>
                m.groupId.equals(groupId) &
                m.checkState.equalsValue(Gv2MemberCheckState.confirmed))
            ..orderBy([(m) => OrderingTerm.asc(m.ciphertext)]))
          .get();

  /// The member of [groupId] with [ciphertext] (lowercase hex), or null.
  Future<Gv2MemberRow?> member(String groupId, String ciphertext) =>
      (select(gv2Members)
            ..where((m) =>
                m.groupId.equals(groupId) & m.ciphertext.equals(ciphertext)))
          .getSingleOrNull();

  /// The member of [groupId] whose ciphertext decrypts to [snowId], or null.
  /// The row says whether that account is confirmed.
  Future<Gv2MemberRow?> memberBySnowId(String groupId, String snowId) =>
      (select(gv2Members)
            ..where((m) => m.groupId.equals(groupId) & m.snowId.equals(snowId)))
          .getSingleOrNull();

  /// This account's role in [groupId] (0 member, 1 admin, 2 owner), or null
  /// when it is not a member.
  Future<int?> myRole(String groupId) async {
    final row = await group(groupId);
    if (row == null) return null;
    final me = await (select(gv2Members)
          ..where((m) =>
              m.groupId.equals(groupId) & m.ciphertext.equals(row.myCiphertext)))
        .getSingleOrNull();
    return me?.role;
  }

  /// Record the outcome of member checks. A result is applied only to the
  /// membership it was computed for (same joinedRevision); returns how many
  /// were applied.
  Future<int> saveMemberChecks(
    String groupId,
    List<Gv2MemberCheckResult> results,
  ) {
    return transaction(() async {
      var applied = 0;
      for (final r in results) {
        final confirmed = r.state == Gv2MemberCheckState.confirmed;
        if (confirmed &&
            (r.snowId == null ||
                r.accountPublicKey?.length != gv2PublicKeyLen ||
                r.certIssuedAtMs == null)) {
          throw ArgumentError('gv2 store: a confirmed member needs its account');
        }
        applied += await (update(gv2Members)
              ..where((m) =>
                  m.groupId.equals(groupId) &
                  m.ciphertext.equals(r.ciphertext) &
                  m.joinedRevision.equals(r.joinedRevision)))
            .write(Gv2MembersCompanion(
          checkState: Value(r.state),
          snowId: Value(r.snowId),
          accountPublicKey: Value(confirmed ? r.accountPublicKey : null),
          certIssuedAtMs: Value(confirmed ? r.certIssuedAtMs : null),
        ));
      }
      return applied;
    });
  }

  /// Record which account each pending invite is for
  /// (ciphertext hex → snowId).
  Future<void> savePendingAccounts(String groupId, Map<String, String> accounts) {
    return transaction(() async {
      for (final e in accounts.entries) {
        await (update(gv2Pending)
              ..where((p) =>
                  p.groupId.equals(groupId) & p.ciphertext.equals(e.key)))
            .write(Gv2PendingCompanion(snowId: Value(e.value)));
      }
    });
  }

  /// Record whether messages to a member arrive.
  /// Record the display names the server gave for members of [groupId]
  /// ([names]: member ciphertext → name, null = the server knows none), and
  /// that they were looked up on local day [day]. Display only — a name is
  /// never identity.
  Future<void> saveNicknames(
    String groupId,
    Map<String, String?> names, {
    required int day,
  }) => transaction(() async {
    for (final e in names.entries) {
      await (update(gv2Members)..where(
            (m) => m.groupId.equals(groupId) & m.ciphertext.equals(e.key),
          ))
          .write(
            Gv2MembersCompanion(
              nickname: Value(e.value),
              nicknameFetchedDay: Value(day),
            ),
          );
    }
  });

  Future<void> setReach(String groupId, String ciphertext, Gv2Reach reach) =>
      (update(gv2Members)
            ..where((m) =>
                m.groupId.equals(groupId) & m.ciphertext.equals(ciphertext)))
          .write(Gv2MembersCompanion(reach: Value(reach)));

  // ---------------------------------------------------------------------------
  // Single-field changes
  // ---------------------------------------------------------------------------

  /// Change this account's standing without a change of state (for example
  /// awaitingConfirm → active once a member confirmed the head). It must
  /// agree with the stored state (StateError). Leaving the invited standing
  /// erases the invite key.
  Future<void> setMembership(String groupId, Gv2Membership membership) {
    return transaction(() async {
      final row = await _require(groupId);
      if (row.stateLoaded) {
        final state = await loadState(groupId);
        _checkMembership(membership, row.myCiphertext, state!);
      } else if (membership != row.membership) {
        throw StateError('gv2 store: standing cannot change before the state is loaded');
      }
      await _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          membership: Value(membership),
          inviteSeed: membership == Gv2Membership.invited
              ? const Value.absent()
              : const Value(null),
        ),
      );
      if (_gone(membership) && !_gone(row.membership)) {
        await _shed(groupId, row.revision);
      }
    });
  }

  /// Put a group on hold or release it. [evidence] is kept with a freeze and
  /// with a withheld hold. A frozen group is never released: its server
  /// signed two logs (the one exception is [liftFreeze]). A withheld group
  /// is not turned into updateRequired
  /// (it is released only by reaching the head it was shown, or frozen).
  Future<void> setHold(String groupId, Gv2Hold hold, {Uint8List? evidence}) {
    return transaction(() async {
      final row = await _require(groupId);
      if (row.hold == Gv2Hold.frozen && hold != Gv2Hold.frozen) {
        throw StateError('gv2 store: a frozen group stays frozen');
      }
      if (row.hold == Gv2Hold.withheld && hold == Gv2Hold.updateRequired) {
        return;
      }
      const withEvidence = {Gv2Hold.frozen, Gv2Hold.withheld};
      await _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          hold: Value(hold),
          holdEvidence: withEvidence.contains(hold)
              ? (evidence == null ? const Value.absent() : Value(evidence))
              : const Value(null),
        ),
      );
    });
  }

  /// Lift the freeze of [groupId] when it rests on exactly [evidence]. Only
  /// for an invalid_entry freeze that the rules of a later build accept
  /// (Gv2Sync judges that); every other freeze stays for good. Returns false
  /// and changes nothing when the group is not frozen on that evidence.
  Future<bool> liftFreeze(String groupId, Uint8List evidence) {
    return transaction(() async {
      final row = await group(groupId);
      final held = row?.holdEvidence;
      if (row == null ||
          row.hold != Gv2Hold.frozen ||
          held == null ||
          !_same(held, evidence)) {
        return false;
      }
      await _updateGroup(
        groupId,
        const Gv2GroupsCompanion(
          hold: Value(Gv2Hold.none),
          holdEvidence: Value(null),
        ),
      );
      return true;
    });
  }

  /// Whether [groupId] — taken from the backup — still has to tell the
  /// group that this device's Sender Keys are gone (member_reset).
  Future<void> setResetPending(String groupId, bool pending) =>
      _updateGroup(groupId, Gv2GroupsCompanion(resetPending: Value(pending)));

  /// What this device knows of the server's copy of its backup, or null
  /// when it never looked.
  Future<Gv2BackupStateRow?> backupState() =>
      select(gv2BackupStates).getSingleOrNull();

  /// Record what this device knows of the backup: whether its first look
  /// (the restore) is done, the server's tag of the blob, what the last
  /// written list was made from, and when the pending write is due (null:
  /// none pending).
  Future<void> saveBackupState({
    required bool restored,
    required String? etag,
    required Uint8List? fingerprint,
    int? writeDueAtMs,
  }) => into(gv2BackupStates).insertOnConflictUpdate(
        Gv2BackupStatesCompanion.insert(
          slot: const Value(0),
          restored: Value(restored),
          etag: Value(etag),
          fingerprint: Value(fingerprint),
          writeDueAtMs: Value(writeDueAtMs),
        ),
      );

  /// Record the revision at which this device's current Sender Key was made
  /// and when ([atMs], local clock); null = it has none.
  Future<void> setMyKeyRevision(String groupId, int? revision, {int? atMs}) =>
      _updateGroup(
        groupId,
        Gv2GroupsCompanion(
          myKeyRevision: Value(revision),
          myKeyAtMs: Value(revision == null ? null : atMs),
        ),
      );

  /// Prune what only grows: the points of a log stored before [headsBeforeMs]
  /// (never a group's current one — that is its anchor's), and the records
  /// of keys given to members before [deliveriesBeforeMs] (an own chain that
  /// old was replaced long since — gv2OwnKeyMaxAge — and no message of it
  /// can still arrive; the record holds a chain key, and keeping it kept
  /// what a stolen device opens of what this device sent).
  Future<void> pruneOld({
    required int headsBeforeMs,
    required int deliveriesBeforeMs,
  }) => transaction(() async {
    await customStatement(
      'DELETE FROM gv2_heads WHERE stored_at_ms < ? AND NOT EXISTS ('
      'SELECT 1 FROM gv2_groups g WHERE g.group_id = gv2_heads.group_id '
      'AND g.revision = gv2_heads.revision)',
      [headsBeforeMs],
    );
    await (delete(gv2KeyDeliveries)
          ..where((d) => d.deliveredAtMs.isSmallerThanValue(deliveriesBeforeMs)))
        .go();
  });

  /// Record that a sync of the log that STARTED at [nowMs] (local clock,
  /// milliseconds) reached the server's head. It also settles a change of
  /// this device whose answer never came, when the change went out before
  /// the sync started: whatever the server took then, the sync has.
  Future<void> markSynced(String groupId, int nowMs) => transaction(() async {
    final row = await group(groupId);
    if (row == null) throw const Gv2StoreConflict('unknown group');
    final sent = row.changeSentAtMs;
    await _updateGroup(
      groupId,
      Gv2GroupsCompanion(
        lastSyncAtMs: Value(nowMs),
        changeSentAtMs: Value(sent != null && nowMs > sent ? null : sent),
      ),
    );
  });

  /// A change of this device is about to go to the server ([atMs], local
  /// clock); its answer has not come yet. See [Gv2Groups.changeSentAtMs].
  Future<void> markChangeSent(String groupId, int atMs) =>
      _updateGroup(groupId, Gv2GroupsCompanion(changeSentAtMs: Value(atMs)));

  /// The answer to this device's change came: the outcome is known.
  Future<void> clearChangeSent(String groupId) => _updateGroup(
    groupId,
    const Gv2GroupsCompanion(changeSentAtMs: Value(null)),
  );

  /// Erase [groupId] when it is no longer this account's (left, removed,
  /// declined, ended) — its chat was removed: nothing on this device needs
  /// it any more, its master key included. Returns whether it was erased; a
  /// group this account is still in (or invited to) is never touched.
  Future<bool> forgetGone(String groupId) => transaction(() async {
    final row = await group(groupId);
    if (row == null || !_gone(row.membership)) return false;
    await deleteGroup(groupId);
    return true;
  });

  /// Erase a group with its master key, members, pending invites, the
  /// points of its log, its Sender Keys and what waits to be sent to it.
  /// After this the device no longer holds an anchor for it.
  Future<void> deleteGroup(String groupId) {
    return transaction(() async {
      await _deleteRows(groupId);
      await (delete(gv2Heads)..where((h) => h.groupId.equals(groupId))).go();
      await (delete(gv2SenderKeys)..where((k) => k.groupId.equals(groupId))).go();
      await (delete(gv2KeyDeliveries)..where((k) => k.groupId.equals(groupId)))
          .go();
      await (delete(gv2OutboxRows)..where((o) => o.groupId.equals(groupId))).go();
      await (delete(gv2Groups)..where((g) => g.groupId.equals(groupId))).go();
    });
  }

  // ---------------------------------------------------------------------------
  // Server keys, auth credentials, endorsements
  // ---------------------------------------------------------------------------

  /// The server's public keys as last stored, or null.
  Future<Gv2ServerKeysRow?> serverKeys() => select(gv2ServerKeys).getSingleOrNull();

  /// Store the server's public keys. Returns true when they REPLACED
  /// different ones; every credential and endorsement (issued under the old
  /// parameters) is then erased in the same transaction.
  Future<bool> saveServerKeys({
    required Uint8List serverPublicParams,
    required Uint8List headPublicKey,
  }) {
    _exact(headPublicKey, gv2PublicKeyLen, 'headPublicKey');
    if (serverPublicParams.isEmpty) {
      throw ArgumentError('gv2 store: serverPublicParams must not be empty');
    }
    return transaction(() async {
      final old = await serverKeys();
      if (old != null &&
          _same(old.serverPublicParams, serverPublicParams) &&
          _same(old.headPublicKey, headPublicKey)) {
        return false;
      }
      await into(gv2ServerKeys).insert(
        Gv2ServerKeysCompanion.insert(
          slot: const Value(0),
          serverPublicParams: serverPublicParams,
          headPublicKey: headPublicKey,
        ),
        mode: InsertMode.insertOrReplace,
      );
      if (old == null) return false;
      await delete(gv2AuthCredentials).go();
      await delete(gv2Endorsements).go();
      return true;
    });
  }

  /// [snowId]'s credential for the day starting at [redemptionTime], or null.
  Future<Gv2AuthCredentialRow?> authCredential(String snowId, int redemptionTime) =>
      (select(gv2AuthCredentials)
            ..where((c) =>
                c.redemptionTime.equals(redemptionTime) & c.snowId.equals(snowId)))
          .getSingleOrNull();

  /// The latest day [snowId] holds a credential for, or null.
  Future<int?> lastAuthCredentialTime(String snowId) async {
    final latest = gv2AuthCredentials.redemptionTime.max();
    final row = await (selectOnly(gv2AuthCredentials)
          ..addColumns([latest])
          ..where(gv2AuthCredentials.snowId.equals(snowId)))
        .getSingle();
    return row.read(latest);
  }

  /// Store [snowId]'s credentials (redemptionTime → credential). Credentials
  /// for days before [pruneBefore] and every row of another account are
  /// erased.
  Future<void> saveAuthCredentials(
    String snowId,
    Map<int, Uint8List> credentials, {
    required int pruneBefore,
  }) {
    return transaction(() async {
      await (delete(gv2AuthCredentials)
            ..where((c) =>
                c.snowId.equals(snowId).not() |
                c.redemptionTime.isSmallerThanValue(pruneBefore)))
          .go();
      await batch((b) {
        b.insertAll(
          gv2AuthCredentials,
          [
            for (final e in credentials.entries)
              if (e.key >= pruneBefore)
                Gv2AuthCredentialsCompanion.insert(
                  redemptionTime: Value(e.key),
                  snowId: snowId,
                  credential: e.value,
                ),
          ],
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  /// The stored endorsements of [groupId].
  Future<List<Gv2EndorsementRow>> endorsements(String groupId) =>
      (select(gv2Endorsements)..where((e) => e.groupId.equals(groupId))).get();

  /// Replace the endorsements of [groupId] with [byCiphertext]
  /// (ciphertext hex → 33 bytes), which were verified against the members at
  /// [revision]. Throws [Gv2StoreConflict] when the group has moved to
  /// another revision meanwhile, or when the set is not exactly its members.
  Future<void> replaceEndorsements({
    required String groupId,
    required int revision,
    required int expiration,
    required Map<String, Uint8List> byCiphertext,
  }) {
    return transaction(() async {
      final row = await _require(groupId);
      if (!row.stateLoaded || row.revision != revision) {
        throw const Gv2StoreConflict('endorsements are for another revision');
      }
      final current = {for (final m in await memberRows(groupId)) m.ciphertext};
      if (current.length != byCiphertext.length ||
          !current.containsAll(byCiphertext.keys)) {
        throw const Gv2StoreConflict('endorsements do not cover the members');
      }
      await (delete(gv2Endorsements)..where((e) => e.groupId.equals(groupId))).go();
      await batch((b) {
        b.insertAll(gv2Endorsements, [
          for (final e in byCiphertext.entries)
            Gv2EndorsementsCompanion.insert(
              groupId: groupId,
              ciphertext: e.key,
              endorsement: e.value,
              expiration: expiration,
            ),
        ]);
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Gv2GroupRow> _require(String groupId) async {
    final row = await group(groupId);
    if (row == null) throw const Gv2StoreConflict('unknown group');
    return row;
  }

  Future<void> _updateGroup(String groupId, Gv2GroupsCompanion change) async {
    final count = await (update(gv2Groups)
          ..where((g) => g.groupId.equals(groupId)))
        .write(change);
    if (count != 1) throw const Gv2StoreConflict('unknown group');
  }

  /// Record a verified point. A point already held is never changed (the
  /// anchor only moves along one chain, and a re-invite forgets the points
  /// of the earlier membership); a signature is added to a point held
  /// without one.
  Future<void> _recordHead(
    String groupId,
    int revision,
    Uint8List chain,
    Uint8List? headSig,
  ) async {
    final held = await head(groupId, revision);
    if (held == null) {
      await into(gv2Heads).insert(Gv2HeadsCompanion.insert(
        groupId: groupId,
        revision: revision,
        chain: chain,
        headSig: Value(headSig),
        storedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ));
    } else if (!_same(held.chain, chain)) {
      throw const Gv2StoreConflict('a log point differs from the one held');
    } else if (held.headSig == null && headSig != null) {
      await (update(gv2Heads)
            ..where((h) => h.groupId.equals(groupId) & h.revision.equals(revision)))
          .write(Gv2HeadsCompanion(headSig: Value(headSig)));
    }
  }

  Future<void> _deleteRows(String groupId) async {
    await (delete(gv2Members)..where((m) => m.groupId.equals(groupId))).go();
    await (delete(gv2Pending)..where((p) => p.groupId.equals(groupId))).go();
    await (delete(gv2Endorsements)..where((e) => e.groupId.equals(groupId))).go();
  }

  Future<void> _writeAllRows(String groupId, Gv2GroupState state) {
    return batch((b) {
      b.insertAll(gv2Members, [
        for (final e in state.members.entries)
          _memberRow(groupId, e.key, e.value),
      ]);
      b.insertAll(gv2Pending, [
        for (final e in state.pending.entries)
          _pendingRow(groupId, e.key, e.value),
      ]);
    });
  }

  Gv2MembersCompanion _memberRow(
    String groupId,
    String ciphertext,
    Gv2MemberState member,
  ) =>
      Gv2MembersCompanion.insert(
        groupId: groupId,
        ciphertext: ciphertext,
        role: member.role,
        memberPub: _exact(member.memberPub, gv2PublicKeyLen, 'memberPub'),
        joinedRevision: member.joinedRevision,
        memberPayload: member.memberPayload,
      );

  Gv2PendingCompanion _pendingRow(
    String groupId,
    String ciphertext,
    Gv2PendingState invite,
  ) =>
      Gv2PendingCompanion.insert(
        groupId: groupId,
        ciphertext: ciphertext,
        invitedBy: gv2Hex(_exact(invite.invitedBy, gv2CiphertextLen, 'invitedBy')),
        invitePub: _exact(invite.invitePub, gv2PublicKeyLen, 'invitePub'),
        revision: invite.revision,
      );

  /// The group name inside the state's title payload, or null when it does
  /// not open with the key derived from [masterKey].
  String? _titleOf(Uint8List masterKey, Gv2GroupState state) =>
      gv2OpenTitlePayload(
        gv2DeriveStateKey(masterKey, state.groupId),
        state.titlePayload,
      )?.name;

  /// Throws StateError unless [membership] agrees with where [myCiphertext]
  /// stands in [state].
  void _checkMembership(
    Gv2Membership membership,
    String myCiphertext,
    Gv2GroupState state,
  ) {
    final member = state.members.containsKey(myCiphertext);
    final invited = state.pending.containsKey(myCiphertext);
    final bool consistent;
    switch (membership) {
      case Gv2Membership.creating:
      case Gv2Membership.active:
      case Gv2Membership.awaitingConfirm:
        consistent = member && !state.deleted;
      case Gv2Membership.invited:
        consistent = invited && !state.deleted;
      case Gv2Membership.left:
      case Gv2Membership.removed:
        consistent = !member;
      case Gv2Membership.declined:
        consistent = !member && !invited;
      case Gv2Membership.ended:
        consistent = state.deleted;
    }
    if (!consistent) {
      throw StateError(
          'gv2 store: standing ${membership.name} does not agree with the state');
    }
  }
}
