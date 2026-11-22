/// @file        gv2_codec.dart
/// @description Group protocol v2 — the byte formats of a change-log entry and
///              of the group state, and the values derived from them (signed
///              bytes, chain hash, state hash, head and invite messages).
///              Pure functions: no database, no network, no native code.
///              The server implements the same formats
///              (server/src/gv2/codec.ts); both sides are tested against the
///              shared vectors in test/fixtures/gv2_state_machine_v1.json.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: a change entry (not CREATE) holds at most MAX_CHANGE_ACTIONS = 64 actions — entries stay a few KB, the log and a replay stay bounded). Earlier 2026-11-20 (gv2IsGroupId comment: no v1 rooms — a 1:1 room is a snowId)
///
/// @functions
///  - Gv2Action (sealed) and its eleven variants: one change inside an entry
///  - Gv2EntryDraft / Gv2Entry: an entry before / after state hash + signature
///  - Gv2MemberState / Gv2PendingState / Gv2GroupState: the group state
///  - gv2EncodeActions / gv2EncodePayloads / gv2EncodeEntry / gv2DecodeEntry
///  - gv2SignedBytes(): what the actor's member key signs
///  - gv2ChainHash(): hash chain link
///  - gv2StateHash(): commitment to the whole group state
///  - gv2HeadMessage(): what the server's log key signs
///  - gv2InviteAcceptMessage(): what the one-time invite key signs in an ACCEPT
///  - gv2Hex() / gv2Unhex(): lowercase hex (state maps are keyed by it)
///  - gv2IsGroupId(): whether an id is one of a v2 group
///
/// Notes:
///  - All integers are big-endian. Fixed-length fields carry no length.
///    Variable fields: a list is `u16 count` + items, a payload is
///    `u32 length` + bytes (length 0 = absent). There is exactly one encoding
///    of every value; gv2DecodeEntry refuses anything else (trailing bytes,
///    unknown tags, wrong lengths).
///  - Format (design document §19):
///      entry   = version(u8) ‖ revision(u32) ‖ prevChain(32) ‖ actor(65)
///                ‖ actions ‖ payloads ‖ stateHashAfter(32) ‖ sig(64)
///      actions = u16 count ‖ action*          action = tag(u8) ‖ fields
///      payloads= member(u32 len ‖ bytes) ‖ title(u32 len ‖ bytes)
///  - A member ciphertext is an opaque 65-byte value here. Whether it decrypts
///    to an account is checked elsewhere and never decides whether an entry is
///    accepted (design §5.2).
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

const int gv2ProtocolVersion = 1;

const int gv2GroupIdLen = 32;
const int gv2CiphertextLen = 65;
const int gv2PublicKeyLen = 32;
const int gv2SignatureLen = 64;
const int gv2HashLen = 32;

/// Upper bound of the encrypted member payload (account key + certificate).
const int gv2MaxMemberPayload = 512;

/// Upper bound of the encrypted title payload (group name + server key hash).
const int gv2MaxTitlePayload = 1024;

/// members + pending.
const int gv2MaxGroupSize = 1024;

/// Actions in one entry (a create may invite a full group).
const int gv2MaxActions = gv2MaxGroupSize + 1;

/// Actions in any entry after the CREATE (state machine shape rule). Keeps
/// an entry a few kilobytes — the server keeps the log whole and replays it,
/// and a member must not be able to make it huge. Larger batches are several
/// entries.
const int gv2MaxChangeActions = 64;

const int gv2RoleMember = 0;
const int gv2RoleAdmin = 1;
const int gv2RoleOwner = 2;

const int gv2TagCreate = 0x01;
const int gv2TagInvite = 0x02;
const int gv2TagRevokeInvite = 0x03;
const int gv2TagAccept = 0x04;
const int gv2TagDecline = 0x05;
const int gv2TagRemove = 0x06;
const int gv2TagLeave = 0x07;
const int gv2TagSetRole = 0x08;
const int gv2TagTransferOwner = 0x09;
const int gv2TagSetTitle = 0x0a;
const int gv2TagDeleteGroup = 0x0b;

/// Thrown by [gv2DecodeEntry] (and the encoders, for a field of the wrong
/// length) on anything that is not a canonical entry.
class Gv2DecodeException implements Exception {
  final String message;
  const Gv2DecodeException(this.message);

  @override
  String toString() => 'Gv2DecodeException: $message';
}

/// One change inside an entry.
sealed class Gv2Action {
  const Gv2Action();

  /// The wire tag.
  int get tag;
}

final class Gv2Create extends Gv2Action {
  final Uint8List memberPub;
  const Gv2Create(this.memberPub);
  @override
  int get tag => gv2TagCreate;
}

final class Gv2Invite extends Gv2Action {
  final Uint8List target;
  final Uint8List invitePub;
  const Gv2Invite(this.target, this.invitePub);
  @override
  int get tag => gv2TagInvite;
}

final class Gv2RevokeInvite extends Gv2Action {
  final Uint8List target;
  const Gv2RevokeInvite(this.target);
  @override
  int get tag => gv2TagRevokeInvite;
}

final class Gv2Accept extends Gv2Action {
  final Uint8List memberPub;
  final Uint8List inviteSig;
  const Gv2Accept(this.memberPub, this.inviteSig);
  @override
  int get tag => gv2TagAccept;
}

final class Gv2Decline extends Gv2Action {
  const Gv2Decline();
  @override
  int get tag => gv2TagDecline;
}

final class Gv2Remove extends Gv2Action {
  final Uint8List target;
  const Gv2Remove(this.target);
  @override
  int get tag => gv2TagRemove;
}

final class Gv2Leave extends Gv2Action {
  const Gv2Leave();
  @override
  int get tag => gv2TagLeave;
}

final class Gv2SetRole extends Gv2Action {
  final Uint8List target;

  /// [gv2RoleMember], [gv2RoleAdmin] or [gv2RoleOwner] on the wire; the state
  /// machine refuses [gv2RoleOwner] (ownership moves with TRANSFER_OWNER).
  final int role;
  const Gv2SetRole(this.target, this.role);
  @override
  int get tag => gv2TagSetRole;
}

final class Gv2TransferOwner extends Gv2Action {
  final Uint8List target;
  const Gv2TransferOwner(this.target);
  @override
  int get tag => gv2TagTransferOwner;
}

final class Gv2SetTitle extends Gv2Action {
  const Gv2SetTitle();
  @override
  int get tag => gv2TagSetTitle;
}

final class Gv2DeleteGroup extends Gv2Action {
  const Gv2DeleteGroup();
  @override
  int get tag => gv2TagDeleteGroup;
}

/// An entry before its state hash and signature exist.
class Gv2EntryDraft {
  final int version;
  final int revision;
  final Uint8List prevChain;

  /// Member ciphertext of whoever makes the change.
  final Uint8List actor;
  final List<Gv2Action> actions;

  /// SecretBox(K_state) of the member payload; empty when absent.
  final Uint8List memberPayload;

  /// SecretBox(K_state) of the title payload; empty when absent.
  final Uint8List titlePayload;

  const Gv2EntryDraft({
    required this.version,
    required this.revision,
    required this.prevChain,
    required this.actor,
    required this.actions,
    required this.memberPayload,
    required this.titlePayload,
  });
}

/// A complete change-log entry.
class Gv2Entry extends Gv2EntryDraft {
  final Uint8List stateHashAfter;
  final Uint8List sig;

  const Gv2Entry({
    required super.version,
    required super.revision,
    required super.prevChain,
    required super.actor,
    required super.actions,
    required super.memberPayload,
    required super.titlePayload,
    required this.stateHashAfter,
    required this.sig,
  });

  /// [draft] completed with its state hash and signature.
  Gv2Entry.complete(
    Gv2EntryDraft draft, {
    required this.stateHashAfter,
    required this.sig,
  }) : super(
          version: draft.version,
          revision: draft.revision,
          prevChain: draft.prevChain,
          actor: draft.actor,
          actions: draft.actions,
          memberPayload: draft.memberPayload,
          titlePayload: draft.titlePayload,
        );
}

class Gv2MemberState {
  int role;
  final Uint8List memberPub;
  final int joinedRevision;
  final Uint8List memberPayload;

  Gv2MemberState({
    required this.role,
    required this.memberPub,
    required this.joinedRevision,
    required this.memberPayload,
  });

  Gv2MemberState copy() => Gv2MemberState(
        role: role,
        memberPub: memberPub,
        joinedRevision: joinedRevision,
        memberPayload: memberPayload,
      );
}

class Gv2PendingState {
  final Uint8List invitedBy;
  final Uint8List invitePub;
  final int revision;

  const Gv2PendingState({
    required this.invitedBy,
    required this.invitePub,
    required this.revision,
  });
}

/// The whole state of a group. The maps are keyed by the lowercase hex of the
/// member ciphertext and iterate in key order (the order of [gv2StateHash]).
class Gv2GroupState {
  int version;
  final Uint8List groupId;
  int revision;
  Uint8List chain;
  bool deleted;
  final SplayTreeMap<String, Gv2MemberState> members;
  final SplayTreeMap<String, Gv2PendingState> pending;
  Uint8List titlePayload;

  Gv2GroupState({
    required this.version,
    required this.groupId,
    required this.revision,
    required this.chain,
    required this.deleted,
    SplayTreeMap<String, Gv2MemberState>? members,
    SplayTreeMap<String, Gv2PendingState>? pending,
    required this.titlePayload,
  })  : members = members ?? SplayTreeMap<String, Gv2MemberState>(),
        pending = pending ?? SplayTreeMap<String, Gv2PendingState>();

  /// Deep copy (member roles are mutable).
  Gv2GroupState copy() => Gv2GroupState(
        version: version,
        groupId: groupId,
        revision: revision,
        chain: chain,
        deleted: deleted,
        members: SplayTreeMap<String, Gv2MemberState>.of(
          members.map((k, m) => MapEntry(k, m.copy())),
        ),
        pending: SplayTreeMap<String, Gv2PendingState>.of(pending),
        titlePayload: titlePayload,
      );
}

final Uint8List _labelChange = ascii.encode('SnowChat_GV2_Change_v1');
final Uint8List _labelChain = ascii.encode('SnowChat_GV2_Chain_v1');
final Uint8List _labelState = ascii.encode('SnowChat_GV2_State_v1');
final Uint8List _labelHead = ascii.encode('SnowChat_GV2_Head_v1');
final Uint8List _labelInviteAccept = ascii.encode('SnowChat_GV2_InviteAccept_v1');

/// First byte of every signed message: never produced by a UTF-8 string.
const int _signPrefix = 0xff;

const String _hexDigits = '0123456789abcdef';

/// Lowercase hex of [bytes].
String gv2Hex(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out
      ..write(_hexDigits[(b >> 4) & 0x0f])
      ..write(_hexDigits[b & 0x0f]);
  }
  return out.toString();
}

/// Bytes of a hex string (either case). Throws [FormatException] otherwise.
Uint8List gv2Unhex(String hex) {
  if (hex.length.isOdd) throw const FormatException('odd-length hex');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

final RegExp _groupIdHex = RegExp(r'^[0-9a-f]{64}$');

/// Whether [id] is the id of a v2 group as the app carries it (and its
/// conversation): 64 lowercase hex characters. A 1:1 room's id is the peer's
/// snowId ("snow" + 32 hex) and never looks like this.
bool gv2IsGroupId(Object? id) => id is String && _groupIdHex.hasMatch(id);

Uint8List _sha256(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final part in parts) {
    b.add(part);
  }
  return Uint8List.fromList(hash.sha256.convert(b.takeBytes()).bytes);
}

Uint8List _u8(int value) => Uint8List.fromList([value & 0xff]);

Uint8List _u16(int value) =>
    (ByteData(2)..setUint16(0, value, Endian.big)).buffer.asUint8List();

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();

Uint8List _fixed(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw Gv2DecodeException('$what must be $length bytes');
  }
  return bytes;
}

void _encodeAction(BytesBuilder b, Gv2Action action) {
  b.addByte(action.tag);
  switch (action) {
    case Gv2Create():
      b.add(_fixed(action.memberPub, gv2PublicKeyLen, 'memberPub'));
    case Gv2Invite():
      b
        ..add(_fixed(action.target, gv2CiphertextLen, 'target'))
        ..add(_fixed(action.invitePub, gv2PublicKeyLen, 'invitePub'));
    case Gv2Accept():
      b
        ..add(_fixed(action.memberPub, gv2PublicKeyLen, 'memberPub'))
        ..add(_fixed(action.inviteSig, gv2SignatureLen, 'inviteSig'));
    case Gv2RevokeInvite():
      b.add(_fixed(action.target, gv2CiphertextLen, 'target'));
    case Gv2Remove():
      b.add(_fixed(action.target, gv2CiphertextLen, 'target'));
    case Gv2TransferOwner():
      b.add(_fixed(action.target, gv2CiphertextLen, 'target'));
    case Gv2SetRole():
      b
        ..add(_fixed(action.target, gv2CiphertextLen, 'target'))
        ..addByte(action.role & 0xff);
    case Gv2Decline():
    case Gv2Leave():
    case Gv2SetTitle():
    case Gv2DeleteGroup():
      break;
  }
}

Uint8List gv2EncodeActions(List<Gv2Action> actions) {
  if (actions.length > 0xffff) throw const Gv2DecodeException('too many actions');
  final b = BytesBuilder(copy: false)..add(_u16(actions.length));
  for (final action in actions) {
    _encodeAction(b, action);
  }
  return b.takeBytes();
}

Uint8List gv2EncodePayloads(Uint8List memberPayload, Uint8List titlePayload) {
  final b = BytesBuilder(copy: false)
    ..add(_u32(memberPayload.length))
    ..add(memberPayload)
    ..add(_u32(titlePayload.length))
    ..add(titlePayload);
  return b.takeBytes();
}

Uint8List gv2EncodeEntry(Gv2Entry entry) {
  final b = BytesBuilder(copy: false)
    ..addByte(entry.version & 0xff)
    ..add(_u32(entry.revision))
    ..add(_fixed(entry.prevChain, gv2HashLen, 'prevChain'))
    ..add(_fixed(entry.actor, gv2CiphertextLen, 'actor'))
    ..add(gv2EncodeActions(entry.actions))
    ..add(gv2EncodePayloads(entry.memberPayload, entry.titlePayload))
    ..add(_fixed(entry.stateHashAfter, gv2HashLen, 'stateHashAfter'))
    ..add(_fixed(entry.sig, gv2SignatureLen, 'sig'));
  return b.takeBytes();
}

class _Reader {
  final Uint8List _bytes;
  final ByteData _view;
  int _offset = 0;

  _Reader(Uint8List bytes)
      : _bytes = bytes,
        _view = ByteData.sublistView(bytes);

  void _need(int length) {
    if (_offset + length > _bytes.length) {
      throw const Gv2DecodeException('truncated entry');
    }
  }

  int u8() {
    _need(1);
    return _bytes[_offset++];
  }

  int u16() {
    _need(2);
    final v = _view.getUint16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = _view.getUint32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  Uint8List take(int length) {
    _need(length);
    final out = Uint8List.fromList(_bytes.sublist(_offset, _offset + length));
    _offset += length;
    return out;
  }

  bool get done => _offset == _bytes.length;
}

Gv2Action _decodeAction(_Reader r) {
  final tag = r.u8();
  switch (tag) {
    case gv2TagCreate:
      return Gv2Create(r.take(gv2PublicKeyLen));
    case gv2TagInvite:
      final target = r.take(gv2CiphertextLen);
      return Gv2Invite(target, r.take(gv2PublicKeyLen));
    case gv2TagRevokeInvite:
      return Gv2RevokeInvite(r.take(gv2CiphertextLen));
    case gv2TagRemove:
      return Gv2Remove(r.take(gv2CiphertextLen));
    case gv2TagTransferOwner:
      return Gv2TransferOwner(r.take(gv2CiphertextLen));
    case gv2TagAccept:
      final memberPub = r.take(gv2PublicKeyLen);
      return Gv2Accept(memberPub, r.take(gv2SignatureLen));
    case gv2TagSetRole:
      final target = r.take(gv2CiphertextLen);
      final role = r.u8();
      if (role != gv2RoleMember && role != gv2RoleAdmin && role != gv2RoleOwner) {
        throw const Gv2DecodeException('unknown role');
      }
      return Gv2SetRole(target, role);
    case gv2TagDecline:
      return const Gv2Decline();
    case gv2TagLeave:
      return const Gv2Leave();
    case gv2TagSetTitle:
      return const Gv2SetTitle();
    case gv2TagDeleteGroup:
      return const Gv2DeleteGroup();
    default:
      throw const Gv2DecodeException('unknown action tag');
  }
}

/// Parse one entry. Structural limits only (lengths, tags, sizes); whether the
/// entry is ALLOWED is decided by the state machine.
Gv2Entry gv2DecodeEntry(Uint8List bytes) {
  final r = _Reader(bytes);
  final version = r.u8();
  final revision = r.u32();
  final prevChain = r.take(gv2HashLen);
  final actor = r.take(gv2CiphertextLen);

  final count = r.u16();
  if (count == 0) {
    throw const Gv2DecodeException('an entry needs at least one action');
  }
  if (count > gv2MaxActions) throw const Gv2DecodeException('too many actions');
  final actions = <Gv2Action>[];
  for (var i = 0; i < count; i++) {
    actions.add(_decodeAction(r));
  }

  final memberLen = r.u32();
  if (memberLen > gv2MaxMemberPayload) {
    throw const Gv2DecodeException('member payload too large');
  }
  final memberPayload = r.take(memberLen);
  final titleLen = r.u32();
  if (titleLen > gv2MaxTitlePayload) {
    throw const Gv2DecodeException('title payload too large');
  }
  final titlePayload = r.take(titleLen);

  final stateHashAfter = r.take(gv2HashLen);
  final sig = r.take(gv2SignatureLen);
  if (!r.done) throw const Gv2DecodeException('trailing bytes after the entry');

  return Gv2Entry(
    version: version,
    revision: revision,
    prevChain: prevChain,
    actor: actor,
    actions: actions,
    memberPayload: memberPayload,
    titlePayload: titlePayload,
    stateHashAfter: stateHashAfter,
    sig: sig,
  );
}

/// The bytes the actor's member key (or the invite key, for DECLINE) signs.
Uint8List gv2SignedBytes(
  Uint8List groupId,
  Gv2EntryDraft entry,
  Uint8List stateHashAfter,
) {
  final b = BytesBuilder(copy: false)
    ..addByte(_signPrefix)
    ..add(_labelChange)
    ..addByte(entry.version & 0xff)
    ..add(_fixed(groupId, gv2GroupIdLen, 'groupId'))
    ..add(_u32(entry.revision))
    ..add(_fixed(entry.prevChain, gv2HashLen, 'prevChain'))
    ..add(_fixed(entry.actor, gv2CiphertextLen, 'actor'))
    ..add(_sha256([gv2EncodeActions(entry.actions)]))
    ..add(_sha256([gv2EncodePayloads(entry.memberPayload, entry.titlePayload)]))
    ..add(_fixed(stateHashAfter, gv2HashLen, 'stateHashAfter'));
  return b.takeBytes();
}

/// chain_n = SHA256(label ‖ chain_{n-1} ‖ signed bytes ‖ signature).
Uint8List gv2ChainHash(Uint8List prevChain, Uint8List signed, Uint8List sig) =>
    _sha256([_labelChain, prevChain, signed, sig]);

/// The value of chain_{-1}: what the genesis entry carries as prevChain.
Uint8List gv2GenesisPrevChain() => Uint8List(gv2HashLen);

/// Commitment to the state AFTER an entry. Does not include the chain hash
/// (the chain hash covers this value through the signed bytes).
Uint8List gv2StateHash(Gv2GroupState state) {
  final parts = <List<int>>[
    _labelState,
    _u8(state.version),
    _fixed(state.groupId, gv2GroupIdLen, 'groupId'),
    _u32(state.revision),
    _u8(state.deleted ? 1 : 0),
    _u16(state.members.length),
  ];
  for (final e in state.members.entries) {
    parts
      ..add(gv2Unhex(e.key))
      ..add(_u8(e.value.role))
      ..add(e.value.memberPub)
      ..add(_u32(e.value.joinedRevision))
      ..add(_sha256([e.value.memberPayload]));
  }
  parts.add(_u16(state.pending.length));
  for (final e in state.pending.entries) {
    parts
      ..add(gv2Unhex(e.key))
      ..add(e.value.invitedBy)
      ..add(e.value.invitePub)
      ..add(_u32(e.value.revision));
  }
  parts.add(_sha256([state.titlePayload]));
  return _sha256(parts);
}

/// What the server's log signing key signs for an accepted entry.
Uint8List gv2HeadMessage(Uint8List groupId, int revision, Uint8List chain) {
  final b = BytesBuilder(copy: false)
    ..addByte(_signPrefix)
    ..add(_labelHead)
    ..add(_fixed(groupId, gv2GroupIdLen, 'groupId'))
    ..add(_u32(revision))
    ..add(_fixed(chain, gv2HashLen, 'chain'));
  return b.takeBytes();
}

/// What the one-time invite key signs so that only the invitee can ACCEPT.
Uint8List gv2InviteAcceptMessage(
  Uint8List groupId,
  Uint8List ciphertext,
  Uint8List memberPub,
) {
  final b = BytesBuilder(copy: false)
    ..addByte(_signPrefix)
    ..add(_labelInviteAccept)
    ..add(_fixed(groupId, gv2GroupIdLen, 'groupId'))
    ..add(_fixed(ciphertext, gv2CiphertextLen, 'ciphertext'))
    ..add(_fixed(memberPub, gv2PublicKeyLen, 'memberPub'));
  return b.takeBytes();
}
