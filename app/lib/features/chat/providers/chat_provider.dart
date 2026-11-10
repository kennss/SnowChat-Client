/// @file        chat_provider.dart
/// @description Chat UI state-management Provider — delegates the data layer to MessageRepository, manages UI state (typing, reply, TTL, deletion)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-10 (B-2 §5.7: IdentityBindingInvalidException / IdentityKeyChangedException handled as terminal — logged once, never retried). Earlier 2026-09-04 (sealed delete-chat: deleteChat() now also sends a sealed_control 'delete_chat' to the peer so an OFFLINE peer loses the room too — ordered AFTER the server DELETE (purgePairRows would wipe a control queued before it) and BEFORE _localCleanup (which wipes the Signal session needed to encrypt it)). Earlier 2026-08-06 (deleteMessageForMe now calls ConversationListNotifier.refreshPreviewAfterDelete(conversationId) after the local delete — covers every sender delete/unsend path (deleteMessageForEveryone routes through it) so unsending the last message advances the Chats-list preview to the surviving newest message instead of lingering the deleted text). Earlier 2026-08-05 (outgoing send (text/file/voice) now persists via MessageRepository.persistOutgoingMessage, which refreshes the drift `conversations` snippet in the same transaction — previously the send path wrote only the message row, so an outgoing-last conversation hydrated from the drift cache as "No messages yet" after restart; status updates still use persistMessage so they don't move the snippet). Earlier 2026-08-03 (F8: clearChat/deleteChat now resolve the shared server CUID via _serverConversationId() (idempotent find-or-create on the peer's snowchatId) before the server DELETE — a snow-id fallback room, created when the peer messages first, 404'd on the CUID-keyed endpoint so the server clear/delete silently no-op'd and Delete's "the other person also loses this conversation" promise broke; deleteChat also tombstones by the CUID so loadFromServer's filter matches). Earlier 2026-07-15 (sealed unsend: deleteMessageForEveryone routes 1:1 delete-for-everyone through EncryptedMessageHandler.sendSealedUnsend (server-opaque) with a client-side 5-min window; group stays on the plaintext server fan-out. Sealed read receipt: wire e2eeHandler + directPeerResolver into MarkReadHelper and e2eeHandler into MessageRepository so read receipts travel E2EE instead of plaintext message_read). Earlier 2026-05-13 (+286: 1:1 sealed sender 활성화. April 13 부터
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
///  - Phase 8.7 round 9: top-level broadcastSenderKeyToGroup helper to
///    pre-distribute Sender Key Distribution Messages without waiting for
///    the user to send a message (fixes 2-3min lazy SKDM trickle).
///
/// @functions
///  - chatProvider: family StateNotifierProvider providing a ChatNotifier per conversation
///  - ChatState: chat-screen state data class
///  - ChatNotifier: UI state management (drift watch binding, typing, reply, deletion, send delegation)
///  - broadcastSenderKeyToGroup(): top-level helper that pushes the local
///    sender key + SKDM to all group members BEFORE the user types anything,
///    so receivers are immediately ready to decrypt the first message.

import '../../../core/crypto/identity_binding_exception.dart';
import '../../../core/crypto/identity_key_changed_exception.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/crypto/encrypted_message_handler.dart';
import '../../../core/crypto/file_encryptor.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/storage/database.dart' hide Conversation;
import '../models/conversation.dart';
import '../models/message.dart';
import '../../../core/storage/secure_storage.dart';
import '../../ai/providers/ai_provider.dart';
import '../../ai/providers/translation_provider.dart';
import 'conversation_list_provider.dart';
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

  // Resolve recipientSnowchatId or groupId from the conversation list
  String? recipientSnowchatId;
  String? groupId;

  try {
    final conversations = ref.read(conversationListProvider);
    final conv = conversations.where((c) => c.id == conversationId).firstOrNull;
    if (conv != null) {
      if (conv.type == ConversationType.group) {
        groupId = conv.groupId ?? conversationId;
        debugPrint('[Chat] Group conversation: groupId=$groupId');
      } else if (mySnowId != null) {
        recipientSnowchatId = conv.otherParticipant(mySnowId);
      }
    }
  } catch (_) {}

  // Phase 3: All conversationIds are server CUIDs. No conv_snowXXX fallback.
  // Do NOT assume group when conversation is missing from list — this caused
  // 1:1 messages to be sent as group messages (silent delivery failure).
  if (recipientSnowchatId == null && groupId == null) {
    debugPrint('[Chat] WARNING: conversationId=$conversationId not in list yet. '
        'Will resolve recipientId when conversation list updates.');
  }

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
    // Evaluated at send time so the reactively-resolved recipientId is used.
    directPeerResolver: () =>
        repository.groupId != null ? null : repository.recipientId,
    expiringManager: ref.read(expiringMessageManagerProvider),
    myId: mySnowId ?? '',
  );

  // Reactively resolve recipientId/groupId when conversationListProvider updates.
  // Handles: other party creates conversation or group → message arrives →
  // conversation appears in list → recipientId/groupId becomes available.
  if (recipientSnowchatId == null && groupId == null) {
    ref.listen<List<Conversation>>(conversationListProvider, (prev, next) {
      if (repository.recipientId != null || repository.groupId != null) {
        return; // already resolved
      }
      final conv = next.where((c) => c.id == conversationId).firstOrNull;
      if (conv == null) return;

      if (conv.type == ConversationType.group) {
        final resolvedGroupId = conv.groupId ?? conversationId;
        repository.groupId = resolvedGroupId;
        debugPrint('[Chat] Resolved groupId=$resolvedGroupId for $conversationId');
      } else if (mySnowId != null) {
        final resolved = conv.otherParticipant(mySnowId);
        if (resolved != null) {
          repository.recipientId = resolved;
          debugPrint('[Chat] Resolved recipientId=$resolved for $conversationId');
        }
      }
    });
  }

  final e2eeHandler = ref.read(encryptedMessageHandlerProvider);

  // Auto-translation callback: always wired up, autoTranslateEnabled is checked at call time
  translateCallback(String messageId, String plaintext) {
    try {
      final convs = ref.read(conversationListProvider);
      final conv = convs.where((c) => c.id == conversationId).firstOrNull;
      debugPrint('[Translate] callback: conv=${conv?.id}, autoTranslate=${conv?.autoTranslateEnabled}, text=${plaintext.substring(0, plaintext.length.clamp(0, 30))}');
      if (conv == null || !conv.autoTranslateEnabled) return;
      ref
          .read(translationCacheProvider(conversationId).notifier)
          .translate(messageId, plaintext);
    } catch (_) {}
  }

  return ChatNotifier(
    conversationId,
    repository: repository,
    markReadHelper: markReadHelper,
    socketManager: socketManager,
    e2eeHandler: e2eeHandler,
    mySnowId: mySnowId,
    secureStorage: ref.read(secureStorageProvider),
    onTranslateRequest: translateCallback,
    onConversationPreviewStale: (convId) => ref
        .read(conversationListProvider.notifier)
        .refreshPreviewAfterDelete(convId),
  );
});

/// Phase 8.7 round 9 — pre-distribute Sender Key Distribution Messages
/// (SKDMs) for [groupId] to every group member who needs one, WITHOUT
/// sending an actual encrypted message.
///
/// Why this exists: previously the SKDM was only constructed and pushed
/// inside [ChatNotifier._sendGroupE2EE], which fires only when the user
/// taps "send" on a group chat. That meant a freshly-installed device
/// stayed "isolated" from group conversations until either (a) it sent
/// its own first message, or (b) every other member sent a message that
/// triggered a piggybacked SKDM. Reproduction in Phase 8.7 round 9 with
/// 5 fresh devices showed it took 2~3 minutes for all SKDMs to fully
/// propagate as the user manually moved between devices typing test
/// messages — exactly because each direction of (sender, receiver) needed
/// a user-initiated send to wake up.
///
/// This helper performs steps 1, 2, 5, 6 of [_sendGroupE2EE] (sender key
/// creation, SKDM capture, batch X3DH, 1:1 SKDM dispatch + tracker
/// markDelivered) WITHOUT step 4 (Sender Key encryption) or step 7
/// (group message socket emit). It is safe to call from socket-connect /
/// conversation-list refresh hooks because:
///
/// 1. The 24-hour [SenderKeyDistributionTracker] dedup means repeat calls
///    are no-ops once SKDM is delivered to a recipient.
/// 2. No actual user-facing message is fan-outed.
/// 3. Calling [GroupSessionManager.senderKeyManager.getExistingSKDM]
///    serializes the current state without ratcheting it, so callers
///    that follow up with [_sendGroupE2EE] still observe the same iter.
///
/// Caller responsibilities:
/// - [myId] must be the resolved snowchatId of the local user (non-empty).
/// - [members] should be the canonical group member list (use
///   [ChatNotifier._getGroupMembers] or refetch via
///   `apiClient.get('/groups/$groupId')`).
/// - [e2eeHandler] must have both groupSessionManager AND sessionManager
///   initialized (i.e. SignalSessionManager.initialize() has completed).
///
/// Returns the count of SKDMs successfully pushed (diagnostic only).
Future<int> broadcastSenderKeyToGroup({
  required String groupId,
  required String myId,
  required List<String> members,
  required EncryptedMessageHandler e2eeHandler,
  required SocketManager socketManager,
  String diagTag = 'SKDMBroadcast',
}) async {
  if (myId.isEmpty || members.isEmpty) return 0;
  final groupSessionMgr = e2eeHandler.groupSessionManager;
  final sessionMgr = e2eeHandler.sessionManager;
  if (groupSessionMgr == null) {
    debugPrint('[DIAG:$diagTag] $groupId ABORT: groupSessionMgr null');
    return 0;
  }

  // 1. Ensure the local sender key exists for this group.
  if (!groupSessionMgr.hasSenderKey(groupId, myId)) {
    groupSessionMgr.senderKeyManager.createSenderKey(groupId, myId);
  }

  // 2. Capture the current SKDM (does NOT advance the chain).
  final skdmTemplate =
      groupSessionMgr.senderKeyManager.getExistingSKDM(groupId, myId);
  final skdmBytes = skdmTemplate.serialize();

  // 3. Filter members needing SKDM via 24h tracker dedup.
  final tracker = sessionMgr.signal.skdmTracker;
  final rotationVersion =
      groupSessionMgr.senderKeyManager.getRotationVersion(groupId);
  final membersNeedingSKDM = members
      .where((id) =>
          id != myId && tracker.needsSKDM(groupId, id, rotationVersion))
      .toList();

  if (membersNeedingSKDM.isEmpty) {
    debugPrint('[DIAG:$diagTag] $groupId all ${members.length} members '
        'already have current SKDM (rotationVersion=$rotationVersion)');
    return 0;
  }
  debugPrint('[DIAG:$diagTag] $groupId membersNeedingSKDM='
      '${membersNeedingSKDM.length}/${members.length} '
      '(${membersNeedingSKDM.join(",")}) rotationVersion=$rotationVersion');

  // 4. Batch ensure 1:1 sessions exist (X3DH).
  await sessionMgr.ensureSessionBatch(membersNeedingSKDM);

  // Bug A guard: retry individually if batch did not populate the cache.
  final stillMissing = <String>[];
  for (final id in membersNeedingSKDM) {
    if (!sessionMgr.hasDeviceIdFor(id)) stillMissing.add(id);
  }
  if (stillMissing.isNotEmpty) {
    debugPrint('[DIAG:$diagTag] $groupId batch missed '
        '${stillMissing.length} member(s); retrying individually');
    for (final id in stillMissing) {
      try {
        await sessionMgr.ensureSession(id);
      } on IdentityBindingInvalidException catch (idErr) {
        // B-2 §5.7: forged / downgraded / replayed identity — terminal,
        // never retried (the store already raised the security notice).
        debugPrint('[DIAG:SKDM] fallback ensureSession: identity rejected (${idErr.reason.name}) — terminal');
      } on IdentityKeyChangedException {
        // B-2 §5.5: verified contact awaits re-verification — terminal.
        debugPrint('[DIAG:SKDM] fallback ensureSession: peer awaits identity re-verification — terminal');
      } catch (e) {
        debugPrint('[DIAG:$diagTag] $groupId fallback ensureSession FAIL '
            '$id: $e');
      }
    }
  }

  // 5. Dispatch SKDM as 1:1 messages.
  final wrapper = {
    'type': 'sender_key_distribution',
    'text': base64Encode(skdmBytes),
    'timestamp': DateTime.now().toIso8601String(),
  };
  final wrapperBytes = Uint8List.fromList(utf8.encode(jsonEncode(wrapper)));

  var sentOk = 0;
  var failed = 0;
  for (final memberId in membersNeedingSKDM) {
    if (!sessionMgr.hasDeviceIdFor(memberId)) {
      failed++;
      debugPrint('[DIAG:$diagTag] $groupId SKIP $memberId (no deviceId)');
      continue;
    }
    try {
      final deviceId = await sessionMgr.getDeviceIdForRecipient(memberId);
      final encrypted =
          await sessionMgr.encrypt(memberId, deviceId, wrapperBytes);
      socketManager.sendPrivateMessage({
        'recipientId': memberId,
        'encryptedContent':
            base64Encode(encrypted['ciphertext'] as Uint8List),
        'type': 'sender_key_distribution',
        'messageType': encrypted['messageType'] as int,
        'groupChatId': groupId,
      });
      tracker.markDelivered(groupId, memberId, rotationVersion);
      sentOk++;
    } catch (e) {
      failed++;
      debugPrint('[DIAG:$diagTag] $groupId SKDM send to $memberId FAIL: $e');
    }
  }

  // 6. Persist sender key state if we just created a new key.
  try {
    await groupSessionMgr.persistState();
  } catch (e) {
    debugPrint('[DIAG:$diagTag] $groupId persistState FAIL: $e');
  }

  debugPrint('[DIAG:$diagTag] $groupId SKDM batch summary: '
      'ok=$sentOk failed=$failed');
  return sentOk;
}

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
  final bool isTyping;
  final String? typingUserName;
  final int? disappearingTTL;
  final Message? replyToMessage;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.isTyping = false,
    this.typingUserName,
    this.disappearingTTL,
    this.replyToMessage,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? isSending,
    bool? isTyping,
    String? typingUserName,
    bool clearTypingUserName = false,
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
      typingUserName: clearTypingUserName
          ? null
          : (typingUserName ?? this.typingUserName),
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
  /// The unsend was dispatched (1:1 sealed control sent, or group emit sent, or
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

  StreamSubscription<List<LocalMessage>>? _messageWatchSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;

  final Map<String, Timer> _deletionTimers = {};
  final Map<String, MessageStatus> _pendingStatuses = {};
  Timer? _typingDebounceTimer;
  DateTime? _lastTypingSent;

  static const _typingSendInterval = Duration(seconds: 2);
  static const _typingStopDelay = Duration(seconds: 3);

  /// Auto-translation request callback — wired up to translationCacheProvider in the provider factory.
  void Function(String messageId, String plaintext)? onTranslateRequest;

  /// Invoked after a local message delete/unsend so the Chats-list preview can
  /// be recomputed. ChatNotifier has no Ref; the provider wires this to
  /// ConversationListNotifier.refreshPreviewAfterDelete(conversationId).
  void Function(String conversationId)? onConversationPreviewStale;

  ChatNotifier(
    this.conversationId, {
    required MessageRepository repository,
    required MarkReadHelper markReadHelper,
    SocketManager? socketManager,
    EncryptedMessageHandler? e2eeHandler,
    String? mySnowId,
    SecureStorageService? secureStorage,
    this.onTranslateRequest,
    this.onConversationPreviewStale,
  })  : _repo = repository,
        _markReadHelper = markReadHelper,
        _socketManager = socketManager,
        _e2eeHandler = e2eeHandler,
        _secureStorage = secureStorage,
        _myId = mySnowId ?? '',
        super(const ChatState()) {
    // Wire up repository callbacks for immediate UI updates
    _repo.onIncomingMessage = _addIncomingMessage;
    _repo.onMessageStatusChanged = _handleStatusChange;
    _repo.onMessageDeleted = _handleRemoteDeletion;

    _loadMessages();
    _repo.startSocketListeners();
    _subscribeToMessages();
    _listenToTyping();
    _repo.resumePendingDownloads();
  }

  /// Convenience getters delegated to repository.
  String? get recipientId => _repo.recipientId;
  String? get groupId => _repo.groupId;
  bool get isGroup => _repo.isGroup;

  @override
  void dispose() {
    _messageWatchSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingDebounceTimer?.cancel();
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

        // Auto-translation trigger: most recent 10 incoming text messages
        debugPrint('[ChatNotifier] translate callback null=${onTranslateRequest == null}, incoming=${merged.where((m) => m.senderSnowchatId != _myId && m.type == MessageType.text).length}');
        if (onTranslateRequest != null) {
          final incoming = merged
              .where((m) =>
                  m.senderSnowchatId != _myId &&
                  m.type == MessageType.text &&
                  m.plaintext.isNotEmpty)
              .toList();
          final recent = incoming.length > 10
              ? incoming.sublist(incoming.length - 10)
              : incoming;
          for (final m in recent) {
            onTranslateRequest!(m.id, m.plaintext);
          }
        }
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

    // Initialize group E2EE (Sender Key) if this is a group conversation
    if (isGroup && _e2eeHandler != null) {
      await _initializeGroupE2EE();
    }

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

  /// Initialize group E2EE by creating a Sender Key if one doesn't exist.
  /// Fetches group members from server and distributes our sender key.
  Future<void> _initializeGroupE2EE() async {
    // Phase 6.9: hard guard against empty myId — the provider is rebuilt
    // when currentSnowIdProvider resolves, so hitting this path means the
    // caller raced ahead of onboarding. Defer rather than crash.
    if (_myId.isEmpty) {
      debugPrint('[Chat] Skip group E2EE init — myId not yet resolved '
          '(groupId=$groupId)');
      return;
    }
    try {
      final groupSessionMgr = _e2eeHandler!.groupSessionManager;
      if (groupSessionMgr == null) return;

      // Check if we already have a sender key for this group
      if (groupSessionMgr.hasSenderKey(groupId!, _myId)) return;

      // Fetch group members from server
      final apiClient = _repo.apiClient;
      if (apiClient == null) return;

      final response = await apiClient.get('/groups/${groupId!}');
      final data = response.data;
      if (data is! Map || data['members'] is! List) return;

      final members = (data['members'] as List)
          .map((m) => (m as Map)['snowchatId'] as String?)
          .where((id) => id != null && id != _myId)
          .cast<String>()
          .toList();

      if (members.isEmpty) return;

      await groupSessionMgr.initializeGroup(groupId!, _myId, members);
      debugPrint('[Chat] Group E2EE initialized: groupId=$groupId '
          'myId=$_myId members=${members.length}');
    } catch (e) {
      debugPrint('[Chat] Group E2EE init failed (non-fatal): $e');
    }
  }

  /// Fetch group members from server (always fresh — no caching).
  /// Members can join/leave at any time, so stale lists cause SKDM
  /// to not be sent to new members → decryption failure.
  Future<List<String>> _getGroupMembers() async {
    final apiClient = _repo.apiClient;
    if (apiClient == null) return [];
    try {
      final response = await apiClient.get('/groups/${groupId!}');
      final data = response.data;
      if (data is! Map || data['members'] is! List) return [];
      return (data['members'] as List)
          .map((m) => (m as Map)['snowchatId'] as String?)
          .where((id) => id != null && id != _myId)
          .cast<String>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Signal Hybrid group E2EE: Sender Key + Pairwise Fallback.
  ///
  /// 1. Try Sender Key encryption (O(1), sent as group message)
  /// 2. For members who might not have our Sender Key:
  ///    send same message via 1:1 E2EE (pairwise fallback)
  /// 3. Also distribute our Sender Key via 1:1 so next message uses O(1)
  /// Signal Hybrid group E2EE (Phase A — belt-and-suspenders).
  ///
  /// 1. Sender Key encrypt (O(1)) → broadcast on the group channel
  /// 2. perMemberData: per-member inline SKDM + pairwise fallback
  /// 3. Legacy fallback: also send private_message for old clients
  /// Phase 6: Send a group message via Sender Key.
  ///
  /// Architecture:
  /// - Sender Key encryption is decoupled from 1:1 ratchet (no inline SKDM,
  ///   no pairwise fallback). The 1:1 and Sender Key state machines never
  ///   touch each other in the send path.
  /// - SKDM is captured BEFORE [encryptGroupMessage] ratchets the state, then
  ///   sent as separate 1:1 messages — this fixes the iter bug where the SKDM
  ///   used to embed iter=N+1 while the encrypted payload had iter=N.
  /// - Server fan-outs the group message to all members. Recipients without
  ///   a sender key for us will request one via sender_key_request, and we
  ///   re-send via [GlobalMessageRouter._handleSenderKeyRequest].
  Future<void> _sendGroupE2EE(
    String text,
    String messageId,
    int? ttl,
    Message? replyTo, {
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
  }) async {
    // Phase 6.9: hard guard — never sign Sender Keys with an empty identity.
    // This used to fall through and silently key the sender-key map at "",
    // causing 100% verification failure on every receiver.
    if (_myId.isEmpty) {
      debugPrint('[Chat] Group send aborted — myId not yet resolved '
          '(groupId=$groupId, messageId=$messageId)');
      _updateMessageStatus(messageId, MessageStatus.failed);
      return;
    }

    final groupSessionMgr = _e2eeHandler!.groupSessionManager;
    final sessionMgr = _e2eeHandler!.sessionManager;
    final members = await _getGroupMembers();

    debugPrint('[DIAG:GroupSend] $messageId members fetched: count=${members.length} '
        'groupId=$groupId members=${members.join(",")}');

    if (groupSessionMgr == null || members.isEmpty) {
      debugPrint('[DIAG:GroupSend] $messageId ABORT: '
          'groupSessionMgr=${groupSessionMgr != null} membersEmpty=${members.isEmpty}');
      _updateMessageStatus(messageId, MessageStatus.failed);
      return;
    }

    // 1. Ensure we have a sender key for this group.
    if (!groupSessionMgr.hasSenderKey(groupId!, _myId)) {
      groupSessionMgr.senderKeyManager.createSenderKey(groupId!, _myId);
    }

    // 2. ===== iter bug fix =====
    // Capture the CURRENT SKDM (chainKey + iteration) BEFORE encryption
    // ratchets the state. This SKDM bootstraps recipients to the same
    // iteration as the message we are about to encrypt.
    final skdmTemplate =
        groupSessionMgr.senderKeyManager.getExistingSKDM(groupId!, _myId);
    final skdmBytes = skdmTemplate.serialize();

    // 3. Build plaintext JSON payload.
    final plainPayload = {
      'text': text,
      'type': type.name,
      'timestamp': DateTime.now().toIso8601String(),
      if (metadata != null) 'metadata': metadata,
      if (ttl != null) 'ttl': ttl,
      if (replyTo?.id != null) 'replyToId': replyTo!.id,
      if (replyTo?.plaintext != null) 'replyToPreview': replyTo!.plaintext,
      if (replyTo?.senderSnowchatId != null)
        'replyToSenderId': replyTo!.senderSnowchatId,
    };
    final plainBytes =
        Uint8List.fromList(utf8.encode(jsonEncode(plainPayload)));

    // 4. Sender Key encryption — O(1), single ciphertext for all recipients.
    Uint8List? groupCiphertext;
    try {
      groupCiphertext =
          groupSessionMgr.sendGroupMessage(groupId!, _myId, plainBytes);
    } catch (e) {
      debugPrint('[Chat] Sender Key encrypt failed: $e');
      _updateMessageStatus(messageId, MessageStatus.failed);
      return;
    }

    // Phase 10 P0-A: Record plaintext in MessageSendLog for retry requests.
    // If a recipient fails to decrypt, they'll send a group retry request
    // and we re-encrypt from this log entry via 1:1 pairwise fallback.
    sessionMgr.signal.messageSendLog.record(
      messageId,
      plainBytes,
      conversationId: groupId!,
      isGroup: true,
    );

    // 5. Decide who needs SKDM (best-effort hint — recipients will also
    //    request via sender_key_request if they're missing it).
    //    Phase 6.4 will replace this tracker with reactive ACK; for now we
    //    keep it as a "send SKDM at most once until restart" optimization.
    final tracker = sessionMgr.signal.skdmTracker;
    final rotationVersion =
        groupSessionMgr.senderKeyManager.getRotationVersion(groupId!);
    final membersNeedingSKDM = members
        .where((id) => tracker.needsSKDM(groupId!, id, rotationVersion))
        .toList();

    debugPrint('[DIAG:GroupSend] $messageId membersNeedingSKDM='
        '${membersNeedingSKDM.length}/${members.length} '
        '(${membersNeedingSKDM.join(",")}) rotationVersion=$rotationVersion');

    if (membersNeedingSKDM.isNotEmpty) {
      // Batch prekey fetch
      await sessionMgr.ensureSessionBatch(membersNeedingSKDM);
      debugPrint('[DIAG:GroupSend] $messageId ensureSessionBatch completed');

      // Phase 8.7 Bug A: verify the deviceId cache was actually populated
      // for every member. If the batch endpoint omitted some recipients
      // (e.g. placeholder identityKey filter), retry them individually so
      // that getDeviceIdForRecipient does not throw below.
      final stillMissing = <String>[];
      for (final id in membersNeedingSKDM) {
        if (!sessionMgr.hasDeviceIdFor(id)) stillMissing.add(id);
      }
      if (stillMissing.isNotEmpty) {
        debugPrint('[DIAG:GroupSend] $messageId batch missed '
            '${stillMissing.length} member(s); retrying individually');
        for (final id in stillMissing) {
          try {
            await sessionMgr.ensureSession(id);
          } on IdentityBindingInvalidException catch (idErr) {
            // B-2 §5.7: forged / downgraded / replayed identity — terminal,
            // never retried (the store already raised the security notice).
            debugPrint('[DIAG:GroupSend] individual ensureSession: identity rejected (${idErr.reason.name}) — terminal');
          } on IdentityKeyChangedException {
            // B-2 §5.5: verified contact awaits re-verification — terminal.
            debugPrint('[DIAG:GroupSend] individual ensureSession: peer awaits identity re-verification — terminal');
          } catch (e) {
            debugPrint('[DIAG:GroupSend] $messageId individual ensureSession '
                'fallback FAILED for $id: $e');
          }
        }
      }

      // 6. Send SKDM as a separate 1:1 message to each member who needs it.
      // The wrapper format matches MessageQueue._processSKDM expectations:
      //   { type: 'sender_key_distribution', text: base64(SKDM bytes) }
      final wrapper = {
        'type': 'sender_key_distribution',
        'text': base64Encode(skdmBytes),
        'timestamp': DateTime.now().toIso8601String(),
      };
      final wrapperBytes =
          Uint8List.fromList(utf8.encode(jsonEncode(wrapper)));

      var skdmSentOk = 0;
      var skdmFailed = 0;
      for (final memberId in membersNeedingSKDM) {
        // Phase 8.7 Bug A: skip members whose deviceId cache is still
        // missing after batch + individual retry. Better to drop the SKDM
        // for one member (recipient will request via sender_key_request)
        // than to encrypt under placeholder 'primary' and corrupt session.
        if (!sessionMgr.hasDeviceIdFor(memberId)) {
          skdmFailed++;
          debugPrint('[DIAG:GroupSend] $messageId SKDM SKIPPED for $memberId '
              '(no deviceId after retries)');
          continue;
        }
        try {
          final deviceId =
              await sessionMgr.getDeviceIdForRecipient(memberId);
          final encrypted =
              await sessionMgr.encrypt(memberId, deviceId, wrapperBytes);
          _socketManager!.sendPrivateMessage({
            'recipientId': memberId,
            'encryptedContent':
                base64Encode(encrypted['ciphertext'] as Uint8List),
            'type': 'sender_key_distribution',
            'messageType': encrypted['messageType'] as int,
            'groupChatId': groupId,
          });
          tracker.markDelivered(groupId!, memberId, rotationVersion);
          skdmSentOk++;
          debugPrint('[DIAG:GroupSend] $messageId SKDM sent to $memberId '
              '(deviceId=$deviceId)');
        } catch (e) {
          skdmFailed++;
          debugPrint('[DIAG:GroupSend] $messageId SKDM send to $memberId FAILED: $e');
          // Non-fatal: recipient will request via sender_key_request.
        }
      }
      debugPrint('[DIAG:GroupSend] $messageId SKDM batch summary: '
          'ok=$skdmSentOk failed=$skdmFailed');
    }

    // 7. Send the group message — pure Sender Key payload, no perMemberData.
    debugPrint('[DIAG:GroupSend] $messageId emitting send_group_message');
    _socketManager!.sendGroupMessage({
      'groupChatId': groupId,
      'encryptedPayload': base64Encode(groupCiphertext),
      'type': 'sender_key',
      'clientMessageId': messageId,
      if (ttl != null) 'expiresIn': ttl,
    });

    // 8. Persist Sender Key state to disk (chain ratcheted during step 4).
    await groupSessionMgr.persistState();
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
      if (serverMessageId != null && _pendingStatuses.containsKey(serverMessageId)) {
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

  void _handleRemoteDeletion(String messageId) {
    if (!mounted) return;
    _repo.expiringManager?.cancel(messageId);
    // Physical delete (drift + attachments + local files) — drift watch updates UI
    _repo.deleteMessageLocally(messageId);
    debugPrint('[ChatNotifier] Message $messageId deleted by sender');
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
        'recipientId=$recipientId groupId=$groupId isGroup=$isGroup');

    if (_socketManager == null) {
      debugPrint('[DIAG:Send] ABORT: socketManager null');
      return;
    }
    if (!isGroup && recipientId == null) {
      debugPrint('[DIAG:Send] ABORT: 1:1 but recipientId null '
          '(convId=$conversationId — chatProvider failed to resolve)');
      return;
    }
    if (isGroup && groupId == null) {
      debugPrint('[DIAG:Send] ABORT: group but groupId null');
      return;
    }
    if (!(_socketManager!.isConnected)) {
      debugPrint('[DIAG:Send] ABORT: socket not connected');
      return;
    }

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
    _repo.persistOutgoingMessage(
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

    // Send via socket — E2EE only. No plaintext fallback under any condition.
    // SnowChat is a Pure Dart Signal Protocol E2EE messenger; if the handler
    // is unavailable (cold-start race, provider initialization bug, etc.) we
    // fail-fast rather than silently sending plaintext to the server. The
    // user sees a 'failed' state and can retry once E2EE is ready.
    if (_e2eeHandler == null) {
      debugPrint('[Chat] E2EE handler unavailable — refusing to send '
          '(message $messageId would have leaked plaintext)');
      _updateMessageStatus(messageId, MessageStatus.failed);
      onUserStoppedTyping();
      return;
    }

    if (isGroup) {
      debugPrint('[DIAG:Send] $messageId routing to _sendGroupE2EE groupId=$groupId');
      try {
        await _sendGroupE2EE(text, messageId, ttl, replyTo);
      } catch (e, st) {
        debugPrint('[DIAG:Send] $messageId GROUP send EXCEPTION: $e\n$st');
        _updateMessageStatus(messageId, MessageStatus.failed);
      }
    } else {
      // 1:1 E2EE path. Sealed Sender wraps the Double Ratchet ciphertext
      // so the server cannot read the senderId (messages row stores it as
      // NULL with senderHash=HMAC binding for blind retry). Activation
      // 2026-05-13 — the original April 13 disable was based on two
      // hazards that are both resolved now:
      //   1. Server's persistent SEALED_SENDER_PRIVATE_KEY env was missing.
      //      Production .env now ships a 64-byte keypair; startup log
      //      confirms "Server Ed25519 key loaded from environment".
      //   2. A sealed→regular fallback used to double-encrypt and shred
      //      the ratchet. That fallback was removed; the catch below
      //      marks the message failed without re-encrypting. retry_handler
      //      handles legitimate recovery via archiveAndResetSession on a
      //      fresh session, not by re-encrypting on the same ratchet.
      // Also sendSealedMessage now pre-fetches certificate + IK before
      // encrypt() so a ratchet advance is never wasted on a throw.
      //
      // VoIP signaling (call_signaling.dart) has been shipping sealed
      // envelopes through the same SealedSenderService end-to-end in
      // production since the certificate service stabilized — this is
      // the message-side counterpart finally going live.
      final useSealed = _e2eeHandler!.isSealedSenderAvailable;
      debugPrint('[DIAG:Send] $messageId routing to 1:1 E2EE '
          '${useSealed ? "(sealed)" : "(regular DR — sealed unavailable)"} '
          'recipientId=$recipientId');
      try {
        if (useSealed) {
          await _e2eeHandler!.sendSealedMessage(
            conversationId: conversationId,
            recipientId: recipientId!,
            text: text,
            clientMessageId: messageId,
            ttlSeconds: ttl,
            replyToId: replyTo?.id,
            replyToPreview: replyTo?.plaintext,
            replyToSenderId: replyTo?.senderSnowchatId,
            onAck: (response) {
              if (!mounted) return;
              debugPrint('[DIAG:Send] $messageId sealed ACK: $response');
              if (response is Map && response['error'] != null) {
                _updateMessageStatus(messageId, MessageStatus.failed);
              }
            },
          );
        } else {
          await _e2eeHandler!.sendEncryptedMessage(
            conversationId: conversationId,
            recipientId: recipientId!,
            text: text,
            clientMessageId: messageId,
            ttlSeconds: ttl,
            replyToId: replyTo?.id,
            replyToPreview: replyTo?.plaintext,
            replyToSenderId: replyTo?.senderSnowchatId,
            onAck: (response) {
              if (!mounted) return;
              debugPrint('[DIAG:Send] $messageId ACK: $response');
              if (response is Map && response['error'] != null) {
                _updateMessageStatus(messageId, MessageStatus.failed);
              }
            },
          );
        }
        debugPrint('[DIAG:Send] $messageId 1:1 send completed');
      } catch (e, st) {
        debugPrint('[DIAG:Send] $messageId 1:1 send EXCEPTION: $e\n$st');
        _updateMessageStatus(messageId, MessageStatus.failed);
      }
    }

    // Timeout: mark as failed after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (!mounted) return;
      final msg = state.messages.where((m) => m.id == messageId).firstOrNull;
      if (msg != null && msg.status == MessageStatus.sending) {
        _updateMessageStatus(messageId, MessageStatus.failed);
      }
    });

    onUserStoppedTyping();
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
    if (!isGroup && recipientId == null) return;

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

    // 2. E2EE path: encrypt file content + upload + send metadata via Signal Protocol
    //    Non-E2EE path: upload raw + send metadata as plaintext
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final fileSize = bytes.length;

      // Encrypt file content with random key (XSalsa20-Poly1305) for E2EE,
      // or upload raw for non-E2EE paths
      String fileId;
      String? fileKeyB64;
      String? contentHash;

      if (_e2eeHandler != null || isGroup) {
        // Zero-Knowledge: server stores only encrypted blob
        final encResult = await FileEncryptor.encryptFile(Uint8List.fromList(bytes));
        fileId = await _repo.fileService!.uploadEncryptedFile(
            encResult.encryptedData, encResult.contentHash);
        fileKeyB64 = base64Encode(encResult.fileKey);
        contentHash = encResult.contentHash;
      } else {
        // Legacy plaintext upload (no E2EE handler available)
        final hash = _computeHash(bytes);
        fileId = await _repo.fileService!.uploadEncryptedFile(bytes, hash);
      }

      // 3. Build metadata (fileKey included only when E2EE encrypted)
      final metadata = {
        'fileId': fileId,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': fileSize,
        if (fileKeyB64 != null) 'fileKey': fileKeyB64,
        if (contentHash != null) 'contentHash': contentHash,
        'attachments': [
          {
            'fileId': fileId,
            'fileName': fileName,
            'mimeType': mimeType,
            'size': fileSize,
          }
        ],
      };

      // Await drift writes BEFORE socket send — prevents race condition where
      // the ACK arrives before attachment row exists, causing messageId mismatch.
      // persistOutgoingMessage also refreshes the conversation snippet so an
      // outgoing-last chat doesn't hydrate as "No messages yet" after restart.
      await _repo.persistOutgoingMessage(
        LocalMessagesCompanion(
          id: Value(messageId),
          conversationId: Value(conversationId),
          senderSnowchatId: Value(_myId),
          plaintext: Value(fileName),
          dateSent: Value(now.millisecondsSinceEpoch),
          dateReceived: Value(now.millisecondsSinceEpoch),
          type: const Value('file'),
          metadata: Value(jsonEncode(metadata)),
          read: const Value(true),
          outgoingStatus: const Value('sending'),
          expiresIn: Value(ttl ?? 0),
          expireStarted: Value(ttl != null ? now.millisecondsSinceEpoch : 0),
        ),
        snippetText: fileName,
        sentTimestamp: now.millisecondsSinceEpoch,
      );

      // Signal pattern: copy PLAINTEXT to permanent path for local display
      // Store RELATIVE path — immune to iOS container UUID changes
      final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
      final dir = await getApplicationDocumentsDirectory();
      final attachDir = Directory('${dir.path}/snowchat_attachments');
      if (!attachDir.existsSync()) attachDir.createSync(recursive: true);
      final relativePath = 'snowchat_attachments/$fileId.$ext';
      await File(filePath).copy('${dir.path}/$relativePath');

      // Await attachment insert — must complete before socket send so that
      // updateMessageId(localId→serverCUID) in ACK handler finds the row.
      await _repo.attachmentDao?.insertAttachment(LocalAttachmentsCompanion(
        id: Value('att_${messageId}_0'),
        messageId: Value(messageId),
        displayOrder: const Value(0),
        contentType: Value(mimeType),
        fileName: Value(fileName),
        fileSize: Value(fileSize),
        remoteFileId: Value(fileId),
        localPath: Value(relativePath),
        transferState: const Value(0), // DONE
      ));

      // E2EE only — fail-fast if handler unavailable. No plaintext fallback.
      // The encrypted blob has already been uploaded to the server, but the
      // recipient cannot decrypt without the fileKey, which lives only in
      // the E2EE payload. Sending plaintext metadata would also leak the
      // filename and mime type to the server.
      if (_e2eeHandler == null) {
        debugPrint('[Chat] E2EE handler unavailable — refusing to send file '
            '(message $messageId would have leaked filename + metadata)');
        _updateMessageStatus(messageId, MessageStatus.failed);
        return;
      }

      if (isGroup) {
        await _sendGroupE2EE(fileName, messageId, ttl, null,
            type: MessageType.file, metadata: metadata);
      } else {
        // +286 활성된 1:1 sealed sender 가 file 에도 그대로 적용된다.
        // metadata 는 fileId / fileKey / contentHash 등 attachment 복호화
        // 정보 + filename 같은 PII 가 포함되므로, regular DR path 면 server
        // 가 sender + filename + mime 모두 보지만 sealed path 면 senderId
        // 만 NULL 로 마스킹된다. (filename + mime 은 여전히 sealed envelope
        // 안에 있어서 server 는 못 봄.) attachmentWatchProvider 측 receive
        // path 는 sealed 든 regular 든 동일하게 작동.
        final useSealed = _e2eeHandler!.isSealedSenderAvailable;
        debugPrint('[Chat] file 1:1 routing '
            '${useSealed ? "(sealed)" : "(regular DR)"} '
            'msgId=$messageId fileId=$fileId');
        try {
          if (useSealed) {
            await _e2eeHandler!.sendSealedMessage(
              conversationId: conversationId,
              recipientId: recipientId!,
              text: fileName,
              clientMessageId: messageId,
              type: MessageType.file,
              metadata: metadata,
              ttlSeconds: ttl,
            );
          } else {
            await _e2eeHandler!.sendEncryptedMessage(
              conversationId: conversationId,
              recipientId: recipientId!,
              text: fileName,
              clientMessageId: messageId,
              type: MessageType.file,
              metadata: metadata,
              ttlSeconds: ttl,
            );
          }
        } catch (e) {
          debugPrint('[Chat] E2EE file send failed: $e');
          _updateMessageStatus(messageId, MessageStatus.failed);
        }
      }

      // Schedule expiration deletion
      if (ttl != null) {
        _repo.expiringManager?.schedule(messageId, ttl);
      }
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
    if (!isGroup && recipientId == null) return;
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

      // 3. Persist drift row with full metadata + TTL columns. The drift
      // watch stream will round-trip this back into in-memory state; if we
      // omit any of {metadata, expiresIn, expireStarted} the in-memory
      // copy gets clobbered with nulls a frame after rendering (the +281 /
      // +282 regression line).
      // persistOutgoingMessage also refreshes the conversation snippet so an
      // outgoing-last chat doesn't hydrate as "No messages yet" after restart.
      await _repo.persistOutgoingMessage(
        LocalMessagesCompanion(
          id: Value(messageId),
          conversationId: Value(conversationId),
          senderSnowchatId: Value(_myId),
          plaintext: const Value('Voice message'),
          dateSent: Value(now.millisecondsSinceEpoch),
          dateReceived: Value(now.millisecondsSinceEpoch),
          type: const Value('voice'),
          metadata: Value(jsonEncode(metadata)),
          read: const Value(true),
          outgoingStatus: const Value('sending'),
          expiresIn: Value(ttl ?? 0),
          expireStarted: Value(ttl != null ? now.millisecondsSinceEpoch : 0),
        ),
        snippetText: 'Voice message',
        sentTimestamp: now.millisecondsSinceEpoch,
      );

      // 4. Copy plaintext m4a to the permanent attachment path so the
      // sender-side voice bubble (and any later watch-stream rebuild) can
      // play it without re-downloading from the server. Relative path keeps
      // it immune to iOS container UUID rotation.
      final dir = await getApplicationDocumentsDirectory();
      final attachDir = Directory('${dir.path}/snowchat_attachments');
      if (!attachDir.existsSync()) attachDir.createSync(recursive: true);
      final relativePath = 'snowchat_attachments/$fileId.wav';
      await file.copy('${dir.path}/$relativePath');

      // 5. Attachment row — voice bubble watches this via attachmentWatchProvider
      // (same provider the file / image bubbles use), so both sender and
      // recipient resolve `localPath` through one path.
      await _repo.attachmentDao?.insertAttachment(LocalAttachmentsCompanion(
        id: Value('att_${messageId}_0'),
        messageId: Value(messageId),
        displayOrder: const Value(0),
        contentType: Value(mimeType),
        fileName: Value(fileName),
        fileSize: Value(fileSize),
        remoteFileId: Value(fileId),
        localPath: Value(relativePath),
        transferState: const Value(0), // DONE
      ));

      // 6. E2EE send (1:1 Double Ratchet or group Sender Key). Mirrors
      // sendFileMessage's fork — sealed sender 활성 가능한 1:1 path 에서는
      // sendSealedMessage 로 가서 server 가 senderId 를 모르게 된다.
      if (isGroup) {
        await _sendGroupE2EE('Voice message', messageId, ttl, null,
            type: MessageType.voice, metadata: metadata);
      } else {
        final useSealed = _e2eeHandler!.isSealedSenderAvailable;
        debugPrint('[Chat] voice 1:1 routing '
            '${useSealed ? "(sealed)" : "(regular DR)"} '
            'msgId=$messageId fileId=$fileId');
        try {
          if (useSealed) {
            await _e2eeHandler!.sendSealedMessage(
              conversationId: conversationId,
              recipientId: recipientId!,
              text: 'Voice message',
              clientMessageId: messageId,
              type: MessageType.voice,
              metadata: metadata,
              ttlSeconds: ttl,
            );
          } else {
            await _e2eeHandler!.sendEncryptedMessage(
              conversationId: conversationId,
              recipientId: recipientId!,
              text: 'Voice message',
              clientMessageId: messageId,
              type: MessageType.voice,
              metadata: metadata,
              ttlSeconds: ttl,
            );
          }
        } catch (e) {
          debugPrint('[Chat] E2EE voice send failed: $e');
          _updateMessageStatus(messageId, MessageStatus.failed);
          return;
        }
      }

      if (ttl != null) {
        _repo.expiringManager?.schedule(messageId, ttl);
      }
      _scheduleDeletionIfNeeded(localMessage);
    } catch (e, st) {
      debugPrint('[Chat] voice send exception: $e\n$st');
      _updateMessageStatus(messageId, MessageStatus.failed);
    }
  }

  /// Compute SHA-256 hash of bytes for upload integrity.
  static String _computeHash(Uint8List bytes) {
    return sha256.convert(bytes).toString();
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
      final stopped = data['stopped'] as bool? ?? false;
      // 1:1 (metadata-min Batch 2): the server sends the typer's snow-id —
      // match it against THIS chat's peer (rooms are peer-keyed now, so the
      // old conversationId match no longer works for 1:1).
      final fromSnow = data['fromSnowchatId'] as String?;
      if (fromSnow != null) {
        if (fromSnow != recipientId) return;
        setTyping(!stopped, userName: stopped ? null : fromSnow);
        return;
      }
      // Group: match by the shared room id (groupId).
      final typingConvId = data['conversationId'] as String?;
      if (typingConvId != conversationId) return;
      final typingUserId = data['userId'] as String?;
      setTyping(!stopped, userName: stopped ? null : typingUserId);
    });
  }

  void onUserTyping() {
    final sm = _socketManager;
    if (sm == null || !sm.isConnected) return;

    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) >= _typingSendInterval) {
      if (isGroup) {
        sm.sendTyping(conversationId: conversationId);
      } else {
        sm.sendTyping(recipientSnowchatId: recipientId);
      }
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
    if (isGroup) {
      _socketManager?.stopTyping(conversationId: conversationId);
    } else {
      _socketManager?.stopTyping(recipientSnowchatId: recipientId);
    }
  }

  void setTyping(bool typing, {String? userName}) {
    if (typing) {
      state = state.copyWith(isTyping: true, typingUserName: userName);
    } else {
      state = state.copyWith(isTyping: false, clearTypingUserName: true);
    }
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
  /// 1:1 → sealed E2EE unsend (server never sees it is a delete). Group →
  /// server-mediated fan-out (per-recipient row ids have no shared client id).
  /// For unsent messages (local ID), only deletes locally.
  Future<UnsendResult> deleteMessageForEveryone(String messageId) async {
    final message = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null || !message.isMine(_myId)) return UnsendResult.failed;

    // Local-only (never left the device) → just remove our copy; nothing to
    // propagate, so this is a clean success.
    if (messageId.startsWith('msg_')) {
      await deleteMessageForMe(messageId);
      return UnsendResult.unsent;
    }

    final peer = _repo.recipientId;
    if (_repo.groupId == null && peer != null && _e2eeHandler != null) {
      // 1:1 → sealed unsend. The server no longer mediates 1:1 deletes, so the
      // window is enforced here (same as the context-menu gate). Only remove our
      // OWN copy once the unsend was actually dispatched — otherwise the peer
      // keeps their copy and deleting ours would falsely imply success (socket
      // down, or no sealed channel to the peer yet). Keep the message so the
      // sender can retry.
      if (!message.isWithinUnsendWindow) return UnsendResult.failed;
      bool dispatched;
      try {
        dispatched = await _e2eeHandler!
            .sendSealedUnsend(recipientId: peer, deleteIds: [messageId]);
      } catch (e) {
        debugPrint('[Chat] sealed unsend failed: $e');
        dispatched = false;
      }
      if (!dispatched) return UnsendResult.failed;
      await deleteMessageForMe(messageId);
      return UnsendResult.unsent;
    }

    // Genuine group → server-mediated fan-out (fire-and-forget; within-window is
    // enforced by the menu gate + the server's own 5-min check).
    if (_repo.groupId != null) {
      _socketManager?.emit('delete_message', {'messageId': messageId});
      await deleteMessageForMe(messageId);
      return UnsendResult.unsent;
    }
    // 1:1 whose peer / e2ee handler couldn't be resolved → we cannot propagate
    // the unsend, so keep the message and report failure rather than silently
    // deleting our copy (which would falsely imply it was removed everywhere).
    return UnsendResult.failed;
  }

  /// Vuln 3 (Stage 3): Local-only Clear Chat.
  /// Used by regular group members who lack admin permission to clear for
  /// everyone (the server returns 403 in that case). Deletes messages +
  /// attachments locally without any network call. The conversation row
  /// stays in the list.
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
  /// Resolve the server conversation id (shared CUID) for this 1:1.
  ///
  /// The peer-keyed room id for the server's 1:1 DELETE / Clear endpoints.
  ///
  /// Metadata-min Batch 2 (2026-08-07): the server dropped the Conversation
  /// table, so those endpoints are now keyed by the PEER's snowchatId — the
  /// same value every 1:1 room is keyed by locally (sealed/non-sealed receive
  /// route by sender snow-id; find-or-create echoes the peer snow-id). No
  /// server round-trip is needed: recipientId holds the peer snow-id, and a
  /// snow-id room's own id IS the peer.
  Future<String> _serverConversationId() async {
    return recipientId ?? conversationId;
  }

  Future<void> clearChat() async {
    // 1. Cancel pending TTL timers
    for (final m in state.messages) {
      _deletionTimers[m.id]?.cancel();
      _deletionTimers.remove(m.id);
      _repo.expiringManager?.cancel(m.id);
    }

    // 2. Clear on SERVER (messages only, keep conversation/group row).
    // Failure paths: 403 (not admin), 401 (auth), network. ALL rethrow so
    // the caller can present a SnackBar + offer the local-only alternative.
    final apiClient = _repo.apiClient;
    if (apiClient == null) {
      throw StateError('clearChat: no API client available — '
          'use clearChatLocally() for offline / local-only clear');
    }

    try {
      if (isGroup) {
        await apiClient.delete('/groups/$groupId/messages');
      } else {
        await apiClient.delete(
            '/conversations/${await _serverConversationId()}/messages');
      }
      debugPrint('[Chat] clearChat: server clear success');
    } catch (e) {
      debugPrint('[Chat] clearChat: server clear failed ($e) — '
          'skipping local cleanup to keep cross-device state in sync');
      // Re-arm timers for messages we did NOT clear (best-effort) so the
      // user does not lose TTL countdown after a failed clear.
      // NOTE: Real timers re-arm on next chat reload via _scheduleDeletionIfNeeded;
      // the cancel above is OK because in-memory `state.messages` still holds them.
      rethrow;
    }

    // 3. Local cleanup (messages + attachments, keep conversation row).
    //    Only reached on server 2xx — guarantees both sides agree on "empty".
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

    final apiClient = _repo.apiClient;
    if (apiClient != null) {
      // Resolve the shared server CUID first: a snow-id fallback room (peer
      // messaged us first) would 404 and leave the server + peer copies alive,
      // breaking the "the other person will also lose this conversation" promise.
      final serverId = await _serverConversationId();
      try {
        await apiClient.delete('/conversations/$serverId');
        debugPrint('[Chat] deleteChat: server DELETE success');
        if (_secureStorage != null) {
          await removeDeletedConvId(_secureStorage!, serverId);
        }
      } catch (e) {
        debugPrint('[Chat] deleteChat: 1:1 server DELETE failed ($e), tombstoning');
        // Tombstone by the server CUID — loadFromServer returns and filters
        // against CUIDs, so a snow-id tombstone would never match and the
        // deleted conversation would reappear on the next sync.
        if (_secureStorage != null) {
          await addDeletedConvId(_secureStorage!, serverId);
        }
      }
    }

    // Tell the peer over the sealed_control channel so an OFFLINE peer also
    // loses the room. The REST delete above emits `chat_deleted` only to
    // sockets connected at that instant and never queues it, so deleting while
    // the peer was offline wiped our side only and left theirs intact
    // (field-confirmed on real devices, 2026-09-04). The control is queued like
    // any other message and applied on their next connect.
    //
    // Ordering is load-bearing:
    //  - AFTER the server DELETE, because purgePairRows() wipes every sealed
    //    row for this pair — a control queued before it would delete itself.
    //  - BEFORE _localCleanup(), which wipes the peer's Signal session and
    //    would leave nothing to encrypt the envelope with.
    final peer = _repo.recipientId;
    if (_repo.groupId == null && peer != null && _e2eeHandler != null) {
      try {
        final dispatched =
            await _e2eeHandler!.sendSealedDeleteChat(recipientId: peer);
        debugPrint('[Chat] deleteChat: sealed delete_chat dispatched=$dispatched');
      } catch (e) {
        // Best-effort, exactly like unsend: our own delete still proceeds.
        debugPrint('[Chat] deleteChat: sealed delete_chat failed: $e');
      }
    }

    await _localCleanup();
  }

  /// Delete Group (room demolition) — owner only.
  /// Deletes the entire group, all messages, and kicks all members.
  /// Server returns 403 if not the creator.
  Future<void> deleteGroup() async {
    _cancelAllTimers();

    final apiClient = _repo.apiClient;
    if (apiClient != null) {
      try {
        await apiClient.delete('/groups/$groupId');
        debugPrint('[Chat] deleteGroup: server DELETE success (방 폭파)');
      } catch (e) {
        debugPrint('[Chat] deleteGroup: server DELETE failed ($e)');
      }
    }

    await _localCleanup();
  }

  /// Leave Group — simple leave without deleting own messages.
  /// Ownership auto-transfers to the oldest member on server side.
  Future<void> leaveGroup() async {
    _cancelAllTimers();

    final apiClient = _repo.apiClient;
    if (apiClient != null) {
      try {
        await apiClient.post('/groups/$groupId/leave');
        debugPrint('[Chat] leaveGroup: server LEAVE success');
      } catch (e) {
        debugPrint('[Chat] leaveGroup: server LEAVE failed ($e)');
      }
    }

    await _localCleanup();
  }

  /// Leave Group + Delete My Messages for everyone.
  /// Uses server batch endpoint (no 5-min limit) then leaves.
  Future<void> leaveAndDeleteMyMessages() async {
    _cancelAllTimers();

    final apiClient = _repo.apiClient;
    if (apiClient != null) {
      try {
        // Step 1: Batch-delete own messages on server (fan-out to members)
        await apiClient.delete('/groups/$groupId/messages/mine');
        debugPrint('[Chat] leaveAndDelete: own messages batch-deleted');
      } catch (e) {
        debugPrint('[Chat] leaveAndDelete: batch delete failed ($e)');
      }
      try {
        // Step 2: Leave the group
        await apiClient.post('/groups/$groupId/leave');
        debugPrint('[Chat] leaveAndDelete: server LEAVE success');
      } catch (e) {
        debugPrint('[Chat] leaveAndDelete: server LEAVE failed ($e)');
      }
    }

    await _localCleanup();
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
