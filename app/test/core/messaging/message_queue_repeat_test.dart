/// @file        message_queue_repeat_test.dart
/// @description The receiver's duplicate guard (schema v17): a 1:1 message the sender's outbox
///              sent again after a lost ack arrives under a second server id with the same `cid`
///              — it is acknowledged and not stored again, on the sealed and the non-sealed path;
///              other messages of the same sender, and a message with no `cid`, are stored.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - _Handler: decrypts every envelope to the message the test set
///  - main(): the cases

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/encrypted_message_handler.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/messaging/message_queue.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/file_service.dart';
import 'package:snowchat/core/network/socket_manager.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/features/chat/models/message.dart';
import 'package:snowchat/features/chat/providers/expiring_message_manager.dart';

class _Socket extends Fake implements SocketManager {
  final List<String> acked = [];

  @override
  bool get isConnected => true;

  @override
  void sendMessageAck(List<String> messageIds) => acked.addAll(messageIds);
}

class _Sessions extends Fake implements SignalSessionManager {}

class _Handler extends Fake implements EncryptedMessageHandler {
  Message? next;

  @override
  Future<Message> decryptSealedMessage(Map<String, dynamic> socketEvent) async =>
      _as(socketEvent);

  @override
  Future<Message> decryptIncomingMessage(Map<String, dynamic> socketEvent) async =>
      _as(socketEvent);

  /// [next] under the envelope's server id (as the real decrypt does).
  Message _as(Map<String, dynamic> event) {
    final m = next!;
    return Message(
      id: (event['id'] ?? event['messageId']) as String,
      conversationId: m.conversationId,
      senderSnowchatId: m.senderSnowchatId,
      plaintext: m.plaintext,
      timestamp: m.timestamp,
      status: MessageStatus.delivered,
      peerClientId: m.peerClientId,
    );
  }

  @override
  Future<void> sendSealedReadReceipt({
    required String recipientId,
    required List<String> readIds,
  }) async {}
}

class _Files extends Fake implements FileService {}

class _Expiring extends Fake implements ExpiringMessageManager {}

class _Api extends Fake implements ApiClient {}

const _me = 'snowmeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const _peer = 'snow0123456789abcdef0123456789abcdef';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SnowDatabase db;
  late _Socket socket;
  late _Handler handler;
  late MessageQueue queue;

  setUp(() {
    db = SnowDatabase(NativeDatabase.memory());
    socket = _Socket();
    handler = _Handler();
    queue = MessageQueue(
      sessionManager: _Sessions(),
      e2eeHandler: handler,
      messageDao: db.messageDao,
      conversationDao: db.conversationDao,
      attachmentDao: db.attachmentDao,
      fileService: _Files(),
      expiringManager: _Expiring(),
      database: db,
      apiClient: _Api(),
      socketManager: socket,
      myIdResolver: () => _me,
    );
  });

  tearDown(() => db.close());

  Message from(String text, {String? cid}) => Message(
        id: 'unused',
        conversationId: _peer,
        senderSnowchatId: _peer,
        plaintext: text,
        timestamp: DateTime.utc(2026, 11, 21, 12),
        peerClientId: cid,
      );

  Future<List<LocalMessage>> rows() => db.messageDao.getMessagesForConversation(_peer);

  for (final type in ['sealed', 'e2ee_text']) {
    test('$type: the same message sent again is acked, stored once', () async {
      handler.next = from('hello', cid: 'msg_1');
      queue.enqueue({
        'id': 'srv_a',
        'type': type,
        'sealedContent': 'AAAA',
        'senderId': _peer,
        'serverTimestamp': '2026-11-21T12:00:00.000Z',
      });
      await queue.waitForIdle();
      // The outbox's second copy: another server id, the same cid.
      queue.enqueue({
        'id': 'srv_b',
        'type': type,
        'sealedContent': 'AAAA',
        'senderId': _peer,
        'serverTimestamp': '2026-11-21T12:00:05.000Z',
      });
      await queue.waitForIdle();
      queue.flushAcks();
      expect(socket.acked.toSet(), {'srv_a', 'srv_b'});
      final stored = await rows();
      expect(stored.map((r) => r.id), ['srv_a']);
      expect(stored.single.peerClientId, 'msg_1');

      // Another message of the same sender is stored.
      handler.next = from('second', cid: 'msg_2');
      queue.enqueue({
        'id': 'srv_c',
        'type': type,
        'sealedContent': 'AAAA',
        'senderId': _peer,
        'serverTimestamp': '2026-11-21T12:00:09.000Z',
      });
      await queue.waitForIdle();
      expect((await rows()).map((r) => r.id).toSet(), {'srv_a', 'srv_c'});
    });
  }

  test('a message with no cid is stored every time it comes', () async {
    handler.next = from('old sender');
    for (final (id, ts) in [('srv_x', '12:00:00'), ('srv_y', '12:00:01')]) {
      queue.enqueue({
        'id': id,
        'type': 'sealed',
        'sealedContent': 'AAAA',
        'serverTimestamp': '2026-11-21T$ts.000Z',
      });
      await queue.waitForIdle();
    }
    expect((await rows()).map((r) => r.id).toSet(), {'srv_x', 'srv_y'});
  });
}
