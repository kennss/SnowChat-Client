/// @file        gv2_state_machine.dart
/// @description Group protocol v2 — the rules that decide whether a change-log
///              entry is accepted, and the state it produces. The server runs
///              the same rules before it appends an entry
///              (server/src/gv2/stateMachine.ts); this client runs them again
///              on every entry it receives, so the server cannot make it
///              accept a change the rules forbid. Both implementations are
///              tested against test/fixtures/gv2_state_machine_v1.json.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: a change entry (not CREATE) holds at most MAX_CHANGE_ACTIONS = 64 actions — entries stay a few KB, the log and a replay stay bounded). Earlier 2026-11-13
///
/// @functions
///  - gv2ApplyEntry(state, groupId, entry): new state, or throws Gv2Reject
///  - gv2PreviewEntry(state, groupId, draft): the state hash a new entry must
///    carry (all rules except the entry signature) — for the side that writes
///  - Gv2RejectCode / Gv2Reject: why an entry was refused
///
/// Notes:
///  - The decision depends ONLY on bytes both sides hold: the entry and the
///    previous state. Things only a client can check (does the ciphertext
///    decrypt to an account, is the member certificate valid, does the title
///    decrypt) never reject an entry — the client marks the member or title as
///    unverified instead (design §5.2).
///  - Actions are applied in order; each one sees the state left by the one
///    before it, including the actor's own role.
///  - Shape rules (design §19.3):
///      CREATE        first action of revision 0 only; only INVITEs may follow
///      ACCEPT        the only action of its entry
///      DECLINE       the only action of its entry
///      DELETE_GROUP  the only action of its entry
///      LEAVE         the last action of its entry
///      SET_TITLE     at most once per entry
///      member payload present  ⇔ the entry has CREATE or ACCEPT
///      title payload present   ⇔ the entry has CREATE or SET_TITLE
///  - Who signs an entry: CREATE / ACCEPT — the member key the action
///    introduces; DECLINE — the one-time invite key of the pending entry;
///    anything else — the actor's registered member key.
///  - Order of checks (a rejected entry must be refused with the SAME code on
///    both sides): version → revision / prev_chain / deleted → shape → signer
///    lookup (actor) → signature → actions in order → state_hash.
///  - There is deliberately no "replay without verifying" entry point here.
///    The server has one for its own log; a client verifies everything.
library;

import 'dart:typed_data';

import '../crypto/ed25519_strict.dart';
import '../crypto/identity_binding.dart' show constantTimeEquals;
import 'gv2_codec.dart';

/// Why an entry was refused. [wire] is the string the server and the shared
/// vectors use.
enum Gv2RejectCode {
  /// Unknown protocol version.
  version('version'),

  /// Not exactly the next revision.
  revision('revision'),

  /// Does not extend the current chain.
  prevChain('prev_chain'),

  /// The group is deleted.
  deleted('deleted'),

  /// Combination of actions / payloads not allowed.
  shape('shape'),

  /// The actor is not what the action requires.
  actor('actor'),

  /// The actor's role does not allow the action.
  permission('permission'),

  /// The target is not valid for the action.
  target('target'),

  /// Group size limit.
  size('size'),

  /// Entry signature does not verify.
  signature('signature'),

  /// ACCEPT without a valid signature of the invite key.
  inviteSignature('invite_signature'),

  /// stateHashAfter does not match the resulting state.
  stateHash('state_hash');

  final String wire;
  const Gv2RejectCode(this.wire);
}

class Gv2Reject implements Exception {
  final Gv2RejectCode code;
  const Gv2Reject(this.code);

  @override
  String toString() => 'Gv2Reject: ${code.wire}';
}

Never _reject(Gv2RejectCode code) => throw Gv2Reject(code);

bool _same(Uint8List a, Uint8List b) => constantTimeEquals(a, b);

void _checkShape(Gv2GroupState? state, Gv2EntryDraft entry) {
  final tags = [for (final a in entry.actions) a.tag];
  bool has(int tag) => tags.contains(tag);
  int count(int tag) => tags.where((t) => t == tag).length;

  if (tags.isEmpty) _reject(Gv2RejectCode.shape);
  if (state != null && tags.length > gv2MaxChangeActions) {
    _reject(Gv2RejectCode.shape);
  }

  if (state == null) {
    if (tags.first != gv2TagCreate) _reject(Gv2RejectCode.shape);
    if (tags.skip(1).any((t) => t != gv2TagInvite)) _reject(Gv2RejectCode.shape);
  } else if (has(gv2TagCreate)) {
    _reject(Gv2RejectCode.shape);
  }

  for (final solo in const [gv2TagAccept, gv2TagDecline, gv2TagDeleteGroup]) {
    if (has(solo) && tags.length != 1) _reject(Gv2RejectCode.shape);
  }
  if (has(gv2TagLeave) && (count(gv2TagLeave) != 1 || tags.last != gv2TagLeave)) {
    _reject(Gv2RejectCode.shape);
  }
  if (count(gv2TagSetTitle) > 1) _reject(Gv2RejectCode.shape);

  final wantsMember = has(gv2TagCreate) || has(gv2TagAccept);
  final wantsTitle = has(gv2TagCreate) || has(gv2TagSetTitle);
  if (wantsMember != entry.memberPayload.isNotEmpty) _reject(Gv2RejectCode.shape);
  if (wantsTitle != entry.titlePayload.isNotEmpty) _reject(Gv2RejectCode.shape);
}

/// The key the entry signature must verify under (see the file notes).
Uint8List _signerKey(Gv2GroupState? state, Gv2EntryDraft entry) {
  final first = entry.actions.first;
  if (first is Gv2Create) return first.memberPub;
  if (first is Gv2Accept) return first.memberPub;
  final actorKey = gv2Hex(entry.actor);
  if (first is Gv2Decline) {
    final pending = state?.pending[actorKey];
    if (pending == null) _reject(Gv2RejectCode.actor);
    return pending.invitePub;
  }
  final member = state?.members[actorKey];
  if (member == null) _reject(Gv2RejectCode.actor);
  return member.memberPub;
}

void _applyAction(Gv2GroupState next, Gv2EntryDraft entry, Gv2Action action) {
  final actorKey = gv2Hex(entry.actor);
  Gv2MemberState actorMember() {
    final m = next.members[actorKey];
    if (m == null) _reject(Gv2RejectCode.actor);
    return m;
  }

  switch (action) {
    case Gv2Create():
      next.members[actorKey] = Gv2MemberState(
        role: gv2RoleOwner,
        memberPub: action.memberPub,
        joinedRevision: entry.revision,
        memberPayload: entry.memberPayload,
      );
      next.titlePayload = entry.titlePayload;

    case Gv2Invite():
      if (actorMember().role < gv2RoleAdmin) _reject(Gv2RejectCode.permission);
      final key = gv2Hex(action.target);
      if (next.members.containsKey(key) || next.pending.containsKey(key)) {
        _reject(Gv2RejectCode.target);
      }
      if (next.members.length + next.pending.length + 1 > gv2MaxGroupSize) {
        _reject(Gv2RejectCode.size);
      }
      next.pending[key] = Gv2PendingState(
        invitedBy: entry.actor,
        invitePub: action.invitePub,
        revision: entry.revision,
      );

    case Gv2RevokeInvite():
      final actor = actorMember();
      final key = gv2Hex(action.target);
      final pending = next.pending[key];
      if (pending == null) _reject(Gv2RejectCode.target);
      if (actor.role < gv2RoleAdmin && !_same(pending.invitedBy, entry.actor)) {
        _reject(Gv2RejectCode.permission);
      }
      next.pending.remove(key);

    case Gv2Accept():
      final pending = next.pending[actorKey];
      if (pending == null) _reject(Gv2RejectCode.actor);
      final message =
          gv2InviteAcceptMessage(next.groupId, entry.actor, action.memberPub);
      if (!verifyEd25519Strict(pending.invitePub, message, action.inviteSig)) {
        _reject(Gv2RejectCode.inviteSignature);
      }
      next.pending.remove(actorKey);
      next.members[actorKey] = Gv2MemberState(
        role: gv2RoleMember,
        memberPub: action.memberPub,
        joinedRevision: entry.revision,
        memberPayload: entry.memberPayload,
      );

    case Gv2Decline():
      if (!next.pending.containsKey(actorKey)) _reject(Gv2RejectCode.actor);
      next.pending.remove(actorKey);

    case Gv2Remove():
      final actor = actorMember();
      final key = gv2Hex(action.target);
      if (key == actorKey) _reject(Gv2RejectCode.target);
      final target = next.members[key];
      if (target == null) _reject(Gv2RejectCode.target);
      if (actor.role == gv2RoleOwner) {
        // The owner may remove anyone else.
      } else if (actor.role == gv2RoleAdmin) {
        if (target.role != gv2RoleMember) _reject(Gv2RejectCode.permission);
      } else {
        _reject(Gv2RejectCode.permission);
      }
      next.members.remove(key);

    case Gv2Leave():
      final actor = actorMember();
      if (actor.role == gv2RoleOwner) {
        // An owner hands the group over first (TRANSFER_OWNER in this entry),
        // unless nobody else is left: then the group ends.
        if (next.members.length != 1) _reject(Gv2RejectCode.permission);
        next.members.remove(actorKey);
        next.pending.clear();
        next.deleted = true;
      } else {
        next.members.remove(actorKey);
      }

    case Gv2SetRole():
      if (actorMember().role != gv2RoleOwner) _reject(Gv2RejectCode.permission);
      final key = gv2Hex(action.target);
      if (key == actorKey) _reject(Gv2RejectCode.target);
      final target = next.members[key];
      if (target == null) _reject(Gv2RejectCode.target);
      if (action.role != gv2RoleMember && action.role != gv2RoleAdmin) {
        _reject(Gv2RejectCode.target);
      }
      target.role = action.role;

    case Gv2TransferOwner():
      final actor = actorMember();
      if (actor.role != gv2RoleOwner) _reject(Gv2RejectCode.permission);
      final key = gv2Hex(action.target);
      if (key == actorKey) _reject(Gv2RejectCode.target);
      final target = next.members[key];
      if (target == null) _reject(Gv2RejectCode.target);
      target.role = gv2RoleOwner;
      actor.role = gv2RoleAdmin;

    case Gv2SetTitle():
      if (actorMember().role < gv2RoleAdmin) _reject(Gv2RejectCode.permission);
      next.titlePayload = entry.titlePayload;

    case Gv2DeleteGroup():
      if (actorMember().role != gv2RoleOwner) _reject(Gv2RejectCode.permission);
      next.deleted = true;
  }
}

/// Everything that can be checked before signatures: version, position, shape.
void _precheck(Gv2GroupState? state, Gv2EntryDraft entry) {
  if (entry.version != gv2ProtocolVersion) _reject(Gv2RejectCode.version);
  if (state != null && state.version != entry.version) {
    _reject(Gv2RejectCode.version);
  }

  if (state == null) {
    if (entry.revision != 0) _reject(Gv2RejectCode.revision);
    if (!_same(entry.prevChain, gv2GenesisPrevChain())) {
      _reject(Gv2RejectCode.prevChain);
    }
  } else {
    if (state.deleted) _reject(Gv2RejectCode.deleted);
    if (entry.revision != state.revision + 1) _reject(Gv2RejectCode.revision);
    if (!_same(entry.prevChain, state.chain)) _reject(Gv2RejectCode.prevChain);
  }

  _checkShape(state, entry);
}

/// The state after the entry's actions. `chain` is still the previous one.
Gv2GroupState _produce(
  Gv2GroupState? state,
  Uint8List groupId,
  Gv2EntryDraft entry,
) {
  final next = state == null
      ? Gv2GroupState(
          version: entry.version,
          groupId: Uint8List.fromList(groupId),
          revision: 0,
          chain: gv2GenesisPrevChain(),
          deleted: false,
          titlePayload: Uint8List(0),
        )
      : state.copy();
  next.revision = entry.revision;
  for (final action in entry.actions) {
    _applyAction(next, entry, action);
  }
  return next;
}

/// For whoever WRITES an entry: runs every rule except the entry signature and
/// returns the state hash the entry must carry. Throws [Gv2Reject] when the
/// change is not allowed, so this client never signs something the server and
/// the other members would refuse.
Uint8List gv2PreviewEntry(
  Gv2GroupState? state,
  Uint8List groupId,
  Gv2EntryDraft draft,
) {
  _precheck(state, draft);
  _signerKey(state, draft);
  return gv2StateHash(_produce(state, groupId, draft));
}

/// Apply [entry] to [state] (null = the group does not exist yet) and return
/// the resulting state. Throws [Gv2Reject] and leaves [state] untouched when
/// the entry is not allowed.
Gv2GroupState gv2ApplyEntry(
  Gv2GroupState? state,
  Uint8List groupId,
  Gv2Entry entry,
) {
  _precheck(state, entry);

  final signed = gv2SignedBytes(groupId, entry, entry.stateHashAfter);
  if (!verifyEd25519Strict(_signerKey(state, entry), signed, entry.sig)) {
    _reject(Gv2RejectCode.signature);
  }

  final next = _produce(state, groupId, entry);
  if (!_same(gv2StateHash(next), entry.stateHashAfter)) {
    _reject(Gv2RejectCode.stateHash);
  }
  next.chain = gv2ChainHash(entry.prevChain, signed, entry.sig);
  return next;
}
