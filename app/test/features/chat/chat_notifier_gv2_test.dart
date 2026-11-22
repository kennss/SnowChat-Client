/// @file        chat_notifier_gv2_test.dart
/// @description ChatNotifier in a group protocol v2 group: everything it does
///              goes through Gv2ChatActions and never through the v1 group
///              paths. A text (with its reply and timer) is handed to the
///              group, one the group refuses shows as failed and is not
///              stored (the chat follows no socket status events — a 1:1's marks are
///              the 1:1 outbox's), typing tells the server nothing, an unsend is the
///              group's (inside the window only) and removes the own copy
///              only once queued, clearing removes the history only once the
///              notice is queued, and ending / leaving / removing the chat
///              ask the server nothing. A message the user writes in a 1:1
///              vouches for its peer (onUserWrote); one in a group vouches
///              for nobody. Stand-ins for the repository and the group
///              actions; the real SocketManager on a stand-in socket.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (a settled 1:1 message is not shown twice). Earlier 2026-11-22 (no status-event case: the chat no longer listens to them). Earlier 2026-11-21 (P5.6: a refused file leaves no plaintext copy; P5.6: a failed clear / leave / end leaves the disappearing-message timers running). Earlier 2026-11-21 (onUserWrote: a 1:1 message the user writes vouches for its peer). Earlier 2026-11-20 (v1 groups removed: the chat has no message_deleted listener of its own)
///
/// @functions
///  - main(): the cases above
///  - _Repo: the repository surface ChatNotifier uses, recording calls
///  - _Actions: Gv2ChatActions, recording what it was asked
///  - _Socket / _Manager: a stand-in socket that records emits
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_messaging.dart' show Gv2NotSendable;
import 'package:snowchat/core/messaging/direct_outbox.dart';
import 'package:snowchat/core/network/file_service.dart';
import 'package:snowchat/core/network/socket_manager.dart';
import 'package:snowchat/core/storage/database.dart' hide Conversation;
import 'package:snowchat/features/chat/models/message.dart';
import 'package:snowchat/features/chat/providers/chat_provider.dart';
import 'package:snowchat/features/chat/providers/expiring_message_manager.dart';
import 'package:snowchat/features/chat/providers/gv2_chat_actions.dart';
import 'package:snowchat/features/chat/providers/mark_read_helper.dart';
import 'package:snowchat/features/chat/providers/message_repository.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
// The manager behind Socket.io (where onReconnect() registers) is not
// exported by the package.
// ignore: implementation_imports
import 'package:socket_io_client/src/manager.dart' as sio_manager;

const String _me = 'snow00000000000000000000000000000000';
final String _group = 'ab' * 32;

class _Socket extends Fake implements sio.Socket {
  final Map<String, dynamic Function(dynamic)> handlers = {};
  final List<String> emitted = [];

  @override
  Function() on(String event, dynamic Function(dynamic) handler) {
    handlers[event] = handler;
    return () => handlers.remove(event);
  }

  @override
  late sio_manager.Manager io = _Manager(this);

  @override
  String? get id => 'test-socket';

  @override
  bool get connected => true;

  @override
  void emit(String event, [dynamic data]) => emitted.add(event);

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

/// A 1:1 outbox that takes a text and does nothing else — the row keeps the
/// status the notifier wrote until a test changes it through the watch.
class _Outbox extends Fake implements DirectOutbox {
  final List<String> texts = [];

  @override
  Future<void> enqueueText({
    required String messageId,
    required String peer,
    required String text,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
  }) async =>
      texts.add(messageId);
}

class _Repo implements MessageRepository {
  final List<Message> stored;
  final List<String> calls = [];
  final StreamController<List<LocalMessage>> watched = StreamController.broadcast();

  _Repo(this.stored);

  /// The disappearing-message timers, when a test looks at them.
  ExpiringMessageManager? expiring;

  @override
  FileService? fileService;
  @override
  ExpiringMessageManager? get expiringManager => expiring;

  @override
  String? groupId = _group;
  @override
  String? recipientId;
  @override
  bool get isGroup => groupId != null;

  @override
  void Function(Message message)? onIncomingMessage;

  @override
  Future<List<Message>> loadFromDrift() async => stored;
  @override
  Stream<List<LocalMessage>> watchMessages() => watched.stream;
  @override
  Future<List<Message>?> fetchFromServer() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString();
    calls.add(name.substring(8, name.length - 2)); // Symbol("x") → x
    if (invocation.isGetter || invocation.isSetter) return null;
    // Every other call the notifier makes returns void or Future<void>.
    return Future<void>.value();
  }
}

class _Actions implements Gv2ChatActions {
  final List<String> calls = [];
  Map<String, Object?>? sent;
  Object? refuse;
  bool unsendTaken = true;

  @override
  String get groupId => _group;

  @override
  Future<String> send({
    required String text,
    required String snippet,
    String type = 'text',
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
    Object? attachment,
  }) async {
    calls.add('send');
    if (refuse != null) throw refuse!;
    sent = {
      'text': text,
      'type': type,
      'ttl': ttlSeconds,
      'replyToId': replyToId,
      'replyToSenderId': replyToSenderId,
    };
    return 'local-1';
  }

  @override
  Future<bool> unsend(String localMessageId) async {
    calls.add('unsend $localMessageId');
    return unsendTaken;
  }

  @override
  Future<void> clearHistory() async {
    calls.add('clearHistory');
    if (refuse != null) throw refuse!;
  }

  @override
  Future<void> leave({bool deleteMyMessages = false}) async {
    calls.add(deleteMyMessages ? 'leave+delete' : 'leave');
    if (refuse != null) throw refuse!;
  }

  @override
  Future<void> end() async {
    calls.add('end');
    if (refuse != null) throw refuse!;
  }

  @override
  Future<void> forgetGroup() async => calls.add('forget');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Uploads take everything and name it with a server file id.
class _Files implements FileService {
  @override
  Future<String> uploadEncryptedFile(
    Uint8List encryptedData,
    String contentHash, {
    void Function(int sent, int total)? onProgress,
  }) async => '123e4567-e89b-42d3-a456-426614174000';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MarkRead implements MarkReadHelper {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    null,
  );

  late SocketManager socketManager;
  late _Socket socket;
  late _Repo repo;
  late _Actions actions;
  late ChatNotifier chat;

  Message mine(String id, {Duration age = Duration.zero}) => Message(
        id: id,
        conversationId: _group,
        senderSnowchatId: _me,
        plaintext: 'mine $id',
        timestamp: DateTime.now().subtract(age),
        status: MessageStatus.sent,
      );

  Future<void> open(List<Message> stored) async {
    socketManager = SocketManager();
    socket = _Socket();
    socketManager.attachForTest(socket);
    socket.handlers['connect']!(null); // a connected socket
    repo = _Repo(stored);
    actions = _Actions();
    chat = ChatNotifier(
      _group,
      repository: repo,
      markReadHelper: _MarkRead(),
      socketManager: socketManager,
      mySnowId: _me,
      gv2: actions,
    );
    await pumpEventQueue();
  }

  tearDown(() {
    chat.dispose();
    socketManager.dispose();
  });

  test('a text goes to the group with its reply and timer; nothing on the '
      'socket', () async {
    await open([mine('m1')]);
    expect(chat.isGv2, isTrue);
    chat.setReplyTo(chat.state.messages.single);
    await chat.sendMessage('hello');
    expect(actions.sent, {
      'text': 'hello',
      'type': 'text',
      'ttl': null,
      'replyToId': 'm1',
      'replyToSenderId': _me,
    });
    expect(socket.emitted, isEmpty);
  });

  test('a text the group refuses shows as failed and is not stored', () async {
    await open([]);
    actions.refuse = const Gv2NotSendable();
    await chat.sendMessage('nobody will read this');
    final shown = chat.state.messages.single;
    expect(shown.plaintext, 'nobody will read this');
    expect(shown.status, MessageStatus.failed);
    expect(repo.calls.where((c) => c.contains('insert') || c.contains('save')),
        isEmpty);
  });


  test('typing tells the server nothing', () async {
    await open([]);
    expect(socketManager.isConnected, isTrue);
    chat.onUserTyping();
    chat.onUserStoppedTyping();
    expect(socket.emitted, isEmpty);
  });

  test('an unsend inside the window is the group\'s, and the own copy goes '
      'only once it was queued', () async {
    await open([mine('m1'), mine('m2'), mine('old', age: const Duration(minutes: 6))]);
    expect(await chat.deleteMessageForEveryone('m1'), UnsendResult.unsent);
    expect(actions.calls, ['unsend m1']);
    expect(repo.calls, contains('deleteMessageLocally'));

    actions.unsendTaken = false;
    repo.calls.clear();
    expect(await chat.deleteMessageForEveryone('m2'), UnsendResult.failed);
    expect(repo.calls, isNot(contains('deleteMessageLocally')));

    actions.calls.clear();
    expect(await chat.deleteMessageForEveryone('old'), UnsendResult.failed);
    expect(actions.calls, isEmpty, reason: 'outside the window nothing is asked');
    expect(socket.emitted, isEmpty);
  });

  test('clearing removes the history only once the notice is queued',
      () async {
    await open([mine('m1')]);
    actions.refuse = const Gv2NotSendable();
    await expectLater(chat.clearChat(), throwsA(isA<Gv2NotSendable>()));
    expect(repo.calls, isNot(contains('clearMessagesLocally')));
    expect(chat.state.messages, hasLength(1));

    actions.refuse = null;
    await chat.clearChat();
    expect(repo.calls, contains('clearMessagesLocally'));
    expect(chat.state.messages, isEmpty);
  });

  test('a clear, leave or end that fails leaves the disappearing-message '
      'timers running; one that is made stops them', () async {
    await open([mine('m1')]);
    final db = SnowDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final expiring = ExpiringMessageManager(
      messageDao: db.messageDao,
      attachmentDao: db.attachmentDao,
    );
    addTearDown(expiring.dispose);
    repo.expiring = expiring;
    expiring.schedule('m1', 3600);

    actions.refuse = const Gv2NotSendable();
    for (final act in <Future<void> Function()>[
      chat.clearChat,
      chat.leaveGroup,
      chat.leaveAndDeleteMyMessages,
      chat.deleteGroup,
    ]) {
      await expectLater(act(), throwsA(isA<Gv2NotSendable>()));
      expect(expiring.activeTimerCount, 1);
    }
    expect(chat.state.messages, hasLength(1));

    actions.refuse = null;
    await chat.leaveGroup();
    expect(expiring.activeTimerCount, 0);
  });

  test('a file the group refuses leaves no copy of its plaintext behind',
      () async {
    final docs = await Directory.systemTemp.createTemp('gv2_docs');
    addTearDown(() => docs.delete(recursive: true));
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => docs.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null));
    final source = File('${docs.path}/picked.jpg')
      ..writeAsBytesSync(List.filled(64, 7));

    await open([]);
    repo.fileService = _Files();
    actions.refuse = const Gv2NotSendable();
    await chat.sendFileMessage(
      filePath: source.path,
      fileName: 'picked.jpg',
      mimeType: 'image/jpeg',
    );
    expect(actions.calls, ['send']);
    final kept = Directory('${docs.path}/snowchat_attachments');
    expect(
      kept.existsSync() ? kept.listSync() : const <FileSystemEntity>[],
      isEmpty,
    );
    expect(chat.state.messages.single.status, MessageStatus.failed);
  });

  test('ending, leaving and removing the chat go through the group and ask '
      'the server nothing', () async {
    await open([mine('m1')]);
    await chat.deleteGroup();
    await chat.leaveGroup();
    await chat.leaveAndDeleteMyMessages();
    await chat.deleteChat();
    // Removing the chat takes the group with it.
    expect(actions.calls, ['end', 'leave', 'leave+delete', 'forget']);
    expect(repo.calls.where((c) => c == 'deleteConversationLocally'), hasLength(4));
    expect(repo.calls, isNot(contains('apiClient')));
    expect(socket.emitted, isEmpty);
  });

  test('a sent 1:1 message shows once after drift moves it to the server id',
      () async {
    const peer = 'snow0123456789abcdef0123456789abcdef';
    socketManager = SocketManager();
    socket = _Socket();
    socketManager.attachForTest(socket);
    socket.handlers['connect']!(null);
    repo = _Repo(const [])
      ..groupId = null
      ..recipientId = peer;
    chat = ChatNotifier(
      peer,
      repository: repo,
      markReadHelper: _MarkRead(),
      socketManager: socketManager,
      mySnowId: _me,
    );
    await pumpEventQueue();
    LocalMessage row(String id, String status) => LocalMessage(
          id: id,
          conversationId: peer,
          senderSnowchatId: _me,
          dateSent: 1000,
          dateReceived: 1000,
          dateServer: 0,
          plaintext: 'hello friend 1',
          type: 'text',
          read: true,
          outgoingStatus: status,
          hasDeliveryReceipt: false,
          hasReadReceipt: false,
          notified: true,
          expiresIn: 0,
          expireStarted: 0,
          remoteDeleted: false,
          mentionsSelf: false,
        );
    // The outbox wrote the local row, then settled it under the server id.
    repo.watched.add([row('msg_local_1', 'sending')]);
    await pumpEventQueue();
    expect(chat.state.messages.map((m) => m.id), ['msg_local_1']);
    repo.watched.add([row('cmserver1', 'delivered')]);
    await pumpEventQueue();
    expect(chat.state.messages.map((m) => m.id), ['cmserver1'],
        reason: 'the local "sending" copy must not stay as a second bubble');
  });

  test('a 1:1 message the watch never showed under its local id is not '
      'doubled once settled', () async {
    final outbox = _Outbox();
    const peer = 'snow0123456789abcdef0123456789abcdef';
    socketManager = SocketManager();
    socket = _Socket();
    socketManager.attachForTest(socket);
    socket.handlers['connect']!(null);
    repo = _Repo(const [])
      ..groupId = null
      ..recipientId = peer;
    chat = ChatNotifier(
      peer,
      repository: repo,
      markReadHelper: _MarkRead(),
      socketManager: socketManager,
      mySnowId: _me,
      outbox: outbox,
    );
    await pumpEventQueue();
    await chat.sendMessage('hi');
    await pumpEventQueue();
    expect(outbox.texts, hasLength(1));
    final local = chat.state.messages.single;
    expect(local.status, MessageStatus.sending);
    // The first emission drift makes already holds the settled row.
    repo.watched.add([
      LocalMessage(
        id: 'cmserver2',
        conversationId: peer,
        senderSnowchatId: _me,
        dateSent: local.timestamp.millisecondsSinceEpoch,
        dateReceived: local.timestamp.millisecondsSinceEpoch,
        dateServer: 0,
        plaintext: 'hi',
        type: 'text',
        read: true,
        outgoingStatus: 'sent',
        hasDeliveryReceipt: false,
        hasReadReceipt: false,
        notified: true,
        expiresIn: 0,
        expireStarted: 0,
        remoteDeleted: false,
        mentionsSelf: false,
      ),
    ]);
    await pumpEventQueue();
    expect(chat.state.messages.map((m) => m.id), ['cmserver2']);
  });

  group('vouching', () {
    const peer = 'snow0123456789abcdef0123456789abcdef';

    test('a message the user writes in a 1:1 vouches for its peer', () async {
      socketManager = SocketManager();
      socket = _Socket();
      socketManager.attachForTest(socket);
      socket.handlers['connect']!(null);
      repo = _Repo(const [])
        ..groupId = null
        ..recipientId = peer;
      final wrote = <String>[];
      chat = ChatNotifier(
        peer,
        repository: repo,
        markReadHelper: _MarkRead(),
        socketManager: socketManager,
        mySnowId: _me,
        onUserWrote: (p) async => wrote.add(p),
      );
      await pumpEventQueue();
      expect(wrote, isEmpty, reason: 'opening a chat vouches for nobody');
      await chat.sendMessage('hi');
      await pumpEventQueue();
      expect(wrote, [peer]);
    });

    test('a message in a group vouches for nobody', () async {
      await open(const []);
      final wrote = <String>[];
      chat.dispose();
      chat = ChatNotifier(
        _group,
        repository: repo,
        markReadHelper: _MarkRead(),
        socketManager: socketManager,
        mySnowId: _me,
        gv2: actions,
        onUserWrote: (p) async => wrote.add(p),
      );
      await pumpEventQueue();
      await chat.sendMessage('hello all');
      await pumpEventQueue();
      expect(actions.calls, contains('send'));
      expect(wrote, isEmpty);
    });
  });
}
