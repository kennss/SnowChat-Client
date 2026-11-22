/// @file        gv2_content_test.dart
/// @description Group protocol v2 content plaintext (what a Sender Key
///              encrypts) and the outbox's queued-message layout: each type
///              round trips, the bytes are the documented layout, and the
///              decoders take one encoding only.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - main(): the content format and the queued-message layout.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_content.dart';
import 'package:snowchat/core/group_v2/gv2_envelope.dart';
import 'package:snowchat/core/group_v2/gv2_outbox.dart';

import 'gv2_test_support.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

void main() {
  final messageId = gv2TestBytes('content test — message id', 16);

  group('content', () {
    test('a message is version, type and the app payload', () {
      final payload = _bytes(utf8.encode('{"text":"hi"}'));
      final bytes = Gv2MessageContent(payload).encode();
      expect(bytes, [0x01, 0x01, ...payload]);
      final back = Gv2Content.decode(bytes) as Gv2MessageContent;
      expect(back.payload, payload);
      // Not a JSON object by its first byte.
      expect(bytes[0], isNot(0x7B));
    });

    test('an unsend is the 16-byte message id', () {
      final bytes = Gv2UnsendContent(messageId).encode();
      expect(bytes, [0x01, 0x02, ...messageId]);
      expect(
        (Gv2Content.decode(bytes) as Gv2UnsendContent).messageId,
        messageId,
      );
    });

    test('clearing the history is a 64-bit time, big-endian', () {
      const beforeMs = 0x0102030405060708;
      final bytes = Gv2ClearHistoryContent(beforeMs).encode();
      expect(bytes, [0x01, 0x03, 1, 2, 3, 4, 5, 6, 7, 8]);
      expect(
        (Gv2Content.decode(bytes) as Gv2ClearHistoryContent).beforeMs,
        beforeMs,
      );
    });

    test('one encoding only', () {
      final unsend = Gv2UnsendContent(messageId).encode();
      final clear = Gv2ClearHistoryContent(5).encode();
      // Another version, an unknown type, nothing at all.
      expect(Gv2Content.decode(_bytes([...unsend]..[0] = 0x02)), isNull);
      expect(Gv2Content.decode(_bytes([...unsend]..[0] = 0x00)), isNull);
      for (final type in [0x00, 0x04, 0x7F, 0xFF]) {
        expect(Gv2Content.decode(_bytes([...unsend]..[1] = type)), isNull);
      }
      expect(Gv2Content.decode(Uint8List(0)), isNull);
      expect(Gv2Content.decode(_bytes([0x01])), isNull);
      // A message with no payload.
      expect(Gv2Content.decode(_bytes([0x01, 0x01])), isNull);
      // Bodies one byte short or long.
      expect(Gv2Content.decode(unsend.sublist(0, unsend.length - 1)), isNull);
      expect(Gv2Content.decode(_bytes([...unsend, 0])), isNull);
      expect(Gv2Content.decode(clear.sublist(0, clear.length - 1)), isNull);
      expect(Gv2Content.decode(_bytes([...clear, 0])), isNull);
      // A time of 2^63 or more.
      expect(
        Gv2Content.decode(_bytes([0x01, 0x03, 0x80, 0, 0, 0, 0, 0, 0, 0])),
        isNull,
      );
    });

    test('the constructors refuse what cannot be encoded', () {
      expect(() => Gv2MessageContent(Uint8List(0)), throwsArgumentError);
      expect(
        () => Gv2MessageContent(Uint8List(gv2MaxMessagePayload + 1)),
        throwsArgumentError,
      );
      expect(() => Gv2UnsendContent(Uint8List(15)), throwsArgumentError);
      expect(() => Gv2ClearHistoryContent(-1), throwsArgumentError);
    });

    test('the longest message fits the largest envelope', () {
      final longest = Gv2MessageContent(
        Uint8List(gv2MaxMessagePayload)..[0] = 1,
      );
      expect(longest.encode().length, gv2MaxContentPlaintext);
    });
  });

  group('a queued message', () {
    final plaintext = Gv2MessageContent(_bytes([1, 2, 3])).encode();

    test('is id, time, expiry, the silent flag and the plaintext', () {
      final bytes = Gv2OutboxContent(
        messageId: messageId,
        timestampMs: 0x0102030405060708,
        expiresIn: 0x0A0B0C0D,
        silent: true,
        plaintext: plaintext,
      ).encode();
      expect(bytes, [
        ...messageId,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        0x0A,
        0x0B,
        0x0C,
        0x0D,
        1,
        ...plaintext,
      ]);
      final back = Gv2OutboxContent.decode(bytes)!;
      expect(back.messageId, messageId);
      expect(back.timestampMs, 0x0102030405060708);
      expect(back.expiresIn, 0x0A0B0C0D);
      expect(back.silent, isTrue);
      expect(back.plaintext, plaintext);
    });

    test('what is not one is refused', () {
      final good = Gv2OutboxContent(
        messageId: messageId,
        timestampMs: 5,
        expiresIn: 0,
        silent: false,
        plaintext: plaintext,
      ).encode();
      // No plaintext; a flag that is neither 0 nor 1.
      expect(Gv2OutboxContent.decode(good.sublist(0, 29)), isNull);
      expect(Gv2OutboxContent.decode(Uint8List(0)), isNull);
      expect(Gv2OutboxContent.decode(_bytes([...good]..[28] = 2)), isNull);
      for (final bad in [
        () => Gv2OutboxContent(
          messageId: Uint8List(15),
          timestampMs: 5,
          expiresIn: 0,
          silent: false,
          plaintext: plaintext,
        ).encode(),
        () => Gv2OutboxContent(
          messageId: messageId,
          timestampMs: -1,
          expiresIn: 0,
          silent: false,
          plaintext: plaintext,
        ).encode(),
        () => Gv2OutboxContent(
          messageId: messageId,
          timestampMs: 5,
          expiresIn: 0x100000000,
          silent: false,
          plaintext: plaintext,
        ).encode(),
        () => Gv2OutboxContent(
          messageId: messageId,
          timestampMs: 5,
          expiresIn: 0,
          silent: false,
          plaintext: Uint8List(0),
        ).encode(),
      ]) {
        expect(bad, throwsArgumentError);
      }
    });
  });
}
