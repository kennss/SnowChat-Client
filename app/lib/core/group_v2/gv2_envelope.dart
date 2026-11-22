/// @file        gv2_envelope.dart
/// @description Group protocol v2 — the group envelope: what a member uploads
///              once for the whole group and every recipient downloads. The
///              server sees an opaque blob; a member finds the group by a
///              short tag, opens the envelope with a key derived from the
///              group master key, and reads a header (who sent it, which
///              message, the sender's view of the change log) and a body.
///              Pure Dart: no database, no network, no native code (design
///              document §7.1, formats in §21).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - Gv2EnvelopeKeys: the envelope and hint keys of one group
///  - Gv2EnvelopeStamp / Gv2EnvelopeHeader: the 117-byte header
///  - gv2EnvelopeInnerLength(): the padded length of header + body
///  - gv2SealEnvelope() / gv2OpenEnvelope() / gv2OpenEnvelopeAmong()
///  - gv2NewMessageId() / gv2LocalMessageId(): message identifiers
///  - gv2ContentBinding(): what ties a Sender Key message to its header
///  - gv2SealContentEnvelope() / gv2OpenContent(): kind 0x01
///  - gv2SealChangeNoticeEnvelope() / gv2ChangeNoticeRevision(): kind 0x04
///  - gv2SealMemberNoticeEnvelope() / gv2VerifyMemberNotice(): kind 0x05
///
/// Notes:
///  - Layout (integers big-endian):
///      envelope = 0x02 ‖ hint(8) ‖ nonce(24) ‖ SecretBox(K_env, nonce, inner)
///      hint     = HMAC-SHA256(K_hint, nonce)[0..8]
///      inner    = header(117) ‖ body ‖ zero padding
///      header   = kind(1) ‖ sender account id(16) ‖ sender device id(36)
///                 ‖ messageId(16) ‖ revision(u32) ‖ chain(32)
///                 ‖ timestampMs(u64) ‖ bodyLength(u32)
///    The first byte tells a group envelope (0x02) from a sealed sender
///    envelope (0x01), which travels through the same queue.
///  - Padding: the inner plaintext is at least 512 bytes and a multiple of
///    64 — the rule the sealed sender envelope already follows — so a short
///    text, a change notice and a member notice have the same length.
///  - K_env is known to everyone who ever held the master key. Opening an
///    envelope therefore proves only "someone who had the group key made
///    this", never who. What may be believed depends on the kind:
///      0x01 content       — the body is a Sender Key message (wire v4) whose
///                           signature covers SHA256(groupId ‖ header): the
///                           sender's own signature vouches for the header.
///      0x04 change notice — nothing vouches for it. It is a hint to fetch
///                           the change log, and must not change state or
///                           raise an alarm by itself.
///      0x05 member notice — payload ‖ signature by the sender's member
///                           signing key over
///                           0xFF ‖ "SnowChat_GV2_MemberNotice_v1" ‖ groupId
///                           ‖ header ‖ payload.
///    Deciding that the sender is a confirmed member of the group is the
///    caller's job, before anything here is believed.
///  - Nothing in this file logs: headers name the group's members.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pinenacl/x25519.dart' as nacl;

import '../crypto/ed25519_strict.dart';
import '../crypto/hkdf.dart' show hmacSha256;
import '../crypto/sender_key.dart';
import 'gv2_codec.dart';
import 'gv2_keys.dart';
import 'gv2_member_check.dart';

/// First byte of a group envelope.
const int gv2EnvelopeVersion = 0x02;

const int gv2EnvelopeHintLen = 8;
const int gv2EnvelopeHeaderLen = 117;
const int gv2DeviceIdLen = 36;
const int gv2MessageIdLen = 16;

const int _nonceLen = 24;
const int _macLen = 16;

/// Bytes around the inner plaintext: version, hint, nonce, authentication tag.
const int gv2EnvelopeOverhead = 1 + gv2EnvelopeHintLen + _nonceLen + _macLen;

/// The server refuses a larger envelope
/// (server/src/services/GroupV2QueueService.ts MAX_ENVELOPE_BYTES).
const int gv2MaxEnvelopeBytes = 64 * 1024;

const int _minInnerLen = 512;
const int _padStep = 64;

/// The longest body that still fits [gv2MaxEnvelopeBytes] after padding.
const int gv2MaxEnvelopeBody =
    (gv2MaxEnvelopeBytes - gv2EnvelopeOverhead) ~/ _padStep * _padStep -
        gv2EnvelopeHeaderLen;

/// The longest plaintext of a content envelope.
const int gv2MaxContentPlaintext =
    gv2MaxEnvelopeBody - senderKeyMessageOverhead;

/// A Sender Key message (wire v4); its signature covers the header.
const int gv2KindContent = 0x01;

/// "The change log has moved" — unauthenticated.
const int gv2KindChangeNotice = 0x04;

/// A notice signed with the sender's member signing key.
const int gv2KindMemberNotice = 0x05;

/// Member notice: the sender lost its Sender Keys (reinstall). Receivers
/// forget that they delivered their key to this member.
final Uint8List gv2NoticeMemberReset = Uint8List.fromList(const [0x01]);

/// Longest payload of a member notice.
const int gv2MaxMemberNoticePayload = 1024;

const int _signPrefix = 0xff;
final Uint8List _labelMemberNotice =
    ascii.encode('SnowChat_GV2_MemberNotice_v1');

final Random _random = Random.secure();

Uint8List _randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

Uint8List _exact(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw ArgumentError('gv2 envelope: $what must be $length bytes');
  }
  return bytes;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The two keys a member needs to make and to recognise the envelopes of one
/// group. Key material: never log it.
class Gv2EnvelopeKeys {
  /// 32-byte group id.
  final Uint8List groupId;

  /// K_env.
  final Uint8List envelopeKey;

  /// K_hint.
  final Uint8List hintKey;

  Gv2EnvelopeKeys({
    required Uint8List groupId,
    required Uint8List envelopeKey,
    required Uint8List hintKey,
  })  : groupId = _exact(groupId, gv2GroupIdLen, 'groupId'),
        envelopeKey = _exact(envelopeKey, gv2SymmetricKeyLen, 'envelopeKey'),
        hintKey = _exact(hintKey, gv2SymmetricKeyLen, 'hintKey');

  factory Gv2EnvelopeKeys.derive(Uint8List masterKey, Uint8List groupId) =>
      Gv2EnvelopeKeys(
        groupId: groupId,
        envelopeKey: gv2DeriveEnvelopeKey(masterKey, groupId),
        hintKey: gv2DeriveHintKey(masterKey, groupId),
      );
}

/// What a sender states about itself and the message in every envelope.
class Gv2EnvelopeStamp {
  /// The first 16 bytes of the sender's account key.
  final Uint8List senderAccountId;

  /// 36 printable ASCII characters.
  final String senderDeviceId;

  /// 16 random bytes chosen by the sender; see [gv2LocalMessageId].
  final Uint8List messageId;

  /// The sender's place in the change log when it sent this.
  final int revision;
  final Uint8List chain;

  /// The sender's clock, Unix time in MILLISECONDS.
  final int timestampMs;

  const Gv2EnvelopeStamp({
    required this.senderAccountId,
    required this.senderDeviceId,
    required this.messageId,
    required this.revision,
    required this.chain,
    required this.timestampMs,
  });

  /// "snow" + hex of [senderAccountId].
  String get senderSnowId => gv2SnowIdOfAccountId(senderAccountId);
}

bool _isDeviceId(List<int> bytes) {
  if (bytes.length != gv2DeviceIdLen) return false;
  for (final b in bytes) {
    if (b <= 0x20 || b >= 0x7f) return false;
  }
  return true;
}

/// The 117 bytes at the start of the inner plaintext.
class Gv2EnvelopeHeader {
  /// One of the gv2Kind* values when this client made the envelope; any byte
  /// when it was read (a newer client may send kinds this one does not know).
  final int kind;
  final Gv2EnvelopeStamp stamp;
  final int bodyLength;

  const Gv2EnvelopeHeader({
    required this.kind,
    required this.stamp,
    required this.bodyLength,
  });

  /// Throws [ArgumentError] when a field does not fit its place.
  Uint8List encode() {
    final deviceId = ascii.encode(stamp.senderDeviceId);
    if (!_isDeviceId(deviceId)) {
      throw ArgumentError(
          'gv2 envelope: senderDeviceId must be $gv2DeviceIdLen printable '
          'ASCII characters');
    }
    if (kind < 0 || kind > 0xff) {
      throw ArgumentError('gv2 envelope: kind must be one byte');
    }
    if (stamp.revision < 0 || stamp.revision > 0xffffffff) {
      throw ArgumentError('gv2 envelope: revision must fit 32 bits');
    }
    if (stamp.timestampMs < 0) {
      throw ArgumentError('gv2 envelope: timestampMs must not be negative');
    }
    if (bodyLength < 0 || bodyLength > gv2MaxEnvelopeBody) {
      throw ArgumentError(
          'gv2 envelope: body must be at most $gv2MaxEnvelopeBody bytes');
    }
    final out = Uint8List(gv2EnvelopeHeaderLen);
    final view = ByteData.sublistView(out);
    out[0] = kind;
    out.setAll(1, _exact(stamp.senderAccountId, gv2AccountIdLen, 'accountId'));
    out.setAll(17, deviceId);
    out.setAll(53, _exact(stamp.messageId, gv2MessageIdLen, 'messageId'));
    view.setUint32(69, stamp.revision, Endian.big);
    out.setAll(73, _exact(stamp.chain, gv2HashLen, 'chain'));
    view.setUint64(105, stamp.timestampMs, Endian.big);
    view.setUint32(113, bodyLength, Endian.big);
    return out;
  }

  /// The header in [bytes], or null when they are not one. Never throws.
  static Gv2EnvelopeHeader? tryDecode(Uint8List bytes) {
    if (bytes.length != gv2EnvelopeHeaderLen) return null;
    final view = ByteData.sublistView(bytes);
    final deviceId = bytes.sublist(17, 53);
    if (!_isDeviceId(deviceId)) return null;
    // Dart integers are signed 64-bit: a time of 2^63 or more reads negative.
    final timestampMs = view.getInt64(105, Endian.big);
    if (timestampMs < 0) return null;
    final bodyLength = view.getUint32(113, Endian.big);
    if (bodyLength > gv2MaxEnvelopeBody) return null;
    return Gv2EnvelopeHeader(
      kind: bytes[0],
      stamp: Gv2EnvelopeStamp(
        senderAccountId: Uint8List.fromList(bytes.sublist(1, 17)),
        senderDeviceId: ascii.decode(deviceId),
        messageId: Uint8List.fromList(bytes.sublist(53, 69)),
        revision: view.getUint32(69, Endian.big),
        chain: Uint8List.fromList(bytes.sublist(73, 105)),
        timestampMs: timestampMs,
      ),
      bodyLength: bodyLength,
    );
  }
}

/// Length of the inner plaintext for a body of [bodyLength] bytes: header +
/// body, at least 512, rounded up to a multiple of 64.
int gv2EnvelopeInnerLength(int bodyLength) {
  final raw = gv2EnvelopeHeaderLen + bodyLength;
  final floor = raw < _minInnerLen ? _minInnerLen : raw;
  return (floor + _padStep - 1) ~/ _padStep * _padStep;
}

/// HMAC-SHA256(K_hint, nonce)[0..8].
Uint8List _hint(Uint8List hintKey, Uint8List nonce) => Uint8List.fromList(
    hmacSha256(hintKey, nonce).sublist(0, gv2EnvelopeHintLen));

/// Seal [body] under [header] for the group of [keys].
///
/// [nonce] fixes the 24-byte nonce; tests only (golden vectors). Everything
/// else draws a fresh random one.
Uint8List gv2SealEnvelope({
  required Gv2EnvelopeKeys keys,
  required Gv2EnvelopeHeader header,
  required Uint8List body,
  @visibleForTesting Uint8List? nonce,
}) {
  if (header.bodyLength != body.length) {
    throw ArgumentError('gv2 envelope: header.bodyLength is not the body');
  }
  final headerBytes = header.encode();
  final inner = Uint8List(gv2EnvelopeInnerLength(body.length))
    ..setAll(0, headerBytes)
    ..setAll(gv2EnvelopeHeaderLen, body);
  final usedNonce = nonce == null
      ? _randomBytes(_nonceLen)
      : Uint8List.fromList(_exact(nonce, _nonceLen, 'nonce'));
  final box = nacl.SecretBox(keys.envelopeKey).encrypt(inner, nonce: usedNonce);

  final out = Uint8List(gv2EnvelopeOverhead + inner.length);
  out[0] = gv2EnvelopeVersion;
  out.setAll(1, _hint(keys.hintKey, usedNonce));
  out.setAll(1 + gv2EnvelopeHintLen, usedNonce);
  out.setAll(1 + gv2EnvelopeHintLen + _nonceLen, box.cipherText);
  return out;
}

/// An envelope this device could open. Nothing in it is believed yet — see
/// the notes at the top of the file.
class Gv2OpenedEnvelope {
  final Gv2EnvelopeHeader header;

  /// The header exactly as it was sealed: what the signatures cover.
  final Uint8List headerBytes;
  final Uint8List body;

  const Gv2OpenedEnvelope({
    required this.header,
    required this.headerBytes,
    required this.body,
  });

  int get kind => header.kind;
  Gv2EnvelopeStamp get stamp => header.stamp;
}

/// True when [bytes] start like a group envelope (and not like a sealed
/// sender envelope, whose first byte is 0x01).
bool gv2IsGroupEnvelope(Uint8List bytes) =>
    bytes.length >= gv2EnvelopeOverhead + _minInnerLen &&
    bytes.length <= gv2MaxEnvelopeBytes &&
    bytes[0] == gv2EnvelopeVersion;

/// Open [envelope] as one of the group of [keys]. Null when it carries
/// another group's hint, does not open, or is not laid out as above. Never
/// throws.
Gv2OpenedEnvelope? gv2OpenEnvelope({
  required Gv2EnvelopeKeys keys,
  required Uint8List envelope,
}) {
  if (!gv2IsGroupEnvelope(envelope)) return null;
  const nonceAt = 1 + gv2EnvelopeHintLen;
  const boxAt = nonceAt + _nonceLen;
  final nonce = Uint8List.fromList(envelope.sublist(nonceAt, boxAt));
  if (!_sameBytes(
      _hint(keys.hintKey, nonce), envelope.sublist(1, nonceAt))) {
    return null;
  }

  final Uint8List inner;
  try {
    inner = Uint8List.fromList(nacl.SecretBox(keys.envelopeKey).decrypt(
      nacl.EncryptedMessage(
        nonce: nonce,
        cipherText: Uint8List.fromList(envelope.sublist(boxAt)),
      ),
    ));
  } catch (_) {
    // Another key, or altered bytes.
    return null;
  }
  if (inner.length < gv2EnvelopeHeaderLen) return null;

  final headerBytes =
      Uint8List.fromList(inner.sublist(0, gv2EnvelopeHeaderLen));
  final header = Gv2EnvelopeHeader.tryDecode(headerBytes);
  if (header == null) return null;
  final bodyEnd = gv2EnvelopeHeaderLen + header.bodyLength;
  if (bodyEnd > inner.length) return null;
  for (var i = bodyEnd; i < inner.length; i++) {
    if (inner[i] != 0) return null;
  }
  return Gv2OpenedEnvelope(
    header: header,
    headerBytes: headerBytes,
    body: Uint8List.fromList(inner.sublist(gv2EnvelopeHeaderLen, bodyEnd)),
  );
}

/// The group among [groups] that [envelope] belongs to, and the envelope
/// opened. Null when it is none of them. Costs one HMAC per group.
({Gv2EnvelopeKeys keys, Gv2OpenedEnvelope envelope})? gv2OpenEnvelopeAmong(
  Uint8List envelope,
  Iterable<Gv2EnvelopeKeys> groups,
) {
  if (!gv2IsGroupEnvelope(envelope)) return null;
  for (final keys in groups) {
    final opened = gv2OpenEnvelope(keys: keys, envelope: envelope);
    if (opened != null) return (keys: keys, envelope: opened);
  }
  return null;
}

/// A fresh message id.
Uint8List gv2NewMessageId() => _randomBytes(gv2MessageIdLen);

/// The id under which a message is stored and de-duplicated on a device:
/// SHA256(groupId ‖ sender account id ‖ messageId).
///
/// For a content envelope the message id is under the sender's signature
/// (it is part of the header), so nobody else can occupy this id first.
Uint8List gv2LocalMessageId({
  required Uint8List groupId,
  required Uint8List senderAccountId,
  required Uint8List messageId,
}) =>
    Uint8List.fromList(hash.sha256.convert([
      ..._exact(groupId, gv2GroupIdLen, 'groupId'),
      ..._exact(senderAccountId, gv2AccountIdLen, 'accountId'),
      ..._exact(messageId, gv2MessageIdLen, 'messageId'),
    ]).bytes);

/// The name of a group in a Sender Key manager.
String gv2SenderKeyGroup(Uint8List groupId) =>
    gv2Hex(_exact(groupId, gv2GroupIdLen, 'groupId'));

/// SHA256(groupId ‖ header): what the Sender Key signature of a content
/// envelope covers besides the message itself.
Uint8List gv2ContentBinding(Uint8List groupId, Uint8List headerBytes) =>
    Uint8List.fromList(hash.sha256.convert([
      ..._exact(groupId, gv2GroupIdLen, 'groupId'),
      ..._exact(headerBytes, gv2EnvelopeHeaderLen, 'header'),
    ]).bytes);

/// Encrypt [plaintext] with the sender's own Sender Key for this group and
/// seal it in an envelope whose header that key signs.
///
/// [senderKeys] must be a v4 manager holding the key of
/// (gv2SenderKeyGroup(groupId), stamp.senderSnowId). The nonces are for
/// tests only.
Uint8List gv2SealContentEnvelope({
  required Gv2EnvelopeKeys keys,
  required Gv2EnvelopeStamp stamp,
  required SenderKeyManager senderKeys,
  required Uint8List plaintext,
  @visibleForTesting Uint8List? nonce,
  @visibleForTesting Uint8List? messageNonce,
}) {
  if (plaintext.length > gv2MaxContentPlaintext) {
    throw ArgumentError(
        'gv2 envelope: content must be at most $gv2MaxContentPlaintext bytes');
  }
  final header = Gv2EnvelopeHeader(
    kind: gv2KindContent,
    stamp: stamp,
    bodyLength: senderKeyMessageLength(plaintext.length),
  );
  final body = senderKeys.encryptBoundGroupMessage(
    gv2SenderKeyGroup(keys.groupId),
    stamp.senderSnowId,
    plaintext,
    gv2ContentBinding(keys.groupId, header.encode()),
    // Forwards this function's own test-only parameter.
    // ignore: invalid_use_of_visible_for_testing_member
    nonce: messageNonce,
  );
  return gv2SealEnvelope(keys: keys, header: header, body: body, nonce: nonce);
}

/// The plaintext of a content envelope of the group [groupId].
///
/// Throws [SenderKeyException]: `noKey` when the sender's key (for that
/// chain) has not arrived, `signature` when the message or its header is not
/// what the sender signed — such an envelope is dropped and the sender's key
/// is kept.
///
/// The caller has already established that the sender is a confirmed member
/// of the group; [senderKeys] is the v4 manager.
Uint8List gv2OpenContent({
  required Uint8List groupId,
  required Gv2OpenedEnvelope envelope,
  required SenderKeyManager senderKeys,
}) {
  if (envelope.kind != gv2KindContent) {
    throw const SenderKeyException(
        SenderKeyFailure.malformed, 'Not a content envelope.');
  }
  return senderKeys.decryptBoundGroupMessage(
    gv2SenderKeyGroup(groupId),
    envelope.stamp.senderSnowId,
    envelope.body,
    gv2ContentBinding(groupId, envelope.headerBytes),
  );
}

/// "The change log has moved to [Gv2EnvelopeStamp.revision]": the body is
/// that revision. Sent after the sender's own change was accepted.
Uint8List gv2SealChangeNoticeEnvelope({
  required Gv2EnvelopeKeys keys,
  required Gv2EnvelopeStamp stamp,
  @visibleForTesting Uint8List? nonce,
}) {
  final body = Uint8List(4);
  ByteData.sublistView(body).setUint32(0, stamp.revision, Endian.big);
  return gv2SealEnvelope(
    keys: keys,
    header: Gv2EnvelopeHeader(
        kind: gv2KindChangeNotice, stamp: stamp, bodyLength: body.length),
    body: body,
    nonce: nonce,
  );
}

/// The revision a change notice points at, or null when [envelope] is not
/// one. Nothing vouches for the number: it only says "fetch the log".
int? gv2ChangeNoticeRevision(Gv2OpenedEnvelope envelope) {
  if (envelope.kind != gv2KindChangeNotice || envelope.body.length != 4) {
    return null;
  }
  return ByteData.sublistView(envelope.body).getUint32(0, Endian.big);
}

/// What a member signing key signs for a member notice.
Uint8List gv2MemberNoticeMessage({
  required Uint8List groupId,
  required Uint8List headerBytes,
  required Uint8List payload,
}) {
  final b = BytesBuilder(copy: false)
    ..addByte(_signPrefix)
    ..add(_labelMemberNotice)
    ..add(_exact(groupId, gv2GroupIdLen, 'groupId'))
    ..add(_exact(headerBytes, gv2EnvelopeHeaderLen, 'header'))
    ..add(payload);
  return b.takeBytes();
}

/// A notice signed with the sender's member signing key ([memberKey]), e.g.
/// [gv2NoticeMemberReset]. The body is payload ‖ signature(64).
Uint8List gv2SealMemberNoticeEnvelope({
  required Gv2EnvelopeKeys keys,
  required Gv2EnvelopeStamp stamp,
  required Gv2SigningKey memberKey,
  required Uint8List payload,
  @visibleForTesting Uint8List? nonce,
}) {
  if (payload.isEmpty || payload.length > gv2MaxMemberNoticePayload) {
    throw ArgumentError(
        'gv2 envelope: a member notice payload is 1 to '
        '$gv2MaxMemberNoticePayload bytes');
  }
  final header = Gv2EnvelopeHeader(
    kind: gv2KindMemberNotice,
    stamp: stamp,
    bodyLength: payload.length + gv2SignatureLen,
  );
  final signature = memberKey.sign(gv2MemberNoticeMessage(
    groupId: keys.groupId,
    headerBytes: header.encode(),
    payload: payload,
  ));
  return gv2SealEnvelope(
    keys: keys,
    header: header,
    body: Uint8List.fromList([...payload, ...signature]),
    nonce: nonce,
  );
}

/// The payload of a member notice when [memberPub] — the member signing key
/// the group state holds for the sender — signed it together with the
/// header; null otherwise. Never throws.
Uint8List? gv2VerifyMemberNotice({
  required Uint8List groupId,
  required Gv2OpenedEnvelope envelope,
  required Uint8List memberPub,
}) {
  final body = envelope.body;
  if (envelope.kind != gv2KindMemberNotice ||
      groupId.length != gv2GroupIdLen ||
      body.length <= gv2SignatureLen ||
      body.length > gv2MaxMemberNoticePayload + gv2SignatureLen) {
    return null;
  }
  final split = body.length - gv2SignatureLen;
  final payload = Uint8List.fromList(body.sublist(0, split));
  final verified = verifyEd25519Strict(
    memberPub,
    gv2MemberNoticeMessage(
      groupId: groupId,
      headerBytes: envelope.headerBytes,
      payload: payload,
    ),
    Uint8List.fromList(body.sublist(split)),
  );
  return verified ? payload : null;
}
