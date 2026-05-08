/// @file        message_repository.dart
/// @description Message data layer — drift DB read/write, server API fetch, socket-receive handlers
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-01
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-12 Phase 10 P0-B: added decryption_failed mapping in parseOutgoingStatus)
///
/// @functions
///  - MessageRepository: message data layer (drift SSoT, server fetch, socket reception)
///  - loadFromDrift(): load messages from drift DB
///  - fetchFromServer(): fetch messages from server API (offline support)
///  - persistMessage(): persist a single message into drift DB
///  - persistServerMessages(): batch-persist messages fetched from server
///  - watchMessages(): return a drift watch stream
///  - startSocketListeners(): register socket event listeners
///  - convertToMessage(): LocalMessage -> Message conversion
///  - updateConversationListPreview(): update conversation-list preview
///  - deleteMessageLocally(): delete a single message + attachments + local files
///  - deleteConversationLocally(): delete the entire conversation + all attachments + local files + conversation row
///  - clearMessagesLocally(): delete messages + attachments + local files (keep conversation row — Clear Chat)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../app/providers.dart';
import '../../../core/crypto/file_encryptor.dart';
// Phase 6: SenderKeyDistributionMessage import removed (handled by MessageQueue)
import '../../../core/network/api_client.dart';
// Phase 6: api_endpoints removed — fetch is via MessageQueue.fetchPending()
import '../../../core/network/file_service.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/storage/daos/attachment_dao.dart';
import '../../../core/storage/daos/message_dao.dart';
import '../../../core/storage/database.dart' hide Conversation;
import '../../../core/storage/tables/attachments_table.dart';
import '../models/message.dart';
import 'conversation_list_provider.dart';
import 'expiring_message_manager.dart';
import 'mark_read_helper.dart';

/// Data layer for chat messages. Handles drift DB, server API, and socket events.
/// Separated from ChatNotifier to follow Signal's Repository pattern.
class MessageRepository {
  final String conversationId;
  final MessageDao _messageDao;
  final AttachmentDao? _attachmentDao;
  final SocketManager? _socketManager;
  final ApiClient? _apiClient;
  final FileService? _fileService;
  final String _myId;
  final Ref? _ref;
  final ExpiringMessageManager? _expiringManager;

  String? recipientId;
  String? groupId;
  bool get isGroup => groupId != null;

  /// Callback for when a new incoming message is received via socket.
  /// ChatNotifier sets this to update UI state immediately.
  void Function(Message message)? onIncomingMessage;

  /// Callback for when message status changes (sent/delivered/read).
  void Function(String messageId, MessageStatus newStatus, {String? serverMessageId})?
      onMessageStatusChanged;

  /// Callback for when a message is remotely deleted.
  void Function(String messageId)? onMessageDeleted;

  StreamSubscription<Map<String, dynamic>>? _messageStatusSubscription;
  StreamSubscription<Map<String, dynamic>>? _messageDeletedSubscription;

  MessageRepository({
    required this.conversationId,
    required MessageDao messageDao,
    AttachmentDao? attachmentDao,
    SocketManager? socketManager,
    ApiClient? apiClient,
    FileService? fileService,
    required String myId,
    this.recipientId,
    this.groupId,
    Ref? ref,
    ExpiringMessageManager? expiringManager,
  })  : _messageDao = messageDao,
        _attachmentDao = attachmentDao,
        _socketManager = socketManager,
        _apiClient = apiClient,
        _fileService = fileService,
        _myId = myId,
        _ref = ref,
        _expiringManager = expiringManager;

  /// Access ExpiringMessageManager for TTL scheduling.
  ExpiringMessageManager? get expiringManager => _expiringManager;

  /// Access FileService for attachment upload/download.
  FileService? get fileService => _fileService;

  /// Access ApiClient for server API calls (e.g., group member fetch).
  ApiClient? get apiClient => _apiClient;

  /// Access AttachmentDao for sender-side attachment creation.
  AttachmentDao? get attachmentDao => _attachmentDao;

  /// Update outgoing message status in drift DB (ID replacement + status).
  void updateOutgoingStatusInDrift(String messageId, String newStatus,
      {String? serverMessageId}) {
    _messageDao
        .updateOutgoingStatus(messageId, newStatus,
            serverMessageId: serverMessageId)
        .catchError((e) {
      debugPrint('[MessageRepo] updateOutgoingStatus failed: $e');
    });
  }

  /// Atomically update message ID + attachment messageId in drift.
  /// Prevents race condition where drift watch fires between the two updates.
  Future<void> updateOutgoingStatusWithAttachment(
      String localMessageId, String newStatus, String serverMessageId) async {
    try {
      // First: update attachment messageId
      await _attachmentDao?.updateMessageId(localMessageId, serverMessageId);
      // Then: update message ID in drift (triggers watch AFTER attachment is ready)
      await _messageDao.updateOutgoingStatus(localMessageId, newStatus,
          serverMessageId: serverMessageId);
    } catch (e) {
      debugPrint('[MessageRepo] updateOutgoingStatusWithAttachment failed: $e');
    }
  }

  /// Physically delete a message + attachments + local files from drift.
  /// Used by deleteForMe, deleteForEveryone, and remote deletion.
  Future<void> deleteMessageLocally(String messageId) async {
    try {
      // 1. Delete local attachment files
      final attachments = await _attachmentDao?.getForMessage(messageId);
      if (attachments != null) {
        for (final att in attachments) {
          if (att.localPath != null) {
            try {
              final file = File(att.localPath!);
              if (file.existsSync()) file.deleteSync();
            } catch (_) {}
          }
        }
        // 2. Delete attachment rows
        await _attachmentDao?.deleteForMessage(messageId);
      }
      // 3. Delete message row (triggers drift watch → UI update)
      await _messageDao.deleteMessage(messageId);
    } catch (e) {
      debugPrint('[MessageRepo] deleteMessageLocally failed: $e');
    }
  }

  /// Delete the entire conversation locally (WhatsApp/Signal "Delete chat"
  /// pattern). Removes:
  ///   1. All attachment files under snowchat_attachments/
  ///   2. All attachment rows for messages in this conversation
  ///   3. All message rows for this conversation
  ///   4. The conversation row itself
  ///
  /// The peer is unaffected — there is no server-side leave for 1:1. If they
  /// message us again the conversation is auto-recreated by MessageQueue's
  /// _processPrivate1to1.findOrCreate path.
  Future<void> deleteConversationLocally() async {
    try {
      // 2026-05-04 회귀 fix: 1:1 conversation 의 경우 peer 의 SnowChat ID 를
      // 미리 조회. 아래에서 conversation row 가 삭제되면 participantIds 를
      // 더 이상 못 읽으므로 *반드시* 삭제 전에 추출해야 함.
      String? peerSnowIdToWipe;
      if (_ref != null) {
        try {
          final convDao = _ref!.read(conversationDaoProvider);
          final conv = await convDao.getConversation(conversationId);
          if (conv != null && conv.type == 'direct' && conv.groupId == null) {
            // participantIds = JSON array of SnowChat IDs (self + peer for 1:1).
            // Pick the entry that isn't us.
            final mySnow = _ref!.read(currentSnowIdProvider);
            final list = (jsonDecode(conv.participantIds) as List)
                .cast<String>();
            for (final p in list) {
              if (p != mySnow) {
                peerSnowIdToWipe = p;
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('[MessageRepo] peer lookup before delete failed '
              '(non-fatal): $e');
        }
      }

      final dao = _attachmentDao;
      if (dao != null) {
        // Resolve relative paths against the current Documents dir.
        final dir = await getApplicationDocumentsDirectory();
        final messages =
            await _messageDao.getMessagesForConversation(conversationId);
        for (final m in messages) {
          final atts = await dao.getForMessage(m.id);
          for (final att in atts) {
            if (att.localPath != null && att.localPath!.isNotEmpty) {
              try {
                final path = att.localPath!.startsWith('/')
                    ? att.localPath!
                    : '${dir.path}/${att.localPath!}';
                final f = File(path);
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
            }
          }
          if (atts.isNotEmpty) {
            await dao.deleteForMessage(m.id);
          }
        }
      }
      // Delete conversation row + all message rows in one transaction.
      if (_ref != null) {
        final convDao = _ref!.read(conversationDaoProvider);
        await convDao.deleteConversation(conversationId);
      }

      // 2026-05-04 회귀 fix: 1:1 인 경우 Signal SessionStore 도 wipe.
      // drift row 만 지우고 ratchet state 남기면 같은 peer 와 다시 메시지
      // 주고받을 때 stale state 로 decrypt 시도 → 실패 → archiveAndResetSession
      // → 양쪽 동시 reset → X3DH bootstrap race → 서로 다른 session 생성 →
      // session_reset 무한 loop (사용자 보고 "1:1 채팅 삭제 후 같은 peer 와
      // 메시징 + 그룹 통신 모두 깨짐" 2026-05-04). deleteSessionForPeer 는
      // peer 한테 알림 안 보냄 — 우리만 깨끗해지고, peer 가 다음 메시지 보낼
      // 때 prekey-message 가 X3DH bootstrap 트리거해서 fresh session 자연
      // convergence.
      if (peerSnowIdToWipe != null && _ref != null) {
        try {
          final sessionMgr = _ref!.read(signalSessionManagerProvider);
          await sessionMgr.deleteSessionForPeer(peerSnowIdToWipe);
        } catch (e) {
          debugPrint('[MessageRepo] signal session wipe for '
              '$peerSnowIdToWipe failed (non-fatal): $e');
        }
      }
    } catch (e) {
      debugPrint('[MessageRepo] deleteConversationLocally failed: $e');
    }
  }

  /// Phase 11: Clear Chat — delete all messages + attachments + local files
  /// but KEEP the conversation row. The chat stays in the list (empty).
  Future<void> clearMessagesLocally() async {
    try {
      final dao = _attachmentDao;
      if (dao != null) {
        final dir = await getApplicationDocumentsDirectory();
        final messages =
            await _messageDao.getMessagesForConversation(conversationId);
        for (final m in messages) {
          final atts = await dao.getForMessage(m.id);
          for (final att in atts) {
            if (att.localPath != null && att.localPath!.isNotEmpty) {
              try {
                final path = att.localPath!.startsWith('/')
                    ? att.localPath!
                    : '${dir.path}/${att.localPath!}';
                final f = File(path);
                if (f.existsSync()) f.deleteSync();
              } catch (_) {}
            }
          }
          if (atts.isNotEmpty) {
            await dao.deleteForMessage(m.id);
          }
        }
      }
      // Delete messages only (keep conversation row)
      await _messageDao.deleteConversationMessages(conversationId);
    } catch (e) {
      debugPrint('[MessageRepo] clearMessagesLocally failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Drift DB operations
  // ---------------------------------------------------------------------------

  /// Load messages from drift DB (SSoT).
  Future<List<Message>> loadFromDrift() async {
    try {
      final rows = await _messageDao.getMessagesForConversation(conversationId);
      return rows.map(convertToMessage).toList();
    } catch (e) {
      debugPrint('[MessageRepo:$conversationId] Drift load failed: $e');
      return [];
    }
  }

  /// Watch drift DB for real-time message changes.
  Stream<List<LocalMessage>> watchMessages() {
    return _messageDao.watchMessages(conversationId);
  }

  /// Persist a single message to drift DB (fire-and-forget).
  Future<void> persistMessage(LocalMessagesCompanion companion) async {
    try {
      await _messageDao.upsertMessage(companion);
    } catch (e) {
      debugPrint('[MessageRepo:$conversationId] Drift persist failed: $e');
    }
  }

  /// Batch-persist server-fetched messages to drift DB.
  /// Own messages → read=true. Others' messages → read=false (unread).
  /// Skip own file messages — local sendFileMessage + ACK handles these
  /// correctly with proper attachment bindings. Re-inserting with CUID
  /// before the ACK arrives would break the attachment messageId link.
  void persistServerMessages(List<Message> messages) {
    final isViewing = MarkReadHelper.isConversationActive(conversationId);
    for (final msg in messages) {
      final isOwn = msg.senderSnowchatId == _myId;
      // Skip own file messages: local message + ACK flow handles ID replacement
      // and attachment messageId binding atomically.
      if (isOwn && msg.type == MessageType.file) continue;
      // Skip E2EE messages from server — they have no plaintext (text=null).
      // The decrypted plaintext was stored in drift during real-time socket reception.
      // Re-upserting would overwrite the decrypted content with empty text.
      if (msg.plaintext.isEmpty && msg.type == MessageType.text) continue;
      final metadataJson =
          msg.metadata != null ? jsonEncode(msg.metadata) : null;
      // Send read receipt immediately for messages viewed in real-time
      if (!isOwn && isViewing && msg.id.isNotEmpty) {
        _socketManager?.sendReadReceipt([msg.id]);
      }
      persistMessage(LocalMessagesCompanion(
        id: Value(msg.id),
        conversationId: Value(msg.conversationId),
        senderSnowchatId: Value(msg.senderSnowchatId),
        plaintext: Value(msg.plaintext),
        dateSent: Value(msg.timestamp.millisecondsSinceEpoch),
        dateReceived: Value(msg.timestamp.millisecondsSinceEpoch),
        type: Value(msg.type.name),
        metadata: Value(metadataJson),
        read: Value(isOwn || isViewing),
        outgoingStatus: Value(msg.status.name),
        senderDisplayName: Value(msg.senderDisplayName),
        replyToId: Value(msg.replyToId),
        // 2026-05-08 schema v10 — round-trip the quote fields so the
        // bubble's `replyToPreview != null` render guard actually sees
        // the data after drift's watch stream replaces in-memory state.
        replyToPreview: Value(msg.replyToPreview),
        replyToSenderId: Value(msg.replyToSenderId),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Server API fetch
  // ---------------------------------------------------------------------------

  /// Fetch messages from server. Phase 3: all IDs are server CUIDs.
  /// Phase 6: Trigger the global MessageQueue to fetch from the server queue.
  /// The queue handles decryption + drift insert; no return value needed.
  /// Returns null so callers can keep the existing flow (legacy callers used
  /// the return value to call persistServerMessages, but the queue persists
  /// directly).
  Future<List<Message>?> fetchFromServer() async {
    if (_ref == null) return null;
    try {
      await _ref!.read(messageQueueProvider).fetchPending();
    } catch (e) {
      debugPrint('[MessageRepo] queue fetchPending failed: $e');
    }
    return null;
  }

  /// Update conversation list preview with the latest message.
  void updateConversationListPreview(List<Message> messages) {
    if (messages.isEmpty || _ref == null) return;
    final sorted = [...messages]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final lastMsg = sorted.last;
    try {
      _ref!.read(conversationListProvider.notifier).updatePreview(
            conversationId,
            text: lastMsg.plaintext,
            senderId: lastMsg.senderSnowchatId,
            messageTime: lastMsg.timestamp,
          );
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Socket listeners
  // ---------------------------------------------------------------------------

  /// Phase 6: Subscribe only to message status + remote deletion events.
  /// Incoming messages (1:1, group, SKDM, system) are handled by the
  /// global MessageQueue which writes to drift; this repository observes
  /// drift via watchMessages() and never decrypts.
  void startSocketListeners() {
    final sm = _socketManager;
    if (sm == null) return;

    // Message status changes (sent → delivered → read)
    _messageStatusSubscription = sm.onMessageStatus.listen(_handleMessageStatus);

    // Remote deletion
    _messageDeletedSubscription =
        sm.onMessageDeleted.listen(_handleMessageDeleted);
  }

  // Phase 6: _handlePrivateMessage / _handleGroupMessage / _handleSenderKeyDistribution
  // removed. All incoming message processing is now in
  // app/lib/core/messaging/message_queue.dart (single serial worker, atomic
  // drift writes, ACK after success).

  void _handleMessageStatus(Map<String, dynamic> data) {
    final serverMsgId = data['messageId'] as String?;
    final statusStr = data['status'] as String?;
    debugPrint('[DIAG:StatusRecv] messageId=$serverMsgId status=$statusStr convId=$conversationId');
    if (statusStr == null) return;

    final newStatus = parseStatus(statusStr);
    if (newStatus == null) return;

    if (newStatus == MessageStatus.sent) {
      final clientMsgId = data['clientMessageId'] as String?;
      if (clientMsgId == null && serverMsgId == null) return;
      onMessageStatusChanged?.call(
        clientMsgId ?? serverMsgId!,
        newStatus,
        serverMessageId: serverMsgId,
      );
    } else {
      if (serverMsgId == null) return;
      onMessageStatusChanged?.call(serverMsgId, newStatus);
    }
  }

  void _handleMessageDeleted(Map<String, dynamic> data) {
    final messageId = data['messageId'] as String?;
    if (messageId != null) {
      onMessageDeleted?.call(messageId);
    }
  }

  // ---------------------------------------------------------------------------
  // Attachment download
  // ---------------------------------------------------------------------------

  /// Process attachments from incoming message metadata.
  /// Inserts attachment rows to drift and triggers auto-download.
  void _processIncomingAttachments(String messageId, Map<String, dynamic> data) {
    final dao = _attachmentDao;
    if (dao == null || _fileService == null) return;

    // Parse attachments from metadata
    final metadata = data['metadata'];
    if (metadata is! Map) return;

    // E2EE file decryption key (present when file was encrypted before upload)
    final fileKeyB64 = metadata['fileKey'] as String?;
    final contentHash = metadata['contentHash'] as String?;

    final attachments = metadata['attachments'];
    if (attachments is! List || attachments.isEmpty) {
      // Single attachment fallback (legacy format)
      final fileId = metadata['fileId'] as String?;
      if (fileId == null) return;
      final att = LocalAttachmentsCompanion(
        id: Value('att_${messageId}_0'),
        messageId: Value(messageId),
        displayOrder: const Value(0),
        contentType: Value((metadata['mimeType'] ?? 'application/octet-stream') as String),
        fileName: Value(metadata['fileName'] as String?),
        fileSize: Value((metadata['size'] as int?) ?? 0),
        remoteFileId: Value(fileId),
        transferState: const Value(TransferState.pending),
      );
      dao.insertAttachment(att);
      _downloadAttachment('att_${messageId}_0', fileId,
          metadata['fileName'] as String? ?? fileId,
          fileKeyB64: fileKeyB64, contentHash: contentHash);
      return;
    }

    // Multi-attachment format
    for (var i = 0; i < attachments.length; i++) {
      final a = Map<String, dynamic>.from(attachments[i] as Map);
      final fileId = a['fileId'] as String?;
      if (fileId == null) continue;
      final attId = 'att_${messageId}_$i';
      dao.insertAttachment(LocalAttachmentsCompanion(
        id: Value(attId),
        messageId: Value(messageId),
        displayOrder: Value(i),
        contentType: Value((a['mimeType'] ?? 'application/octet-stream') as String),
        fileName: Value(a['fileName'] as String?),
        fileSize: Value((a['size'] as int?) ?? 0),
        width: Value((a['width'] as int?) ?? 0),
        height: Value((a['height'] as int?) ?? 0),
        remoteFileId: Value(fileId),
        transferState: const Value(TransferState.pending),
      ));
      _downloadAttachment(attId, fileId, a['fileName'] as String? ?? fileId,
          fileKeyB64: fileKeyB64, contentHash: contentHash);
    }
  }

  /// Download a single attachment, decrypt if E2EE, and save locally.
  /// Stores RELATIVE path (snowchat_attachments/{fileId}.{ext}) in drift
  /// so it survives iOS container UUID changes across flutter run / OS updates.
  ///
  /// If [fileKeyB64] is provided, the downloaded blob is decrypted with
  /// XSalsa20-Poly1305 before saving (Zero-Knowledge: server stores only ciphertext).
  Future<void> _downloadAttachment(
      String attachmentId, String fileId, String fileName,
      {String? fileKeyB64, String? contentHash}) async {
    final dao = _attachmentDao;
    final fs = _fileService;
    if (dao == null || fs == null) return;

    try {
      await dao.markStarted(attachmentId);

      final encryptedBytes = await fs.downloadEncryptedFile(fileId);

      // Decrypt if E2EE file key is available
      Uint8List plainBytes;
      if (fileKeyB64 != null) {
        final fileKey = Uint8List.fromList(base64Decode(fileKeyB64));
        plainBytes = await FileEncryptor.decryptFile(
          encryptedBytes, fileKey, expectedHash: contentHash);
        debugPrint('[MessageRepo] Decrypted file $fileId '
            '(${encryptedBytes.length}B → ${plainBytes.length}B)');
      } else {
        plainBytes = encryptedBytes;
      }

      // Save plaintext to local storage
      final dir = await getApplicationDocumentsDirectory();
      final attachDir = Directory('${dir.path}/snowchat_attachments');
      if (!attachDir.existsSync()) {
        attachDir.createSync(recursive: true);
      }
      final ext = fileName.contains('.') ? fileName.split('.').last : 'bin';
      // Store relative path — immune to iOS container UUID changes
      final relativePath = 'snowchat_attachments/$fileId.$ext';
      await File('${dir.path}/$relativePath').writeAsBytes(plainBytes);

      await dao.finalizeDownload(attachmentId, relativePath);
      debugPrint('[MessageRepo] Downloaded attachment $fileId → $relativePath');
    } catch (e) {
      debugPrint('[MessageRepo] Download attachment $fileId failed: $e');
      await dao.markFailed(attachmentId);
    }
  }

  /// Ensure attachment rows exist for file messages that were received
  /// while the user was outside the chat room (no ChatNotifier was active).
  Future<void> ensureAttachmentsForFileMessages() async {
    final dao = _attachmentDao;
    if (dao == null) return;

    try {
      final messages = await _messageDao.getMessagesForConversation(conversationId);
      for (final msg in messages) {
        if (msg.type != 'file') continue;

        // Check if attachment already exists
        final existing = await dao.getForMessage(msg.id);
        if (existing.isNotEmpty) continue;

        // Parse metadata to get fileId
        if (msg.metadata == null || msg.metadata!.isEmpty) continue;
        Map<String, dynamic>? metadata;
        try {
          final decoded = jsonDecode(msg.metadata!);
          if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
        } catch (_) {
          continue;
        }
        if (metadata == null) continue;

        // Create attachment rows and trigger download
        _processIncomingAttachments(msg.id, {'metadata': metadata});
        debugPrint('[MessageRepo] Created missing attachment for ${msg.id}');
      }
    } catch (e) {
      debugPrint('[MessageRepo] ensureAttachments failed: $e');
    }
  }

  /// Resume incomplete downloads + re-download missing files (called on app startup).
  /// Handles: pending, started, failed states + done state with missing file
  /// (e.g., iOS container UUID changed after flutter run / OS update).
  Future<void> resumePendingDownloads() async {
    final dao = _attachmentDao;
    if (dao == null) return;

    // 1. Retry incomplete/failed downloads
    final pending = await dao.getPendingDownloads();
    for (final att in pending) {
      if (att.remoteFileId != null) {
        _downloadAttachment(att.id, att.remoteFileId!, att.fileName ?? att.id);
      }
    }
    if (pending.isNotEmpty) {
      debugPrint('[MessageRepo] Resuming ${pending.length} pending downloads');
    }

    // 2. Re-download "done" attachments whose local file is missing
    //    (iOS container UUID change, file cleanup, etc.)
    final done = await dao.getDoneAttachments();
    final dir = await getApplicationDocumentsDirectory();
    var redownloadCount = 0;
    for (final att in done) {
      if (att.remoteFileId == null || att.localPath == null) continue;
      // Resolve relative or absolute path
      final absPath = att.localPath!.startsWith('/')
          ? att.localPath!
          : '${dir.path}/${att.localPath!}';
      if (!File(absPath).existsSync()) {
        redownloadCount++;
        _downloadAttachment(att.id, att.remoteFileId!, att.fileName ?? att.id);
      }
    }
    if (redownloadCount > 0) {
      debugPrint('[MessageRepo] Re-downloading $redownloadCount missing files');
    }
  }

  // ---------------------------------------------------------------------------
  // Converters
  // ---------------------------------------------------------------------------

  /// Convert drift LocalMessage to app Message model.
  static Message convertToMessage(LocalMessage row) {
    // Parse metadata JSON string back to Map
    Map<String, dynamic>? metadata;
    if (row.metadata != null && row.metadata!.isNotEmpty) {
      try {
        final decoded = jsonDecode(row.metadata!);
        if (decoded is Map) metadata = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    // Restore expiry from drift columns
    final expiresAtMs = (row.expiresIn > 0 && row.expireStarted > 0)
        ? row.expireStarted + row.expiresIn * 1000
        : null;

    return Message(
      id: row.id,
      conversationId: row.conversationId,
      senderSnowchatId: row.senderSnowchatId,
      plaintext: row.plaintext,
      timestamp: DateTime.fromMillisecondsSinceEpoch(row.dateSent),
      type: parseMessageType(row.type),
      status: parseOutgoingStatus(row.outgoingStatus),
      metadata: metadata,
      expiresAt: expiresAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
          : null,
      ttlSeconds: row.expiresIn > 0 ? row.expiresIn : null,
      senderDisplayName: row.senderDisplayName,
      replyToId: row.replyToId,
      // 2026-05-08 schema v10 — drift columns added so the quote bubble
      // can render after a watch-stream rebuild without losing context.
      replyToPreview: row.replyToPreview,
      replyToSenderId: row.replyToSenderId,
      isDeleted: row.remoteDeleted,
    );
  }

  static MessageType parseMessageType(String type) {
    return MessageType.values.firstWhere(
      (t) => t.name == type,
      orElse: () => MessageType.text,
    );
  }

  static MessageStatus parseOutgoingStatus(String status) {
    switch (status) {
      case 'sending':
        return MessageStatus.sending;
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read_by_recipient':
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      case 'decryption_failed':
        return MessageStatus.decryptionFailed;
      default:
        return MessageStatus.sent;
    }
  }

  static MessageStatus? parseStatus(String status) {
    switch (status) {
      case 'sent':
        return MessageStatus.sent;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      case 'failed':
        return MessageStatus.failed;
      default:
        return null;
    }
  }

  /// Parse TTL from socket data. Prefers exact expiresIn, falls back to bucket.
  static int? _parseExpiryFromSocket(Map<String, dynamic> data) {
    // Exact TTL (sent by client in socket payload)
    final expiresIn = data['expiresIn'] as int?;
    if (expiresIn != null && expiresIn > 0) return expiresIn;
    // Fallback: bucket from server relay
    return _bucketToSeconds(data['expiryBucket'] as String?);
  }

  /// Convert server expiryBucket to TTL seconds.
  static int? _bucketToSeconds(String? bucket) {
    switch (bucket) {
      case '1m':
        return 60;
      case '5m':
        return 300;
      case '30m':
        return 1800;
      case '1h':
        return 3600;
      default:
        return null;
    }
  }

  /// Clean up subscriptions.
  void dispose() {
    _messageStatusSubscription?.cancel();
    _messageDeletedSubscription?.cancel();
  }
}
