/// @file        socket_manager_gv2_test.dart
/// @description SocketManager and groups, driven through a stand-in socket:
///              no v1 group event is listened to any more, nor the server's
///              chat_deleted (a peer's deletion arrives as its sealed
///              control); the handlers that remain and take a conversation
///              id (typing) drop one that names a v2 group id — in
///              `groupChatId`, `groupId` or `conversationId` — before any
///              listener sees it, while the same event about a 1:1 peer
///              passes; and `gv2_message` rows reach the inbox stream.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (chat_deleted is not listened to; the guarded set is typing). Earlier
///              2026-11-20 (v1 groups removed: the v1 events are not registered; the counterpart
///              that passes is a 1:1 event)
///
/// @functions
///  - main(): the cases above
///  - _Socket / _Manager: record the handlers SocketManager registers, fire
///    events
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/network/socket_manager.dart';
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

  /// onReconnect() and the like register on the manager.
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

/// A v2 group id (64 lowercase hex) and a 1:1 peer (a snowId).
final String _v2 = 'ab' * 32;
final String _peer = 'snow${'0123456789abcdef' * 2}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // connectivity_plus listens on an event channel when SocketManager is
  // made; nothing answers it here.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    null,
  );

  late SocketManager manager;
  late _Socket socket;

  setUp(() {
    manager = SocketManager();
    socket = _Socket();
    manager.attachForTest(socket);
  });
  tearDown(() => manager.dispose());

  /// The events of the v1 groups, and the server's chat_deleted. None is
  /// listened to any more.
  const v1Events = [
    'chat_deleted',
    'new_group_message', 'group_message', 'sender_key_request',
    'sender_key_request_failed', 'group_message_retry_request',
    'group_deleted', 'group_messages_cleared', 'group_member_added',
    'group_member_removed', 'group_updated', 'group_owner_changed',
    'request_gmk', 'gmk_response', 'group_invite', 'group_invite_rejected',
  ];

  /// Each event that remains and takes a conversation id, and the stream
  /// it feeds.
  Map<String, Stream<Map<String, dynamic>>> guarded() => {
        'user_typing': manager.onTyping,
        'user_stopped_typing': manager.onTyping,
      };

  test('no v1 group event nor chat_deleted is listened to; the guarded ones '
      'are', () {
    for (final event in v1Events) {
      expect(socket.handlers, isNot(contains(event)), reason: event);
    }
    for (final event in guarded().keys) {
      expect(socket.handlers, contains(event), reason: event);
    }
  });

  for (final field in ['groupChatId', 'groupId', 'conversationId']) {
    test('an event naming a v2 group in `$field` reaches no listener; the '
        'same about a 1:1 peer does', () async {
      for (final MapEntry(key: event, value: stream) in guarded().entries) {
        final seen = <Map<String, dynamic>>[];
        final sub = stream.listen(seen.add);
        socket.fire(event, {field: _v2, 'n': 1});
        await pumpEventQueue();
        expect(seen, isEmpty, reason: '$event about a v2 group');
        socket.fire(event, {field: _peer, 'n': 2});
        await pumpEventQueue();
        expect(seen.map((e) => e['n']), [2], reason: '$event about a peer');
        await sub.cancel();
      }
    });
  }

  test('an id that only looks like one — upper case, or 63 characters — is '
      'not a v2 group', () {
    expect(SocketManager.namesV2Group({'groupId': _v2}), isTrue);
    expect(SocketManager.namesV2Group({'groupId': _v2.toUpperCase()}), isFalse);
    expect(SocketManager.namesV2Group({'groupId': _v2.substring(1)}), isFalse);
    expect(SocketManager.namesV2Group({'groupId': 12}), isFalse);
    expect(SocketManager.namesV2Group('not a map'), isFalse);
  });

  test('a row of the group queue reaches the inbox stream as it came',
      () async {
    final rows = <Map<String, dynamic>>[];
    final sub = manager.onGv2Row.listen(rows.add);
    socket.fire('gv2_message', {'id': 'r1', 'seq': '7', 'envelope': 'AQID'});
    socket.fire('gv2_message', 'not a map');
    await pumpEventQueue();
    expect(rows, [
      {'id': 'r1', 'seq': '7', 'envelope': 'AQID'},
    ]);
    await sub.cancel();
  });

}
