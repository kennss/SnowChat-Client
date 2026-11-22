/// @file        gv2_invite.dart
/// @description Group protocol v2 — the 1:1 invite message: what a member
///              sends an account it invited so that the account can find
///              the group, verify its state and accept (design document
///              §5.5, §9.1, §9.2; format in §24). It travels the ordinary
///              1:1 sealed sender path — the invitee is not a member yet and
///              cannot be reached through the group queue.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - Gv2InviteMessage.encode() / decode(): the invite bytes
///  - gv2InviteInnerType: the inner type of the 1:1 message that carries it
///
/// Notes:
///  - Format (big-endian integers), 166 bytes:
///      invite = 0xF4 ‖ version 0x01 ‖ groupId(32) ‖ masterKey(32)
///               ‖ revision(u32) ‖ chain(32) ‖ stateHash(32) ‖ inviteSeed(32)
///    (revision, chain, stateHash) is the inviter's head when it sent the
///    message: the anchor the invitee starts from. inviteSeed is the private
///    seed of the one-time invite key whose public key the INVITE entry
///    recorded; only its holder can ACCEPT or DECLINE.
///  - The group id is carried for a consistency check only: the receiver
///    always derives it from the master key and refuses a message that
///    states another.
///  - Nothing in an invite is believed by itself. The receiver fetches the
///    state at the anchor and keeps the invite only when that state hashes
///    to stateHash and has this account pending under the invite key
///    (gv2_groups.dart).
///  - One encoding only: decode() returns null for anything else.
///  - Dart is the reference for this format (the server never sees it).
///  - Key material (the master key, the invite seed): never log an invite.
library;

import 'dart:typed_data';

import 'gv2_codec.dart';
import 'gv2_keys.dart';

/// First byte of an invite.
const int gv2InviteFormat = 0xF4;

/// The version this build writes and reads.
const int gv2InviteVersion = 0x01;

/// Total length.
const int gv2InviteLen =
    2 + gv2GroupIdLen + gv2MasterKeyLen + 4 + 2 * gv2HashLen + gv2SeedLen;

/// The inner `type` of the 1:1 message whose `text` is base64(invite).
const String gv2InviteInnerType = 'group_invite_v2';

class Gv2InviteMessage {
  final Uint8List groupId;
  final Uint8List masterKey;

  /// The anchor: the inviter's head when it sent the invite.
  final int revision;
  final Uint8List chain;
  final Uint8List stateHash;

  /// The private seed of the one-time invite key.
  final Uint8List inviteSeed;

  Gv2InviteMessage({
    required Uint8List groupId,
    required Uint8List masterKey,
    required this.revision,
    required Uint8List chain,
    required Uint8List stateHash,
    required Uint8List inviteSeed,
  }) : groupId = _exact(groupId, gv2GroupIdLen, 'groupId'),
       masterKey = _exact(masterKey, gv2MasterKeyLen, 'masterKey'),
       chain = _exact(chain, gv2HashLen, 'chain'),
       stateHash = _exact(stateHash, gv2HashLen, 'stateHash'),
       inviteSeed = _exact(inviteSeed, gv2SeedLen, 'inviteSeed') {
    if (revision < 0 || revision > 0xFFFFFFFF) {
      throw ArgumentError('gv2 invite: revision out of range');
    }
  }

  Uint8List encode() {
    final out = Uint8List(gv2InviteLen);
    var at = 0;
    out[at++] = gv2InviteFormat;
    out[at++] = gv2InviteVersion;
    out.setAll(at, groupId);
    at += gv2GroupIdLen;
    out.setAll(at, masterKey);
    at += gv2MasterKeyLen;
    ByteData.sublistView(out).setUint32(at, revision, Endian.big);
    at += 4;
    out.setAll(at, chain);
    at += gv2HashLen;
    out.setAll(at, stateHash);
    at += gv2HashLen;
    out.setAll(at, inviteSeed);
    return out;
  }

  /// The invite in [bytes], or null when they are not one.
  static Gv2InviteMessage? decode(Uint8List bytes) {
    if (bytes.length != gv2InviteLen ||
        bytes[0] != gv2InviteFormat ||
        bytes[1] != gv2InviteVersion) {
      return null;
    }
    var at = 2;
    Uint8List take(int length) {
      final part = Uint8List.fromList(bytes.sublist(at, at + length));
      at += length;
      return part;
    }

    final groupId = take(gv2GroupIdLen);
    final masterKey = take(gv2MasterKeyLen);
    final revision = ByteData.sublistView(bytes).getUint32(at, Endian.big);
    at += 4;
    return Gv2InviteMessage(
      groupId: groupId,
      masterKey: masterKey,
      revision: revision,
      chain: take(gv2HashLen),
      stateHash: take(gv2HashLen),
      inviteSeed: take(gv2SeedLen),
    );
  }
}

Uint8List _exact(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw ArgumentError('gv2 invite: $what must be $length bytes');
  }
  return bytes;
}
