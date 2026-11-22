/// @file        global_message_router_gv2_test.dart
/// @description GlobalMessageRouter and the server's `message_deleted` — the
///              one place a remote unsend is applied: it removes only a
///              peer's own message in the 1:1 room with that peer. A message
///              of a group protocol v2 group (taken back only by its sender's
///              signed unsend, core/group_v2) and this account's own message
///              stay, with their attachments. Driven through the real
///              SocketManager on a stand-in socket and a real in-memory
///              database.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20 (a removable message is a peer's own, in that peer's room; the router
///              takes no E2EE handler or account id any more)
///
/// @functions
///  - main(): the cases above
///  - _Socket / _Manager: record the handlers SocketManager registers
///  - _Sessions / _Signal: the parts of the 1:1 stack the router touches
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/message_send_log.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/messaging/global_message_router.dart';
import 'package:snowchat/core/messaging/message_queue.dart';
import 'package:snowchat/core/network/socket_manager.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
// The manager behind Socket.io (where onReconnect() registers) is not
// exported by the package.
// ignore: implementation_imports
import 'package:socket_io_client/src/manager.dart' as sio_manager;

class _Socket extends Fake implements sio.Socket {
  final Map<String, dynamic Function(dynamic)> handlers = {};

  void fire(String event, Object? data) => handlers[event]!(data);

  @override
  Function() on(String event, dynamic Function(dynamic) handler) {
    handlers[event] = handler;
    return () => handlers.remove(event);
  }

  @override
  late sio_manager.Manager io = _Manager(this);

  @override
  sio.Socket disconnect() => this;

  @override
  void dispose() {}
}

class _Manager extends Fake implements sio_manager.Manager {
  final _Socket owner;
  _Manager(this.owner);

  @override
  Function() on(String event, dynamic Function(dynamic) handler) =>
      owner.on(event, handler);
}

class _Signal extends Fake implements SignalProtocolService {
  @override
  final MessageSendLog messageSendLog = MessageSendLog();
}

class _Sessions extends Fake implements SignalSessionManager {
  @override
  final SignalProtocolService signal = _Signal();
}

class _Queue extends Fake implements MessageQueue {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    null,
  );
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SnowDatabase db;
  late SocketManager socketManager;
  late _Socket socket;
  late GlobalMessageRouter router;

  setUp(() {
    db = SnowDatabase(NativeDatabase.memory());
    socketManager = SocketManager();
    socket = _Socket();
    socketManager.attachForTest(socket);
    router = GlobalMessageRouter(
      socketManager: socketManager,
      queue: _Queue(),
      sessionManager: _Sessions(),
      messageDao: db.messageDao,
      attachmentDao: db.attachmentDao,
    )..start();
  });
  tearDown(() async {
    router.stop();
    socketManager.dispose();
    await db.close();
  });

  final peer = 'snow${'1' * 32}';
  const me = 'snow00000000000000000000000000000000';

  Future<void> message(String id, String conversationId, {String? sender}) =>
      db.messageDao.insertMessage(LocalMessagesCompanion.insert(
        id: id,
        conversationId: conversationId,
        senderSnowchatId: sender ?? peer,
        dateSent: 1,
        dateReceived: 2,
        plaintext: 'hello',
      ));

  test('the server\'s message_deleted does not remove a message of a v2 '
      'group, nor its attachment', () async {
    final group = 'ab' * 32;
    await message('m-v2', group);
    await db.attachmentDao.insertAttachment(LocalAttachmentsCompanion.insert(
      id: 'a-v2',
      messageId: 'm-v2',
      contentType: 'image/png',
    ));

    socket.fire('message_deleted', {'messageId': 'm-v2', 'messageGuid': 'g'});
    await pumpEventQueue();
    expect(await db.messageDao.getMessageById('m-v2'), isNotNull);
    expect(await db.attachmentDao.getForMessage('m-v2'), hasLength(1));
  });

  test('the same event for the peer\'s own message in its 1:1 room removes '
      'it and its attachment', () async {
    await message('m-1', peer);
    await db.attachmentDao.insertAttachment(LocalAttachmentsCompanion.insert(
      id: 'a-1',
      messageId: 'm-1',
      contentType: 'image/png',
    ));
    socket.fire('message_deleted', {'messageId': 'm-1', 'messageGuid': 'g'});
    await pumpEventQueue();
    expect(await db.messageDao.getMessageById('m-1'), isNull);
    expect(await db.attachmentDao.getForMessage('m-1'), isEmpty);
  });

  test('it does not remove this account\'s own message, nor a message filed '
      'under another room than its sender\'s', () async {
    await message('m-mine', peer, sender: me);
    await message('m-elsewhere', 'snow${'2' * 32}');
    await message('m-legacy', 'conv-1');
    for (final id in ['m-mine', 'm-elsewhere', 'm-legacy']) {
      socket.fire('message_deleted', {'messageId': id, 'messageGuid': 'g'});
    }
    await pumpEventQueue();
    for (final id in ['m-mine', 'm-elsewhere', 'm-legacy']) {
      expect(await db.messageDao.getMessageById(id), isNotNull, reason: id);
    }
  });

  test('an event without a message id, or for a message this device does '
      'not hold, changes nothing', () async {
    await message('m-v2', 'ab' * 32);
    socket.fire('message_deleted', {'messageGuid': 'g'});
    socket.fire('message_deleted', {'messageId': 'nope'});
    await pumpEventQueue();
    expect(await db.messageDao.getMessageById('m-v2'), isNotNull);
  });
}
