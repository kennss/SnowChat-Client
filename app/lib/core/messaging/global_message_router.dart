/// @file        global_message_router.dart
/// @description Phase 6 — Subscribes to all incoming socket envelopes and forwards
///              them to the MessageQueue for serial processing. Also handles
///              SKDM requests (we are the sender) and triggers initial fetch.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation; Vuln 2 Stage B: force_prekey_upload listener → uploadPreKeys)
///
/// @functions
///  - GlobalMessageRouter: Bridges SocketManager streams → MessageQueue
///  - start(): Subscribe to socket events and trigger initial fetch
///  - stop(): Cancel all subscriptions
///  - _handleIncomingEnvelope(): Forward envelope to MessageQueue
///  - _handleSenderKeyRequest(): Respond to a recipient asking for our SKDM
///  - _handleConnectionChange(): Re-fetch pending messages on reconnect + prekey replenishment (P1-B)
///  - _handlePrekeysLow(): Server notified prekeys are depleted — trigger immediate replenishment (P1-B)
///  - _handleForcePrekeyUpload(): Vuln 2 Stage B — server requests Ed25519 verify key re-upload
///  - _handleMessageDeleted(): Delete-for-everyone receiver-side handler
///                             (deletes drift row + attachments + local files,
///                             so any open drift watcher updates the UI)
///  - _handleGroupMessagesCleared(): Vuln 3 admin-triggered group clear chat receiver
///  - RetryHandler integration: sender-side retry response (Phase 10 P0-E)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../crypto/encrypted_message_handler.dart';
import '../crypto/signal_session_manager.dart';
import '../network/socket_manager.dart';
import '../storage/daos/attachment_dao.dart';
import '../storage/daos/message_dao.dart';
import '../../features/chat/providers/conversation_list_provider.dart';
import 'message_queue.dart';
import 'retry_handler.dart';

class GlobalMessageRouter {
  final SocketManager _socketManager;
  final MessageQueue _queue;
  final EncryptedMessageHandler _e2eeHandler;
  final SignalSessionManager _sessionMgr;
  final MessageDao _messageDao;
  final AttachmentDao _attachmentDao;
  final String Function() _myIdResolver;
  // Vuln 3 (Stage 3): used to clear conversation list preview after admin clear chat.
  // Optional so legacy tests / callers without Riverpod can still construct the router.
  final Ref? _ref;

  /// Phase 10 P0-E: Sender-side retry handler. Responds to retry requests
  /// from recipients who failed to decrypt our messages.
  late final RetryHandler _retryHandler;

  StreamSubscription<Map<String, dynamic>>? _envelopeSub;
  StreamSubscription<Map<String, dynamic>>? _skdmRequestSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeletedSub;
  StreamSubscription<Map<String, dynamic>>? _groupMessagesClearedSub;
  StreamSubscription<bool>? _connectionSub;

  /// Phase 10 P1-B: Server emits `prekeys_low` when one-time prekeys are
  /// nearly exhausted. We listen here and trigger immediate replenishment.
  StreamSubscription<void>? _prekeysLowSub;

  /// Vuln 2 Stage B: server emits `force_prekey_upload` when our device row
  /// is missing identityKeyEd25519 (legacy registration before Phase 5).
  /// Trigger uploadPreKeys() so the server gets the verify key.
  StreamSubscription<Map<String, dynamic>>? _forcePrekeyUploadSub;

  bool _started = false;

  GlobalMessageRouter({
    required SocketManager socketManager,
    required MessageQueue queue,
    required EncryptedMessageHandler e2eeHandler,
    required SignalSessionManager sessionManager,
    required MessageDao messageDao,
    required AttachmentDao attachmentDao,
    required String Function() myIdResolver,
    Ref? ref,
  })  : _socketManager = socketManager,
        _queue = queue,
        _e2eeHandler = e2eeHandler,
        _sessionMgr = sessionManager,
        _messageDao = messageDao,
        _attachmentDao = attachmentDao,
        _myIdResolver = myIdResolver,
        _ref = ref {
    _retryHandler = RetryHandler(
      sessionManager: _sessionMgr,
      socketManager: _socketManager,
      messageSendLog: _sessionMgr.signal.messageSendLog,
    );
  }

  /// Begin routing. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    _envelopeSub = _socketManager.onIncomingEnvelope.listen(_handleIncomingEnvelope);
    _skdmRequestSub = _socketManager.onSenderKeyRequest.listen(_handleSenderKeyRequest);
    _messageDeletedSub = _socketManager.onMessageDeleted.listen(_handleMessageDeleted);
    _groupMessagesClearedSub = _socketManager.groupMessagesClearedStream
        .listen(_handleGroupMessagesCleared);
    _connectionSub = _socketManager.onConnectionChange.listen(_handleConnectionChange);

    // Phase 10 P1-B: Replenish prekeys when server signals low count.
    _prekeysLowSub = _socketManager.onPrekeysLow.listen((_) => _handlePrekeysLow());

    // Vuln 2 Stage B: server requested Ed25519 re-upload (missing on a device).
    _forcePrekeyUploadSub =
        _socketManager.onForcePrekeyUpload.listen(_handleForcePrekeyUpload);

    // Phase 10 P0-E: Start listening for retry requests (sender side).
    _retryHandler.start();

    debugPrint('[GlobalMessageRouter] started');

    // If we are already connected at startup, kick off an initial fetch.
    if (_socketManager.isConnected) {
      _queue.fetchPending();
    }
  }

  /// Stop routing.
  void stop() {
    _envelopeSub?.cancel();
    _skdmRequestSub?.cancel();
    _messageDeletedSub?.cancel();
    _groupMessagesClearedSub?.cancel();
    _connectionSub?.cancel();
    _prekeysLowSub?.cancel();
    _forcePrekeyUploadSub?.cancel();
    _envelopeSub = null;
    _skdmRequestSub = null;
    _messageDeletedSub = null;
    _groupMessagesClearedSub = null;
    _connectionSub = null;
    _prekeysLowSub = null;
    _forcePrekeyUploadSub = null;
    _retryHandler.dispose();
    _started = false;
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  void _handleIncomingEnvelope(Map<String, dynamic> envelope) {
    // [DIAG] Bug 1/2 diagnostic: trace whether GlobalMessageRouter listener fired and forwarding to the queue
    final id = envelope['id'] ?? envelope['messageId'];
    final type = envelope['type'] ?? 'unknown';
    final groupChatId = envelope['groupChatId'];
    debugPrint('[DIAG:Router] forwarding to MessageQueue: id=$id type=$type groupChatId=$groupChatId');
    _queue.enqueue(envelope);
  }

  /// A recipient asked us for the sender key. Re-send our current SKDM via 1:1.
  Future<void> _handleSenderKeyRequest(Map<String, dynamic> data) async {
    final groupId = data['groupId'] as String?;
    final requesterSnow = data['requesterSnowchatId'] as String?;
    debugPrint('[DIAG:SKDMReq] received: groupId=$groupId requester=$requesterSnow');
    try {
      if (groupId == null || requesterSnow == null) {
        debugPrint('[DIAG:SKDMReq] ABORT: missing groupId or requester');
        return;
      }

      final myId = _myIdResolver();
      if (myId.isEmpty) {
        debugPrint('[DIAG:SKDMReq] ABORT: myId empty');
        return;
      }

      final groupSessionMgr = _e2eeHandler.groupSessionManager;
      if (groupSessionMgr == null) {
        debugPrint('[DIAG:SKDMReq] ABORT: groupSessionManager null');
        return;
      }

      // Only respond if we have a sender key for this group.
      if (!groupSessionMgr.hasSenderKey(groupId, myId)) {
        debugPrint('[DIAG:SKDMReq] ABORT: no sender key for groupId=$groupId myId=$myId');
        return;
      }

      final skdm = groupSessionMgr.senderKeyManager.getExistingSKDM(groupId, myId);
      final skdmBytes = skdm.serialize();

      // Wrap in standard 1:1 payload format expected by _processSKDM
      final payload = <String, dynamic>{
        'type': 'sender_key_distribution',
        'text': base64Encode(skdmBytes),
        'timestamp': DateTime.now().toIso8601String(),
      };
      final payloadBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

      // 1:1 encrypt + send
      debugPrint('[DIAG:SKDMReq] establishing session with $requesterSnow');
      await _sessionMgr.ensureSession(requesterSnow);
      final deviceId = await _sessionMgr.getDeviceIdForRecipient(requesterSnow);
      final encrypted = await _sessionMgr.encrypt(requesterSnow, deviceId, payloadBytes);

      _socketManager.sendPrivateMessage({
        'recipientId': requesterSnow,
        'encryptedContent': base64Encode(encrypted['ciphertext'] as Uint8List),
        'type': 'sender_key_distribution',
        'messageType': encrypted['messageType'] as int,
        'groupChatId': groupId,
      });
      debugPrint('[DIAG:SKDMReq] RE-SENT SKDM to $requesterSnow for $groupId '
          '(deviceId=$deviceId)');
    } catch (e) {
      debugPrint('[DIAG:SKDMReq] FAILED groupId=$groupId requester=$requesterSnow error=$e');
    }
  }

  void _handleConnectionChange(bool connected) {
    if (connected) {
      debugPrint('[DIAG:Router] socket reconnected, triggering fetchPending + prekey check');
      _queue.fetchPending();

      // Phase 10 P1-B (Mechanism 5): Replenish prekeys on every reconnect.
      // Signal checks prekey count on every socket connect to prevent
      // prekey exhaustion during offline periods.
      _sessionMgr.checkPreKeyCount().catchError((e) {
        debugPrint('[GlobalMessageRouter] prekey check on reconnect failed: $e');
      });
    } else {
      debugPrint('[DIAG:Router] socket disconnected');
    }
  }

  /// Phase 10 P1-B (Mechanism 5): Server emitted `prekeys_low` — a recipient
  /// consumed one of our one-time prekeys and the remaining count dropped
  /// below threshold. Trigger immediate prekey generation and upload.
  void _handlePrekeysLow() {
    debugPrint('[GlobalMessageRouter] prekeys_low event — triggering replenishment');
    _sessionMgr.checkPreKeyCount().catchError((e) {
      debugPrint('[GlobalMessageRouter] prekey replenishment failed: $e');
    });
  }

  /// Vuln 2 Stage B — server-side `KeyDistributionService.fetchPreKeyBundle`
  /// found a device row missing identityKeyEd25519 and asked us to re-upload.
  /// `uploadPreKeys()` is in-flight-guarded so duplicate emits collapse to a
  /// single network roundtrip; safe to invoke unconditionally on every event.
  void _handleForcePrekeyUpload(Map<String, dynamic> data) {
    final reason = data['reason'] as String? ?? 'unknown';
    debugPrint('[GlobalMessageRouter] force_prekey_upload received '
        '(reason=$reason) — triggering uploadPreKeys');
    _sessionMgr.uploadPreKeys().catchError((e) {
      debugPrint('[GlobalMessageRouter] uploadPreKeys after '
          'force_prekey_upload failed (will retry on socket reconnect): $e');
    });
  }

  /// Delete-for-everyone broadcast handler.
  ///
  /// Server emits `message_deleted` with `{ messageId, messageGuid }` to every
  /// recipient, where `messageId` is THAT recipient's per-row id (matching the
  /// drift row id stored locally). We delete the local row + attachments here
  /// so that:
  ///   1. Any open ChatNotifier's drift watch fires and removes the bubble.
  ///   2. Receivers not currently viewing the chat still drop the message
  ///      from drift before the next entry — previously this only happened
  ///      via MessageRepository which is per-screen.
  Future<void> _handleMessageDeleted(Map<String, dynamic> data) async {
    final messageId = data['messageId'] as String?;
    if (messageId == null || messageId.isEmpty) {
      debugPrint('[GlobalMessageRouter] message_deleted missing messageId — '
          'cannot resolve local row');
      return;
    }
    try {
      // 1. Delete local attachment files (images / files / voice payloads).
      final attachments = await _attachmentDao.getForMessage(messageId);
      for (final att in attachments) {
        if (att.localPath != null && att.localPath!.isNotEmpty) {
          try {
            final f = File(att.localPath!);
            if (f.existsSync()) f.deleteSync();
          } catch (_) {}
        }
      }
      // 2. Delete attachment rows.
      if (attachments.isNotEmpty) {
        await _attachmentDao.deleteForMessage(messageId);
      }
      // 3. Delete the message row — drift watch fires → all open chat screens
      //    rebuild without this message.
      await _messageDao.deleteMessage(messageId);
      debugPrint('[GlobalMessageRouter] removed deleted message $messageId '
          '(${attachments.length} attachments)');
    } catch (e) {
      debugPrint('[GlobalMessageRouter] _handleMessageDeleted failed: $e');
    }
  }

  /// Vuln 3 (Stage 3): a group admin cleared all messages for everyone.
  /// Server emits `group_messages_cleared` to every accepted member except
  /// the admin who triggered it. We mirror that on-device:
  ///   1. Delete every drift message row for the group conversation
  ///   2. Delete every attachment row + on-disk file for those messages
  ///   3. Clear the conversation list preview / unread badge
  ///
  /// Conversation id == groupId for group chats (see message_queue.dart).
  Future<void> _handleGroupMessagesCleared(Map<String, dynamic> data) async {
    final groupId = data['groupChatId'] as String?;
    if (groupId == null || groupId.isEmpty) {
      debugPrint('[GlobalMessageRouter] group_messages_cleared missing groupChatId');
      return;
    }
    debugPrint('[GlobalMessageRouter] group_messages_cleared groupId=$groupId '
        'clearedBy=${data['clearedBy']}');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final messages = await _messageDao.getMessagesForConversation(groupId);

      for (final m in messages) {
        try {
          final atts = await _attachmentDao.getForMessage(m.id);
          for (final att in atts) {
            if (att.localPath != null && att.localPath!.isNotEmpty) {
              try {
                final p = att.localPath!.startsWith('/')
                    ? att.localPath!
                    : '${dir.path}/${att.localPath!}';
                final f = File(p);
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
            }
          }
          if (atts.isNotEmpty) {
            await _attachmentDao.deleteForMessage(m.id);
          }
        } catch (_) {}
      }

      await _messageDao.deleteConversationMessages(groupId);

      // Clear preview / unread in the conversation list (best-effort).
      try {
        _ref?.read(conversationListProvider.notifier).clearPreview(groupId);
      } catch (_) {}

      debugPrint('[GlobalMessageRouter] cleared ${messages.length} messages '
          'for group $groupId');
    } catch (e) {
      debugPrint('[GlobalMessageRouter] _handleGroupMessagesCleared failed: $e');
    }
  }
}
