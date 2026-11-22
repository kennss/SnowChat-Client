/// @file        gv2_chat_actions_test.dart
/// @description Tests for what a chat does in a group protocol v2 group
///              (Gv2ChatActions): a message is queued and stored in one
///              transaction under its final id, an unsend names the 16-byte
///              id the own row keeps, the history is cleared by a queued
///              notice, and a leave takes this account's messages back
///              first. A real runtime over an in-memory database; the group
///              server is not reachable, so nothing leaves the outbox.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (P5.6: leaving with one's messages unsends nothing when the leave cannot be made). Earlier 2026-11-21 (no autoAccept). Earlier 2026-11-20 (the runtime takes the server keys this build trusts)
///
/// @functions
///  - main(): the test groups
///  - _Sink / _Crypto / _Backup: what the runtime needs and these tests do
///    not look at
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_backup.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_content.dart';
import 'package:snowchat/core/group_v2/gv2_envelope.dart';
import 'package:snowchat/core/group_v2/gv2_groups.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_credentials.dart';
import 'package:snowchat/core/group_v2/gv2_messaging.dart';
import 'package:snowchat/core/group_v2/gv2_outbox.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise_crypto.dart';
import 'package:snowchat/core/group_v2/gv2_runtime.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart';
import 'package:snowchat/core/messaging/gv2_message_sink.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/chat/providers/gv2_chat_actions.dart';

import '../../core/group_v2/gv2_test_support.dart';

class _Crypto extends Fake implements Gv2PairwiseCrypto {}

class _Backup implements Gv2BackupApi {
  @override
  Future<Gv2BackupBlob> fetch() async => const Gv2BackupBlob(null, null);

  @override
  Future<String?> store(Uint8List blob, String? ifMatch) async => 'tag';
}

class _Sink implements Gv2MessageSink {
  @override
  Future<void> message(Gv2IncomingMessage message) async {}

  @override
  Future<void> unsent({
    required String groupId,
    required String localMessageId,
    required String senderSnowId,
  }) async {}

  @override
  Future<void> historyCleared({
    required String groupId,
    required int beforeMs,
    required String bySnowId,
  }) async {}

  @override
  Future<bool> waiting({
    required String groupId,
    required String localMessageId,
    required int sentAtMs,
    required int receivedAtMs,
  }) async => false;

  @override
  Future<void> outgoing({
    required String groupId,
    required String localMessageId,
    required bool sent,
  }) async {}

  @override
  void committed(Gv2SinkEvent event) {}

  @override
  void groupChanged(String groupId, List<Gv2Entry> applied) {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SnowDatabase db;
  late Gv2TestGroup g;
  late Gv2TestPerson alice;
  late Gv2Runtime runtime;
  late Gv2ChatActions actions;
  Gv2Runtime? handedOut;

  setUp(() async {
    db = SnowDatabase(NativeDatabase.memory());
    g = Gv2TestGroup('chat');
    alice = g.person('alice');
    g.create(alice);
    await db.gv2Store.insertCreated(
      masterKey: g.masterKey,
      myCiphertext: alice.ciphertext,
      state: g.state,
      headSig: g.headSig(0),
      nowMs: 1794600000000,
    );
    await db.conversationDao.findOrCreate(
      id: g.id,
      type: 'group',
      participantIds: const [],
      title: 'Snow',
      groupId: g.id,
    );
    runtime = Gv2Runtime(
      db: db,
      mySnowId: alice.snowId,
      // As the app's API client fails when the server cannot be reached.
      authenticatedPost: (path) async => throw DioException.connectionError(
        requestOptions: RequestOptions(path: path),
        reason: 'no server',
      ),
      pinnedAccountKey: (_) async => null,
      crypto: _Crypto(),
      myDeviceId: () async => '11111111-1111-4111-8111-111111111111',
      memberKey: (groupId) async => Gv2SigningKey.fromSeed(
        gv2DeriveMemberSeed(alice.accountSeed, groupId),
      ),
      memberCert: (_, _) async => Uint8List(64),
      accountPublicKey: () async => alice.accountPub,
      ack: (_) async {},
      sink: _Sink(),
      sendInvite: (_, _) async => false,
      backupApi: _Backup(),
      backupKey: () async => gv2DeriveBackupKey(alice.accountSeed),
      trustedKeys: gv2TrustedServerKeysFor('dev')!,
      isBlocked: (_) async => false,
      // Nothing listens here: the group server is "not reachable".
      baseUrl: 'http://127.0.0.1:9',
    );
    handedOut = runtime;
    actions = Gv2ChatActions(
      groupId: g.id,
      runtime: () => handedOut,
      messages: db.messageDao,
      attachments: db.attachmentDao,
      groups: db.gv2Store,
      mySnowId: alice.snowId,
    );
  });
  tearDown(() async {
    runtime.dispose();
    await db.close();
  });

  /// The queued contents of the outbox, in the order they were written.
  Future<List<Gv2OutboxContent>> queued() async => [
    for (final row in await db.gv2OutboxStore.allRows())
      if (row.kind == Gv2OutboxKind.content)
        Gv2OutboxContent.decode(row.payload)!,
  ];

  group('a message', () {
    test('is queued and stored together, under the id every member derives, '
        'as "sending"', () async {
      final id = await actions.send(
        text: 'hello',
        snippet: 'hello',
        ttlSeconds: 60,
        replyToId: 'r1',
        replyToPreview: 'before',
        replyToSenderId: alice.snowId,
      );

      final content = (await queued()).single;
      expect(content.silent, isFalse);
      expect(content.expiresIn, 60);
      expect(
        id,
        gv2Hex(
          gv2LocalMessageId(
            groupId: g.groupId,
            senderAccountId: gv2AccountIdOfSnowId(alice.snowId),
            messageId: content.messageId,
          ),
        ),
      );
      // What goes to the group is the app's payload — nothing of this
      // device's own bookkeeping.
      final sent = Gv2Content.decode(content.plaintext) as Gv2MessageContent;
      expect(jsonDecode(utf8.decode(sent.payload)), {
        'text': 'hello',
        'type': 'text',
        'ttl': 60,
        'replyToId': 'r1',
        'replyToPreview': 'before',
        'replyToSenderId': alice.snowId,
      });

      final row = (await db.messageDao.getMessageById(id))!;
      expect(row.conversationId, g.id);
      expect(row.senderSnowchatId, alice.snowId);
      expect(row.plaintext, 'hello');
      expect(row.type, 'text');
      expect(row.outgoingStatus, 'sending');
      expect(row.read, isTrue);
      expect(row.dateSent, content.timestampMs);
      expect(row.expiresIn, 60);
      expect(row.expireStarted, content.timestampMs);
      expect(row.replyToId, 'r1');
      expect(jsonDecode(row.metadata!), {
        gv2OwnMessageIdKey: gv2Hex(content.messageId),
      });
      expect(Gv2ChatActions.ownMessageId(row), content.messageId);

      final conversation = (await db.conversationDao.getConversation(g.id))!;
      expect(conversation.lastMessageText, 'hello');
      expect(conversation.unreadCount, 0);
    });

    test('a file message keeps its metadata and gets its attachment row in '
        'the same step', () async {
      final id = await actions.send(
        text: 'a.pdf',
        snippet: 'a.pdf',
        type: 'file',
        metadata: {'fileId': 'f1', 'fileKey': 'k'},
        attachment: (id) => LocalAttachmentsCompanion(
          id: Value('att_${id}_0'),
          messageId: Value(id),
          displayOrder: const Value(0),
          contentType: const Value('application/pdf'),
          fileName: const Value('a.pdf'),
          fileSize: const Value(10),
          remoteFileId: const Value('f1'),
          localPath: const Value('snowchat_attachments/f1.pdf'),
          transferState: const Value(0),
        ),
      );
      final row = (await db.messageDao.getMessageById(id))!;
      expect(row.type, 'file');
      final metadata = jsonDecode(row.metadata!) as Map;
      expect(metadata['fileId'], 'f1');
      expect(metadata['fileKey'], 'k');
      expect(metadata[gv2OwnMessageIdKey], hasLength(32));
      expect((await db.attachmentDao.getForMessage(id)).single.remoteFileId, 'f1');
      // The key that names the own message stays on this device.
      final sent =
          Gv2Content.decode((await queued()).single.plaintext)
              as Gv2MessageContent;
      expect(
        (jsonDecode(utf8.decode(sent.payload)) as Map)['metadata'],
        {'fileId': 'f1', 'fileKey': 'k'},
      );
    });

    test('two messages written in the same millisecond are both stored', () async {
      final a = await actions.send(text: 'one', snippet: 'one');
      final b = await actions.send(text: 'two', snippet: 'two');
      final rows = await db.messageDao.getMessagesForConversation(g.id);
      expect({for (final r in rows) r.id}, {a, b});
      expect({for (final r in rows) r.dateSent}, hasLength(2));
    });

    test('in a group this account is not in nothing is queued and nothing '
        'stored', () async {
      await db.gv2Store.setHold(g.id, Gv2Hold.frozen, evidence: Uint8List(1));
      await expectLater(
        actions.send(text: 'no', snippet: 'no'),
        throwsA(isA<Gv2NotSendable>()),
      );
      expect(await queued(), isEmpty);
      expect(await db.messageDao.getMessagesForConversation(g.id), isEmpty);
    });

    test('when the attachment row cannot be written, the message is neither '
        'queued nor stored', () async {
      await expectLater(
        actions.send(
          text: 'a.pdf',
          snippet: 'a.pdf',
          type: 'file',
          attachment: (_) => throw StateError('the store failed'),
        ),
        throwsStateError,
      );
      expect(await queued(), isEmpty);
      expect(await db.messageDao.getMessagesForConversation(g.id), isEmpty);
    });

    test('without a runtime nothing can be written', () async {
      handedOut = null;
      await expectLater(
        actions.send(text: 'no', snippet: 'no'),
        throwsA(isA<Gv2NotSendable>()),
      );
      expect(await actions.unsend('x'), isFalse);
    });
  });

  group('taking a message back', () {
    test('queues an unsend that names the message\'s 16-byte id, silently', () async {
      final id = await actions.send(text: 'oops', snippet: 'oops');
      final messageId = (await queued()).single.messageId;
      expect(await actions.unsend(id), isTrue);
      final unsend = (await queued()).last;
      expect(unsend.silent, isTrue);
      final content = Gv2Content.decode(unsend.plaintext) as Gv2UnsendContent;
      expect(content.messageId, messageId);
      // The own copy is the caller's to remove.
      expect(await db.messageDao.getMessageById(id), isNotNull);
    });

    test('is refused for a message of someone else, of another chat, or one '
        'that keeps no id', () async {
      Future<void> insert(String id, {String? sender, String? chat, String? meta}) =>
          db.messageDao.upsertMessage(
            LocalMessagesCompanion(
              id: Value(id),
              conversationId: Value(chat ?? g.id),
              senderSnowchatId: Value(sender ?? alice.snowId),
              plaintext: const Value('x'),
              dateSent: Value(id.hashCode),
              dateReceived: const Value(1),
              type: const Value('text'),
              metadata: Value(meta),
            ),
          );
      final key = jsonEncode({gv2OwnMessageIdKey: '00' * 16});
      await insert('theirs', sender: 'snow000000000000000000000000000000b0', meta: key);
      await insert('elsewhere', chat: 'other', meta: key);
      await insert('noKey');
      await insert('shortKey', meta: jsonEncode({gv2OwnMessageIdKey: '00'}));
      await insert('notJson', meta: 'x');
      for (final id in ['theirs', 'elsewhere', 'noKey', 'shortKey', 'notJson', 'gone']) {
        expect(await actions.unsend(id), isFalse, reason: id);
      }
      expect(await queued(), isEmpty);
    });

    test('is refused, not thrown, where nothing can be said', () async {
      final id = await actions.send(text: 'oops', snippet: 'oops');
      await db.gv2Store.setHold(g.id, Gv2Hold.frozen, evidence: Uint8List(1));
      expect(await actions.unsend(id), isFalse);
    });
  });

  test('clearing the history queues a silent notice for everything sent up '
      'to now', () async {
    final before = DateTime.now().millisecondsSinceEpoch;
    await actions.clearHistory();
    final clear = (await queued()).single;
    expect(clear.silent, isTrue);
    final content =
        Gv2Content.decode(clear.plaintext) as Gv2ClearHistoryContent;
    expect(content.beforeMs, greaterThanOrEqualTo(before));
  });

  group('leaving', () {
    test('with "delete my messages", when the leave cannot be made (no '
        'server here), nothing is unsent and it says so', () async {
      await actions.send(text: 'one', snippet: 'one');
      await actions.send(text: 'two', snippet: 'two');
      final ids = [for (final c in await queued()) c.messageId];
      // Someone else's message is not this account's to take back.
      await db.messageDao.upsertMessage(
        LocalMessagesCompanion(
          id: const Value('theirs'),
          conversationId: Value(g.id),
          senderSnowchatId: const Value('snow000000000000000000000000000000b0'),
          plaintext: const Value('x'),
          dateSent: const Value(5),
          dateReceived: const Value(5),
          type: const Value('text'),
          metadata: Value(jsonEncode({gv2OwnMessageIdKey: 'ff' * 16})),
        ),
      );

      await expectLater(
        actions.leave(deleteMyMessages: true),
        throwsA(
          isA<Gv2GroupException>().having(
            (e) => e.reason,
            'reason',
            Gv2GroupFailure.unavailable,
          ),
        ),
      );
      final unsends = [
        for (final c in await queued())
          if (Gv2Content.decode(c.plaintext) case Gv2UnsendContent(:final messageId))
            messageId,
      ];
      // Unsent messages of an account that stays in the group would be gone
      // for everyone: none goes out unless the leave can follow.
      expect(unsends, isEmpty);
      expect(ids, hasLength(2));
      // Still a member: nothing was removed.
      expect(
        (await db.gv2Store.group(g.id))!.membership,
        Gv2Membership.active,
      );
    });

    test('a plain leave queues no unsend', () async {
      await actions.send(text: 'one', snippet: 'one');
      await expectLater(actions.leave(), throwsA(isA<Gv2GroupException>()));
      expect(await queued(), hasLength(1));
    });

    test('a frozen group is erased from this device, with or without "delete '
        'my messages"', () async {
      await actions.send(text: 'one', snippet: 'one');
      await db.gv2Store.setHold(g.id, Gv2Hold.frozen, evidence: Uint8List(1));
      await actions.leave(deleteMyMessages: true);
      expect(await db.gv2Store.group(g.id), isNull);
    });
  });
}
