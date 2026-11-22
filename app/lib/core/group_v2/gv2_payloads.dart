/// @file        gv2_payloads.dart
/// @description Group protocol v2 — the two encrypted parts of a change-log
///              entry. The member payload (carried by CREATE and ACCEPT) names
///              the account behind a member ciphertext and carries the member
///              certificate; the title payload (CREATE and SET_TITLE) carries
///              the group name and the hash of the server keys. Both are
///              SecretBox(K_state); the server stores them as opaque bytes
///              and can read neither (design document §5.1).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - Gv2MemberPayload / Gv2TitlePayload: the decoded contents
///  - gv2EncodeMemberPayload / gv2DecodeMemberPayload: plaintext bytes
///  - gv2EncodeTitlePayload / gv2DecodeTitlePayload: plaintext bytes
///  - gv2SealMemberPayload / gv2OpenMemberPayload: with K_state
///  - gv2SealTitlePayload / gv2OpenTitlePayload: with K_state
///
/// Notes:
///  - Sealed form: nonce (24, random) ‖ XSalsa20-Poly1305 box (plaintext + 16).
///  - Member plaintext, 106 bytes:
///      kind 0x01 ‖ version 0x01 ‖ accountPub (32) ‖ issuedAtMs (u64 BE)
///      ‖ certSig (64)                                       → sealed 146 bytes
///  - Title plaintext, 292 bytes, ALWAYS this length:
///      kind 0x02 ‖ version 0x01 ‖ serverKeyHash (32) ‖ nameLength (u16 BE)
///      ‖ name (UTF-8) ‖ zero padding up to 256 bytes        → sealed 332 bytes
///    The name is padded so that the stored length tells the server nothing
///    about it.
///  - Both plaintexts have exactly one encoding. The decoders refuse a wrong
///    kind or version, a wrong length, non-zero padding and a name that is
///    not well-formed UTF-8.
///  - A payload that does not open NEVER rejects its entry (the server cannot
///    check it, so rejecting would split the two views of the log). The
///    openers return null and the caller shows "unverified member" or "name
///    unknown" (design §5.2).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pinenacl/x25519.dart' as nacl;

import 'gv2_codec.dart';
import 'gv2_keys.dart';

const int _kindMember = 0x01;
const int _kindTitle = 0x02;
const int _payloadVersion = 0x01;

const int _nonceLen = 24;
const int _macLen = 16;

/// Plaintext length of a member payload: 2 + 32 + 8 + 64.
const int gv2MemberPayloadPlainLen = 106;

/// Longest group name, in UTF-8 bytes.
const int gv2MaxTitleNameBytes = 256;

/// Plaintext length of a title payload: 2 + 32 + 2 + 256.
const int gv2TitlePayloadPlainLen = 292;

/// Sealed lengths (what the server stores).
const int gv2MemberPayloadSealedLen = _nonceLen + _macLen + gv2MemberPayloadPlainLen;
const int gv2TitlePayloadSealedLen = _nonceLen + _macLen + gv2TitlePayloadPlainLen;

/// What a member says about itself when it joins.
class Gv2MemberPayload {
  /// The 32-byte ACCOUNT public key the member claims to be.
  final Uint8List accountPublicKey;

  /// When the member certificate was made, Unix milliseconds.
  final int issuedAtMs;

  /// The account key's signature over (groupId, memberPub, issuedAtMs).
  final Uint8List certSignature;

  const Gv2MemberPayload({
    required this.accountPublicKey,
    required this.issuedAtMs,
    required this.certSignature,
  });
}

/// The name of a group and the server keys it was created under.
class Gv2TitlePayload {
  final String name;

  /// gv2ServerKeyHash() of the keys the writer's server gave it.
  final Uint8List serverKeyHash;

  const Gv2TitlePayload({required this.name, required this.serverKeyHash});
}

Uint8List _exact(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw ArgumentError('gv2 payload: $what must be $length bytes');
  }
  return bytes;
}

/// Plaintext of a member payload. Throws [ArgumentError] on a field of the
/// wrong length.
Uint8List gv2EncodeMemberPayload(Gv2MemberPayload payload) {
  if (payload.issuedAtMs < 0) {
    throw ArgumentError('gv2 payload: issuedAtMs must be >= 0');
  }
  final time = ByteData(8)..setUint64(0, payload.issuedAtMs, Endian.big);
  final b = BytesBuilder(copy: false)
    ..addByte(_kindMember)
    ..addByte(_payloadVersion)
    ..add(_exact(payload.accountPublicKey, gv2PublicKeyLen, 'accountPublicKey'))
    ..add(time.buffer.asUint8List())
    ..add(_exact(payload.certSignature, gv2SignatureLen, 'certSignature'));
  final out = b.takeBytes();
  assert(out.length == gv2MemberPayloadPlainLen);
  return out;
}

/// Null unless [plain] is exactly one encoded member payload.
Gv2MemberPayload? gv2DecodeMemberPayload(Uint8List plain) {
  if (plain.length != gv2MemberPayloadPlainLen) return null;
  if (plain[0] != _kindMember || plain[1] != _payloadVersion) return null;
  final view = ByteData.sublistView(plain);
  // A time with the top bit set does not fit a Dart int and is no real time.
  if (view.getUint8(34) & 0x80 != 0) return null;
  return Gv2MemberPayload(
    accountPublicKey: Uint8List.fromList(plain.sublist(2, 34)),
    issuedAtMs: view.getUint64(34, Endian.big),
    certSignature: Uint8List.fromList(plain.sublist(42, 106)),
  );
}

/// Plaintext of a title payload. Throws [ArgumentError] when the name is
/// longer than [gv2MaxTitleNameBytes] in UTF-8 or the hash is not 32 bytes.
Uint8List gv2EncodeTitlePayload(Gv2TitlePayload payload) {
  final name = utf8.encode(payload.name);
  if (name.length > gv2MaxTitleNameBytes) {
    throw ArgumentError(
        'gv2 payload: group name longer than $gv2MaxTitleNameBytes bytes');
  }
  // A name the decoder would read back differently (a leading byte-order
  // mark, an unpaired surrogate) has no canonical bytes.
  if (utf8.decode(name) != payload.name) {
    throw ArgumentError('gv2 payload: group name is not well-formed text');
  }
  final out = Uint8List(gv2TitlePayloadPlainLen);
  out[0] = _kindTitle;
  out[1] = _payloadVersion;
  out.setAll(2, _exact(payload.serverKeyHash, gv2HashLen, 'serverKeyHash'));
  ByteData.sublistView(out).setUint16(34, name.length, Endian.big);
  out.setAll(36, name);
  return out;
}

/// Null unless [plain] is exactly one encoded title payload.
Gv2TitlePayload? gv2DecodeTitlePayload(Uint8List plain) {
  if (plain.length != gv2TitlePayloadPlainLen) return null;
  if (plain[0] != _kindTitle || plain[1] != _payloadVersion) return null;
  final nameLength = ByteData.sublistView(plain).getUint16(34, Endian.big);
  if (nameLength > gv2MaxTitleNameBytes) return null;
  for (var i = 36 + nameLength; i < plain.length; i++) {
    if (plain[i] != 0) return null;
  }
  final String name;
  try {
    name = utf8.decode(plain.sublist(36, 36 + nameLength));
  } on FormatException {
    return null;
  }
  // utf8.decode drops a leading byte-order mark, which would give two byte
  // strings the same name: only the canonical bytes of the name are accepted.
  final canonical = utf8.encode(name);
  if (canonical.length != nameLength) return null;
  for (var i = 0; i < nameLength; i++) {
    if (canonical[i] != plain[36 + i]) return null;
  }
  return Gv2TitlePayload(
    name: name,
    serverKeyHash: Uint8List.fromList(plain.sublist(2, 34)),
  );
}

Uint8List _seal(Uint8List stateKey, Uint8List plain) {
  final box = nacl.SecretBox(_exact(stateKey, gv2SymmetricKeyLen, 'stateKey'));
  final random = Random.secure();
  final nonce = Uint8List(_nonceLen);
  for (var i = 0; i < _nonceLen; i++) {
    nonce[i] = random.nextInt(256);
  }
  final sealed = box.encrypt(plain, nonce: nonce);
  final out = Uint8List(_nonceLen + sealed.cipherText.length)
    ..setAll(0, nonce)
    ..setAll(_nonceLen, sealed.cipherText);
  return out;
}

Uint8List? _open(Uint8List stateKey, Uint8List sealed, int sealedLength) {
  if (stateKey.length != gv2SymmetricKeyLen) return null;
  if (sealed.length != sealedLength) return null;
  try {
    final plain = nacl.SecretBox(stateKey).decrypt(
      nacl.EncryptedMessage(
        nonce: Uint8List.fromList(sealed.sublist(0, _nonceLen)),
        cipherText: Uint8List.fromList(sealed.sublist(_nonceLen)),
      ),
    );
    return Uint8List.fromList(plain);
  } catch (_) {
    // Wrong key or altered bytes.
    return null;
  }
}

/// SecretBox(K_state) of [payload] with a fresh random nonce.
Uint8List gv2SealMemberPayload(Uint8List stateKey, Gv2MemberPayload payload) =>
    _seal(stateKey, gv2EncodeMemberPayload(payload));

/// The member payload inside [sealed], or null when it does not open with
/// [stateKey] or is not a member payload. Never throws.
Gv2MemberPayload? gv2OpenMemberPayload(Uint8List stateKey, Uint8List sealed) {
  final plain = _open(stateKey, sealed, gv2MemberPayloadSealedLen);
  return plain == null ? null : gv2DecodeMemberPayload(plain);
}

/// SecretBox(K_state) of [payload] with a fresh random nonce.
Uint8List gv2SealTitlePayload(Uint8List stateKey, Gv2TitlePayload payload) =>
    _seal(stateKey, gv2EncodeTitlePayload(payload));

/// The title payload inside [sealed], or null when it does not open with
/// [stateKey] or is not a title payload. Never throws.
Gv2TitlePayload? gv2OpenTitlePayload(Uint8List stateKey, Uint8List sealed) {
  final plain = _open(stateKey, sealed, gv2TitlePayloadSealedLen);
  return plain == null ? null : gv2DecodeTitlePayload(plain);
}
