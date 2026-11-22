/// @file        message_queue_gv2_test.dart
/// @description What MessageQueue does for groups and the rooms it stores
///              into: the `gv2` rows of a REST fetch go to the local inbox and
///              the fetch repeats while the group queue has more (and only
///              while the rows are acknowledged); an envelope whose id was
///              acknowledged in this session is acknowledged again instead of
///              processed again; an envelope that names a v2 group in any id
///              field, and a server system line, are refused (acknowledged,
///              never decrypted, nothing stored); a non-sealed 1:1 message is
///              stored in its sender's room whatever conversation the envelope
///              names, and a retry response fills only a placeholder of the
///              same sender; a sealed 1:1 message that is a v2 invite goes to
///              the group actions and is consumed without a chat row.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (X1: what a blocked account sent is acknowledged and dropped, never retried). Earlier 2026-11-21 (a fetch asked for during one is not skipped). Earlier 2026-11-21 (a v2 invite is kept, with its message id, before it is acknowledged). Earlier 2026-11-20 (v1 groups removed: no Sender Key / name key cases; the room of a 1:1
///              message and the retry response are checked on a real in-memory database)
///
/// @functions
///  - main(): the test groups below.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/blocking/block_list.dart' show BlockedSenderException;
import 'package:snowchat/core/crypto/encrypted_message_handler.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/messaging/message_queue.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/api_endpoints.dart';
import 'package:snowchat/core/network/file_service.dart';
import 'package:snowchat/core/network/socket_manager.dart';
import 'package:snowchat/core/storage/daos/attachment_dao.dart';
import 'package:snowchat/core/storage/daos/conversation_dao.dart';
import 'package:snowchat/core/storage/daos/message_dao.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/features/chat/models/message.dart';
import 'package:snowchat/features/chat/providers/expiring_message_manager.dart';

const _me = 'snow0123456789abcdef0123456789abcdef';
const _peer = 'snowfedcba9876543210fedcba9876543210';
const _other = 'snow00112233445566778899aabbccddeeff';
final String _v2Group = 'ab' * 32;
const _cuid = 'cmb4x2k9d0001jz08abcd1234';

/// Answers GET /messages from a script, one response per fetch.
class _Api extends Fake implements ApiClient {
  final List<Map<String, Object?>> fetches = [];
  int gets = 0;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    expect(path, ApiEndpoints.fetchMessages);
    expect(queryParameters, isNull, reason: 'no parameter tells a group fetch');
    final data = gets < fetches.length
        ? fetches[gets]
        : <String, Object?>{'messages': <Object?>[]};
    gets++;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data as T?,
    );
  }
}

class _Socket extends Fake implements SocketManager {
  final List<String> acked = [];

  @override
  bool get isConnected => true;

  @override
  void sendMessageAck(List<String> messageIds) => acked.addAll(messageIds);
}

/// Decrypts every 1:1 wrapper to [wrapper].
class _Sessions extends Fake implements SignalSessionManager {
  Uint8List wrapper = Uint8List(0);
  int decrypts = 0;

  @override
  String peekDeviceIdForIncoming(String senderId, String? envelopeDeviceId) =>
      envelopeDeviceId ?? 'device';

  @override
  Future<Uint8List> decrypt(
    String senderId,
    String deviceId,
    Uint8List ciphertext,
    int messageType, {
    String? envelopeDeviceId,
  }) async {
    decrypts++;
    return wrapper;
  }
}

class _Handler extends Fake implements EncryptedMessageHandler {
  /// What the next sealed envelope decrypts to.
  Message? sealed;

  /// What the next non-sealed 1:1 envelope decrypts to.
  Message? incoming;
  int incomingDecrypts = 0;
  int sealedDecrypts = 0;

  /// Every decrypt finds the sender blocked (X1).
  bool senderBlocked = false;

  @override
  Future<Message> decryptSealedMessage(Map<String, dynamic> socketEvent) async {
    sealedDecrypts++;
    if (senderBlocked) throw const BlockedSenderException();
    return sealed!;
  }

  @override
  Future<Message> decryptIncomingMessage(Map<String, dynamic> socketEvent) async {
    incomingDecrypts++;
    if (senderBlocked) throw const BlockedSenderException();
    return incoming!;
  }

  @override
  Future<void> sendSealedReadReceipt({
    required String recipientId,
    required List<String> readIds,
  }) async {}
}

class _Messages extends Fake implements MessageDao {
  @override
  Future<LocalMessage?> getMessageById(String messageId) async => null;
}

/// Anything that would create or change a conversation is not implemented
/// here and fails the test.
class _Conversations extends Fake implements ConversationDao {}

class _Attachments extends Fake implements AttachmentDao {}

class _Files extends Fake implements FileService {}

class _Expiring extends Fake implements ExpiringMessageManager {}

class _Db extends Fake implements SnowDatabase {}

void main() {
  // The message banner of a stored 1:1 message needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Api api;
  late _Socket socket;
  late _Sessions sessions;
  late _Handler handler;
  late MessageQueue queue;

  setUp(() {
    api = _Api();
    socket = _Socket();
    sessions = _Sessions();
    handler = _Handler();
    queue = MessageQueue(
      sessionManager: sessions,
      e2eeHandler: handler,
      messageDao: _Messages(),
      conversationDao: _Conversations(),
      attachmentDao: _Attachments(),
      fileService: _Files(),
      expiringManager: _Expiring(),
      database: _Db(),
      apiClient: api,
      socketManager: socket,
      myIdResolver: () => _me,
    );
  });

  Map<String, Object?> page(List<Object?> gv2, {bool more = false}) => {
    'gv2': gv2,
    'gv2More': more,
    'messages': <Object?>[],
  };

  group('the gv2 rows of a fetch', () {
    test('go to the local inbox, and the fetch repeats while the group queue '
        'has more', () async {
      api.fetches.addAll([
        page(['row 1', 'row 2'], more: true),
        page(['row 3'], more: true),
        page(['row 4']),
      ]);
      final seen = <List<dynamic>>[];
      queue.onGv2Rows = (rows) async {
        seen.add(rows);
        return true;
      };
      await queue.fetchPending();
      expect(seen, [
        ['row 1', 'row 2'],
        ['row 3'],
        ['row 4'],
      ]);
      expect(api.gets, 3);
    });

    test('rows that were not acknowledged are not fetched again in a loop', () async {
      api.fetches.addAll([
        page(['row 1'], more: true),
        page(['row 1'], more: true),
      ]);
      var calls = 0;
      queue.onGv2Rows = (rows) async {
        calls++;
        return false;
      };
      await queue.fetchPending();
      expect(api.gets, 1);
      expect(calls, 1);
    });

    test('a fetch asked for while one runs is not skipped: it shares the '
        'running one, which fetches once more after', () async {
      // (A fetch that started before the runtime took group rows left them
      // on the server; the runtime's fetch, asked meanwhile, was skipped.)
      api.fetches.addAll([page(['row 1']), page(['row 2'])]);
      final seen = <List<dynamic>>[];
      queue.onGv2Rows = (rows) async {
        seen.add(rows);
        return true;
      };
      final first = queue.fetchPending();
      final second = queue.fetchPending();
      await Future.wait([first, second]);
      // One after the other, never two requests at once.
      expect(api.gets, 2);
      expect(seen, [
        ['row 1'],
        ['row 2'],
      ]);
    });

    test('an inbox that throws does not break the fetch of 1:1 messages', () async {
      api.fetches.add(page(['row 1'], more: true));
      queue.onGv2Rows = (rows) async => throw StateError('the database');
      await queue.fetchPending();
      expect(api.gets, 1);
    });

    test('with group protocol v2 off the rows stay where they are', () async {
      api.fetches.add(page(['row 1'], more: true));
      await queue.fetchPending();
      expect(api.gets, 1);
    });

    test('a queue that never ends is not followed for ever', () async {
      for (var i = 0; i < 50; i++) {
        api.fetches.add(page(['row $i'], more: true));
      }
      queue.onGv2Rows = (rows) async => true;
      await queue.fetchPending();
      expect(api.gets, 20);
    });
  });

  /// A decrypted 1:1 text from [sender].
  Message text(String id, String sender, {Map<String, dynamic>? metadata}) =>
      Message(
        id: id,
        // What the handler fills in is not what the queue stores under.
        conversationId: _cuid,
        senderSnowchatId: sender,
        plaintext: 'hello $id',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        type: MessageType.text,
        status: MessageStatus.delivered,
        metadata: metadata,
      );

  group('an envelope that names a v2 group', () {
    for (final field in ['groupChatId', 'groupId', 'conversationId']) {
      test('in `$field` is refused: acknowledged, never decrypted, nothing '
          'stored', () async {
        handler.incoming = text('m1', _peer);
        queue.enqueue({
          'id': 'm1',
          'type': 'e2ee_text',
          'senderSnowchatId': _peer,
          field: _v2Group,
          'encryptedContent': base64Encode([1, 2, 3]),
        });
        await queue.waitForIdle();
        queue.flushAcks();
        expect(socket.acked, ['m1']);
        expect(handler.incomingDecrypts, 0);
        expect(queue.depth, 0);
      });
    }

    test('an id that only looks like one names no group', () {
      for (final field in ['groupChatId', 'groupId', 'conversationId']) {
        expect(SocketManager.namesV2Group({field: _v2Group}), isTrue);
        expect(SocketManager.namesV2Group({field: _cuid}), isFalse);
        expect(SocketManager.namesV2Group({field: _peer}), isFalse);
      }
      expect(SocketManager.namesV2Group({'messageId': _v2Group}), isFalse);
      expect(SocketManager.namesV2Group(const <String, Object?>{}), isFalse);
      expect(SocketManager.namesV2Group(null), isFalse);
      expect(SocketManager.namesV2Group('x'), isFalse);
    });
  });

  test('what a blocked account sent — a sealed message, a sealed control, a '
      'non-sealed 1:1 — is acknowledged and dropped: decrypted once, never '
      'stored, never retried', () async {
    // (The stores of this test fail when they are written to.)
    handler.senderBlocked = true;
    queue.enqueue({
      'id': 'b1',
      'type': 'sealed',
      'sealedContent': base64Encode([1, 2, 3]),
    });
    queue.enqueue({
      'id': 'b2',
      'type': 'sealed_control',
      'sealedContent': base64Encode([4, 5, 6]),
    });
    queue.enqueue({
      'id': 'b3',
      'type': 'e2ee_text',
      'senderSnowchatId': _peer,
      'encryptedContent': base64Encode([7, 8, 9]),
    });
    await queue.waitForIdle();
    queue.flushAcks();
    expect(socket.acked.toSet(), {'b1', 'b2', 'b3'});
    expect(handler.sealedDecrypts, 2, reason: 'once each, no retry');
    expect(handler.incomingDecrypts, 1);
    expect(queue.depth, 0);
  });

  test('a server system line is refused wherever it points: acknowledged, '
      'never stored', () async {
    // (The stores of this test fail when they are written to.)
    queue.enqueue({
      'id': 's1',
      'type': 'system',
      'conversationId': _peer,
      'metadata': {'text': 'Bob was removed'},
    });
    queue.enqueue({'id': 's2', 'type': 'system', 'groupChatId': _cuid});
    await queue.waitForIdle();
    queue.flushAcks();
    expect(socket.acked, ['s1', 's2']);
    expect(queue.depth, 0);
  });

  group('an id acknowledged in this session', () {
    test('is acknowledged again when it comes again, not processed again', () async {
      // A session reset is consumed without a row — nothing to dedupe on.
      handler.incoming = text('r1', _peer, metadata: {'isSessionReset': true});
      Map<String, dynamic> reset() => {
        'id': 'r1',
        'type': 'e2ee_text',
        'senderSnowchatId': _peer,
        'encryptedContent': base64Encode([1, 2, 3]),
      };
      queue.enqueue(reset());
      await queue.waitForIdle();
      queue.flushAcks();
      expect(handler.incomingDecrypts, 1);
      expect(socket.acked.toSet(), {'r1'});
      final acksBefore = socket.acked.length;

      // Fetched again before the server applied the acknowledgement.
      queue.enqueue(reset());
      expect(queue.depth, 0);
      await queue.waitForIdle();
      queue.flushAcks();
      expect(handler.incomingDecrypts, 1,
          reason: 'a second decrypt breaks the session');
      expect(socket.acked.length, acksBefore + 1);
      expect(socket.acked.last, 'r1');
    });
  });

  group('the room of a non-sealed 1:1 message (real database)', () {
    late SnowDatabase db;
    late MessageQueue stored;

    setUp(() {
      db = SnowDatabase(NativeDatabase.memory());
      stored = MessageQueue(
        sessionManager: sessions,
        e2eeHandler: handler,
        messageDao: db.messageDao,
        conversationDao: db.conversationDao,
        attachmentDao: _Attachments(),
        fileService: _Files(),
        expiringManager: _Expiring(),
        database: db,
        apiClient: api,
        socketManager: socket,
        myIdResolver: () => _me,
      );
    });
    tearDown(() => db.close());

    for (final named in [_other, _cuid, null]) {
      test('is its sender\'s, whatever the envelope names ($named)', () async {
        handler.incoming = text('m1', _peer);
        stored.enqueue({
          'id': 'm1',
          'type': 'e2ee_text',
          'senderSnowchatId': _peer,
          'conversationId': ?named,
          'encryptedContent': base64Encode([1, 2, 3]),
        });
        await stored.waitForIdle();
        final row = await db.messageDao.getMessageById('m1');
        expect(row!.conversationId, _peer);
        expect(row.senderSnowchatId, _peer);
        final rooms = await db.conversationDao.getAllConversations();
        expect(rooms.map((c) => c.id), [_peer]);
        stored.flushAcks();
        expect(socket.acked, ['m1']);
      });
    }

    test('a retry response fills only a placeholder of the same sender',
        () async {
      // A placeholder of _other's message, in _other's room.
      await db.conversationDao.findOrCreate(
        id: _other,
        type: 'direct',
        participantIds: [_me, _other],
      );
      await db.messageDao.upsertMessage(LocalMessagesCompanion(
        id: const Value('lost-1'),
        conversationId: const Value(_other),
        senderSnowchatId: const Value(_other),
        plaintext: const Value(''),
        dateSent: const Value(1),
        dateReceived: const Value(2),
        type: const Value('system'),
        outgoingStatus: const Value('decryption_failed'),
      ));

      // _peer answers as if it were the resend of that message.
      handler.incoming = text('m2', _peer,
          metadata: {'isRetry': true, 'originalMessageId': 'lost-1'});
      stored.enqueue({
        'id': 'm2',
        'type': 'e2ee_text',
        'senderSnowchatId': _peer,
        'encryptedContent': base64Encode([1, 2, 3]),
      });
      await stored.waitForIdle();

      final placeholder = await db.messageDao.getMessageById('lost-1');
      expect(placeholder!.outgoingStatus, 'decryption_failed');
      expect(placeholder.plaintext, isEmpty);
      // The answer lands as a message of its own sender, in that room.
      final row = await db.messageDao.getMessageById('m2');
      expect(row!.conversationId, _peer);

      // The real sender's resend fills it.
      handler.incoming = text('m3', _other,
          metadata: {'isRetry': true, 'originalMessageId': 'lost-1'});
      stored.enqueue({
        'id': 'm3',
        'type': 'e2ee_text',
        'senderSnowchatId': _other,
        'encryptedContent': base64Encode([1, 2, 3]),
      });
      await stored.waitForIdle();
      final filled = await db.messageDao.getMessageById('lost-1');
      expect(filled!.outgoingStatus, 'delivered');
      expect(filled.plaintext, 'hello m3');
      // It has no row of its own and is acknowledged at once — not retried
      // and dead-lettered for want of one.
      expect(await db.messageDao.getMessageById('m3'), isNull);
      stored.flushAcks();
      expect(socket.acked, containsAll(['m2', 'm3']));
      expect(stored.depth, 0);
    });
  });

  group('a v2 invite on the sealed 1:1 path', () {
    final inviteBytes = Uint8List.fromList(List.generate(166, (i) => i));
    Message invite({Object? encoded}) => Message(
      id: 'i1',
      conversationId: _peer,
      senderSnowchatId: _peer,
      plaintext: '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      type: MessageType.system,
      status: MessageStatus.delivered,
      metadata: {
        '_isGroupInviteV2': true,
        'invite': encoded ?? base64Encode(inviteBytes),
      },
    );

    for (final type in ['sealed', 'sealed_control']) {
      test('($type) is kept (with its message id) before it is consumed: '
          'acknowledged, no chat row asked for', () async {
        handler.sealed = invite();
        final seen = <(String, Uint8List, String)>[];
        var ackedWhenKept = <String>{};
        queue.onGv2Invite = (sender, bytes, messageId) async {
          ackedWhenKept = socket.acked.toSet();
          seen.add((sender, bytes, messageId));
        };
        queue.enqueue({'id': 'i1', 'type': type, 'sealedContent': 'AAAA'});
        await queue.waitForIdle();
        queue.flushAcks();
        expect(seen.single.$1, _peer);
        expect(seen.single.$2, inviteBytes);
        expect(seen.single.$3, 'i1');
        expect(ackedWhenKept, isEmpty, reason: 'kept before acknowledged');
        expect(socket.acked.toSet(), {'i1'});
        expect(queue.depth, 0);
      });
    }

    test('with nothing to keep it, or when keeping it fails (the database), '
        'it is still consumed — never a chat message', () async {
      handler.sealed = invite();
      queue.enqueue({'id': 'i1', 'type': 'sealed', 'sealedContent': 'AAAA'});
      await queue.waitForIdle();
      queue.flushAcks();
      expect(socket.acked.toSet(), {'i1'});

      queue.onGv2Invite = (sender, bytes, id) async => throw StateError('disk');
      handler.sealed = invite();
      queue.enqueue({'id': 'i2', 'type': 'sealed', 'sealedContent': 'AAAA'});
      await queue.waitForIdle();
      queue.flushAcks();
      expect(socket.acked.toSet(), {'i1', 'i2'});
    });

    test('an invite that is not base64 is consumed without reaching the '
        'group actions', () async {
      var calls = 0;
      queue.onGv2Invite = (sender, bytes, id) async => calls++;
      handler.sealed = invite(encoded: 'not base64!');
      queue.enqueue({'id': 'i1', 'type': 'sealed', 'sealedContent': 'AAAA'});
      await queue.waitForIdle();
      queue.flushAcks();
      expect(calls, 0);
      expect(socket.acked.toSet(), {'i1'});
    });
  });
}
