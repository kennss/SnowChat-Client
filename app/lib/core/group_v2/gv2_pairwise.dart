/// @file        gv2_pairwise.dart
/// @description Group protocol v2 — the plaintext of a pairwise message: what
///              one member says to one other member about a group, carried
///              over their 1:1 session inside a sealed sender envelope and
///              delivered by the group queue (design document §7.2). Every
///              message names its group, its sender and its recipient, and
///              the receiver checks all three against the sealed envelope
///              and its own state — a message cannot be moved to another
///              group or another person.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - Gv2PairwiseMessage.encode() / decode(): the message bytes
///  - Gv2SenderKeyBody: a Sender Key of the sender (v4)
///  - Gv2KeyRequestBody: "send me your key of this chain"
///  - Gv2HeadConfirmBody: "I see you in the group at this signed head"
///  - Gv2BehindBody: "your envelope came from behind this signed head"
///  - Gv2SessionResetBody: carries the first message of a new 1:1 session
///  - Gv2HeadRequestBody: "show me the signed head you hold"
///  - Gv2HeadProofBody: the answer — the sender's signed head
///  - Gv2SignedHead: a point of the log with the server's signature
///
/// Notes:
///  - Format (big-endian integers):
///      message = 0xF2 ‖ version 0x01 ‖ type(1) ‖ groupId(32)
///                ‖ sender account id(16) ‖ recipient account id(16) ‖ body
///      0x01 Sender Key     chainId(u32) ‖ iteration(u32) ‖ chainKey(32)
///                          ‖ signingKey(32)                          72 B
///      0x02 key request    chainId(u32)                                4 B
///      0x03 head confirm   revision(u32) ‖ chain(32) ‖ headSig(64)   100 B
///      0x04 behind         revision(u32) ‖ chain(32) ‖ headSig(64)   100 B
///      0x05 session reset  (empty)
///      0x06 head request   (empty)
///      0x07 head proof     revision(u32) ‖ chain(32) ‖ headSig(64)   100 B
///  - The first byte is not '{': the 1:1 message path decodes its plaintext
///    as JSON, so a pairwise message that reached it would fail there instead
///    of being taken for a chat message.
///  - One encoding only. decode() returns null for anything else: another
///    format or version byte, an unknown type, a body of the wrong length, a
///    chain id of 2^31 or more.
///  - Dart is the reference for this format (the server never sees it);
///    the vectors are app/test/fixtures/gv2_pairwise_v1.json.
///  - Key material passes through here: never log a message.
library;

import 'dart:typed_data';

import '../crypto/sender_key.dart';
import 'gv2_codec.dart';
import 'gv2_member_check.dart';

/// First byte of every pairwise message.
const int gv2PairwiseFormat = 0xF2;

/// The version this build writes and reads.
const int gv2PairwiseVersion = 0x01;

const int gv2PairwiseTypeSenderKey = 0x01;
const int gv2PairwiseTypeKeyRequest = 0x02;
const int gv2PairwiseTypeHeadConfirm = 0x03;
const int gv2PairwiseTypeBehind = 0x04;
const int gv2PairwiseTypeSessionReset = 0x05;
const int gv2PairwiseTypeHeadRequest = 0x06;
const int gv2PairwiseTypeHeadProof = 0x07;

/// format(1) + version(1) + type(1) + groupId(32) + sender(16) + recipient(16).
const int gv2PairwiseHeaderLen = 3 + gv2GroupIdLen + 2 * gv2AccountIdLen;

const int _keyLen = 32;
const int _sigLen = 64;

/// A point of a group's change log and the server's signature over it.
class Gv2SignedHead {
  final int revision;
  final Uint8List chain;
  final Uint8List headSig;

  Gv2SignedHead({
    required this.revision,
    required Uint8List chain,
    required Uint8List headSig,
  }) : chain = _exact(chain, gv2HashLen, 'chain'),
       headSig = _exact(headSig, _sigLen, 'headSig') {
    _u32(revision, 'revision');
  }

  static const int length = 4 + gv2HashLen + _sigLen;

  void _write(Uint8List out, int at) {
    _putU32(out, at, revision);
    out.setAll(at + 4, chain);
    out.setAll(at + 4 + gv2HashLen, headSig);
  }

  static Gv2SignedHead _read(Uint8List bytes, int at) => Gv2SignedHead(
    revision: _getU32(bytes, at),
    chain: Uint8List.fromList(bytes.sublist(at + 4, at + 4 + gv2HashLen)),
    headSig: Uint8List.fromList(
      bytes.sublist(at + 4 + gv2HashLen, at + length),
    ),
  );
}

/// What a pairwise message says.
sealed class Gv2PairwiseBody {
  const Gv2PairwiseBody();

  int get type;
  int get length;
  void _write(Uint8List out, int at);
}

/// A Sender Key of the sender for this group: its chain from [iteration] on.
final class Gv2SenderKeyBody extends Gv2PairwiseBody {
  final int chainId;
  final int iteration;
  final Uint8List chainKey;
  final Uint8List signingKey;

  Gv2SenderKeyBody({
    required this.chainId,
    required this.iteration,
    required Uint8List chainKey,
    required Uint8List signingKey,
  }) : chainKey = _exact(chainKey, _keyLen, 'chainKey'),
       signingKey = _exact(signingKey, _keyLen, 'signingKey') {
    _chainId(chainId);
    _u32(iteration, 'iteration');
  }

  /// The key a [SenderKeyDistributionMessage] gives.
  factory Gv2SenderKeyBody.of(SenderKeyDistributionMessage m) =>
      Gv2SenderKeyBody(
        chainId: m.chainId,
        iteration: m.iteration,
        chainKey: m.chainKey,
        signingKey: m.signingKey,
      );

  /// The key as a distribution message of [sender] in the v4 manager's
  /// group [managerGroup] (gv2SenderKeyGroup).
  SenderKeyDistributionMessage toDistribution(
    String managerGroup,
    String sender,
  ) => SenderKeyDistributionMessage(
    groupId: managerGroup,
    senderId: sender,
    chainId: chainId,
    iteration: iteration,
    chainKey: Uint8List.fromList(chainKey),
    signingKey: Uint8List.fromList(signingKey),
  );

  /// The body bytes (also what a key delivery record keeps).
  Uint8List encode() {
    final out = Uint8List(length);
    _write(out, 0);
    return out;
  }

  /// The body of [bytes] (exactly [length] bytes), or null.
  static Gv2SenderKeyBody? decode(Uint8List bytes) {
    if (bytes.length != 72) return null;
    return _readSenderKey(bytes, 0);
  }

  @override
  int get type => gv2PairwiseTypeSenderKey;

  @override
  int get length => 72;

  @override
  void _write(Uint8List out, int at) {
    _putU32(out, at, chainId);
    _putU32(out, at + 4, iteration);
    out.setAll(at + 8, chainKey);
    out.setAll(at + 8 + _keyLen, signingKey);
  }
}

/// "I cannot read your messages of chain [chainId]: send me that key."
final class Gv2KeyRequestBody extends Gv2PairwiseBody {
  final int chainId;

  Gv2KeyRequestBody(this.chainId) {
    _chainId(chainId);
  }

  @override
  int get type => gv2PairwiseTypeKeyRequest;

  @override
  int get length => 4;

  @override
  void _write(Uint8List out, int at) => _putU32(out, at, chainId);
}

/// "I see your ACCEPT in the log, at this head" — sent to a member who has
/// just joined (or restored), who may send only once a member confirmed
/// (design §5.5).
final class Gv2HeadConfirmBody extends Gv2PairwiseBody {
  final Gv2SignedHead head;
  const Gv2HeadConfirmBody(this.head);

  @override
  int get type => gv2PairwiseTypeHeadConfirm;

  @override
  int get length => Gv2SignedHead.length;

  @override
  void _write(Uint8List out, int at) => head._write(out, at);
}

/// "Your envelope came from an earlier revision than this head: sync."
final class Gv2BehindBody extends Gv2PairwiseBody {
  final Gv2SignedHead head;
  const Gv2BehindBody(this.head);

  @override
  int get type => gv2PairwiseTypeBehind;

  @override
  int get length => Gv2SignedHead.length;

  @override
  void _write(Uint8List out, int at) => head._write(out, at);
}

/// Carries the first message of a new 1:1 session after the sender gave up
/// the old one (a pairwise envelope of this group did not decrypt). Says
/// nothing else: decrypting it is what sets the session up.
final class Gv2SessionResetBody extends Gv2PairwiseBody {
  const Gv2SessionResetBody();

  @override
  int get type => gv2PairwiseTypeSessionReset;

  @override
  int get length => 0;

  @override
  void _write(Uint8List out, int at) {}
}

/// "Show me the head of the log you hold, with the server's signature." Sent
/// to a member whose (authenticated) envelope header disagrees with this
/// device's log, or is ahead of what the server serves this device (design
/// §5.5: a claim alone does nothing; the server's own signature is proof).
final class Gv2HeadRequestBody extends Gv2PairwiseBody {
  const Gv2HeadRequestBody();

  @override
  int get type => gv2PairwiseTypeHeadRequest;

  @override
  int get length => 0;

  @override
  void _write(Uint8List out, int at) {}
}

/// The answer to a head request: the head the sender holds, signed by the
/// server.
final class Gv2HeadProofBody extends Gv2PairwiseBody {
  final Gv2SignedHead head;
  const Gv2HeadProofBody(this.head);

  @override
  int get type => gv2PairwiseTypeHeadProof;

  @override
  int get length => Gv2SignedHead.length;

  @override
  void _write(Uint8List out, int at) => head._write(out, at);
}

/// One pairwise message.
class Gv2PairwiseMessage {
  final Uint8List groupId;

  /// 16-byte account ids.
  final Uint8List sender;
  final Uint8List recipient;
  final Gv2PairwiseBody body;

  Gv2PairwiseMessage({
    required Uint8List groupId,
    required Uint8List sender,
    required Uint8List recipient,
    required this.body,
  }) : groupId = _exact(groupId, gv2GroupIdLen, 'groupId'),
       sender = _exact(sender, gv2AccountIdLen, 'sender'),
       recipient = _exact(recipient, gv2AccountIdLen, 'recipient');

  String get senderSnowId => gv2SnowIdOfAccountId(sender);
  String get recipientSnowId => gv2SnowIdOfAccountId(recipient);

  Uint8List encode() {
    final out = Uint8List(gv2PairwiseHeaderLen + body.length)
      ..[0] = gv2PairwiseFormat
      ..[1] = gv2PairwiseVersion
      ..[2] = body.type
      ..setAll(3, groupId)
      ..setAll(3 + gv2GroupIdLen, sender)
      ..setAll(3 + gv2GroupIdLen + gv2AccountIdLen, recipient);
    body._write(out, gv2PairwiseHeaderLen);
    return out;
  }

  /// The message of [bytes], or null when they are not one (see the notes).
  static Gv2PairwiseMessage? decode(Uint8List bytes) {
    if (bytes.length < gv2PairwiseHeaderLen ||
        bytes[0] != gv2PairwiseFormat ||
        bytes[1] != gv2PairwiseVersion) {
      return null;
    }
    const at = gv2PairwiseHeaderLen;
    final bodyLen = bytes.length - at;
    Gv2PairwiseBody? body;
    try {
      switch (bytes[2]) {
        case gv2PairwiseTypeSenderKey:
          if (bodyLen == 72) body = _readSenderKey(bytes, at);
        case gv2PairwiseTypeKeyRequest:
          if (bodyLen == 4) body = Gv2KeyRequestBody(_getU32(bytes, at));
        case gv2PairwiseTypeHeadConfirm:
          if (bodyLen == Gv2SignedHead.length) {
            body = Gv2HeadConfirmBody(Gv2SignedHead._read(bytes, at));
          }
        case gv2PairwiseTypeBehind:
          if (bodyLen == Gv2SignedHead.length) {
            body = Gv2BehindBody(Gv2SignedHead._read(bytes, at));
          }
        case gv2PairwiseTypeSessionReset:
          if (bodyLen == 0) body = const Gv2SessionResetBody();
        case gv2PairwiseTypeHeadRequest:
          if (bodyLen == 0) body = const Gv2HeadRequestBody();
        case gv2PairwiseTypeHeadProof:
          if (bodyLen == Gv2SignedHead.length) {
            body = Gv2HeadProofBody(Gv2SignedHead._read(bytes, at));
          }
      }
    } on ArgumentError {
      return null; // a chain id of 2^31 or more
    }
    if (body == null) return null;
    return Gv2PairwiseMessage(
      groupId: Uint8List.fromList(bytes.sublist(3, 3 + gv2GroupIdLen)),
      sender: Uint8List.fromList(
        bytes.sublist(3 + gv2GroupIdLen, 3 + gv2GroupIdLen + gv2AccountIdLen),
      ),
      recipient: Uint8List.fromList(
        bytes.sublist(
          3 + gv2GroupIdLen + gv2AccountIdLen,
          gv2PairwiseHeaderLen,
        ),
      ),
      body: body,
    );
  }
}

Gv2SenderKeyBody _readSenderKey(Uint8List bytes, int at) => Gv2SenderKeyBody(
  chainId: _getU32(bytes, at),
  iteration: _getU32(bytes, at + 4),
  chainKey: Uint8List.fromList(bytes.sublist(at + 8, at + 8 + _keyLen)),
  signingKey: Uint8List.fromList(
    bytes.sublist(at + 8 + _keyLen, at + 8 + 2 * _keyLen),
  ),
);

Uint8List _exact(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw ArgumentError('gv2 pairwise: $what must be $length bytes');
  }
  return bytes;
}

void _u32(int value, String what) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw ArgumentError('gv2 pairwise: $what out of range');
  }
}

/// Sender Key chain ids are 31-bit (sender_key.dart).
void _chainId(int value) {
  if (value < 0 || value > 0x7FFFFFFF) {
    throw ArgumentError('gv2 pairwise: chainId out of range');
  }
}

void _putU32(Uint8List out, int at, int value) {
  out[at] = (value >> 24) & 0xFF;
  out[at + 1] = (value >> 16) & 0xFF;
  out[at + 2] = (value >> 8) & 0xFF;
  out[at + 3] = value & 0xFF;
}

int _getU32(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
