/// @file        gv2_message_sink_test.dart
/// @description Gv2AppMessageSink on a real (in-memory) database: a verified
///              v2 group message becomes a message row and updates its
///              conversation; an unsend and a cleared history remove rows
///              and attachment rows inside the transaction and files only
///              after the commit; nothing is announced for what was not
///              committed. And the app's message payload: round trip and
///              what is refused.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (the cap on "cannot be read" places; outgoing(): the status of this account's message). Earlier 2026-11-20
///
/// @functions
///  - main(): the test groups below.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_messaging.dart';
import 'package:snowchat/core/messaging/gv2_message_sink.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';

import '../group_v2/gv2_test_support.dart';

const _t0 = 1794600000000;

Uint8List _json(Map<String, Object?> m) =>
    Uint8List.fromList(utf8.encode(jsonEncode(m)));

void main() {
  late SnowDatabase db;
  late Gv2TestGroup g;
  late Directory dir;
  late Gv2AppMessageSink sink;
  late List<Gv2StoredMessage> stored;
  late List<String> removed;
  late List<String> waitingTold;
  late List<String> changed;
  var viewing = false;
  var n = 0;

  setUp(() async {
    db = SnowDatabase(NativeDatabase.memory());
    g = Gv2TestGroup('sink')..create(Gv2TestGroup('sink').person('alice'));
    await db.gv2Store.insertCreated(
      masterKey: g.masterKey,
      myCiphertext: g.person('alice').ciphertext,
      state: g.state,
      headSig: g.headSig(0),
      nowMs: _t0,
    );
    dir = Directory.systemTemp.createTempSync('gv2_sink_test');
    stored = [];
    removed = [];
    waitingTold = [];
    changed = [];
    viewing = false;
    n = 0;
    sink = Gv2AppMessageSink(
      groups: db.gv2Store,
      messages: db.messageDao,
      conversations: db.conversationDao,
      attachments: db.attachmentDao,
      viewing: (_) => viewing,
      documentsDir: () async => dir.path,
      onStored: stored.add,
      onRemoved: removed.add,
      onWaiting: waitingTold.add,
      onGroupChanged: (id, _) => changed.add(id),
      nowMs: () => _t0 + 5000,
    );
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  const bob = 'snow000000000000000000000000000000b0';

  Gv2IncomingMessage incoming(
    Map<String, Object?> payload, {
    String? id,
    String sender = bob,
    int? sentAtMs,
  }) => Gv2IncomingMessage(
    groupId: g.id,
    localMessageId: id ?? 'id-${n++}'.padRight(64, '0'),
    senderSnowId: sender,
    senderDeviceId: 'd' * 36,
    sentAtMs: sentAtMs ?? _t0 + 1000,
    receivedAtMs: _t0 + 2000,
    payload: _json(payload),
  );

  group('payload', () {
    test('round trips with every field', () {
      final payload = Gv2AppMessagePayload(
        text: 'photo.jpg',
        type: 'file',
        metadata: {'fileId': 'f1', 'size': 10},
        ttlSeconds: 60,
        replyToId: 'r',
        replyToPreview: 'earlier',
        replyToSenderId: bob,
      );
      final back = Gv2AppMessagePayload.tryDecode(payload.encode())!;
      expect(back.text, 'photo.jpg');
      expect(back.type, 'file');
      expect(back.metadata, {'fileId': 'f1', 'size': 10});
      expect(back.ttlSeconds, 60);
      expect(back.replyToId, 'r');
      expect(back.replyToPreview, 'earlier');
      expect(back.replyToSenderId, bob);
      // A plain text carries nothing it does not need.
      expect(
        jsonDecode(utf8.decode(Gv2AppMessagePayload(text: 'hi').encode())),
        {'text': 'hi', 'type': 'text'},
      );
    });

    test(
      'what is not a payload is not read; an unknown type reads as text',
      () {
        expect(
          Gv2AppMessagePayload.tryDecode(Uint8List.fromList([1, 2])),
          isNull,
        );
        expect(
          Gv2AppMessagePayload.tryDecode(Uint8List.fromList(utf8.encode('[]'))),
          isNull,
        );
        for (final bad in <Map<String, Object?>>[
          {'type': 'text'}, // no text
          {'text': 5},
          {'text': 'x', 'type': 7},
          {'text': 'x', 'metadata': 'no'},
          {'text': 'x', 'ttl': '60'},
          {'text': 'x', 'ttl': -1},
          {'text': 'x', 'ttl': gv2MaxTtlSeconds + 1},
          {'text': 'x', 'replyToId': 1},
        ]) {
          expect(
            Gv2AppMessagePayload.tryDecode(_json(bad)),
            isNull,
            reason: '$bad',
          );
        }
        expect(
          Gv2AppMessagePayload.tryDecode(
            _json({'text': 'x', 'type': 'poll'}),
          )!.type,
          'text',
        );
        expect(
          () => Gv2AppMessagePayload(text: 'x', type: 'poll'),
          throwsArgumentError,
        );
        expect(
          () => Gv2AppMessagePayload(text: 'x', ttlSeconds: -1),
          throwsArgumentError,
        );
      },
    );
  });

  group('a message', () {
    test(
      'becomes a message row, creates the conversation and updates it',
      () async {
        final m = incoming({
          'text': 'hello',
          'type': 'text',
          'ttl': 30,
          'replyToId': 'r1',
          'replyToPreview': 'before',
          'replyToSenderId': bob,
        });
        await sink.message(m);

        final row = (await db.messageDao.getMessageById(m.localMessageId))!;
        expect(row.conversationId, g.id);
        expect(row.senderSnowchatId, bob);
        expect(row.plaintext, 'hello');
        expect(row.type, 'text');
        expect(row.dateSent, _t0 + 1000);
        expect(row.dateReceived, _t0 + 2000);
        expect(row.expiresIn, 30);
        expect(row.expireStarted, 0);
        expect(row.read, isFalse);
        expect(row.replyToId, 'r1');
        expect(row.replyToPreview, 'before');
        expect(row.replyToSenderId, bob);

        final conversation = (await db.conversationDao.getConversation(g.id))!;
        expect(conversation.type, 'group');
        expect(conversation.groupId, g.id);
        expect(conversation.title, 'Snow');
        expect(conversation.lastMessageText, 'hello');
        expect(conversation.lastMessageId, m.localMessageId);
        expect(conversation.unreadCount, 1);

        // Announced only once the messaging layer says it committed.
        expect(stored, isEmpty);
        sink.committed(Gv2MessageStored(m));
        expect(stored.single.messageId, m.localMessageId);
        expect(stored.single.payload.text, 'hello');
        expect(stored.single.groupName, 'Snow');
        expect(stored.single.viewing, isFalse);
        sink.committed(Gv2MessageStored(m));
        expect(stored, hasLength(1));
      },
    );

    test('in an open chat it is stored read, its timer started', () async {
      viewing = true;
      final m = incoming({'text': 'now', 'ttl': 30});
      await sink.message(m);
      final row = (await db.messageDao.getMessageById(m.localMessageId))!;
      expect(row.read, isTrue);
      expect(row.expireStarted, _t0 + 5000);
      expect((await db.conversationDao.getConversation(g.id))!.unreadCount, 0);
    });

    test('two messages of one sender at the same millisecond are both '
        'stored', () async {
      final first = incoming({'text': 'one'}, sentAtMs: _t0 + 700);
      final second = incoming({'text': 'two'}, sentAtMs: _t0 + 700);
      await sink.message(first);
      await sink.message(second);
      final a = (await db.messageDao.getMessageById(first.localMessageId))!;
      final b = (await db.messageDao.getMessageById(second.localMessageId))!;
      expect(a.dateSent, _t0 + 700);
      expect(b.dateSent, _t0 + 701);
      // The same message again (a retry of the same row) keeps its time.
      await sink.message(second);
      expect(
        (await db.messageDao.getMessageById(second.localMessageId))!.dateSent,
        _t0 + 701,
      );
    });

    test('a file message keeps its metadata', () async {
      final metadata = {
        'fileId': 'f1',
        'fileName': 'a.jpg',
        'mimeType': 'image/jpeg',
      };
      final m = incoming({
        'text': 'a.jpg',
        'type': 'file',
        'metadata': metadata,
      });
      await sink.message(m);
      final row = (await db.messageDao.getMessageById(m.localMessageId))!;
      expect(row.type, 'file');
      expect(jsonDecode(row.metadata!), metadata);
    });

    test('a sender\'s clock ahead of this device does not date the message '
        'after its arrival', () async {
      final m = incoming({'text': 'from the future'}, sentAtMs: _t0 + 999999);
      await sink.message(m);
      expect(
        (await db.messageDao.getMessageById(m.localMessageId))!.dateSent,
        _t0 + 2000,
      );
    });

    test(
      'a payload this build cannot read stores and announces nothing',
      () async {
        final m = Gv2IncomingMessage(
          groupId: g.id,
          localMessageId: 'f' * 64,
          senderSnowId: bob,
          senderDeviceId: 'd' * 36,
          sentAtMs: _t0,
          receivedAtMs: _t0,
          payload: Uint8List.fromList([0xff, 0xfe]),
        );
        await sink.message(m);
        expect(await db.messageDao.getMessageById(m.localMessageId), isNull);
        sink.committed(Gv2MessageStored(m));
        expect(stored, isEmpty);
      },
    );

    test('a write rolled back with its transaction leaves nothing', () async {
      final m = incoming({'text': 'gone'});
      await expectLater(
        db.transaction(() async {
          await sink.message(m);
          throw StateError('the inbox transaction failed');
        }),
        throwsStateError,
      );
      expect(await db.messageDao.getMessageById(m.localMessageId), isNull);
      expect(await db.conversationDao.getConversation(g.id), isNull);
    });
  });

  group('removing', () {
    Future<File> attach(String messageId, String name) async {
      final file = File('${dir.path}/snowchat_attachments/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('decrypted');
      await db
          .into(db.localAttachments)
          .insert(
            LocalAttachmentsCompanion.insert(
              id: 'att_$messageId',
              messageId: messageId,
              contentType: 'image/jpeg',
              localPath: Value('snowchat_attachments/$name'),
            ),
          );
      return file;
    }

    test('an unsend removes the row and its attachment rows; the file goes '
        'only after the commit', () async {
      final m = incoming({'text': 'a.jpg', 'type': 'file'});
      await sink.message(m);
      final file = await attach(m.localMessageId, 'a.jpg');

      await sink.unsent(
        groupId: g.id,
        localMessageId: m.localMessageId,
        senderSnowId: bob,
      );
      expect(await db.messageDao.getMessageById(m.localMessageId), isNull);
      expect(await db.attachmentDao.getForMessage(m.localMessageId), isEmpty);
      expect(file.existsSync(), isTrue);
      expect(removed, isEmpty);

      sink.committed(
        Gv2MessageUnsent(
          groupId: g.id,
          localMessageId: m.localMessageId,
          senderSnowId: bob,
        ),
      );
      await pumpEventQueue();
      expect(file.existsSync(), isFalse);
      expect(removed, [g.id]);
    });

    test('an unsend does not reach a row of another sender or another '
        'conversation', () async {
      final m = incoming({'text': 'mine'});
      await sink.message(m);
      await sink.unsent(
        groupId: g.id,
        localMessageId: m.localMessageId,
        senderSnowId: 'snow00000000000000000000000000000ca7',
      );
      await sink.unsent(
        groupId: 'f' * 64,
        localMessageId: m.localMessageId,
        senderSnowId: bob,
      );
      expect(await db.messageDao.getMessageById(m.localMessageId), isNotNull);
      // One that is not there at all is nothing to do.
      await sink.unsent(
        groupId: g.id,
        localMessageId: 'e' * 64,
        senderSnowId: bob,
      );
    });

    test('a cleared history removes what was sent before the time, with its '
        'attachments, and nothing later', () async {
      final old = incoming({'text': 'old'}, sentAtMs: _t0 + 100);
      final older = incoming({
        'text': 'older.jpg',
        'type': 'file',
      }, sentAtMs: _t0 + 50);
      final kept = incoming({'text': 'kept'}, sentAtMs: _t0 + 1500);
      for (final m in [older, old, kept]) {
        await sink.message(m);
      }
      final file = await attach(older.localMessageId, 'older.jpg');

      await sink.historyCleared(
        groupId: g.id,
        beforeMs: _t0 + 1500,
        bySnowId: bob,
      );
      expect(await db.messageDao.getMessageById(old.localMessageId), isNull);
      expect(await db.messageDao.getMessageById(older.localMessageId), isNull);
      expect(
        await db.messageDao.getMessageById(kept.localMessageId),
        isNotNull,
      );
      expect(
        await db.attachmentDao.getForMessage(older.localMessageId),
        isEmpty,
      );
      expect(file.existsSync(), isTrue);

      sink.committed(
        Gv2HistoryCleared(groupId: g.id, beforeMs: _t0 + 1500, bySnowId: bob),
      );
      await pumpEventQueue();
      expect(file.existsSync(), isFalse);
      expect(removed, [g.id]);
    });
  });

  group('a message that cannot be read', () {
    final id = 'wait'.padRight(64, '0');

    test('at most gv2WaitingShownPerGroup places at a time: beyond, none is '
        'made (the message still waits for its key)', () async {
      await sink.message(incoming({'text': 'before'}));
      for (var i = 0; i < gv2WaitingShownPerGroup; i++) {
        expect(
          await sink.waiting(
            groupId: g.id,
            localMessageId: 'w${i}x'.padRight(64, '0'),
            sentAtMs: _t0 + i,
            receivedAtMs: _t0 + 2000,
          ),
          isTrue,
          reason: '$i',
        );
      }
      expect(
        await sink.waiting(
          groupId: g.id,
          localMessageId: 'over'.padRight(64, '0'),
          sentAtMs: _t0 + 999,
          receivedAtMs: _t0 + 2000,
        ),
        isFalse,
      );
      expect(await db.messageDao.getMessageById('over'.padRight(64, '0')), isNull);
    });

    test('gets a place in the conversation: no sender, nothing unread, the '
        'preview untouched — and only one', () async {
      await sink.message(incoming({'text': 'before'}));
      expect(
        await sink.waiting(
          groupId: g.id,
          localMessageId: id,
          sentAtMs: _t0 + 1500,
          receivedAtMs: _t0 + 2000,
        ),
        isTrue,
      );
      final row = (await db.messageDao.getMessageById(id))!;
      expect(row.conversationId, g.id);
      expect(row.type, 'system');
      expect(row.outgoingStatus, 'decryption_failed');
      expect(row.senderSnowchatId, '');
      expect(row.plaintext, '');
      expect(row.read, isTrue);
      expect(row.dateSent, _t0 + 1500);
      final conversation = (await db.conversationDao.getConversation(g.id))!;
      expect(conversation.unreadCount, 1); // the message before, not this
      expect(conversation.lastMessageText, 'before');

      expect(
        await sink.waiting(
          groupId: g.id,
          localMessageId: id,
          sentAtMs: _t0 + 1500,
          receivedAtMs: _t0 + 2000,
        ),
        isFalse,
      );
      expect(waitingTold, isEmpty);
      sink.committed(Gv2MessageWaiting(groupId: g.id, localMessageId: id));
      expect(waitingTold, [g.id]);
    });

    test('never takes the place of a row that is there', () async {
      final m = incoming({'text': 'real'}, id: id);
      await sink.message(m);
      expect(
        await sink.waiting(
          groupId: g.id,
          localMessageId: id,
          sentAtMs: _t0,
          receivedAtMs: _t0,
        ),
        isFalse,
      );
      expect((await db.messageDao.getMessageById(id))!.plaintext, 'real');
    });

    test('a sender\'s clock ahead of this device does not date it later than '
        'it arrived', () async {
      sink.groupChanged(g.id, const []);
      await pumpEventQueue();
      await sink.waiting(
        groupId: g.id,
        localMessageId: id,
        sentAtMs: _t0 + 999999,
        receivedAtMs: _t0 + 2000,
      );
      expect((await db.messageDao.getMessageById(id))!.dateSent, _t0 + 2000);
    });

    test('in a group without a conversation there is no place', () async {
      expect(
        await sink.waiting(
          groupId: g.id,
          localMessageId: id,
          sentAtMs: _t0,
          receivedAtMs: _t0,
        ),
        isFalse,
      );
      expect(await db.messageDao.getMessageById(id), isNull);
    });

    test('the message takes the place when its key comes, and counts like '
        'any message', () async {
      sink.groupChanged(g.id, const []);
      await pumpEventQueue();
      await sink.waiting(
        groupId: g.id,
        localMessageId: id,
        sentAtMs: _t0 + 1000,
        receivedAtMs: _t0 + 2000,
      );
      await sink.message(incoming({'text': 'at last'}, id: id));
      final row = (await db.messageDao.getMessageById(id))!;
      expect(row.type, 'text');
      expect(row.plaintext, 'at last');
      expect(row.senderSnowchatId, bob);
      expect(row.outgoingStatus, 'delivered');
      expect(row.metadata, isNull);
      expect(row.read, isFalse);
      expect(
        await db.messageDao.getMessagesForConversation(g.id),
        hasLength(1),
      );
      final conversation = (await db.conversationDao.getConversation(g.id))!;
      expect(conversation.unreadCount, 1);
      expect(conversation.lastMessageText, 'at last');
    });
  });

  group('the conversation of a group', () {
    test('exists once this account is a member, under the group id and with '
        'the group\'s name', () async {
      sink.groupChanged(g.id, const []);
      // The app is told once the row is there — not before: what it reads
      // on being told is what the change left.
      expect(changed, isEmpty);
      await pumpEventQueue();
      final row = (await db.conversationDao.getConversation(g.id))!;
      expect(row.type, 'group');
      expect(row.groupId, g.id);
      expect(row.title, 'Snow');
      expect(changed, [g.id]);
      // Again: one row, untouched.
      sink.groupChanged(g.id, const []);
      await pumpEventQueue();
      expect((await db.conversationDao.getConversation(g.id))!.createdAt, row.createdAt);
    });

    test('a group this account is only invited to, or does not hold, has none', () async {
      final invited = Gv2TestGroup('sink invited');
      final owner = invited.person('owner');
      final me = invited.person('alice');
      invited.create(owner, invite: [me]);
      await db.gv2Store.insertAnchored(
        groupId: invited.groupId,
        masterKey: invited.masterKey,
        myCiphertext: me.ciphertext,
        protocolVersion: gv2ProtocolVersion,
        revision: 0,
        chain: invited.state.chain,
        stateHash: gv2StateHash(invited.state),
        membership: Gv2Membership.invited,
        inviteSeed: invited.inviteKeyOf(me).seed,
      );
      sink.groupChanged(invited.id, const []);
      sink.groupChanged('f' * 64, const []);
      await pumpEventQueue();
      expect(await db.conversationDao.getConversation(invited.id), isNull);
      expect(await db.conversationDao.getConversation('f' * 64), isNull);
    });
  });

  group('system lines', () {
    test('an applied entry becomes lines in the conversation, once, with the '
        'event in the metadata', () async {
      final bobPerson = g.person('bob');
      g.invite(g.person('alice'), bobPerson);
      g.accept(bobPerson);
      final entries = [g.log[1], g.log[2]];
      sink.groupChanged(g.id, entries);
      await pumpEventQueue();
      final rows = (await db.messageDao.getMessagesForConversation(g.id))
          .where((m) => m.type == 'system')
          .toList();
      expect(rows, hasLength(2));
      expect(rows.every((m) => m.read && m.senderSnowchatId == ''), isTrue);
      final invited = rows.firstWhere((m) => m.plaintext.contains('invited'));
      // This account (alice) did it: worded as "You".
      expect(invited.plaintext, contains(' invited snow'));
      final metadata = jsonDecode(invited.metadata!) as Map;
      expect(metadata['gv2Event'], 'invited');
      expect(metadata['revision'], 1);
      expect(metadata['by'], g.person('alice').snowId);
      expect(metadata['about'], bobPerson.snowId);
      expect(rows.any((m) => m.plaintext.endsWith(' joined')), isTrue);
      // Not unread.
      expect((await db.conversationDao.getConversation(g.id))!.unreadCount, 0);

      // The same entries again write nothing more.
      sink.groupChanged(g.id, entries);
      await pumpEventQueue();
      expect(
        (await db.messageDao.getMessagesForConversation(g.id))
            .where((m) => m.type == 'system'),
        hasLength(2),
      );
    });

    test('a group without a conversation gets no lines', () async {
      // Held on this device, but only as an invite: no conversation yet.
      final invited = Gv2TestGroup('sink lines invited');
      final owner = invited.person('owner');
      final me = invited.person('alice');
      invited.create(owner, invite: [me]);
      await db.gv2Store.insertAnchored(
        groupId: invited.groupId,
        masterKey: invited.masterKey,
        myCiphertext: me.ciphertext,
        protocolVersion: gv2ProtocolVersion,
        revision: 0,
        chain: invited.state.chain,
        stateHash: gv2StateHash(invited.state),
        membership: Gv2Membership.invited,
        inviteSeed: invited.inviteKeyOf(me).seed,
      );
      sink.groupChanged(invited.id, [invited.log[0]]);
      await pumpEventQueue();
      expect(await db.messageDao.getMessagesForConversation(invited.id), isEmpty);
      expect(await db.conversationDao.getConversation(invited.id), isNull);
    });
  });

  group('this account\'s messages', () {
    test('what became of one is its status: sent, or failed; one that is not '
        'stored changes nothing', () async {
      for (final (id, at) in [('m-sent', 1), ('m-failed', 2)]) {
        await db.messageDao.upsertMessage(
          LocalMessagesCompanion(
            id: Value(id),
            conversationId: Value('ab' * 32),
            senderSnowchatId: Value('snow${'0' * 32}'),
            plaintext: const Value('x'),
            dateSent: Value(at),
            dateReceived: Value(at),
            outgoingStatus: const Value('sending'),
          ),
        );
      }
      await sink.outgoing(groupId: 'ab' * 32, localMessageId: 'm-sent', sent: true);
      await sink.outgoing(groupId: 'ab' * 32, localMessageId: 'm-failed', sent: false);
      await sink.outgoing(groupId: 'ab' * 32, localMessageId: 'gone', sent: true);
      expect((await db.messageDao.getMessageById('m-sent'))!.outgoingStatus, 'sent');
      expect((await db.messageDao.getMessageById('m-failed'))!.outgoingStatus, 'failed');
      expect(await db.messageDao.getMessageById('gone'), isNull);
    });
  });
}
