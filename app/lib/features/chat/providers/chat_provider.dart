/// @file        chat_provider.dart
/// @description Chat UI state-management Provider — delegates the data layer to MessageRepository, manages UI state (typing, reply, TTL, deletion)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-21 (1:1 sends go through the 1:1 outbox (DirectOutbox): text, file and voice are
///              stored and shown at once — also offline, where text used to be dropped — and the
///              outbox uploads / sends / retries them; the 10 s "failed" timer is gone;
///              retryFailedMessage() for the failed bubble). Earlier 2026-11-21 (typing: no typer name in ChatState — it was the raw snow-id the server
///              relays, shown as "snow… is typing…"; the 1:1 header already names the peer).
///              Earlier 2026-11-21 (P5.6: the kept copy of a file or voice message the group refused is deleted; P5.6: removing the chat of a group this account left erases the group too; P5.6: the disappearing-message timers are cancelled only after a clear / leave / end was made — a failed one left the messages without expiry). Earlier 2026-11-21 (P5.6: attachment paths only through AttachmentStorage.relativePathFor — the upload's file id is the server's word; earlier the same day: a text, file or voice message the user sends in a 1:1 vouches for its peer). Earlier same day (comment: the peer is told only by the sealed delete_chat). Earlier 2026-11-20 (v1 groups removed: a chat's id says what it is — the peer's snowId
///              for a 1:1, a v2 group id for a group — so nothing waits for the list to
///              resolve it; no Sender Key send, SKDM broadcast or server group calls; a
///              remote unsend arrives through GlobalMessageRouter only; sent files are
///              always encrypted (the plaintext upload branch is gone). Earlier: group protocol v2: a chat whose id is a v2 group id sends, takes back,
///              clears, leaves and ends through Gv2ChatActions — queued on this device,
///              stored under the final message id — and takes none of the v1 group paths;
///              no typing events for such a group).
///              Earlier 2026-11-12 (a remote "typing…" indicator now clears itself after 6 s unless
///              renewed — a lost / reordered stop event used to leave it on forever).
///              Earlier 2026-11-11 (auto-translate trigger removed from ChatNotifier — the
///              immortal chat provider pushed into the per-screen autoDispose translation
///              cache, so results were dropped for an empty room or a reopened room;
///              translationCacheProvider now drives itself). Earlier same day (at-rest level 1: sent file / voice copies go through AttachmentStorage.ensureDirectory() + protectFile() (iOS backup-excluded, CompleteUnlessOpen)). Earlier 2026-11-10 (B-2 §5.7: IdentityBindingInvalidException / IdentityKeyChangedException handled as terminal — logged once, never retried). Earlier 2026-09-04 (sealed delete-chat: deleteChat() now also sends a sealed_control 'delete_chat' to the peer so an OFFLINE peer loses the room too — ordered AFTER the server DELETE (purgePairRows would wipe a control queued before it) and BEFORE _localCleanup (which wipes the Signal session needed to encrypt it)). Earlier 2026-08-06 (deleteMessageForMe now calls ConversationListNotifier.refreshPreviewAfterDelete(conversationId) after the local delete — covers every sender delete/unsend path (deleteMessageForEveryone routes through it) so unsending the last message advances the Chats-list preview to the surviving newest message instead of lingering the deleted text). Earlier 2026-08-05 (outgoing send (text/file/voice) now persists via MessageRepository.persistOutgoingMessage, which refreshes the drift `conversations` snippet in the same transaction — previously the send path wrote only the message row, so an outgoing-last conversation hydrated from the drift cache as "No messages yet" after restart; status updates still use persistMessage so they don't move the snippet). Earlier 2026-08-03 (F8: clearChat/deleteChat now resolve the shared server CUID via _serverConversationId() (idempotent find-or-create on the peer's snowchatId) before the server DELETE — a snow-id fallback room, created when the peer messages first, 404'd on the CUID-keyed endpoint so the server clear/delete silently no-op'd and Delete's "the other person also loses this conversation" promise broke; deleteChat also tombstones by the CUID so loadFromServer's filter matches). Earlier 2026-07-15 (sealed unsend: deleteMessageForEveryone routes 1:1 delete-for-everyone through EncryptedMessageHandler.sendSealedUnsend (server-opaque) with a client-side 5-min window; group stays on the plaintext server fan-out. Sealed read receipt: wire e2eeHandler + directPeerResolver into MarkReadHelper and e2eeHandler into MessageRepository so read receipts travel E2EE instead of plaintext message_read). Earlier 2026-05-13 (+286: 1:1 sealed sender 활성화. April 13 부터
///              disabled 상태였지만 두 blocker 가 모두 해소됨 — (a)
///              production .env 의 persistent SEALED_SENDER_PRIVATE_KEY
///              박힘 + server "loaded from environment" startup log
///              확인, (b) sealed→regular fallback 코드 자체가 이미 제거
///              + chat_provider catch 가 fail mark only + retry_handler
///              가 fresh session 으로 self-heal (Phase 10 P0-A retry
///              + messageSendLog) → "double-encrypt ratchet corruption"
///              architectural 회피. sendSealedMessage 의 Step 4/5
///              (cert fetch + IK lookup) 도 encrypt 앞으로 reorder
///              해서 ratchet advance 후 throw 가능 지점 제거.
///              Group sealed 은 fan-out 모델 변경 + push UX 정책 필요
///              → V1.1 으로 분리. Earlier +283 sendVoiceMessage E2EE
///              패턴; 2026-05-11 Tier 2A disappearing; 2026-04-26
///              header English.)
///  - Phase 1 Step 6: ChatNotifier split (MessageRepository + MarkReadHelper extracted)
///
/// @functions
///  - chatProvider: family StateNotifierProvider providing a ChatNotifier per conversation
///  - ChatState: chat-screen state data class
///  - ChatNotifier: UI state management (drift watch binding, typing, reply, deletion, send delegation)
///  - ChatNotifier.retryFailedMessage(): send a failed 1:1 message again (1:1 outbox)
///  - ChatNotifier._queueDirectAttachment(): keep, store and queue a 1:1 file / voice message

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/crypto/verified_identity_store.dart' show VouchSource;
import '../../../core/crypto/encrypted_message_handler.dart';
import '../../../core/crypto/file_encryptor.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../core/group_v2/gv2_codec.dart' show gv2IsGroupId;
import '../../../core/messaging/direct_outbox.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/storage/database.dart' hide Conversation;
import '../models/message.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/storage/local_file_protection.dart';
import 'conversation_list_provider.dart';
import 'gv2_chat_actions.dart';
import 'mark_read_helper.dart';
import 'message_repository.dart';

/// Provides messages for a specific conversation.
final chatProvider = StateNotifierProvider.family<
    ChatNotifier, ChatState, String>((ref, conversationId) {
  // Phase 6.9: ref.watch (not ref.read) — rebuild ChatNotifier when
  // currentSnowIdProvider transitions from null → resolved. Without this,
  // the notifier captures an empty myId at cold-start and silently signs
  // sender keys with the wrong identity.
  final mySnowId = ref.watch(currentSnowIdProvider);
  final socketManager = ref.read(socketManagerProvider);
  final apiClient = ref.read(apiClientProvider);
  final messageDao = ref.read(messageDaoProvider);

  // A chat's id says what it is: a 1:1 room is keyed by the peer's snowId,
  // a group protocol v2 group by its id (64 hex characters). Nothing waits
  // for the conversation list, and nothing the server says changes it.
  final isGv2 = gv2IsGroupId(conversationId);
  final String? groupId = isGv2 ? conversationId : null;
  final String? recipientSnowchatId =
      KeyDerivation.isValidSnowChatId(conversationId) ? conversationId : null;

  final repository = MessageRepository(
    conversationId: conversationId,
    messageDao: messageDao,
    attachmentDao: ref.read(attachmentDaoProvider),
    socketManager: socketManager,
    apiClient: apiClient,
    fileService: ref.read(fileServiceProvider),
    e2eeHandler: ref.read(encryptedMessageHandlerProvider),
    myId: mySnowId ?? '',
    recipientId: recipientSnowchatId,
    groupId: groupId,
    ref: ref,
    expiringManager: ref.read(expiringMessageManagerProvider),
  );

  final markReadHelper = MarkReadHelper(
    conversationId: conversationId,
    messageDao: messageDao,
    e2eeHandler: ref.read(encryptedMessageHandlerProvider),
    // Direct chat → peer snowId; group → null (no per-member receipts).
    directPeerResolver: () => repository.recipientId,
    expiringManager: ref.read(expiringMessageManagerProvider),
    myId: mySnowId ?? '',
  );

  final e2eeHandler = ref.read(encryptedMessageHandlerProvider);

  return ChatNotifier(
    conversationId,
    repository: repository,
    markReadHelper: markReadHelper,
    socketManager: socketManager,
    e2eeHandler: e2eeHandler,
    mySnowId: mySnowId,
    secureStorage: ref.read(secureStorageProvider),
    gv2: isGv2
        ? Gv2ChatActions(
            groupId: conversationId,
            runtime: () => ref.read(gv2RuntimeProvider),
            messages: messageDao,
            attachments: ref.read(attachmentDaoProvider),
            groups: ref.read(snowDatabaseProvider).gv2Store,
            mySnowId: mySnowId ?? '',
          )
        : null,
    outbox: isGv2 ? null : ref.read(directOutboxProvider),
    onConversationPreviewStale: (convId) => ref
        .read(conversationListProvider.notifier)
        .refreshPreviewAfterDelete(convId),
    // The user wrote to the peer of a 1:1: they chose that account.
    onUserWrote: (peer) => ref
        .read(verifiedIdentityStoreProvider)
        .vouch(peer, VouchSource.message),
  );
});

/// MIME whitelist for disappearing-mode attachments. Must match the picker
/// constraint in attachment_picker_sheet (FileType.custom +
/// allowedExtensions=['pdf','txt','md']) and the in-app viewer routing in
/// file_message_bubble. Any type added here also needs a viewer that does
/// NOT route through OpenFilex / external apps — otherwise the
/// disappearing TTL promise breaks.
bool _isDisappearingAllowedMime(String mimeType) {
  if (mimeType.startsWith('image/')) return true;
  if (mimeType == 'application/pdf') return true;
  if (mimeType.startsWith('text/')) return true;
  return false;
}

class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final bool isSending;
  /// The 1:1 peer is typing (groups have none). No name: the chat header
  /// already shows who the peer is — the old name field carried the raw
  /// snow-id the server relays, shown as "snow… is typing…".
  final bool isTyping;
  final int? disappearingTTL;
  final Message? replyToMessage;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.isTyping = false,
    this.disappearingTTL,
    this.replyToMessage,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? isSending,
    bool? isTyping,
    int? disappearingTTL,
    bool clearTTL = false,
    Message? replyToMessage,
    bool clearReplyTo = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      isTyping: isTyping ?? this.isTyping,
      disappearingTTL:
          clearTTL ? null : (disappearingTTL ?? this.disappearingTTL),
      replyToMessage:
          clearReplyTo ? null : (replyToMessage ?? this.replyToMessage),
    );
  }
}

/// Outcome of a "Delete for Everyone" (unsend) request, so the UI can give the
/// sender honest feedback instead of a silent (and sometimes false) success.
enum UnsendResult {
  /// The unsend was dispatched (1:1 sealed control sent, v2 unsend queued, or
  /// the message was local-only) — safe to tell the user it was unsent.
  unsent,

  /// The unsend could NOT be dispatched (past the window, socket down, or no
  /// sealed channel to the peer yet). The sender's copy was KEPT so they can
  /// retry — do not claim the peer's copy was removed.
  failed,
}

/// Chat UI state manager. Delegates data operations to MessageRepository.
class ChatNotifier extends StateNotifier<ChatState> {
  final String conversationId;
  final MessageRepository _repo;
  final MarkReadHelper _markReadHelper;
  final SocketManager? _socketManager;
  final EncryptedMessageHandler? _e2eeHandler;
  final SecureStorageService? _secureStorage;
  final String _myId;

  /// Set for a group protocol v2 group: what this chat does goes through
  /// it. Null for a 1:1 room.
  final Gv2ChatActions? _gv2;

  /// The 1:1 outbox (app-wide): sends this chat's outgoing messages and keeps
  /// them until the server acks them. Null for a v2 group.
  final DirectOutbox? _outbox;

  StreamSubscription<List<LocalMessage>>? _messageWatchSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;

  final Map<String, Timer> _deletionTimers = {};
  final Map<String, MessageStatus> _pendingStatuses = {};
  Timer? _typingDebounceTimer;
  DateTime? _lastTypingSent;

  static const _typingSendInterval = Duration(seconds: 2);
  static const _typingStopDelay = Duration(seconds: 3);

  /// How long a remote "typing…" stays on without being renewed.
  static const _remoteTypingTimeout = Duration(seconds: 6);
  Timer? _remoteTypingTimer;

  /// Invoked after a local message delete/unsend so the Chats-list preview can
  /// be recomputed. ChatNotifier has no Ref; the provider wires this to
  /// ConversationListNotifier.refreshPreviewAfterDelete(conversationId).
  void Function(String conversationId)? onConversationPreviewStale;

  /// Called with the peer when the user sends a message of their own in a
  /// 1:1 (never for what the app sends by itself).
  final Future<void> Function(String peer)? _onUserWrote;

  ChatNotifier(
    this.conversationId, {
    required MessageRepository repository,
    required MarkReadHelper markReadHelper,
    SocketManager? socketManager,
    EncryptedMessageHandler? e2eeHandler,
    String? mySnowId,
    SecureStorageService? secureStorage,
    Gv2ChatActions? gv2,
    DirectOutbox? outbox,
    this.onConversationPreviewStale,
    Future<void> Function(String peer)? onUserWrote,
  })  : _repo = repository,
        _outbox = outbox,
        _onUserWrote = onUserWrote,
        _gv2 = gv2,
        _markReadHelper = markReadHelper,
        _socketManager = socketManager,
        _e2eeHandler = e2eeHandler,
        _secureStorage = secureStorage,
        _myId = mySnowId ?? '',
        super(const ChatState()) {
    // Wire up repository callbacks for immediate UI updates
    _repo.onIncomingMessage = _addIncomingMessage;
    _repo.onMessageStatusChanged = _handleStatusChange;

    _loadMessages();
    _repo.startSocketListeners();
    _subscribeToMessages();
    _listenToTyping();
    _repo.resumePendingDownloads();
  }

  /// Convenience getters delegated to repository. [recipientId] is the
  /// peer's snowId of a 1:1 room (its id); [groupId] the id of a v2 group.
  String? get recipientId => _repo.recipientId;
  String? get groupId => _repo.groupId;

  /// The user is sending a message of their own in this 1:1: its peer is an
  /// account they chose (the group pickers' "known").
  void _userWroteToPeer() {
    final peer = recipientId;
    final onUserWrote = _onUserWrote;
    if (peer == null || onUserWrote == null) return;
    unawaited(
      onUserWrote(peer).catchError((Object e) {
        debugPrint('[Chat] vouch not stored: ${e.runtimeType}');
      }),
    );
  }
  bool get isGroup => _repo.isGroup;

  /// Whether this chat is a group protocol v2 group (the only kind of group).
  bool get isGv2 => _gv2 != null;

  @override
  void dispose() {
    _messageWatchSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingDebounceTimer?.cancel();
    _remoteTypingTimer?.cancel();
    for (final timer in _deletionTimers.values) {
      timer.cancel();
    }
    _deletionTimers.clear();
    _markReadHelper.dispose();
    _repo.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Drift watch stream (reactive SSoT)
  // ---------------------------------------------------------------------------

  void _subscribeToMessages() {
    _messageWatchSubscription = _repo.watchMessages().listen(
      (dbMessages) {
        if (!mounted) return;

        final driftMessages =
            dbMessages.map(MessageRepository.convertToMessage).toList();

        // Preserve in-flight "sending" messages not yet in drift
        final sendingMessages = state.messages
            .where((m) => m.status == MessageStatus.sending)
            .toList();
        final driftIds = driftMessages.map((m) => m.id).toSet();
        final mergedSending =
            sendingMessages.where((m) => !driftIds.contains(m.id)).toList();

        final merged = [...driftMessages, ...mergedSending];
        merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        state = state.copyWith(messages: merged, isLoading: false);
        // Auto-translation is driven by translationCacheProvider, which
        // listens to this state while the chat screen is open.
      },
      onError: (e) {
        debugPrint('[ChatNotifier:$conversationId] Drift watch error: $e');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Message loading
  // ---------------------------------------------------------------------------

  Future<void> _loadMessages() async {
    state = state.copyWith(isLoading: true);

    // Load from drift DB (SSoT)
    final driftMessages = await _repo.loadFromDrift();
    if (driftMessages.isNotEmpty) {
      state = state.copyWith(messages: driftMessages, isLoading: false);
    }

    // Fetch from server for offline/missed messages
    final serverMessages = await _repo.fetchFromServer();
    if (serverMessages != null && serverMessages.isNotEmpty && mounted) {
      _repo.persistServerMessages(serverMessages);
      _repo.updateConversationListPreview(serverMessages);
    }

    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }

    // Ensure attachment rows exist for file messages received while outside chat.
    // When user was outside the chat room, _processIncomingAttachments didn't run.
    _repo.ensureAttachmentsForFileMessages();
  }

  /// Phase 5.6: Refresh messages from server.
  /// Called from ChatScreen.initState whenever the user navigates into the chat.
  /// ChatNotifier persists across navigation (Riverpod), so _loadMessages only
  /// runs once at first entry. Without this refresh, messages received while
  /// the user was in another app or chat are not fetched.
  Future<void> refresh() async {
    final serverMessages = await _repo.fetchFromServer();
    if (serverMessages != null && serverMessages.isNotEmpty && mounted) {
      _repo.persistServerMessages(serverMessages);
      _repo.updateConversationListPreview(serverMessages);
    }
  }

  // ---------------------------------------------------------------------------
  // Repository callbacks
  // ---------------------------------------------------------------------------

  void _addIncomingMessage(Message message) {
    if (!mounted) return;
    if (state.messages.any((m) => m.id == message.id)) return;

    final newMessages = List<Message>.from(state.messages)..add(message);
    state = state.copyWith(messages: newMessages);
    debugPrint(
        '[ChatNotifier:$conversationId] addIncomingMessage OK: ${message.id} (total: ${newMessages.length})');
    _scheduleDeletionIfNeeded(message);
  }

  void _handleStatusChange(String messageId, MessageStatus newStatus,
      {String? serverMessageId}) async {
    if (!mounted) return;
    // The status of a v2 group message comes from this device's outbox
    // (Gv2Runtime.sendEvents, written to the row), never from the socket.
    if (isGv2) return;

    if (newStatus == MessageStatus.sent && serverMessageId != null) {
      // Update drift FIRST: attachment messageId + message ID (atomic).
      // This ensures attachmentWatchProvider(CUID) returns results
      // BEFORE the widget rebuilds with the new message ID.
      await _repo.updateOutgoingStatusWithAttachment(
          messageId, 'sent', serverMessageId);
      // Rekey expiration timer (localId → serverId)
      _repo.expiringManager?.rekey(messageId, serverMessageId);
      if (!mounted) return;
      // Then update in-memory state (drift watch will also fire)
      state = state.copyWith(
        messages: state.messages.map((m) {
          if (m.id == messageId) {
            return Message(
              id: serverMessageId,
              conversationId: m.conversationId,
              senderSnowchatId: m.senderSnowchatId,
              plaintext: m.plaintext,
              timestamp: m.timestamp,
              type: m.type,
              status: MessageStatus.sent,
              metadata: m.metadata,
              expiresAt: m.expiresAt,
              ttlSeconds: m.ttlSeconds,
              replyToId: m.replyToId,
              replyToPreview: m.replyToPreview,
              replyToSenderId: m.replyToSenderId,
              isDeleted: m.isDeleted,
              senderDisplayName: m.senderDisplayName,
            );
          }
          return m;
        }).toList(),
      );
      // Apply any pending statuses that arrived during async sent processing
      if (_pendingStatuses.containsKey(serverMessageId)) {
        final pending = _pendingStatuses.remove(serverMessageId)!;
        // Update drift DB — watch will rebuild UI
        _repo.updateOutgoingStatusInDrift(serverMessageId, pending.name);
      }
    } else {
      final hasMessage = state.messages.any((m) => m.id == messageId);
      if (!hasMessage) {
        // Race condition: delivered/read arrive before sent handler replaces
        // localId → serverId. Queue the highest priority status.
        final existing = _pendingStatuses[messageId];
        if (existing == null || newStatus.index > existing.index) {
          _pendingStatuses[messageId] = newStatus;
        }
        return;
      }
      // Update drift DB FIRST — drift watch will rebuild UI with correct status.
      // Do NOT update in-memory state here; the watch subscription handles it.
      _repo.updateOutgoingStatusInDrift(messageId, newStatus.name);
    }
  }

  void _updateMessageStatus(String messageId, MessageStatus status) {
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (m.id == messageId) return m.copyWith(status: status);
        return m;
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Sending (delegates to repository)
  // ---------------------------------------------------------------------------

  Future<void> sendMessage(String text) async {
    final replyTo = state.replyToMessage;
    clearReplyTo();

    debugPrint('[DIAG:Send] sendMessage entry: convId=$conversationId '
        'gv2=$isGv2');

    // Group protocol v2: queued on this device (it leaves when the group can
    // send, also after a reconnect), stored under its final id.
    final gv2 = _gv2;
    if (gv2 != null) {
      final ttl = state.disappearingTTL;
      try {
        final id = await gv2.send(
          text: text,
          snippet: text,
          ttlSeconds: ttl,
          replyToId: replyTo?.id,
          replyToPreview: replyTo?.plaintext,
          replyToSenderId: replyTo?.senderSnowchatId,
        );
        if (ttl != null) _repo.expiringManager?.schedule(id, ttl);
      } catch (e) {
        debugPrint('[Chat] v2 group send refused: ${e.runtimeType}');
        _gv2Refused(text, MessageType.text);
      }
      return;
    }

    if (_socketManager == null) {
      debugPrint('[DIAG:Send] ABORT: socketManager null');
      return;
    }
    if (recipientId == null) {
      debugPrint('[DIAG:Send] ABORT: not a 1:1 room or a v2 group '
          '(convId=$conversationId)');
      return;
    }
    _userWroteToPeer();
    // Connected or not: the message is stored and shown now; the 1:1 outbox
    // sends it when it can (it used to be dropped here while offline).

    final messageId =
        'msg_${DateTime.now().millisecondsSinceEpoch}_${text.hashCode.abs()}';
    final now = DateTime.now();

    // Add locally immediately
    final ttl = state.disappearingTTL;
    final localMessage = Message(
      id: messageId,
      conversationId: conversationId,
      senderSnowchatId: _myId,
      plaintext: text,
      timestamp: now,
      type: MessageType.text,
      status: MessageStatus.sending,
      expiresAt: ttl != null ? now.add(Duration(seconds: ttl)) : null,
      ttlSeconds: ttl,
      replyToId: replyTo?.id,
      replyToPreview: replyTo?.plaintext,
      replyToSenderId: replyTo?.senderSnowchatId,
    );
    state = state.copyWith(messages: [...state.messages, localMessage]);

    // Persist to drift (including TTL for app restart recovery).
    // persistOutgoingMessage also refreshes the conversation snippet so an
    // outgoing-last chat doesn't hydrate as "No messages yet" after restart.
    await _repo.persistOutgoingMessage(
      LocalMessagesCompanion(
        id: Value(messageId),
        conversationId: Value(conversationId),
        senderSnowchatId: Value(_myId),
        plaintext: Value(text),
        dateSent: Value(now.millisecondsSinceEpoch),
        dateReceived: Value(now.millisecondsSinceEpoch),
        type: const Value('text'),
        read: const Value(true),
        outgoingStatus: const Value('sending'),
        expiresIn: Value(ttl ?? 0),
        expireStarted: Value(ttl != null ? now.millisecondsSinceEpoch : 0),
        replyToId: Value(replyTo?.id),
        // 2026-05-08 schema v10 — persist the same denormalized quote
        // fields we already keep on the in-memory Message, so the watch
        // stream's drift-loaded version doesn't lose the quote text.
        replyToPreview: Value(replyTo?.plaintext),
        replyToSenderId: Value(replyTo?.senderSnowchatId),
      ),
      snippetText: text,
      sentTimestamp: now.millisecondsSinceEpoch,
    );

    // Schedule expiration deletion
    if (ttl != null) {
      _repo.expiringManager?.schedule(messageId, ttl);
    }

    // The 1:1 outbox sends it — E2EE only (sealed when available), encrypted
    // at the moment it leaves, kept and tried again until the server acks it
    // (core/messaging/direct_outbox.dart). Its status comes back on the row.
    final outbox = _outbox;
    if (outbox == null) {
      debugPrint('[Chat] 1:1 outbox unavailable — message $messageId not sent');
      _repo.updateOutgoingStatusInDrift(messageId, 'failed');
      _updateMessageStatus(messageId, MessageStatus.failed);
      onUserStoppedTyping();
      return;
    }
    await outbox.enqueueText(
      messageId: messageId,
      peer: recipientId!,
      text: text,
      ttlSeconds: ttl,
      replyToId: replyTo?.id,
      replyToPreview: replyTo?.plaintext,
      replyToSenderId: replyTo?.senderSnowchatId,
    );

    onUserStoppedTyping();
  }

  /// Send the failed 1:1 message [messageId] again (the bubble's retry). The
  /// same message and id go out again through the 1:1 outbox; the peer stores
  /// it once even if an earlier copy did arrive.
  Future<void> retryFailedMessage(String messageId) async {
    final outbox = _outbox;
    if (outbox == null || isGv2) return;
    final queued = await outbox.retry(messageId);
    if (!queued) {
      debugPrint('[Chat] $messageId cannot be sent again (nothing to send it from)');
    }
  }

  // _sendPlaintext removed (2026-04-08): SnowChat is E2EE-only. No plaintext
  // socket fallback under any condition. See chat_provider's sendMessage
  // fail-fast path when _e2eeHandler is null.

  Future<void> sendFileMessage({
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async {
    if (_socketManager == null) return;
    if (!isGv2 && recipientId == null) return;
    if (!isGv2) _userWroteToPeer();

    // Tier 2A defense-in-depth: disappearing mode is restricted to MIME types
    // we have in-app viewers for — image/* (image_viewer_screen),
    // application/pdf (pdf_viewer_screen), text/* (text_file_viewer_screen).
    // Anything else would route through OpenFilex on the receiving device,
    // handing the decrypted file to a system viewer that exposes save/forward
    // outside our control — the TTL promise would be a lie. The
    // attachment_picker_sheet already constrains the picker in this mode, so
    // reaching this branch with a disallowed MIME implies a non-UI caller
    // (future code) or a modded sender. Log + abort.
    if (state.disappearingTTL != null && !_isDisappearingAllowedMime(mimeType)) {
      debugPrint('[ChatNotifier] sendFileMessage rejected — disallowed mime '
          '($mimeType) in disappearing mode');
      return;
    }

    final messageId =
        'msg_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs()}';
    final now = DateTime.now();

    // 1. Add local message immediately (sending state)
    final ttl = state.disappearingTTL;
    final localMessage = Message(
      id: messageId,
      conversationId: conversationId,
      senderSnowchatId: _myId,
      plaintext: fileName,
      timestamp: now,
      type: MessageType.file,
      status: MessageStatus.sending,
      expiresAt: ttl != null ? now.add(Duration(seconds: ttl)) : null,
      ttlSeconds: ttl,
      metadata: {'fileName': fileName, 'mimeType': mimeType},
    );
    state = state.copyWith(
      messages: [...state.messages, localMessage],
    );

    // 1:1: stored, shown and queued now — the 1:1 outbox uploads and sends
    // it (also later, offline or after a restart).
    if (!isGv2) {
      await _queueDirectAttachment(
        messageId: messageId,
        sourcePath: filePath,
        kind: MessageType.file,
        text: fileName,
        fileName: fileName,
        keptName: fileName,
        mimeType: mimeType,
        now: now,
        ttl: ttl,
      );
      return;
    }

    // 2. Group protocol v2: encrypt the file content + upload, then the group
    //    queues the message under its final id.
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;

      // Encrypt file content with a random key (XSalsa20-Poly1305). Always:
      // the server stores only the encrypted blob (zero-knowledge) — there
      // is no plaintext upload, whatever path sends the message.
      final encResult =
          await FileEncryptor.encryptFile(Uint8List.fromList(bytes));
      final fileId = await _repo.fileService!.uploadEncryptedFile(
          encResult.encryptedData, encResult.contentHash);
      final fileKeyB64 = base64Encode(encResult.fileKey);
      final contentHash = encResult.contentHash;

      // 3. Build metadata (fileKey travels inside the E2EE payload only)
      final metadata = {
        'fileId': fileId,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': fileSize,
        'fileKey': fileKeyB64,
        'contentHash': contentHash,
        'attachments': [
          {
            'fileId': fileId,
            'fileName': fileName,
            'mimeType': mimeType,
            'size': fileSize,
          }
        ],
      };

      // Group protocol v2: the message row and its attachment row are
      // written with the queued message, under its final id; the row shown
      // while the file was uploading goes.
      final gv2 = _gv2!;
      final relativePath = await _keepOutgoingFile(
        filePath,
        AttachmentStorage.relativePathFor(fileId, fileName, fallbackExtension: 'jpg'),
      );
      final id = await _withKeptFile(relativePath, () => gv2.send(
        text: fileName,
        snippet: fileName,
        type: MessageType.file.name,
        metadata: metadata,
        ttlSeconds: ttl,
        attachment: (id) => LocalAttachmentsCompanion(
          id: Value('att_${id}_0'),
          messageId: Value(id),
          displayOrder: const Value(0),
          contentType: Value(mimeType),
          fileName: Value(fileName),
          fileSize: Value(fileSize),
          remoteFileId: Value(fileId),
          localPath: Value(relativePath),
          transferState: const Value(0), // DONE
        ),
      ));
      _dropInMemory(messageId);
      if (ttl != null) _repo.expiringManager?.schedule(id, ttl);
    } catch (e) {
      debugPrint('[ChatNotifier] File upload failed: $e');
      _updateMessageStatus(messageId, MessageStatus.failed);
    }
  }

  Future<void> sendVoiceMessage({
    required String audioPath,
    required int durationSeconds,
  }) async {
    // Voice now follows the exact same E2EE path as files: encrypt the
    // m4a body, upload the ciphertext, then send a Signal DR envelope
    // whose plaintext is the file metadata (fileId + fileKey + duration +
    // ...). Up through +282 sendVoiceMessage published a raw socket frame
    // without `encryptedContent`, which the server rejects with
    // `INVALID_REQUEST: recipientId and encryptedContent required` — so
    // voice messages between Galaxy and iPhone never landed at all. Logged
    // 2026-05-12 iPhone Console: AVError -11829 was the SENDER's own
    // bubble failing on a 28-byte corrupt m4a (separate VoiceRecorder
    // guard); the cross-device half was the missing encryption.
    if (_socketManager == null) return;
    if (!isGv2 && recipientId == null) return;
    if (!isGv2) _userWroteToPeer();
    if (_repo.fileService == null) {
      debugPrint('[Chat] fileService unavailable — voice send aborted');
      return;
    }
    if (_e2eeHandler == null) {
      debugPrint('[Chat] E2EE handler unavailable — refusing to send voice '
          '(message would have leaked audio metadata)');
      return;
    }

    state = state.copyWith(isSending: true);

    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_voice';
    final now = DateTime.now();
    final ttl = state.disappearingTTL;
    // WAV chosen 2026-05-12 (+285) after record_ios m4a wrapping turned
    // out to be permanently broken — see voice_recorder.dart header for
    // the iPhone 17 logcat showing a 12-second recording stuck at 28
    // bytes. mimeType has to match the container so the recipient's
    // attachment download writes the right extension and audioplayers
    // picks the right decoder on both ends.
    final fileName = 'voice_${now.millisecondsSinceEpoch}.wav';
    const mimeType = 'audio/wav';

    // Optimistic local message — duration is enough to render the bubble.
    // localPath / fileId get folded in once the upload completes and the
    // permanent copy lands under snowchat_attachments/.
    final localMessage = Message(
      id: messageId,
      conversationId: conversationId,
      senderSnowchatId: _myId,
      plaintext: 'Voice message',
      timestamp: now,
      type: MessageType.voice,
      status: MessageStatus.sending,
      metadata: {'duration': durationSeconds, 'mimeType': mimeType},
      expiresAt: ttl != null ? now.add(Duration(seconds: ttl)) : null,
      ttlSeconds: ttl,
    );
    state = state.copyWith(
      messages: [...state.messages, localMessage],
      isSending: false,
    );

    // 1:1: stored, shown and queued now — the 1:1 outbox uploads and sends
    // it (also later, offline or after a restart).
    if (!isGv2) {
      await _queueDirectAttachment(
        messageId: messageId,
        sourcePath: audioPath,
        kind: MessageType.voice,
        text: 'Voice message',
        fileName: fileName,
        keptName: 'voice.wav',
        mimeType: mimeType,
        now: now,
        ttl: ttl,
        durationSeconds: durationSeconds,
      );
      _scheduleDeletionIfNeeded(localMessage);
      return;
    }

    try {
      // 1. Encrypt audio + upload ciphertext (Zero-Knowledge).
      final file = File(audioPath);
      if (!await file.exists()) {
        debugPrint('[Chat] voice file missing on disk: $audioPath');
        _updateMessageStatus(messageId, MessageStatus.failed);
        return;
      }
      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;

      final encResult =
          await FileEncryptor.encryptFile(Uint8List.fromList(bytes));
      final fileId = await _repo.fileService!
          .uploadEncryptedFile(encResult.encryptedData, encResult.contentHash);
      final fileKeyB64 = base64Encode(encResult.fileKey);

      // 2. Build E2EE metadata. `attachments: [...]` matches the multi-shape
      // the recipient's MessageQueue._processIncomingAttachments consumes.
      final metadata = <String, dynamic>{
        'fileId': fileId,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': fileSize,
        'duration': durationSeconds,
        'fileKey': fileKeyB64,
        'contentHash': encResult.contentHash,
        'attachments': [
          {
            'fileId': fileId,
            'fileName': fileName,
            'mimeType': mimeType,
            'size': fileSize,
          }
        ],
      };

      // Group protocol v2: as for a file (sendFileMessage).
      final gv2 = _gv2!;
      final relativePath = await _keepOutgoingFile(
        audioPath,
        AttachmentStorage.relativePathFor(fileId, 'voice.wav'),
      );
      final id = await _withKeptFile(relativePath, () => gv2.send(
        text: 'Voice message',
        snippet: 'Voice message',
        type: MessageType.voice.name,
        metadata: metadata,
        ttlSeconds: ttl,
        attachment: (id) => LocalAttachmentsCompanion(
          id: Value('att_${id}_0'),
          messageId: Value(id),
          displayOrder: const Value(0),
          contentType: Value(mimeType),
          fileName: Value(fileName),
          fileSize: Value(fileSize),
          remoteFileId: Value(fileId),
          localPath: Value(relativePath),
          transferState: const Value(0), // DONE
        ),
      ));
      _dropInMemory(messageId);
      if (ttl != null) _repo.expiringManager?.schedule(id, ttl);
    } catch (e, st) {
      debugPrint('[Chat] voice send exception: $e\n$st');
      _updateMessageStatus(messageId, MessageStatus.failed);
    }
  }

  /// A 1:1 file or voice message [messageId] (already shown in memory):
  /// keep the plaintext at its permanent place (under a local id — the
  /// server's file id comes with the upload), store the message as `sending`
  /// with its attachment row, and hand it to the 1:1 outbox, which uploads
  /// and sends it. Upload and send no longer depend on this screen or on the
  /// network at this moment.
  Future<void> _queueDirectAttachment({
    required String messageId,
    required String sourcePath,
    required MessageType kind,
    required String text,
    required String fileName,
    required String keptName,
    required String mimeType,
    required DateTime now,
    required int? ttl,
    int? durationSeconds,
  }) async {
    final outbox = _outbox;
    final peer = recipientId;
    if (outbox == null || peer == null) {
      debugPrint('[Chat] 1:1 outbox unavailable — attachment $messageId not sent');
      _updateMessageStatus(messageId, MessageStatus.failed);
      return;
    }
    try {
      final size = await File(sourcePath).length();
      final relativePath = await _keepOutgoingFile(
        sourcePath,
        AttachmentStorage.relativePathFor(const Uuid().v4(), keptName,
            fallbackExtension: 'jpg'),
      );
      // What the bubble needs until the upload adds the file id and key.
      final shown = <String, dynamic>{
        'fileName': fileName,
        'mimeType': mimeType,
        'size': size,
        'duration': ?durationSeconds,
      };
      await _repo.persistOutgoingMessage(
        LocalMessagesCompanion(
          id: Value(messageId),
          conversationId: Value(conversationId),
          senderSnowchatId: Value(_myId),
          plaintext: Value(text),
          dateSent: Value(now.millisecondsSinceEpoch),
          dateReceived: Value(now.millisecondsSinceEpoch),
          type: Value(kind.name),
          metadata: Value(jsonEncode(shown)),
          read: const Value(true),
          outgoingStatus: const Value('sending'),
          expiresIn: Value(ttl ?? 0),
          expireStarted: Value(ttl != null ? now.millisecondsSinceEpoch : 0),
        ),
        snippetText: text,
        sentTimestamp: now.millisecondsSinceEpoch,
      );
      // The attachment row shows the kept copy now (the bubbles watch it);
      // the outbox adds the server file id once uploaded.
      await _repo.attachmentDao?.insertAttachment(LocalAttachmentsCompanion(
        id: Value('att_${messageId}_0'),
        messageId: Value(messageId),
        displayOrder: const Value(0),
        contentType: Value(mimeType),
        fileName: Value(fileName),
        fileSize: Value(size),
        localPath: Value(relativePath),
        transferState: const Value(0), // DONE — the plaintext is here
      ));
      await outbox.enqueueAttachment(
        messageId: messageId,
        peer: peer,
        kind: kind,
        text: text,
        relativePath: relativePath,
        fileName: fileName,
        mimeType: mimeType,
        size: size,
        durationSeconds: durationSeconds,
        ttlSeconds: ttl,
      );
      if (ttl != null) _repo.expiringManager?.schedule(messageId, ttl);
    } catch (e) {
      debugPrint('[Chat] attachment $messageId not queued: ${e.runtimeType}');
      _updateMessageStatus(messageId, MessageStatus.failed);
    }
  }

  /// Copy the plaintext of an outgoing attachment to its permanent place
  /// [relativePath] (from AttachmentStorage.relativePathFor) for local
  /// display. Returns it — relative to the app documents directory, immune
  /// to iOS container UUID changes.
  Future<String> _keepOutgoingFile(String sourcePath, String relativePath) async {
    final dir = await getApplicationDocumentsDirectory();
    await AttachmentStorage.ensureDirectory();
    await File(sourcePath).copy('${dir.path}/$relativePath');
    // File.copy carries source metadata — enforce the attachment class.
    await AttachmentStorage.protectFile('${dir.path}/$relativePath');
    return relativePath;
  }

  /// Send through the group what refers to the file kept at
  /// [relativePath]. When the group does not take it, nothing refers to the
  /// copy, and it goes (it is the plaintext of what was not sent).
  Future<String> _withKeptFile(
    String relativePath,
    Future<String> Function() send,
  ) async {
    try {
      return await send();
    } catch (_) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final copy = File('${dir.path}/$relativePath');
        if (await copy.exists()) await copy.delete();
      } catch (_) {
        // An orphan file: gone with the attachments of a reinstall.
      }
      rethrow;
    }
  }

  /// Remove a message that lives in memory only (the row shown while an
  /// attachment uploads) once its stored row took its place.
  void _dropInMemory(String messageId) {
    if (!mounted) return;
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  /// A v2 group did not take what this account wrote (it is not in the
  /// group any more, or the group is frozen): the text is shown as failed.
  /// In memory only — nothing was queued or stored.
  void _gv2Refused(String text, MessageType type) {
    if (!mounted) return;
    final now = DateTime.now();
    state = state.copyWith(
      messages: [
        ...state.messages,
        Message(
          id: 'msg_${now.millisecondsSinceEpoch}_${text.hashCode.abs()}',
          conversationId: conversationId,
          senderSnowchatId: _myId,
          plaintext: text,
          timestamp: now,
          type: type,
          status: MessageStatus.failed,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Read receipts
  // ---------------------------------------------------------------------------

  void markMessagesAsRead() {
    _markReadHelper.markAllVisibleAsRead();
  }

  // ---------------------------------------------------------------------------
  // Typing indicator
  // ---------------------------------------------------------------------------

  void _listenToTyping() {
    _typingSubscription = _socketManager?.onTyping.listen((data) {
      // 1:1 only — a v2 group has no typing indicator (design §12). The
      // server sends the typer's snow-id (metadata-min Batch 2); it counts
      // only when it is this chat's peer.
      final fromSnow = data['fromSnowchatId'] as String?;
      final peer = recipientId;
      if (fromSnow == null || peer == null || fromSnow != peer) return;
      final stopped = data['stopped'] as bool? ?? false;
      _applyRemoteTyping(!stopped);
    });
  }

  /// Show / hide the peer's "typing…" indicator.
  ///
  /// A shown indicator clears itself after [_remoteTypingTimeout] unless a
  /// newer typing event renews it. The stop event is not guaranteed to arrive
  /// (the typer disconnected, the server dropped or reordered it), and without
  /// this timeout the indicator stayed on forever in those cases. A typer who
  /// keeps typing re-sends typing_start every [_typingSendInterval], well
  /// inside the timeout.
  void _applyRemoteTyping(bool typing) {
    _remoteTypingTimer?.cancel();
    _remoteTypingTimer = null;
    if (!mounted) return;
    setTyping(typing);
    if (typing) {
      _remoteTypingTimer = Timer(_remoteTypingTimeout, () {
        if (mounted) setTyping(false);
      });
    }
  }

  void onUserTyping() {
    // 1:1 only: the server is told nothing about a v2 group.
    final peer = recipientId;
    if (peer == null) return;
    final sm = _socketManager;
    if (sm == null || !sm.isConnected) return;

    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) >= _typingSendInterval) {
      sm.sendTyping(recipientSnowchatId: peer);
      _lastTypingSent = now;
    }

    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(_typingStopDelay, () {
      onUserStoppedTyping();
    });
  }

  void onUserStoppedTyping() {
    _typingDebounceTimer?.cancel();
    _lastTypingSent = null;
    final peer = recipientId;
    if (peer == null) return;
    _socketManager?.stopTyping(recipientSnowchatId: peer);
  }

  void setTyping(bool typing) {
    state = state.copyWith(isTyping: typing);
  }

  // ---------------------------------------------------------------------------
  // Reply / Quote
  // ---------------------------------------------------------------------------

  void setReplyTo(Message message) {
    state = state.copyWith(replyToMessage: message);
  }

  void clearReplyTo() {
    state = state.copyWith(clearReplyTo: true);
  }

  // ---------------------------------------------------------------------------
  // Disappearing messages
  // ---------------------------------------------------------------------------

  void setDisappearingTimer(int? seconds) {
    if (seconds == null) {
      state = state.copyWith(clearTTL: true);
    } else {
      state = state.copyWith(disappearingTTL: seconds);
    }
  }

  void _scheduleMessageDeletion(String messageId, Duration duration) {
    _deletionTimers[messageId]?.cancel();
    _deletionTimers[messageId] = Timer(duration, () {
      if (!mounted) return;
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != messageId).toList(),
      );
      _deletionTimers.remove(messageId);
    });
  }

  void _scheduleDeletionIfNeeded(Message message) {
    if (message.expiresAt == null) return;
    final remaining = message.expiresAt!.difference(DateTime.now());
    if (remaining.isNegative) {
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != message.id).toList(),
      );
      return;
    }
    _scheduleMessageDeletion(message.id, remaining);
  }

  // ---------------------------------------------------------------------------
  // Message deletion
  // ---------------------------------------------------------------------------

  /// Delete a message from my device only (received or sent).
  /// Physically removes message + attachments + local files from drift.
  Future<void> deleteMessageForMe(String messageId) async {
    // Remove from in-memory state immediately (prevents merge logic re-adding sending messages)
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
    _deletionTimers[messageId]?.cancel();
    _deletionTimers.remove(messageId);
    _repo.expiringManager?.cancel(messageId);
    // Physical delete (drift + attachments + local files)
    await _repo.deleteMessageLocally(messageId);
    // Recompute the Chats-list preview: if this was the conversation's last
    // message, the denormalized snippet must advance to the surviving newest
    // message (or clear), else the deleted text lingers in the list.
    onConversationPreviewStale?.call(conversationId);
  }

  /// Delete a message for everyone (sender only).
  /// 1:1 → sealed E2EE unsend (server never sees it is a delete). v2 group →
  /// an unsend signed with this account's Sender Key.
  /// For unsent messages (local ID), only deletes locally.
  Future<UnsendResult> deleteMessageForEveryone(String messageId) async {
    final message = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null || !message.isMine(_myId)) return UnsendResult.failed;

    // Group protocol v2: an unsend signed with this account's Sender Key —
    // the members remove their copy (design §12). The own copy goes only
    // when the unsend was queued.
    final gv2 = _gv2;
    if (gv2 != null) {
      if (!message.isWithinUnsendWindow) return UnsendResult.failed;
      if (!await gv2.unsend(messageId)) return UnsendResult.failed;
      await deleteMessageForMe(messageId);
      return UnsendResult.unsent;
    }

    // Local-only (never left the device) → just remove our copy; nothing to
    // propagate, so this is a clean success.
    if (messageId.startsWith('msg_')) {
      await deleteMessageForMe(messageId);
      return UnsendResult.unsent;
    }

    final peer = _repo.recipientId;
    if (peer != null && _e2eeHandler != null) {
      // 1:1 → sealed unsend. The server no longer mediates 1:1 deletes, so the
      // window is enforced here (same as the context-menu gate). Only remove our
      // OWN copy once the unsend was actually dispatched — otherwise the peer
      // keeps their copy and deleting ours would falsely imply success (socket
      // down, or no sealed channel to the peer yet). Keep the message so the
      // sender can retry.
      if (!message.isWithinUnsendWindow) return UnsendResult.failed;
      bool dispatched;
      try {
        dispatched = await _e2eeHandler
            .sendSealedUnsend(recipientId: peer, deleteIds: [messageId]);
      } catch (e) {
        debugPrint('[Chat] sealed unsend failed: $e');
        dispatched = false;
      }
      if (!dispatched) return UnsendResult.failed;
      await deleteMessageForMe(messageId);
      return UnsendResult.unsent;
    }

    // 1:1 whose peer / e2ee handler couldn't be resolved → we cannot propagate
    // the unsend, so keep the message and report failure rather than silently
    // deleting our copy (which would falsely imply it was removed everywhere).
    return UnsendResult.failed;
  }

  /// Vuln 3 (Stage 3): Local-only Clear Chat.
  /// Deletes messages + attachments locally without any network call (used
  /// when the server clear failed, or a v2 group member who is neither owner
  /// nor admin clears only this device). The conversation row stays in the
  /// list.
  Future<void> clearChatLocally() async {
    for (final m in state.messages) {
      _deletionTimers[m.id]?.cancel();
      _deletionTimers.remove(m.id);
      _repo.expiringManager?.cancel(m.id);
    }
    await _repo.clearMessagesLocally();
    if (mounted) {
      state = state.copyWith(messages: const []);
    }
  }

  /// Phase 11: Clear Chat — delete all messages but keep the conversation.
  /// Server deletes messages only; local cleanup removes messages + files.
  /// The conversation stays in the list (empty, ready for new messages).
  ///
  /// P1-2 (2026-04-18): server failure now RETHROWS so the caller can show
  /// a SnackBar AND skip local cleanup. Previously a 403/network failure was
  /// silently swallowed and the local store was wiped anyway, breaking
  /// cross-device sync (other devices still see messages, this one doesn't,
  /// and re-fetch could re-populate them).
  ///
  /// Caller (chat_screen `_confirmClearChat`) must wrap this in try/catch.
  /// If the user explicitly wants a local-only clear, they should call
  /// [clearChatLocally] instead — it never touches the server.
  Future<void> clearChat() async {
    // The disappearing-message timers are cancelled only once the clear was
    // made: when it fails the messages stay, and must still expire.

    // Group protocol v2: the members are told (they honour it from an owner
    // or admin only); the own copy goes once that is queued. Throws when it
    // cannot be said — nothing is removed then.
    final gv2 = _gv2;
    if (gv2 != null) {
      await gv2.clearHistory();
      _cancelAllTimers();
      await _repo.clearMessagesLocally();
      if (mounted) state = state.copyWith(messages: const []);
      return;
    }

    // 2. Clear on SERVER (1:1 messages only, keep the conversation row). The
    // server keys a 1:1 by the peer's snowId (metadata-min Batch 2).
    // Failure paths: 401 (auth), network. ALL rethrow so the caller can
    // present a SnackBar + offer the local-only alternative.
    final apiClient = _repo.apiClient;
    final peer = recipientId;
    if (apiClient == null || peer == null) {
      throw StateError('clearChat: no API client or no 1:1 peer — '
          'use clearChatLocally() for a local-only clear');
    }

    try {
      await apiClient.delete('/conversations/$peer/messages');
      debugPrint('[Chat] clearChat: server clear success');
    } catch (e) {
      debugPrint('[Chat] clearChat: server clear failed ($e) — '
          'skipping local cleanup to keep cross-device state in sync');
      // The timers were not touched: the messages that stay still expire.
      rethrow;
    }

    // 3. Local cleanup (messages + attachments, keep conversation row).
    //    Only reached on server 2xx — guarantees both sides agree on "empty".
    _cancelAllTimers();
    await _repo.clearMessagesLocally();

    // 4. Clear in-memory state
    if (mounted) {
      state = state.copyWith(messages: const []);
    }
  }

  /// Delete a 1:1 chat (WhatsApp/Signal pattern).
  ///
  /// Removes the conversation row, all messages, all attachment rows, and
  /// all local attachment files. The peer is unaffected — there is no
  /// "leave conversation" concept on the server for 1:1 chats. If the peer
  /// messages us again, the conversation is naturally re-created by
  /// MessageQueue's _processPrivate1to1.findOrCreate path.
  Future<void> deleteChat() async {
    _cancelAllTimers();

    // A v2 group's chat is removed from this device only (what is left of a
    // group this account is no longer in): the server holds no 1:1 room for
    // it and is told nothing. The group goes with it.
    if (isGv2) {
      await _gv2?.forgetGroup();
      await _localCleanup();
      return;
    }

    // The server keys a 1:1 by the peer's snowId (the room's id).
    final peer = recipientId;
    if (peer == null) {
      await _localCleanup();
      return;
    }

    final apiClient = _repo.apiClient;
    if (apiClient != null) {
      final serverId = peer;
      try {
        await apiClient.delete('/conversations/$serverId');
        debugPrint('[Chat] deleteChat: server DELETE success');
        if (_secureStorage != null) {
          await removeDeletedConvId(_secureStorage, serverId);
        }
      } catch (e) {
        debugPrint('[Chat] deleteChat: 1:1 server DELETE failed ($e), tombstoning');
        // Tombstone by the room id — loadFromServer filters against it, and
        // _retryPendingDeletions repeats the server DELETE.
        if (_secureStorage != null) {
          await addDeletedConvId(_secureStorage, serverId);
        }
      }
    }

    // Tell the peer over the sealed_control channel — the only way the peer
    // learns of it (the server says nothing). The control is queued like any
    // other message, so an OFFLINE peer applies it on their next connect.
    //
    // Ordering is load-bearing:
    //  - AFTER the server DELETE, because purgePairRows() wipes every sealed
    //    row for this pair — a control queued before it would delete itself.
    //  - BEFORE _localCleanup(), which wipes the peer's Signal session and
    //    would leave nothing to encrypt the envelope with.
    if (_e2eeHandler != null) {
      try {
        final dispatched =
            await _e2eeHandler.sendSealedDeleteChat(recipientId: peer);
        debugPrint('[Chat] deleteChat: sealed delete_chat dispatched=$dispatched');
      } catch (e) {
        // Best-effort, exactly like unsend: our own delete still proceeds.
        debugPrint('[Chat] deleteChat: sealed delete_chat failed: $e');
      }
    }

    await _localCleanup();
  }

  /// End the group (owner only) in its change log. Throws
  /// (Gv2GroupException) when that could not be done — nothing is removed
  /// then — and StateError for a chat that is not a group.
  Future<void> deleteGroup() async {
    final gv2 = _requireGroup('deleteGroup');
    await gv2.end();
    // Only once it was made: on a failure the messages stay, and expire.
    _cancelAllTimers();
    await _localCleanup();
  }

  /// Leave the group without taking back this account's messages: a LEAVE
  /// in the change log (an owner hands the group over first). Throws
  /// (Gv2GroupException) when it could not be made — this account is then
  /// still a member and nothing is removed — and StateError for a chat that
  /// is not a group.
  Future<void> leaveGroup() async {
    final gv2 = _requireGroup('leaveGroup');
    await gv2.leave();
    _cancelAllTimers(); // only once it was made (see deleteGroup)
    await _localCleanup();
  }

  /// Leave the group and take back this account's messages: an unsend for
  /// each, then the LEAVE (design §12). Throws like [leaveGroup].
  Future<void> leaveAndDeleteMyMessages() async {
    final gv2 = _requireGroup('leaveAndDeleteMyMessages');
    await gv2.leave(deleteMyMessages: true);
    _cancelAllTimers(); // only once it was made (see deleteGroup)
    await _localCleanup();
  }

  /// The v2 group actions of this chat; StateError when it is a 1:1 room.
  Gv2ChatActions _requireGroup(String action) {
    final gv2 = _gv2;
    if (gv2 == null) {
      throw StateError('$action: $conversationId is not a group');
    }
    return gv2;
  }

  /// Cancel all pending TTL / deletion timers for this chat.
  void _cancelAllTimers() {
    for (final m in state.messages) {
      _deletionTimers[m.id]?.cancel();
      _deletionTimers.remove(m.id);
      _repo.expiringManager?.cancel(m.id);
    }
  }

  /// Shared local cleanup: delete drift rows + files, clear in-memory state.
  Future<void> _localCleanup() async {
    await _repo.deleteConversationLocally();
    if (mounted) {
      state = state.copyWith(messages: const []);
    }
  }
}
