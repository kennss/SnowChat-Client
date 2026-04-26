/// @file        chat_provider.dart
/// @description Chat UI state-management Provider — delegates the data layer to MessageRepository, manages UI state (typing, reply, TTL, deletion)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-18 P1-2: rethrow on clearChat server failure — block silent local-clear)
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
    myId: mySnowId ?? '',
    recipientId: recipientSnowchatId,
    groupId: groupId,
    ref: ref,
    expiringManager: ref.read(expiringMessageManagerProvider),
  );

  final markReadHelper = MarkReadHelper(
    conversationId: conversationId,
    messageDao: messageDao,
    socketManager: socketManager,
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

  ChatNotifier(
    this.conversationId, {
    required MessageRepository repository,
    required MarkReadHelper markReadHelper,
    SocketManager? socketManager,
    EncryptedMessageHandler? e2eeHandler,
    String? mySnowId,
    SecureStorageService? secureStorage,
    this.onTranslateRequest,
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

    // Persist to drift (including TTL for app restart recovery)
    _repo.persistMessage(LocalMessagesCompanion(
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
    ));

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
      // 1:1 E2EE path — always use regular Double Ratchet.
      //
      // Sealed Sender is disabled for 1:1 sends until the server configures a
      // persistent SEALED_SENDER_PRIVATE_KEY. The ephemeral keypair generated
      // on every server restart causes getCertificate() to fail, and the
      // fallback path corrupts the ratchet state (double-encrypt: the sealed
      // path's encrypt() advances the ratchet before the exception, so the
      // fallback encrypt() produces a message at counter N+1 while step N was
      // never sent — permanent decrypt failure on the recipient side).
      debugPrint('[DIAG:Send] $messageId routing to 1:1 E2EE (regular DR) '
          'recipientId=$recipientId');
      try {
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
      await _repo.persistMessage(LocalMessagesCompanion(
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
      ));

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
        try {
          await _e2eeHandler!.sendEncryptedMessage(
            conversationId: conversationId,
            recipientId: recipientId!,
            text: fileName,
            clientMessageId: messageId,
            type: MessageType.file,
            metadata: metadata,
            ttlSeconds: ttl,
          );
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
    if (_socketManager == null || recipientId == null) return;
    state = state.copyWith(isSending: true);

    final messageId = 'msg_${DateTime.now().millisecondsSinceEpoch}_voice';
    final now = DateTime.now();
    final ttl = state.disappearingTTL;

    final localMessage = Message(
      id: messageId,
      conversationId: conversationId,
      senderSnowchatId: _myId,
      plaintext: 'Voice message',
      timestamp: now,
      type: MessageType.voice,
      status: MessageStatus.sending,
      metadata: {'duration': durationSeconds, 'localPath': audioPath},
      expiresAt: ttl != null ? now.add(Duration(seconds: ttl)) : null,
      ttlSeconds: ttl,
    );
    state = state.copyWith(
      messages: [...state.messages, localMessage],
      isSending: false,
    );

    _repo.persistMessage(LocalMessagesCompanion(
      id: Value(messageId),
      conversationId: Value(conversationId),
      senderSnowchatId: Value(_myId),
      plaintext: const Value('Voice message'),
      dateSent: Value(now.millisecondsSinceEpoch),
      dateReceived: Value(now.millisecondsSinceEpoch),
      type: const Value('voice'),
      read: const Value(true),
      outgoingStatus: const Value('sending'),
    ));

    _socketManager!.sendPrivateMessage({
      'recipientId': recipientId,
      'text': 'Voice message',
      'type': 'voice',
      'metadata': {'duration': durationSeconds, 'audioPath': audioPath},
      if (ttl != null) 'expiresIn': ttl,
    });
    _scheduleDeletionIfNeeded(localMessage);
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
      final typingConvId = data['conversationId'] as String?;
      if (typingConvId != conversationId) return;
      final stopped = data['stopped'] as bool? ?? false;
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
      sm.sendTyping(conversationId);
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
    _socketManager?.stopTyping(conversationId);
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
  }

  /// Delete a message for everyone (sender only).
  /// Sends delete_message to server, which relays to all recipients.
  /// For unsent messages (local ID), only deletes locally.
  Future<void> deleteMessageForEveryone(String messageId) async {
    final message = state.messages.where((m) => m.id == messageId).firstOrNull;
    if (message == null) return;
    if (!message.isMine(_myId)) return;

    // Only send to server if message has a server ID (not local msg_ prefix)
    if (!messageId.startsWith('msg_')) {
      _socketManager?.emit('delete_message', {'messageId': messageId});
    }
    // Physical delete locally
    await deleteMessageForMe(messageId);
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
        await apiClient.delete('/conversations/$conversationId/messages');
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
      try {
        await apiClient.delete('/conversations/$conversationId');
        debugPrint('[Chat] deleteChat: server DELETE success');
        if (_secureStorage != null) {
          await removeDeletedConvId(_secureStorage!, conversationId);
        }
      } catch (e) {
        debugPrint('[Chat] deleteChat: 1:1 server DELETE failed ($e), tombstoning');
        if (_secureStorage != null) {
          await addDeletedConvId(_secureStorage!, conversationId);
        }
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
