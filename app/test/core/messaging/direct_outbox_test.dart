/// @file        direct_outbox_test.dart
/// @description The 1:1 outbox (DirectOutbox) on a real in-memory database: nothing leaves while
///              offline and everything leaves on connect, in order per peer and one at a time; an
///              ack settles the message under the server's id; no ack in time, no socket or a
///              server hiccup postpone it with a growing wait (a late ack still settles it); a
///              refusal, a forged identity binding or 24 hours fail it; a failed message is sent
///              again from its row; an attachment is uploaded from the kept copy first (later
///              when the upload fails, failed when the copy is gone); with Sealed Sender not active
///              nothing is sent and the message waits (no non-sealed fallback).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (Sealed Sender not active: the message waits — SC-05). Earlier 2026-11-21
///
/// @functions
///  - _Handler: an EncryptedMessageHandler whose sends are recorded and answered by the test
///  - _Clock: the outbox's clock
///  - main(): the cases

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/encrypted_message_handler.dart';
import 'package:snowchat/core/crypto/identity_binding_exception.dart';
import 'package:snowchat/core/messaging/direct_outbox.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/features/chat/models/message.dart';

/// One send the outbox made.
class _Sent {
  _Sent(this.messageId, this.peer, this.type, this.text, this.metadata, this.ttl,
      this.replyToId, this.onAck);
  final String messageId;
  final String peer;
  final MessageType type;
  final String text;
  final Map<String, dynamic>? metadata;
  final int? ttl;
  final String? replyToId;
  final Function(dynamic)? onAck;
}

class _Handler extends Fake implements EncryptedMessageHandler {
  final sent = <_Sent>[];

  /// How a send is answered: an ack map, null (no ack ever), or a throw.
  Object? Function(_Sent send) answer = (s) => {'messageId': 'srv_${s.messageId}'};

  /// Whether Sealed Sender is active (the outbox never sends otherwise).
  bool sealed = true;

  @override
  bool get isSealedSenderAvailable => sealed;

  @override
  Future<void> sendSealedMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    required String clientMessageId,
    String? attachmentFileKey,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
    Function(dynamic)? onAck,
  }) async {
    final s = _Sent(clientMessageId, recipientId, type, text, metadata, ttlSeconds,
        replyToId, onAck);
    sent.add(s);
    final a = answer(s);
    if (a is Exception) throw a;
    if (a != null) onAck?.call(a);
  }
}

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 21, 12);
  void advance(Duration d) => now = now.add(d);
}

const _alice = 'snow0123456789abcdef0123456789abcdef';
const _bob = 'snow1123456789abcdef0123456789abcdef';

void main() {
  late SnowDatabase db;
  late _Handler handler;
  late _Clock clock;
  late bool connected;
  late StreamController<bool> connection;
  late List<(Uint8List, String)> uploads;
  late Future<String> Function(Uint8List, String) uploader;
  late Directory docs;
  late DirectOutbox outbox;

  DirectOutbox make({Duration ackTimeout = const Duration(seconds: 20)}) =>
      DirectOutbox(
        jobs: db.directOutboxDao,
        messages: db.messageDao,
        attachments: db.attachmentDao,
        handler: () => handler,
        isConnected: () => connected,
        connectionChanges: connection.stream,
        upload: (data, hash) => uploader(data, hash),
        documentsPath: () async => docs.path,
        now: () => clock.now,
        ackTimeout: ackTimeout,
      );

  setUp(() async {
    db = SnowDatabase(NativeDatabase.memory());
    handler = _Handler();
    clock = _Clock();
    connected = true;
    connection = StreamController<bool>.broadcast();
    uploads = [];
    uploader = (data, hash) async {
      uploads.add((data, hash));
      return '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';
    };
    docs = await Directory.systemTemp.createTemp('outbox');
    outbox = make();
  });

  tearDown(() async {
    await outbox.stop();
    await connection.close();
    await db.close();
    await docs.delete(recursive: true);
  });

  // Each stored row gets its own send time: (sender, date_sent, conversation)
  // is unique in local_messages.
  var sentOffset = 0;

  /// Store an outgoing message row the way the chat screen does.
  Future<void> stored(String id, String peer,
      {String text = 'hello', String type = 'text', String? metadata}) async {
    final sentAt = clock.now.millisecondsSinceEpoch + sentOffset++;
    await db.messageDao.insertOutgoingMessage(
      message: LocalMessagesCompanion(
        id: Value(id),
        conversationId: Value(peer),
        senderSnowchatId: const Value('snowmeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'),
        plaintext: Value(text),
        dateSent: Value(sentAt),
        dateReceived: Value(sentAt),
        type: Value(type),
        metadata: Value(metadata),
        read: const Value(true),
        outgoingStatus: const Value('sending'),
      ),
      conversationId: peer,
      snippetText: text,
      sentTimestamp: clock.now.millisecondsSinceEpoch,
    );
  }

  Future<String?> status(String id) async =>
      (await db.messageDao.getMessageById(id))?.outgoingStatus;

  test('queued offline, nothing leaves; on connect each peer goes in order, '
      'settled under the server id', () async {
    connected = false;
    await stored('m1', _alice);
    await stored('m2', _alice);
    await stored('m3', _bob);
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'one');
    await outbox.enqueueText(messageId: 'm2', peer: _alice, text: 'two');
    await outbox.enqueueText(messageId: 'm3', peer: _bob, text: 'three');
    await outbox.drain();
    expect(handler.sent, isEmpty);
    expect(await db.directOutboxDao.allJobs(), hasLength(3));

    connected = true;
    outbox.start();
    connection.add(true);
    await pumpEventQueue();
    await outbox.drain();
    expect(handler.sent.map((s) => s.messageId), ['m1', 'm3', 'm2']);
    expect(handler.sent.first.text, 'one');
    // Settled: the local row became the server's, `sent`; no job is left.
    expect(await db.messageDao.getMessageById('m1'), isNull);
    expect(await status('srv_m1'), 'sent');
    expect(await status('srv_m2'), 'sent');
    expect(await status('srv_m3'), 'sent');
    expect(await db.directOutboxDao.allJobs(), isEmpty);
  });

  test('a peer\'s next message waits until the one before it is acked; '
      'another peer does not wait', () async {
    await stored('a1', _alice);
    await stored('a2', _alice);
    await stored('b1', _bob);
    handler.answer = (s) => s.messageId == 'a1'
        ? {'error': {'code': 'INTERNAL_ERROR'}}
        : {'messageId': 'srv_${s.messageId}'};
    await outbox.enqueueText(messageId: 'a1', peer: _alice, text: 'x');
    await outbox.enqueueText(messageId: 'a2', peer: _alice, text: 'y');
    await outbox.enqueueText(messageId: 'b1', peer: _bob, text: 'z');
    await outbox.drain();
    expect(handler.sent.map((s) => s.messageId).toSet(), {'a1', 'b1'});
    expect(await status('a2'), 'sending');
    final a1 = await db.directOutboxDao.job('a1');
    expect(a1!.attempts, 1);
    expect(a1.nextAttemptAtMs,
        clock.now.millisecondsSinceEpoch + DirectOutbox.baseBackoff.inMilliseconds);

    // Not before the wait is over.
    await outbox.drain();
    expect(handler.sent.where((s) => s.messageId == 'a1'), hasLength(1));
    clock.advance(DirectOutbox.baseBackoff);
    handler.answer = (s) => {'messageId': 'srv_${s.messageId}'};
    await outbox.drain();
    expect(handler.sent.map((s) => s.messageId), ['a1', 'b1', 'a1', 'a2']);
    expect(await status('srv_a2'), 'sent');
  });

  test('the wait grows per attempt and stops growing at the cap', () {
    expect(DirectOutbox.backoff(1), DirectOutbox.baseBackoff);
    expect(DirectOutbox.backoff(2), DirectOutbox.baseBackoff * 2);
    expect(DirectOutbox.backoff(3), DirectOutbox.baseBackoff * 4);
    expect(DirectOutbox.backoff(40), DirectOutbox.maxBackoff);
  });

  test('no ack in time: later; an ack that comes after still settles it',
      () async {
    await outbox.stop();
    outbox = make(ackTimeout: const Duration(milliseconds: 50));
    await stored('m1', _alice);
    handler.answer = (s) => null;
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'x');
    await outbox.drain();
    expect((await db.directOutboxDao.job('m1'))!.attempts, 1);
    expect(await status('m1'), 'sending');

    handler.sent.single.onAck!({'messageId': 'srv_late'});
    await pumpEventQueue();
    expect(await status('srv_late'), 'sent');
    expect(await db.directOutboxDao.allJobs(), isEmpty);
  });

  test('Sealed Sender not active: nothing is sent (no non-sealed fallback), '
      'the message waits and leaves sealed once it is', () async {
    await stored('m1', _alice);
    handler.sealed = false;
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'x');
    await outbox.drain();
    expect(handler.sent, isEmpty);
    expect(await status('m1'), 'sending');
    expect((await db.directOutboxDao.job('m1'))!.attempts, 1);

    handler.sealed = true;
    clock.advance(DirectOutbox.baseBackoff);
    await outbox.drain();
    expect(handler.sent.map((s) => s.messageId), ['m1']);
    expect(await status('srv_m1'), 'sent');
  });

  test('no socket at the moment of sending (NOT_CONNECTED): later, not failed',
      () async {
    await stored('m1', _alice);
    handler.answer = (s) => {'error': {'code': 'NOT_CONNECTED'}};
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'x');
    await outbox.drain();
    expect(await status('m1'), 'sending');
    expect((await db.directOutboxDao.job('m1'))!.attempts, 1);
  });

  test('a refusal that will not change fails the message', () async {
    await stored('m1', _alice);
    handler.answer = (s) => {'error': {'code': 'USER_NOT_FOUND'}};
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'x');
    await outbox.drain();
    expect(await status('m1'), 'failed');
    expect(await db.directOutboxDao.allJobs(), isEmpty);
  });

  test('a forged identity binding fails the message', () async {
    await stored('m1', _alice);
    handler.answer = (s) => IdentityBindingInvalidException(
        peerSnowchatId: _alice, reason: IdentityBindingFailure.bindingRequired);
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'x');
    await outbox.drain();
    expect(await status('m1'), 'failed');
  });

  test('not taken within 24 hours: failed, even while offline', () async {
    connected = false;
    await stored('m1', _alice);
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'x');
    clock.advance(DirectOutbox.maxAge + const Duration(minutes: 1));
    await outbox.drain();
    expect(await status('m1'), 'failed');
    expect(handler.sent, isEmpty);
  });

  test('a failed message is sent again from its row, under the same id',
      () async {
    await stored('m1', _alice, text: 'again');
    handler.answer = (s) => {'error': {'code': 'USER_NOT_FOUND'}};
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'again');
    await outbox.drain();
    expect(await status('m1'), 'failed');

    handler.answer = (s) => {'messageId': 'srv_${s.messageId}'};
    expect(await outbox.retry('m1'), isTrue);
    await outbox.drain();
    expect(handler.sent.last.messageId, 'm1');
    expect(handler.sent.last.text, 'again');
    expect(await status('srv_m1'), 'sent');
    // Only a failed message can be sent again.
    expect(await outbox.retry('srv_m1'), isFalse);
  });

  test('a message deleted before it left is dropped, not sent', () async {
    connected = false;
    await stored('m1', _alice);
    await outbox.enqueueText(messageId: 'm1', peer: _alice, text: 'x');
    await db.messageDao.deleteMessage('m1');
    connected = true;
    await outbox.drain();
    expect(handler.sent, isEmpty);
    expect(await db.directOutboxDao.allJobs(), isEmpty);
  });

  group('attachments', () {
    Future<String> keep(String name, List<int> bytes) async {
      final rel = 'snowchat_attachments/$name';
      await Directory('${docs.path}/snowchat_attachments').create(recursive: true);
      await File('${docs.path}/$rel').writeAsBytes(bytes);
      return rel;
    }

    Future<void> attachmentRow(String messageId, String rel) =>
        db.attachmentDao.insertAttachment(LocalAttachmentsCompanion(
          id: Value('att_${messageId}_0'),
          messageId: Value(messageId),
          displayOrder: const Value(0),
          contentType: const Value('image/png'),
          fileName: const Value('a.png'),
          fileSize: const Value(3),
          localPath: Value(rel),
          transferState: const Value(0),
        ));

    test('uploaded from the kept copy, then sent with the file key; the row '
        'and the attachment get the server file id', () async {
      final rel = await keep('k.png', [1, 2, 3]);
      await stored('f1', _alice, type: 'file', text: 'a.png',
          metadata: jsonEncode({'fileName': 'a.png'}));
      await attachmentRow('f1', rel);
      await outbox.enqueueAttachment(
        messageId: 'f1',
        peer: _alice,
        kind: MessageType.file,
        text: 'a.png',
        relativePath: rel,
        fileName: 'a.png',
        mimeType: 'image/png',
        size: 3,
      );
      await outbox.drain();
      expect(uploads, hasLength(1));
      final sent = handler.sent.single;
      expect(sent.type, MessageType.file);
      expect(sent.metadata!['fileId'], '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f');
      expect(sent.metadata!['fileKey'], isA<String>());
      expect(sent.metadata!['attachments'], hasLength(1));
      final row = await db.messageDao.getMessageById('srv_f1');
      expect(row!.outgoingStatus, 'sent');
      expect(jsonDecode(row.metadata!)['fileId'],
          '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f');
      final att = await db.attachmentDao.getForMessage('srv_f1');
      expect(att.single.remoteFileId, '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f');
    });

    test('an upload that fails is tried again later, not failed; once '
        'uploaded it is not uploaded again', () async {
      final rel = await keep('k.png', [1, 2, 3]);
      await stored('f1', _alice, type: 'file', text: 'a.png');
      await attachmentRow('f1', rel);
      uploader = (data, hash) async => throw const SocketException('offline');
      await outbox.enqueueAttachment(
        messageId: 'f1', peer: _alice, kind: MessageType.file, text: 'a.png',
        relativePath: rel, fileName: 'a.png', mimeType: 'image/png', size: 3,
      );
      await outbox.drain();
      expect(await status('f1'), 'sending');
      expect(handler.sent, isEmpty);

      // Uploaded, then the send gets no ack: the next try only sends.
      var uploadCount = 0;
      uploader = (data, hash) async {
        uploadCount++;
        return '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';
      };
      handler.answer = (s) => {'error': {'code': 'INTERNAL_ERROR'}};
      clock.advance(DirectOutbox.maxBackoff);
      await outbox.drain();
      expect(uploadCount, 1);
      handler.answer = (s) => {'messageId': 'srv_${s.messageId}'};
      clock.advance(DirectOutbox.maxBackoff);
      await outbox.drain();
      expect(uploadCount, 1);
      expect(await status('srv_f1'), 'sent');
    });

    test('the kept copy is gone: failed', () async {
      await stored('f1', _alice, type: 'file', text: 'a.png');
      await outbox.enqueueAttachment(
        messageId: 'f1', peer: _alice, kind: MessageType.file, text: 'a.png',
        relativePath: 'snowchat_attachments/missing.png', fileName: 'a.png',
        mimeType: 'image/png', size: 3,
      );
      await outbox.drain();
      expect(await status('f1'), 'failed');
    });

    test('a failed attachment never uploaded is sent again from its kept copy',
        () async {
      final rel = await keep('k.png', [1, 2, 3]);
      await stored('f1', _alice, type: 'file', text: 'a.png',
          metadata: jsonEncode({'fileName': 'a.png', 'mimeType': 'image/png'}));
      await attachmentRow('f1', rel);
      await db.messageDao.updateOutgoingStatus('f1', 'failed');
      expect(await outbox.retry('f1'), isTrue);
      await outbox.drain();
      expect(uploads, hasLength(1));
      expect(await status('srv_f1'), 'sent');
    });
  });
}
