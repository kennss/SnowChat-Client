/// @file        gv2_keys.dart
/// @description Group protocol v2 — the keys a client derives or creates and
///              the signatures it makes with them: the symmetric keys derived
///              from the group master key, the per-group member signing key
///              derived from the account seed, the member certificate (the
///              account key vouching for that member key), one-time invite
///              keys, and signing a change-log entry. Pure Dart: no database,
///              no network, no native code (design document §4).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20
///
/// @functions
///  - gv2NewMasterKey(): 32 random bytes, the root secret of a new group
///  - gv2DeriveStateKey / gv2DeriveEnvelopeKey / gv2DeriveHintKey: from the
///    master key and the group id
///  - gv2DeriveMemberSeed(): the member signing seed, from the account seed
///  - Gv2SigningKey: an Ed25519 key that signs entries (member or invite key)
///  - gv2MemberCertMessage() / gv2VerifyMemberCert(): the member certificate
///  - gv2SignInviteAccept(): what an ACCEPT carries, made with the invite key
///  - gv2SignEntry(): complete a draft (state hash + signature) and check it
///  - gv2ServerKeyHash(): commitment to the server keys a group was made under
///
/// Notes:
///  - Derivations (HKDF-SHA256, 32-byte output):
///      K_state    = HKDF(ikm = MK,  salt = groupId, info = "SnowChat_GV2_State_v1")
///      K_env      = HKDF(ikm = MK,  salt = groupId, info = "SnowChat_GV2_Envelope_v1")
///      K_hint     = HKDF(ikm = MK,  salt = groupId, info = "SnowChat_GV2_EnvelopeHint_v1")
///      memberSeed = HKDF(ikm = account seed, salt = "SnowChat_GV2_MemberKey_v1",
///                        info = groupId)
///      K_backup   = HKDF(ikm = account seed, salt = "SnowChat_GV2_Backup_v1",
///                        info = empty)
///    The member key is DERIVED, so a reinstall from the recovery phrase gets
///    the same key back; the group id in the derivation keeps a member's keys
///    in two groups unlinkable.
///  - Member certificate (99 bytes signed by the ACCOUNT key):
///      0xFF ‖ "SnowChat_GV2_MemberCert_v1" (26) ‖ groupId (32)
///           ‖ memberPub (32) ‖ issuedAtMs (u64 big-endian)
///    issuedAtMs is Unix time in MILLISECONDS; it is what a deletion proof is
///    compared with (design §9.7).
///  - Server key hash (carried in the title payload, design §6.1):
///      SHA256("SnowChat_GV2_ServerKeys_v1" ‖ u32 length ‖ zk public params
///             ‖ head signing public key (32))
///    Members of a group compare it with the keys their own server handed
///    them, so a server giving different keys to different users is noticed.
///  - The account seed never enters this file's callers directly: the only
///    caller of gv2DeriveMemberSeed with the real seed is
///    IdentityManager.deriveGroupMemberKey().
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pinenacl/ed25519.dart' as ed;

import '../crypto/ed25519_strict.dart';
import '../crypto/hkdf.dart' show hkdfDerive;
import 'gv2_codec.dart';
import 'gv2_state_machine.dart';

const int gv2MasterKeyLen = 32;
const int gv2SeedLen = 32;
const int gv2SymmetricKeyLen = 32;

/// Length of the message a member certificate signs: 1 + 26 + 32 + 32 + 8.
const int gv2MemberCertMessageLen = 99;

const int _signPrefix = 0xff;

final Uint8List _labelMemberKey = ascii.encode('SnowChat_GV2_MemberKey_v1');
final Uint8List _labelMemberCert = ascii.encode('SnowChat_GV2_MemberCert_v1');
final Uint8List _labelState = ascii.encode('SnowChat_GV2_State_v1');
final Uint8List _labelEnvelope = ascii.encode('SnowChat_GV2_Envelope_v1');
final Uint8List _labelHint = ascii.encode('SnowChat_GV2_EnvelopeHint_v1');
final Uint8List _labelServerKeys = ascii.encode('SnowChat_GV2_ServerKeys_v1');
final Uint8List _labelBackup = ascii.encode('SnowChat_GV2_Backup_v1');

Uint8List _exact(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw ArgumentError('gv2 keys: $what must be $length bytes');
  }
  return bytes;
}

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = random.nextInt(256);
  }
  return out;
}

/// The root secret of a new group.
Uint8List gv2NewMasterKey() => _randomBytes(gv2MasterKeyLen);

Uint8List _fromMasterKey(Uint8List masterKey, Uint8List groupId, Uint8List info) =>
    hkdfDerive(
      ikm: _exact(masterKey, gv2MasterKeyLen, 'masterKey'),
      salt: _exact(groupId, gv2GroupIdLen, 'groupId'),
      info: info,
      length: gv2SymmetricKeyLen,
    );

/// K_state: seals the member and title payloads of the change log.
Uint8List gv2DeriveStateKey(Uint8List masterKey, Uint8List groupId) =>
    _fromMasterKey(masterKey, groupId, _labelState);

/// K_env: seals the header of a group envelope.
Uint8List gv2DeriveEnvelopeKey(Uint8List masterKey, Uint8List groupId) =>
    _fromMasterKey(masterKey, groupId, _labelEnvelope);

/// K_hint: keys the short tag by which a receiver finds the group of an
/// envelope.
Uint8List gv2DeriveHintKey(Uint8List masterKey, Uint8List groupId) =>
    _fromMasterKey(masterKey, groupId, _labelHint);

/// K_backup: seals the backup of an account's group keys (design §9.8). From
/// the account seed alone, so a reinstall from the recovery phrase can open
/// the backup the previous install wrote.
Uint8List gv2DeriveBackupKey(Uint8List accountSeed) => hkdfDerive(
      ikm: _exact(accountSeed, gv2SeedLen, 'accountSeed'),
      salt: _labelBackup,
      info: Uint8List(0),
      length: gv2SymmetricKeyLen,
    );

/// The seed of an account's member signing key in one group.
Uint8List gv2DeriveMemberSeed(Uint8List accountSeed, Uint8List groupId) =>
    hkdfDerive(
      ikm: _exact(accountSeed, gv2SeedLen, 'accountSeed'),
      salt: _labelMemberKey,
      info: _exact(groupId, gv2GroupIdLen, 'groupId'),
      length: gv2SeedLen,
    );

/// An Ed25519 key that signs change-log entries: a member signing key
/// (derived) or a one-time invite key (random, travels inside the 1:1 invite
/// message so that only the invitee can ACCEPT or DECLINE).
class Gv2SigningKey {
  /// 32-byte seed. Key material: never log it.
  final Uint8List seed;

  /// 32-byte public key.
  final Uint8List publicKey;

  final ed.SigningKey _key;

  Gv2SigningKey._(this.seed, this._key)
      : publicKey = Uint8List.fromList(_key.verifyKey.asTypedList);

  factory Gv2SigningKey.fromSeed(Uint8List seed) {
    final copy = Uint8List.fromList(_exact(seed, gv2SeedLen, 'seed'));
    return Gv2SigningKey._(copy, ed.SigningKey(seed: copy));
  }

  /// A fresh random key (an invite key).
  factory Gv2SigningKey.generate() =>
      Gv2SigningKey.fromSeed(_randomBytes(gv2SeedLen));

  /// 64-byte detached signature over [message].
  Uint8List sign(Uint8List message) =>
      Uint8List.fromList(_key.sign(message).signature.asTypedList);
}

/// The 99 bytes an account key signs to vouch for [memberPub] in one group.
Uint8List gv2MemberCertMessage({
  required Uint8List groupId,
  required Uint8List memberPub,
  required int issuedAtMs,
}) {
  if (issuedAtMs < 0) {
    throw ArgumentError('gv2 keys: issuedAtMs must be >= 0');
  }
  final time = ByteData(8)..setUint64(0, issuedAtMs, Endian.big);
  final b = BytesBuilder(copy: false)
    ..addByte(_signPrefix)
    ..add(_labelMemberCert)
    ..add(_exact(groupId, gv2GroupIdLen, 'groupId'))
    ..add(_exact(memberPub, gv2PublicKeyLen, 'memberPub'))
    ..add(time.buffer.asUint8List());
  final out = b.takeBytes();
  assert(out.length == gv2MemberCertMessageLen);
  return out;
}

/// True only when [signature] is [accountPublicKey]'s strict Ed25519
/// signature over the certificate for ([groupId], [memberPub], [issuedAtMs]).
/// Never throws. Whether the account key belongs to the member ciphertext is
/// a separate check (gv2_member_check.dart).
bool gv2VerifyMemberCert({
  required Uint8List accountPublicKey,
  required Uint8List groupId,
  required Uint8List memberPub,
  required int issuedAtMs,
  required Uint8List signature,
}) {
  try {
    final message = gv2MemberCertMessage(
      groupId: groupId,
      memberPub: memberPub,
      issuedAtMs: issuedAtMs,
    );
    return verifyEd25519Strict(accountPublicKey, message, signature);
  } catch (_) {
    return false;
  }
}

/// The inviteSig of an ACCEPT: the one-time invite key signing that this
/// member ciphertext joins with this member key.
Uint8List gv2SignInviteAccept({
  required Gv2SigningKey inviteKey,
  required Uint8List groupId,
  required Uint8List ciphertext,
  required Uint8List memberPub,
}) =>
    inviteKey.sign(gv2InviteAcceptMessage(groupId, ciphertext, memberPub));

/// Complete [draft] into an entry: compute the state hash it must carry, sign
/// it with [key], then apply it to [state] exactly as a receiver would.
/// Returns the entry and the state it produces.
///
/// Throws [Gv2Reject] when the change is not allowed, or when [key] is not
/// the key this entry must be signed with (the member key a CREATE / ACCEPT
/// introduces, the invite key for a DECLINE, the actor's registered member
/// key otherwise) — so this client never submits an entry it would itself
/// refuse.
({Gv2Entry entry, Gv2GroupState next}) gv2SignEntry({
  required Gv2GroupState? state,
  required Uint8List groupId,
  required Gv2EntryDraft draft,
  required Gv2SigningKey key,
}) {
  final stateHashAfter = gv2PreviewEntry(state, groupId, draft);
  final sig = key.sign(gv2SignedBytes(groupId, draft, stateHashAfter));
  final entry =
      Gv2Entry.complete(draft, stateHashAfter: stateHashAfter, sig: sig);
  return (entry: entry, next: gv2ApplyEntry(state, groupId, entry));
}

/// Commitment to the server keys a group was created under: the zkgroup
/// server public parameters and the public key that signs log heads.
Uint8List gv2ServerKeyHash({
  required Uint8List serverPublicParams,
  required Uint8List headPublicKey,
}) {
  final length = ByteData(4)..setUint32(0, serverPublicParams.length, Endian.big);
  final b = BytesBuilder(copy: false)
    ..add(_labelServerKeys)
    ..add(length.buffer.asUint8List())
    ..add(serverPublicParams)
    ..add(_exact(headPublicKey, gv2PublicKeyLen, 'headPublicKey'));
  return Uint8List.fromList(hash.sha256.convert(b.takeBytes()).bytes);
}
