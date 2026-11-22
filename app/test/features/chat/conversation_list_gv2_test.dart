/// @file        conversation_list_gv2_test.dart
/// @description ConversationListNotifier.syncGv2Group — the Chats list entry
///              of a group protocol v2 group follows this device's
///              conversation row (nothing is asked of the server): it appears
///              when the row is made, takes a rename, carries the unread
///              count, keeps the list sorted, and goes when the row goes or
///              stops being active. A v1 id is left alone. The message queue
///              is wired to it, so a change of a v2 group reaches the list.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20
///
/// @functions
///  - main(): the cases above
///  - _Queue: the message queue's callbacks, as the notifier sets them
///  - _Socket / _Manager: a socket that never delivers anything
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/messaging/message_queue.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/socket_manager.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/features/chat/providers/conversation_list_provider.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
// The manager behind Socket.io (where onReconnect() registers) is not
// exported by the package.
// ignore: implementation_imports
import 'package:socket_io_client/src/manager.dart' as sio_manager;

class _Socket extends Fake implements sio.Socket {
  @override
  Function() on(String event, dynamic Function(dynamic) handler) => () {};

  @override
  late sio_manager.Manager io = _Manager();

  @override
  sio.Socket disconnect() => this;

  @override
  void dispose() {}
}

class _Manager extends Fake implements sio_manager.Manager {
  @override
  Function() on(String event, dynamic Function(dynamic) handler) => () {};
}

/// Takes the callbacks the notifier sets; anything else is not expected.
class _Queue implements MessageQueue {
  void Function(String groupId)? gv2Changed;

  @override
  set onGv2GroupChanged(void Function(String groupId)? callback) =>
      gv2Changed = callback;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _Api implements ApiClient {
  final List<Symbol> calls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('no server in this test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    null,
  );
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SnowDatabase db;
  late SocketManager socket;
  late _Queue queue;
  late _Api api;
  late ProviderContainer container;
  late ConversationListNotifier list;
  final group = 'ab' * 32;
  final other = 'cd' * 32;

  setUp(() async {
    db = SnowDatabase(NativeDatabase.memory());
    socket = SocketManager()..attachForTest(_Socket());
    queue = _Queue();
    api = _Api();
    container = ProviderContainer(overrides: [
      snowDatabaseProvider.overrideWithValue(db),
      messageDaoProvider.overrideWithValue(db.messageDao),
      conversationDaoProvider.overrideWithValue(db.conversationDao),
      socketManagerProvider.overrideWithValue(socket),
      messageQueueProvider.overrideWithValue(queue),
      apiClientProvider.overrideWithValue(api),
      // Signed out of the server: nothing is loaded from it.
      authTokenProvider.overrideWith((ref) => null),
      currentSnowIdProvider.overrideWith((ref) => 'snow${'0' * 32}'),
    ]);
    list = container.read(conversationListProvider.notifier);
    await pumpEventQueue();
  });
  tearDown(() async {
    container.dispose();
    socket.dispose();
    await db.close();
  });

  Future<void> row(String id, String title) => db.conversationDao.findOrCreate(
        id: id,
        type: 'group',
        participantIds: const [],
        title: title,
        groupId: id,
      );

  List<String> ids() => [for (final c in container.read(conversationListProvider)) c.id];

  test('the entry appears with the row, takes a rename and the unread count, '
      'and asks the server nothing', () async {
    await row(group, 'Snow');
    await list.syncGv2Group(group);
    expect(ids(), [group]);
    expect(container.read(conversationListProvider).single.title, 'Snow');

    await db.conversationDao.updateTitle(group, 'Winter');
    for (final (id, at) in [('m1', 1), ('m2', 2)]) {
      await db.messageDao.insertMessage(LocalMessagesCompanion.insert(
        id: id,
        conversationId: group,
        senderSnowchatId: 'snow${'1' * 32}',
        dateSent: at,
        dateReceived: 2,
        plaintext: 'hello',
      ));
    }
    await list.syncGv2Group(group);
    final entry = container.read(conversationListProvider).single;
    expect(entry.title, 'Winter');
    expect(entry.unreadCount, 2);
    expect(ids(), [group], reason: 'one entry, replaced');
    expect(api.calls, isEmpty);
  });

  test('the entry goes when the row goes, or stops being active', () async {
    await row(group, 'Snow');
    await row(other, 'Other');
    await list.syncGv2Group(group);
    await list.syncGv2Group(other);
    expect(ids().toSet(), {group, other});

    await db.conversationDao.deleteConversation(group);
    await list.syncGv2Group(group);
    expect(ids(), [other]);

    await (db.update(db.conversations)..where((c) => c.id.equals(other)))
        .write(const ConversationsCompanion(isActive: Value(false)));
    await list.syncGv2Group(other);
    expect(ids(), isEmpty);
  });

  test('the list stays sorted by the latest message', () async {
    await row(group, 'Snow');
    await row(other, 'Other');
    await db.conversationDao.updateLastMessage(
      conversationId: other,
      text: 'later',
      senderId: 'snow${'1' * 32}',
      timestamp: 2000,
    );
    await db.conversationDao.updateLastMessage(
      conversationId: group,
      text: 'earlier',
      senderId: 'snow${'1' * 32}',
      timestamp: 1000,
    );
    await list.syncGv2Group(group);
    await list.syncGv2Group(other);
    expect(ids(), [other, group]);
  });

  test('a v1 id is not this path\'s business', () async {
    await row('clx0v1group000000000000001', 'v1');
    await list.syncGv2Group('clx0v1group000000000000001');
    expect(ids(), isEmpty);
  });

  test('the message queue is wired to it: a change of a v2 group reaches '
      'the list', () async {
    await row(group, 'Snow');
    expect(queue.gv2Changed, isNotNull);
    queue.gv2Changed!(group);
    for (var i = 0; i < 50 && ids().isEmpty; i++) {
      await pumpEventQueue();
    }
    expect(ids(), [group]);
  });
}
