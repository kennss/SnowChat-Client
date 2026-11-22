/// @file        gv2_content.dart
/// @description Group protocol v2 — the plaintext of a content envelope: what
///              a member's Sender Key encrypts (design document §7.1, format
///              in §23). Three things can be said: a message, "take back my
///              message", and "clear the history before this time".
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (comment: the message payload is the 1:1 message object — no v1 rooms). Earlier 2026-11-13
///
/// @functions
///  - Gv2Content.encode() / decode(): the plaintext bytes
///  - Gv2MessageContent: a message (the app's own payload)
///  - Gv2UnsendContent: take back one of the sender's own messages
///  - Gv2ClearHistoryContent: clear the history before a time
///
/// Notes:
///  - Format (big-endian integers):
///      content = version 0x01 ‖ type(1) ‖ body
///      0x01 message        the app's message payload (UTF-8 JSON, the same
///                          object a 1:1 message carries: text, type,
///                          metadata, ttl, reply fields), 1 byte or more
///      0x02 unsend         messageId(16) — of a message of the SAME sender
///      0x03 clear history  beforeMs(u64) — messages sent before this time
///  - The message payload is opaque here: this layer authenticates who sent
///    it and delivers it once; the app reads it.
///  - An unsend names only the 16-byte message id. The message it removes is
///    found by the local message id SHA256(groupId ‖ the UNSENDER's account
///    id ‖ messageId), so it can only ever reach the unsender's own messages.
///  - decode() returns null for anything else: another version, an unknown
///    type (a newer build may add types — an older one drops them), a body
///    of the wrong length.
///  - Dart is the reference for this format (the server never sees it).
///  - Message content passes through here: never log it.
library;

import 'dart:typed_data';

import 'gv2_envelope.dart';

/// The version this build writes and reads.
const int gv2ContentVersion = 0x01;

const int gv2ContentTypeMessage = 0x01;
const int gv2ContentTypeUnsend = 0x02;
const int gv2ContentTypeClearHistory = 0x03;

/// version(1) + type(1).
const int gv2ContentHeaderLen = 2;

/// The longest app payload of a message.
const int gv2MaxMessagePayload = gv2MaxContentPlaintext - gv2ContentHeaderLen;

/// What a content envelope says.
sealed class Gv2Content {
  const Gv2Content();

  int get type;

  Uint8List _body();

  Uint8List encode() {
    final body = _body();
    return Uint8List(gv2ContentHeaderLen + body.length)
      ..[0] = gv2ContentVersion
      ..[1] = type
      ..setAll(gv2ContentHeaderLen, body);
  }

  /// The content of [bytes], or null when they are not one (see the notes).
  static Gv2Content? decode(Uint8List bytes) {
    if (bytes.length < gv2ContentHeaderLen || bytes[0] != gv2ContentVersion) {
      return null;
    }
    final body = Uint8List.fromList(bytes.sublist(gv2ContentHeaderLen));
    switch (bytes[1]) {
      case gv2ContentTypeMessage:
        return body.isEmpty ? null : Gv2MessageContent(body);
      case gv2ContentTypeUnsend:
        return body.length == gv2MessageIdLen ? Gv2UnsendContent(body) : null;
      case gv2ContentTypeClearHistory:
        if (body.length != 8) return null;
        // Dart integers are signed 64-bit: 2^63 or more reads negative.
        final beforeMs = ByteData.sublistView(body).getInt64(0, Endian.big);
        return beforeMs < 0 ? null : Gv2ClearHistoryContent(beforeMs);
    }
    return null;
  }
}

/// A message. [payload] is the app's own (UTF-8 JSON); opaque here.
final class Gv2MessageContent extends Gv2Content {
  final Uint8List payload;

  Gv2MessageContent(this.payload) {
    if (payload.isEmpty || payload.length > gv2MaxMessagePayload) {
      throw ArgumentError(
        'gv2 content: a message payload is 1 to $gv2MaxMessagePayload bytes',
      );
    }
  }

  @override
  int get type => gv2ContentTypeMessage;

  @override
  Uint8List _body() => payload;
}

/// "Take back my message [messageId]" (the 16 bytes of its envelope header).
final class Gv2UnsendContent extends Gv2Content {
  final Uint8List messageId;

  Gv2UnsendContent(this.messageId) {
    if (messageId.length != gv2MessageIdLen) {
      throw ArgumentError(
        'gv2 content: messageId must be $gv2MessageIdLen bytes',
      );
    }
  }

  @override
  int get type => gv2ContentTypeUnsend;

  @override
  Uint8List _body() => messageId;
}

/// "Clear the history sent before [beforeMs]" (Unix MILLISECONDS). Honoured
/// only from an owner or admin, and never beyond the time it was sent at.
final class Gv2ClearHistoryContent extends Gv2Content {
  final int beforeMs;

  Gv2ClearHistoryContent(this.beforeMs) {
    if (beforeMs < 0) {
      throw ArgumentError('gv2 content: beforeMs must not be negative');
    }
  }

  @override
  int get type => gv2ContentTypeClearHistory;

  @override
  Uint8List _body() {
    final out = Uint8List(8);
    ByteData.sublistView(out).setUint64(0, beforeMs, Endian.big);
    return out;
  }
}
