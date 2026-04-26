/// @file        conversation_list_provider.dart
/// @description Conversation-list state-management Provider — server conversation-list fetch, add/remove conversations, last-message updates, pending group-invite management
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-13 fix: removeConversation matches both c.id and c.groupId)
///  - [DIAG] added enter/skip logging for _listenForIncomingMessages / _listenForGroupEvents
///  - Fix: listen for group_invite to auto-load group on creation
///  - Fix: _drainConversation() now stores metadata for file/image messages
///  - Fix: _drainPendingMessages() merges new drift conversations into state
///         after queue drain (offline 1:1 first-message bug)
///  - Phase 8.7 round 9: after the very first server load completes and the
///    Signal session manager is ready, fire-and-forget a Sender Key
///    Distribution broadcast for every group the user is a member of. This
///    eliminates the 2-3min lazy-trickle that previously occurred between
///    fresh-installed devices because SKDM was only ever sent piggyback on
///    a user-initiated group message.
///
/// @functions
///  - conversationListProvider: StateNotifierProvider supplying the conversation list
///  - ConversationListNotifier: StateNotifier managing conversation-list state
///  - loadFromServer(): load the conversation list from the server
///  - addConversation(): add a new conversation
///  - removeConversation(): remove a conversation
///  - updateLastMessage(): update the last message of a conversation
///  - markAsRead(): mark a conversation as read
///  - pendingInvites: getter for the list of pending group invites
///  - clearPendingInvites(): clear the pending group-invite list
///  - loadDeletedConvIds(storage): load locally deleted conversation-ID tombstones (top-level)
///  - addDeletedConvId(storage, id): add a deleted conversation-ID tombstone (top-level)
///  - removeDeletedConvId(storage, id): remove a conversation ID from the tombstone (top-level)
///  - _retryPendingDeletions(): retry server DELETE for conversations remaining in the tombstone
///  - _listenForIncomingMessages(): T0-pattern socket message reception — auto create/update the conversation list (+ drift dual-write)
///  - _persistIncomingToDrift(): transactional persistence of received messages into the drift DB (SSoT)
///  - _resolveSenderDisplayName(): fetch and update the sender display name from the server
///  - _listenForGroupEvents(): listen for group-member-removed / group-info-changed socket events
///  - _preBroadcastGroupSenderKeys(): pre-distribute SKDM for every group the user
///    is a member of (called immediately after socket connect / first server load)
///  - _invalidateSenderKeyForGroup(): invalidate the Sender Key on member leave/kick,
///    plus lazy rotation (regenerate key + redistribute SKDM on next send)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
// Phase 6: drift import is needed only for the drift-generated Conversation
// row type, aliased as `db` to avoid colliding with the in-memory model
// `Conversation` from models/conversation.dart.
import '../../../core/storage/database.dart' as db show Conversation;
import '../../../core/crypto/group_metadata_crypto.dart';
import '../../../core/network/api_endpoints.dart';
import '../models/conversation.dart';
import '../../../core/storage/secure_storage.dart';
import 'chat_provider.dart' show broadcastSenderKeyToGroup;
import 'mark_read_helper.dart';

// ---------------------------------------------------------------------------
// Top-level tombstone helpers for locally-deleted conversation IDs.
// Accessible from both ConversationListNotifier and ChatNotifier (via import).
// ---------------------------------------------------------------------------

const _tombstoneKey = 'locally_deleted_conversation_ids';

/// Load tombstoned conversation IDs from SecureStorage.
Future<Set<String>> loadDeletedConvIds(SecureStorageService storage) async {
  try {
    final raw = await storage.read(_tombstoneKey);
    if (raw == null || raw.isEmpty) return {};
    final ids = (jsonDecode(raw) as List).cast<String>();
    return ids.toSet();
  } catch (e) {
    debugPrint('[Tombstone] loadDeletedConvIds failed: $e');
    return {};
  }
}

/// Add a conversation ID to the tombstone set.
Future<void> addDeletedConvId(SecureStorageService storage, String id) async {
  try {
    final ids = await loadDeletedConvIds(storage);
    ids.add(id);
    await storage.write(_tombstoneKey, jsonEncode(ids.toList()));
    debugPrint('[Tombstone] ADDED: $id (total=${ids.length})');
  } catch (e) {
    debugPrint('[Tombstone] addDeletedConvId failed: $e');
  }
}

/// Remove a conversation ID from the tombstone set (server delete succeeded).
Future<void> removeDeletedConvId(SecureStorageService storage, String id) async {
  try {
    final ids = await loadDeletedConvIds(storage);
    ids.remove(id);
    if (ids.isEmpty) {
      await storage.delete(_tombstoneKey);
    } else {
      await storage.write(_tombstoneKey, jsonEncode(ids.toList()));
    }
    debugPrint('[Tombstone] REMOVED: $id (remaining=${ids.length})');
  } catch (e) {
    debugPrint('[Tombstone] removeDeletedConvId failed: $e');
  }
}

/// Provides the list of conversations.
/// Loads from server when authenticated, falls back to mock data otherwise.
final conversationListProvider =
    StateNotifierProvider<ConversationListNotifier, List<Conversation>>((ref) {
  final notifier = ConversationListNotifier(ref);
  // Fix 1.1: Use ref.read (not ref.watch) so this provider is NOT recreated
  // on every token refresh. Use ref.listen to trigger loadFromServer once.
  final token = ref.read(authTokenProvider);
  if (token != null) {
    Future.microtask(() => notifier.loadFromServer());
  }
  ref.listen<String?>(authTokenProvider, (previous, next) {
    if (next != null && previous == null) {
      Future.microtask(() => notifier.loadFromServer());
    }
  });
  return notifier;
});

class ConversationListNotifier extends StateNotifier<List<Conversation>> {
  final Ref _ref;
  bool _serverLoaded = false;
  List<Map<String, dynamic>> _pendingInvites = [];
  List<Map<String, dynamic>> get pendingInvites => _pendingInvites;
  StreamSubscription<Map<String, dynamic>>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _groupMemberRemovedSubscription;
  StreamSubscription<Map<String, dynamic>>? _groupUpdatedSubscription;
  StreamSubscription<Map<String, dynamic>>? _friendRequestSubscription;

  StreamSubscription<Map<String, dynamic>>? _gmkRequestSubscription;
  final Set<String> _gmkRequested = {}; // Debounce: request GMK only once per group

  ConversationListNotifier(this._ref) : super([]) {
    _listenForIncomingMessages();
    _listenForGroupEvents();
    _listenForFriendRequests();
    _listenForGmkRequests();
    _listenForChatDeleted();
    // Wire onNewConversation callback — when MessageQueue creates a new
    // conversation in drift, mirror it into in-memory state immediately.
    // Resolves the socket-listener timing issue.
    _ref.read(messageQueueProvider).onNewConversation = (convId, senderSnowId) {
      final exists = state.any((c) => c.id == convId);
      if (!exists) {
        final mySnowId = _ref.read(currentSnowIdProvider) ?? '';
        debugPrint('[DIAG:ConvList] onNewConversation: adding $convId from $senderSnowId');
        final newConv = Conversation(
          id: convId,
          type: ConversationType.direct,
          participantIds: [mySnowId, senderSnowId],
          title: senderSnowId,
          lastMessageText: 'New message',
          lastMessageTime: DateTime.now(),
          lastMessageSenderId: senderSnowId,
          unreadCount: 1,
          createdAt: DateTime.now(),
        );
        state = [newConv, ...state];
        _resolveSenderDisplayName(convId, senderSnowId);
      }
    };

    // Phase 8.8: Wire GMK received callback to update specific group name
    _ref.read(messageQueueProvider).onGmkReceived = (groupId) async {
      final (gmk, _) = await GroupMetadataCrypto.loadGMK(groupId);
      if (gmk == null) return;
      final updated = [...state];
      for (int i = 0; i < updated.length; i++) {
        if (updated[i].groupId == groupId && (updated[i].title == null || updated[i].title!.isEmpty)) {
          // Try to decrypt from server's encryptedName
          // For now, mark as needing refresh — the next loadFromServer will pick it up
          _serverLoaded = false;
          loadFromServer();
          return;
        }
      }
    };
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _groupMemberRemovedSubscription?.cancel();
    _groupUpdatedSubscription?.cancel();
    _friendRequestSubscription?.cancel();
    _gmkRequestSubscription?.cancel();
    super.dispose();
  }

  /// Load conversations from the server API.
  /// Falls back to mock data on failure.
  Future<void> loadFromServer() async {
    if (_serverLoaded) return;

    try {
      final apiClient = _ref.read(apiClientProvider);
      final response = await apiClient.get(ApiEndpoints.conversations);
      final data = Map<String, dynamic>.from(response.data as Map);
      final serverConversations =
          (data['conversations'] as List).map((conv) {
        final c = Map<String, dynamic>.from(conv as Map);
        final mySnowId = _ref.read(currentSnowIdProvider);

        // Parse lastMessageText from server response.
        // Server returns lastMessageText directly (not nested in lastMessage).
        String? parsedLastMsgText;
        if (c['lastMessageText'] != null) {
          parsedLastMsgText = c['lastMessageText'].toString();
        } else if (c['lastMessage'] is Map) {
          parsedLastMsgText = (c['lastMessage'] as Map)['text']?.toString();
        }
        return Conversation(
          id: c['id'] as String,
          type: ConversationType.direct,
          participantIds: [
            mySnowId ?? '',
            c['recipientSnowchatId'] as String,
          ],
          title: c['recipientDisplayName'] as String?,
          lastMessageText: parsedLastMsgText,
          lastMessageTime: c['lastMessageAt'] != null
              ? DateTime.parse(c['lastMessageAt'] as String)
              : null,
          // unreadCount populated by _drainPendingMessages from local DB
          createdAt: c['lastMessageAt'] != null
              ? DateTime.parse(c['lastMessageAt'] as String)
              : DateTime.now(),
        );
      }).toList();

      // Filter out locally-deleted (tombstoned) conversations that the server
      // still returns because the DELETE failed on a previous attempt.
      final deletedIds = await _loadDeletedConvIds();
      if (deletedIds.isNotEmpty) {
        serverConversations.removeWhere((c) => deletedIds.contains(c.id));
        debugPrint('[ConversationList] Filtered ${deletedIds.length} '
            'tombstoned conversations from server list');
      }

      state = serverConversations;
      _serverLoaded = true;
      debugPrint(
          '[ConversationList] Loaded ${serverConversations.length} '
          'conversations from server');

      // Load group conversations
      try {
        final groupRes = await apiClient.get(ApiEndpoints.groups);
        final groupData = Map<String, dynamic>.from(groupRes.data as Map);
        final serverGroups = await Future.wait(
          (groupData['groups'] as List).map((g) async {
          final group = Map<String, dynamic>.from(g as Map);
          // Phase 8.8: Decrypt group name with locally stored GMK
          String? groupTitle;
          final groupId = group['id'] as String;
          final encName = group['encryptedName'] as String?;
          if (encName != null) {
            final (gmk, _) = await GroupMetadataCrypto.loadGMK(groupId);
            if (gmk != null) {
              groupTitle = GroupMetadataCrypto.decryptGroupName(gmk, encName);
            } else if (!_gmkRequested.contains(groupId)) {
              // GMK missing — auto-request once per group
              _gmkRequested.add(groupId);
              debugPrint('[ConversationList] GMK missing for $groupId — requesting');
              _ref.read(socketManagerProvider).requestGmk(groupId);
            }
          }
          // Fallback: use server 'name' field for pre-Phase 8.8 groups
          groupTitle ??= group['name'] as String?;
          return Conversation(
            id: group['id'] as String,
            type: ConversationType.group,
            groupId: group['id'] as String,
            channelId: group['channelId'] as String?,
            title: groupTitle,
            participantIds: [],
            lastMessageText:
                (group['lastMessage'] as Map?)?['text'] as String?,
            lastMessageTime:
                (group['lastMessage'] as Map?)?['timestamp'] != null
                    ? DateTime.parse(
                        (group['lastMessage'] as Map)['timestamp'] as String)
                    : null,
            createdAt: DateTime.parse(group['createdAt'] as String),
          );
        }));
        state = [...state, ...serverGroups];
        debugPrint(
            '[ConversationList] Loaded ${serverGroups.length} groups from server');
      } catch (e) {
        debugPrint('[ConversationList] Failed to load groups: $e');
      }

      // Sort all conversations by last message time
      state = [...state]..sort((a, b) =>
          (b.lastMessageTime ?? b.createdAt)
              .compareTo(a.lastMessageTime ?? a.createdAt));

      // Signal pattern: Message Drain — fetch pending messages for all conversations
      // and process via insertIncomingMessage to build accurate local unread counts.
      await _drainPendingMessages();

      // Signal pattern: ExpiringMessageManager — load pending expirations
      // and schedule timers (deletes expired messages, schedules remaining).
      _ref.read(expiringMessageManagerProvider).initialize();

      // E2EE: Initialize Signal session manager — restore sessions,
      // check/replenish pre-keys on server. Non-fatal: if it fails,
      // messages will be marked as failed (not silently sent as plaintext).
      try {
        await _ref.read(signalSessionManagerProvider).initialize();
      } catch (e) {
        debugPrint('[ConversationList] E2EE init failed (non-fatal): $e');
      }

      // Check for pending group invites
      try {
        final pendingRes =
            await apiClient.get(ApiEndpoints.pendingGroupInvites);
        final pendingData =
            Map<String, dynamic>.from(pendingRes.data as Map);
        final invites = pendingData['invites'] as List? ?? [];
        if (invites.isNotEmpty) {
          debugPrint(
              '[ConversationList] ${invites.length} pending group invites');
          _pendingInvites = invites.cast<Map<String, dynamic>>();
        }
      } catch (e) {
        debugPrint(
            '[ConversationList] Failed to load pending invites: $e');
      }

      // Phase 8.7 round 9 — pre-distribute Sender Key Distribution Messages
      // for every group the user is a member of, WITHOUT waiting for the
      // user to type a message. Reproduction with 5 fresh devices showed it
      // took ~2-3 minutes for SKDMs to fully propagate as the user manually
      // typed test messages on each device. Now we proactively push them
      // immediately after the first server load (and after the Signal
      // session manager has finished initializing). The 24h
      // SenderKeyDistributionTracker dedup makes this a no-op for groups
      // whose members already have an up-to-date SKDM.
      //
      // Fire-and-forget on purpose: do NOT block loadFromServer on this,
      // because the user expects the conversation list to render immediately.
      unawaited(_preBroadcastGroupSenderKeys());

      // Retry server DELETE for conversations that were locally deleted but
      // whose server-side deletion failed previously. Fire-and-forget.
      unawaited(_retryPendingDeletions());
    } catch (e) {
      debugPrint('[ConversationList] Failed to load from server: $e');
      // Keep current state as fallback (empty until server responds)
    }
  }

  /// Phase 8.7 round 9 — proactively push Sender Key Distribution Messages
  /// (SKDMs) for every group the user is a member of, so receivers can
  /// decrypt the next group message immediately instead of waiting for the
  /// user to send a message that piggybacks an SKDM.
  ///
  /// Called once after the first successful [loadFromServer] (and after
  /// SignalSessionManager.initialize() has completed in that same load).
  /// Repeat invocations are cheap because the 24h tracker dedup short-
  /// circuits already-delivered members.
  Future<void> _preBroadcastGroupSenderKeys() async {
    try {
      final myId = _ref.read(currentSnowIdProvider);
      if (myId == null || myId.isEmpty) {
        debugPrint('[ConversationList] preBroadcast skip — myId not resolved');
        return;
      }
      final e2eeHandler = _ref.read(encryptedMessageHandlerProvider);
      final socketManager = _ref.read(socketManagerProvider);
      final apiClient = _ref.read(apiClientProvider);

      // Pick groups the user is currently a member of (skip 1:1 conversations).
      final groupConvs = state
          .where((c) => c.type == ConversationType.group && c.groupId != null)
          .toList();
      if (groupConvs.isEmpty) {
        debugPrint('[ConversationList] preBroadcast — no group conversations');
        return;
      }
      debugPrint('[ConversationList] preBroadcast START for '
          '${groupConvs.length} group(s)');

      // Process groups concurrently. Each group needs an HTTP roundtrip to
      // /groups/:id to fetch the canonical member list, then the helper
      // performs ensureSessionBatch + 1:1 SKDM dispatch.
      await Future.wait(groupConvs.map((conv) async {
        final groupId = conv.groupId!;
        try {
          final response = await apiClient.get('/groups/$groupId');
          final data = response.data;
          if (data is! Map || data['members'] is! List) return;
          final members = (data['members'] as List)
              .map((m) => (m as Map)['snowchatId'] as String?)
              .where((id) => id != null && id != myId)
              .cast<String>()
              .toList();
          if (members.isEmpty) return;
          await broadcastSenderKeyToGroup(
            groupId: groupId,
            myId: myId,
            members: members,
            e2eeHandler: e2eeHandler,
            socketManager: socketManager,
            diagTag: 'PreBroadcast',
          );
        } catch (e) {
          debugPrint('[ConversationList] preBroadcast group $groupId FAIL: $e');
        }
      }));
      debugPrint('[ConversationList] preBroadcast DONE');
    } catch (e) {
      debugPrint('[ConversationList] preBroadcast FAILED: $e');
    }
  }

  /// Invalidate our Sender Key for [groupId] after a member departs.
  ///
  /// This is the core of forward-secrecy on member removal: the old Sender Key
  /// that the departed member possessed is discarded, and a fresh key will be
  /// generated on the next outbound message (lazy rotation, matching Signal's
  /// approach). Steps:
  ///
  ///  1. Remove the departed member from the SKDM tracker so we never send
  ///     them a future SKDM.
  ///  2. Remove the departed member from GroupSessionManager's membership set.
  ///  3. Rotate our Sender Key (drops old key, creates new chainId).
  ///  4. Invalidate the full group tracker so the next send redistributes
  ///     SKDM to ALL remaining members.
  ///  5. Persist updated state to disk.
  void _invalidateSenderKeyForGroup(
    String groupId,
    String? removedSnowchatId,
  ) {
    try {
      final myId = _ref.read(currentSnowIdProvider);
      if (myId == null || myId.isEmpty) {
        debugPrint('[ConversationList] SK rotation skip — myId not resolved '
            '(group $groupId)');
        return;
      }

      final e2eeHandler = _ref.read(encryptedMessageHandlerProvider);
      final groupSessionMgr = e2eeHandler.groupSessionManager;

      if (groupSessionMgr == null) {
        debugPrint('[ConversationList] SK rotation skip — groupSessionManager '
            'not initialized (group $groupId)');
        return;
      }

      final sessionMgr = e2eeHandler.sessionManager;
      final tracker = sessionMgr.signal.skdmTracker;
      final senderKeyMgr = groupSessionMgr.senderKeyManager;

      // 1. Remove departed member from SKDM tracker
      if (removedSnowchatId != null && removedSnowchatId.isNotEmpty) {
        tracker.removeMember(groupId, removedSnowchatId);
        groupSessionMgr.removeMemberFromGroup(groupId, removedSnowchatId);
        debugPrint('[ConversationList] SK rotation: removed $removedSnowchatId '
            'from tracker + membership (group $groupId)');
      }

      // 2. Rotate our Sender Key (new chainId, bumps rotation version)
      if (senderKeyMgr.hasSenderKey(groupId, myId)) {
        senderKeyMgr.rotateSenderKey(groupId, myId);
        debugPrint('[ConversationList] SK rotation: rotated own sender key '
            '(group $groupId, new rotationVersion='
            '${senderKeyMgr.getRotationVersion(groupId)})');
      }

      // 3. Invalidate full group tracker — next send will re-distribute
      tracker.invalidateGroup(groupId);

      // 4. Persist state to disk (fire-and-forget)
      groupSessionMgr.persistState().catchError((e) {
        debugPrint('[ConversationList] SK rotation persistState FAIL '
            '(group $groupId): $e');
      });

      debugPrint('[ConversationList] SK rotation complete for group $groupId');
    } catch (e) {
      debugPrint('[ConversationList] SK rotation FAILED (group $groupId): $e');
    }
  }

  /// Force reload from server.
  Future<void> refresh() async {
    _serverLoaded = false;
    await loadFromServer();
  }

  /// Clear pending invites after they have been shown to the user.
  void clearPendingInvites() {
    _pendingInvites = [];
  }

  void addConversation(Conversation conversation) {
    state = [conversation, ...state];
  }

  void removeConversation(String id) {
    state = state.where((c) => c.id != id && c.groupId != id).toList();
  }

  // ---------------------------------------------------------------------------
  // Tombstone helpers — locally-deleted conversation IDs (SecureStorage)
  // ---------------------------------------------------------------------------
  // Delegates to top-level functions (shared with ChatNotifier).
  // When a 1:1 server DELETE fails (network error), we persist the conversation
  // ID so loadFromServer() can filter it out until the deletion is retried
  // successfully. This prevents "ghost" conversations from reappearing after
  // a failed server-side deletion.

  SecureStorageService get _storage => _ref.read(secureStorageProvider);

  Future<Set<String>> _loadDeletedConvIds() => loadDeletedConvIds(_storage);
  Future<void> _removeDeletedConvId(String id) => removeDeletedConvId(_storage, id);

  /// Retry server DELETE for each tombstoned conversation ID.
  /// On success, remove the tombstone. On failure, leave it for next retry.
  Future<void> _retryPendingDeletions() async {
    final ids = await _loadDeletedConvIds();
    if (ids.isEmpty) return;
    debugPrint('[ConversationList] _retryPendingDeletions: ${ids.length} pending');
    final apiClient = _ref.read(apiClientProvider);
    for (final id in ids.toList()) {
      try {
        await apiClient.delete('/conversations/$id');
        await _removeDeletedConvId(id);
        debugPrint('[ConversationList] retry DELETE success: $id');
      } catch (e) {
        debugPrint('[ConversationList] retry DELETE failed for $id: $e');
      }
    }
  }

  /// Phase 11: Listen for chat_deleted / group_deleted (room demolition).
  /// Remove the conversation locally when the other side deletes it.
  void _listenForChatDeleted() {
    final sm = _ref.read(socketManagerProvider);
    sm.onChatDeleted.listen((data) async {
      // Works for both 1:1 (conversationId) and group (groupChatId)
      final id = (data['conversationId'] ?? data['groupChatId']) as String?;
      if (id == null) return;
      debugPrint('[ConversationList] chat/group deleted received: $id');

      // Remove from drift DB (messages + conversation row)
      try {
        final convDao = _ref.read(conversationDaoProvider);
        await convDao.deleteConversation(id);
      } catch (e) {
        debugPrint('[ConversationList] chat_deleted drift cleanup failed: $e');
      }

      // Remove from in-memory state
      removeConversation(id);
    });
  }

  void updateLastMessage(
    String conversationId, {
    required String text,
    required String senderId,
  }) {
    state = state.map((c) {
      if (c.id == conversationId) {
        return c.copyWith(
          lastMessageText: text,
          lastMessageTime: DateTime.now(),
          lastMessageSenderId: senderId,
          unreadCount: c.unreadCount + 1,
        );
      }
      return c;
    }).toList();
  }

  /// Update conversation preview without incrementing unread count.
  /// Phase 3: server CUID matching only.
  void updatePreview(
    String conversationId, {
    required String text,
    required String senderId,
    required DateTime messageTime,
    String? recipientId,
  }) {
    final exists = state.any(
        (c) => c.id == conversationId || c.groupId == conversationId);
    if (exists) {
      state = state.map((c) {
        final match = c.id == conversationId || c.groupId == conversationId;
        if (match) {
          if (c.lastMessageTime != null &&
              c.lastMessageTime!.isAfter(messageTime)) {
            return c;
          }
          return c.copyWith(
            lastMessageText: text,
            lastMessageTime: messageTime,
            lastMessageSenderId: senderId,
          );
        }
        return c;
      }).toList();
    } else {
      // Sender-side: first message sent to a new conversation.
      // Create the conversation entry so it appears in the list immediately.
      final mySnowId = _ref.read(currentSnowIdProvider) ?? '';
      final otherSnowId = recipientId ?? (senderId == mySnowId ? '' : senderId);
      final newConv = Conversation(
        id: conversationId,
        type: ConversationType.direct,
        participantIds: [mySnowId, otherSnowId],
        title: null,
        lastMessageText: text,
        lastMessageTime: messageTime,
        lastMessageSenderId: senderId,
        unreadCount: 0,
        createdAt: DateTime.now(),
      );
      state = [newConv, ...state];
      if (otherSnowId.isNotEmpty) {
        _resolveSenderDisplayName(conversationId, otherSnowId);
      }
    }
  }

  void markAsRead(String conversationId) {
    state = state.map((c) {
      if (c.id == conversationId || c.groupId == conversationId) {
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();
  }

  /// Auto-translation toggle (immediate in-memory state reflection).
  void toggleAutoTranslate(String conversationId, {required bool enabled}) {
    state = state.map((c) {
      if (c.id == conversationId) {
        return c.copyWith(autoTranslateEnabled: enabled);
      }
      return c;
    }).toList();
  }

  /// Set per-room translation target language (immediate in-memory state reflection).
  /// Falls back to the global preferredLanguage when null.
  void setAutoTranslateTarget(String conversationId, String? targetLang) {
    state = state.map((c) {
      if (c.id == conversationId) {
        return c.copyWith(autoTranslateTargetLang: targetLang);
      }
      return c;
    }).toList();
  }

  /// Phase 11: Clear Chat — reset preview text and unread count (keep conversation in list).
  void clearPreview(String conversationId) {
    state = state.map((c) {
      if (c.id == conversationId || c.groupId == conversationId) {
        return c.copyWith(
          lastMessageText: null,
          unreadCount: 0,
        );
      }
      return c;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Group event listeners
  // ---------------------------------------------------------------------------

  /// Listen for group management events (member removed, group updated).
  /// Phase 9.1: Global listener for friend_request_received socket events.
  /// Updates the badge counter so the Friends tab shows a notification dot
  /// even when the user is on a different tab.
  void _listenForFriendRequests() {
    final sm = _ref.read(socketManagerProvider);
    _friendRequestSubscription = sm.onFriendRequestReceived.listen((data) {
      final current = _ref.read(pendingFriendBadgeProvider);
      _ref.read(pendingFriendBadgeProvider.notifier).state = current + 1;
      debugPrint('[ConversationList] friend_request_received — badge=${current + 1}');
    });
  }

  /// Phase 8.8: Respond to GMK requests from other group members.
  /// When someone can't decrypt a group name, they emit request_gmk.
  /// If we have the GMK, we send it back via 1:1 E2EE.
  void _listenForGmkRequests() {
    final sm = _ref.read(socketManagerProvider);
    _gmkRequestSubscription = sm.onGmkRequest.listen((data) async {
      final groupId = data['groupId'] as String?;
      final requesterSnowId = data['requesterSnowchatId'] as String?;
      if (groupId == null || requesterSnowId == null) return;

      // Check if we have the GMK for this group
      final (gmk, epoch) = await GroupMetadataCrypto.loadGMK(groupId);
      if (gmk == null) return; // We don't have it either

      debugPrint('[GMK] Responding to request_gmk from $requesterSnowId for $groupId');

      try {
        final sessionManager = _ref.read(signalSessionManagerProvider);
        final mySnowId = _ref.read(currentSnowIdProvider) ?? '';
        await sessionManager.ensureSession(requesterSnowId);
        final deviceId = await sessionManager.getDeviceIdForRecipient(requesterSnowId);

        final signingKeySeed = sessionManager.signal.signingKeySeed;
        final signature = signingKeySeed != null
            ? GroupMetadataCrypto.signGMK(
                signingKeySeed: signingKeySeed,
                groupId: groupId,
                gmk: gmk,
                epoch: epoch,
              )
            : null;

        final payload = utf8.encode(jsonEncode({
          'type': 'group_metadata_key',
          'groupId': groupId,
          'gmk': base64Encode(gmk),
          'epoch': epoch,
          if (signature != null) 'signature': base64Encode(signature),
          'coordinatorSnowId': mySnowId,
        }));

        final encrypted = await sessionManager.encrypt(
          requesterSnowId, deviceId, Uint8List.fromList(payload),
        );

        sm.sendPrivateMessage({
          'recipientId': requesterSnowId,
          'encryptedContent': {
            'ciphertext': base64Encode(encrypted['ciphertext'] as Uint8List),
          },
          'messageType': encrypted['messageType'],
          'type': 'group_metadata_key',
        });
        debugPrint('[GMK] Sent GMK response to $requesterSnowId');
      } catch (e) {
        debugPrint('[GMK] Failed to respond to request_gmk: $e');
      }
    });
  }

  void _listenForGroupEvents() {
    final sm = _ref.read(socketManagerProvider);

    // When a new group message arrives, update preview + unread count.
    // Phase 5.6: Decryption/persistence is delegated to single source of truth:
    //   - Real-time: message_repository._handleGroupMessage (when chat open)
    //   - Offline recovery: _fetchGroupMessages + _handleGroupMessage (when chat opens)
    // Doing it here too caused triple-processing race conditions and corrupted
    // Sender Key state.
    debugPrint('[DIAG:ConvList] _listenForGroupEvents SUBSCRIBED to socket onGroupMessage');
    sm.onGroupMessage.listen((data) async {
      final id = data['id'] ?? data['messageId'];
      final msgGroupId = (data['groupChatId'] ?? data['groupId']) as String?;
      if (msgGroupId == null) {
        debugPrint('[DIAG:ConvList] $id GROUP SKIP: missing groupChatId');
        return;
      }

      final senderSnowchatId =
          (data['senderSnowchatId'] ?? data['senderId'] ?? '') as String;
      final mySnowId = _ref.read(currentSnowIdProvider);

      // Skip own messages (echoed back from server)
      if (senderSnowchatId == mySnowId) {
        debugPrint('[DIAG:ConvList] $id GROUP SKIP own echo');
        return;
      }

      debugPrint('[DIAG:ConvList] $id GROUP listener fire: groupId=$msgGroupId '
          'from=$senderSnowchatId');

      final isViewing = MarkReadHelper.isConversationActive(msgGroupId);

      final idx = state.indexWhere(
          (c) => c.id == msgGroupId || c.groupId == msgGroupId);

      if (idx < 0) {
        debugPrint('[DIAG:ConvList] $id Unknown group $msgGroupId, reloading');
        _serverLoaded = false;
        loadFromServer();
        return;
      }

      final senderName =
          (data['senderDisplayName'] ?? senderSnowchatId) as String;
      final msgTime = data['serverTimestamp'] != null
          ? DateTime.parse(data['serverTimestamp'] as String)
          : (data['createdAt'] != null
              ? DateTime.parse(data['createdAt'] as String)
              : DateTime.now());

      // Ensure group conversation exists in drift DB so it shows in list.
      _ensureConversationInDrift(
        conversationId: msgGroupId,
        senderSnowchatId: senderSnowchatId,
      );

      // Preview text: server text is null for E2EE messages → placeholder.
      // Real plaintext will be available once user enters the chat
      // (via _handleGroupMessage or _fetchGroupMessages → _handleGroupMessage).
      final preview = (data['text'] ?? '[New message]') as String;

      // Update conversation list UI
      final updated = state[idx].copyWith(
        lastMessageText: '$senderName: $preview',
        lastMessageTime: msgTime,
        lastMessageSenderId: senderSnowchatId,
        unreadCount: isViewing
            ? state[idx].unreadCount
            : state[idx].unreadCount + 1,
      );
      final newList = [...state];
      newList[idx] = updated;
      newList.sort((a, b) => (b.lastMessageTime ?? b.createdAt)
          .compareTo(a.lastMessageTime ?? a.createdAt));
      state = newList;
    });

    // When a new member is added to a group (we might be the new member)
    sm.onGroupMemberAdded.listen((data) {
      final groupId = data['groupChatId'] as String?;
      if (groupId == null) return;
      final exists = state.any((c) => c.id == groupId || c.groupId == groupId);
      if (!exists) {
        debugPrint('[ConversationList] Added to group $groupId, reloading');
        _serverLoaded = false;
        loadFromServer();
      }
    });

    // When invited to a group (initial creation with autoJoined=true)
    sm.onGroupInvite.listen((data) {
      final groupId = (data['groupId'] ?? data['groupChatId']) as String?;
      if (groupId == null) return;
      final exists = state.any((c) => c.id == groupId || c.groupId == groupId);
      if (!exists) {
        debugPrint('[ConversationList] Group invite received $groupId, reloading');
        _serverLoaded = false;
        loadFromServer();
      }
    });

    // When a member is removed from a group (or you are removed)
    _groupMemberRemovedSubscription = sm.onGroupMemberRemoved.listen((data) {
      final groupId = data['groupChatId'] as String?;
      final youWereRemoved = data['youWereRemoved'] as bool? ?? false;
      if (groupId == null) return;

      if (youWereRemoved) {
        // Remove group from conversation list
        state = state.where((c) => c.groupId != groupId).toList();
        debugPrint('[ConversationList] Removed from group $groupId');
      } else {
        // Another member was removed/left — rotate our Sender Key so the
        // departed member cannot decrypt future messages. Lazy rotation:
        // invalidate the existing key + tracker; the next _sendGroupE2EE
        // or broadcastSenderKeyToGroup call will generate a fresh key and
        // distribute SKDM to remaining members only.
        _invalidateSenderKeyForGroup(
          groupId,
          data['removedSnowchatId'] as String?,
        );
      }
    });

    // When a member rejects a group invite that was auto-accepted
    // (wasAccepted=true), the composition changed — rotate Sender Key.
    sm.onGroupInviteRejected.listen((data) {
      final wasAccepted = data['wasAccepted'] as bool? ?? false;
      if (!wasAccepted) return; // pending reject — no key rotation needed

      final groupId = (data['groupId'] ?? data['groupChatId']) as String?;
      if (groupId == null) return;

      final rejectedBy = data['rejectedBy'] as Map?;
      final rejectedSnowchatId = rejectedBy?['snowchatId'] as String?;
      _invalidateSenderKeyForGroup(groupId, rejectedSnowchatId);
    });

    // When group info is updated (name change, avatar, etc.)
    _groupUpdatedSubscription = sm.onGroupUpdated.listen((data) {
      final groupId = data['groupChatId'] as String?;
      if (groupId == null) return;
      // Trigger a reload to get updated info
      _serverLoaded = false;
      loadFromServer();
    });
  }

  // ---------------------------------------------------------------------------
  // Global incoming message listener
  // ---------------------------------------------------------------------------

  /// Listen for incoming Socket.IO messages globally (T0 pattern).
  /// Auto-creates and updates conversations even when chat screen is not open.
  ///
  /// Phase 6: This listener does NOT decrypt or persist messages — that is the
  /// responsibility of MessageQueue (single global processor). It only updates
  /// the conversation list UI state (preview placeholder, optimistic unread).
  /// Real preview text appears once the queue inserts into drift and the
  /// conversations table watch fires.
  void _listenForIncomingMessages() {
    final sm = _ref.read(socketManagerProvider);
    debugPrint('[DIAG:ConvList] _listenForIncomingMessages SUBSCRIBED to socket onMessage');
    _messageSubscription = sm.onMessage.listen((data) async {
      final id = data['id'] ?? data['messageId'];
      final senderSnowchatId =
          (data['senderSnowchatId'] ?? data['senderId']) as String?;
      final mySnowId = _ref.read(currentSnowIdProvider);
      if (senderSnowchatId == null || senderSnowchatId == mySnowId) {
        debugPrint('[DIAG:ConvList] $id SKIP own/null '
            '(sender=$senderSnowchatId mySnowId=$mySnowId)');
        return;
      }

      // Phase 6: SKDM is handled by MessageQueue. Skip here so we don't
      // double-decrypt and corrupt the 1:1 ratchet.
      final msgType = data['type'] as String?;
      if (msgType == 'sender_key_distribution') {
        debugPrint('[DIAG:ConvList] $id SKIP SKDM (handled by MessageQueue)');
        return;
      }

      // Ghost-conversation fix: session_reset is a control message that must
      // never create or update a conversation entry.
      if (msgType == 'session_reset') {
        debugPrint('[DIAG:ConvList] $id SKIP session_reset (control message)');
        return;
      }
      // Backward compat: old clients send type='e2ee_text' with metadata
      // containing isSessionReset: true.
      if (data['metadata'] != null) {
        try {
          final meta = data['metadata'] is String
              ? jsonDecode(data['metadata'] as String) as Map<String, dynamic>
              : data['metadata'] as Map<String, dynamic>;
          if (meta['isSessionReset'] == true) {
            debugPrint('[DIAG:ConvList] $id SKIP session_reset via metadata');
            return;
          }
        } catch (_) {
          // malformed metadata — not a session reset
        }
      }

      final msgTime = data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now();

      // Phase 3: Use server conversationId (CUID) as the single ID.
      // Server always includes conversationId in private_message events.
      final serverConvId = data['conversationId'] as String?;
      if (serverConvId == null) {
        debugPrint('[DIAG:ConvList] $id SKIP missing conversationId '
            '(envelope keys=${data.keys.toList()})');
        return;
      }

      debugPrint('[DIAG:ConvList] $id LIVE listener fire: convId=$serverConvId '
          'from=$senderSnowchatId type=$msgType');

      // Phase 10 P2: Do NOT create conversations here. Conversation creation
      // is the responsibility of MessageQueue after successful decryption.
      // Creating conversations optimistically from encrypted socket events
      // caused phantom "[New message]" entries for messages that later fail
      // to decrypt (session corruption, retry fallback, etc.).
      //
      // Only UPDATE conversations that already exist in state (created by
      // MessageQueue or server load). New conversations surface through the
      // drift merge step after MessageQueue drain.
      final preview = (data['text'] ?? '[New message]') as String;

      // Find existing conversation by server CUID or participant match.
      final existingIndex = state.indexWhere((c) =>
          c.id == serverConvId || c.participantIds.contains(senderSnowchatId));

      if (existingIndex >= 0) {
        debugPrint('[DIAG:ConvList] $id UPDATE existing conv $serverConvId');
        final existing = state[existingIndex];
        final isViewing = MarkReadHelper.isConversationActive(existing.id);
        final updated = existing.copyWith(
          lastMessageText: preview,
          lastMessageTime: msgTime,
          lastMessageSenderId: senderSnowchatId,
          unreadCount: isViewing
              ? existing.unreadCount
              : existing.unreadCount + 1,
        );
        final newList = [...state];
        newList[existingIndex] = updated;
        newList.sort((a, b) => (b.lastMessageTime ?? b.createdAt)
            .compareTo(a.lastMessageTime ?? a.createdAt));
        state = newList;
      } else {
        // Skip control messages (session_reset) — they should never create conversations.
        final msgType = data['type'] as String?;
        if (msgType == 'session_reset') {
          debugPrint('[DIAG:ConvList] $id SKIP new conv $serverConvId '
              '(session_reset control message)');
          return;
        }
        // E2EE messages arrive with text=null (encrypted). Use placeholder;
        // MessageQueue decryption will update preview via updatePreview().
        final displayPreview = (data['text'] as String?) ?? 'New message';
        debugPrint('[DIAG:ConvList] $id IN-MEMORY new conv $serverConvId '
            'for sender $senderSnowchatId');
        final newConv = Conversation(
          id: serverConvId,
          type: ConversationType.direct,
          participantIds: [mySnowId ?? '', senderSnowchatId],
          title: senderSnowchatId,
          lastMessageText: displayPreview,
          lastMessageTime: msgTime,
          lastMessageSenderId: senderSnowchatId,
          unreadCount: 1,
          createdAt: DateTime.now(),
        );
        state = [newConv, ...state];
        _resolveSenderDisplayName(serverConvId, senderSnowchatId);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Drift DB sync
  // ---------------------------------------------------------------------------

  /// Phase 6: Trigger the global MessageQueue to fetch pending messages.
  /// The queue handles per-message decryption + drift insert + ACK.
  /// After the queue drains, this method:
  ///   1. refreshes in-memory unread counts on already-known conversations
  ///   2. **merges any NEW conversations created by the queue** (e.g. an
  ///      offline 1:1 from a brand-new peer) into the in-memory state.
  ///      Without this merge step, drift has the new conversation row but
  ///      the UI list never displays it because the in-memory list is the
  ///      sole UI source.
  Future<void> _drainPendingMessages() async {
    try {
      final mySnowId = _ref.read(currentSnowIdProvider);
      if (mySnowId != null) {
        final messageDao = _ref.read(messageDaoProvider);
        await messageDao.fixOwnMessagesReadStatus(mySnowId);
      }
      // fetchPending now awaits the worker drain internally — when this
      // returns, every fetched envelope has been written to drift.
      await _ref.read(messageQueueProvider).fetchPending();

      final messageDao = _ref.read(messageDaoProvider);
      final conversationDao = _ref.read(conversationDaoProvider);

      // Step 1: refresh unread counts for existing conversations.
      final updated = <int, Conversation>{};
      for (var i = 0; i < state.length; i++) {
        final conv = state[i];
        final count = await messageDao.getUnreadCount(conv.id);
        if (count != conv.unreadCount) {
          updated[i] = conv.copyWith(unreadCount: count);
        }
      }
      if (updated.isNotEmpty) {
        final newList = [...state];
        for (final entry in updated.entries) {
          newList[entry.key] = entry.value;
        }
        state = newList;
      }

      // Step 2: merge any newly-created conversations from drift into state.
      // The MessageQueue's _processPrivate1to1 calls findOrCreate for new
      // 1:1 chats — those rows must surface in the in-memory list here.
      final knownIds = state.map((c) => c.id).toSet();
      final List<db.Conversation> driftRows =
          await conversationDao.getAllConversations();
      final additions = <Conversation>[];
      for (final row in driftRows) {
        if (knownIds.contains(row.id)) continue;
        if (!row.isActive) continue;
        final unread = await messageDao.getUnreadCount(row.id);
        additions.add(Conversation(
          id: row.id,
          type: row.type == 'group'
              ? ConversationType.group
              : ConversationType.direct,
          title: row.title,
          groupId: row.groupId,
          participantIds: _decodeParticipants(row.participantIds),
          lastMessageText: row.lastMessageText,
          lastMessageTime: row.lastMessageTime != null
              ? DateTime.fromMillisecondsSinceEpoch(row.lastMessageTime!)
              : null,
          lastMessageSenderId: row.lastMessageSenderId,
          unreadCount: unread,
          autoTranslateEnabled: row.autoTranslateEnabled,
          autoTranslateTargetLang: row.autoTranslateTargetLang,
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        ));
      }
      if (additions.isNotEmpty) {
        debugPrint('[ConversationList] Merging ${additions.length} new '
            'conversation(s) from drift after fetchPending drain');
        // Try to resolve real display names for the new conversations.
        for (final conv in additions) {
          if (conv.type == ConversationType.direct) {
            final peer = conv.participantIds.firstWhere(
              (id) => id != mySnowId,
              orElse: () => '',
            );
            if (peer.isNotEmpty) {
              _resolveSenderDisplayName(conv.id, peer);
            }
          }
        }
        final merged = [...additions, ...state]..sort((a, b) =>
            (b.lastMessageTime ?? b.createdAt)
                .compareTo(a.lastMessageTime ?? a.createdAt));
        state = merged;
      }
    } catch (e, st) {
      debugPrint('[DRAIN] FAILED: $e\n$st');
    }
  }

  /// Decode the comma-separated participantIds string stored in drift.
  static List<String> _decodeParticipants(String encoded) {
    if (encoded.isEmpty) return const [];
    return encoded.split(',').where((s) => s.isNotEmpty).toList();
  }

  // Phase 6: All decryption / persistence is delegated to MessageQueue.
  // The conversation list reacts to drift watch (via ConversationDao) and to
  // socket envelope events for optimistic preview/unread updates only.
  // Removed in Phase 6.5:
  //   - _decryptAndPersistMessage()
  //   - _decryptAndPersistGroupMessage()
  //   - _processInlineSKDM() / _doProcessSKDM()
  //   - _handleGlobalSenderKeyDistribution()

  /// Ensure conversation exists in drift DB for incoming messages.
  /// Message INSERT + unreadCount is handled by MessageRepository (single source).
  /// This only ensures the conversation record exists.
  Future<void> _ensureConversationInDrift({
    required String conversationId,
    required String senderSnowchatId,
  }) async {
    try {
      final conversationDao = _ref.read(conversationDaoProvider);
      final mySnowId = _ref.read(currentSnowIdProvider);
      await conversationDao.findOrCreate(
        id: conversationId,
        type: 'direct',
        participantIds: [mySnowId ?? '', senderSnowchatId],
        title: senderSnowchatId,
      );
    } catch (e) {
      debugPrint('[ConversationList] Drift findOrCreate failed: $e');
    }
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

  /// Fetch the sender's display name from the server and update the
  /// conversation title. Also persists to drift — survives app restart so
  /// the VoIP outbound screen shows the nickname correctly (previously only
  /// in-memory was updated, so it regressed to a truncated snow ID after
  /// restart).
  Future<void> _resolveSenderDisplayName(
    String convId,
    String senderSnowchatId,
  ) async {
    try {
      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.get('/users/$senderSnowchatId');
      final data = res.data as Map?;
      final name = data?['displayName'] as String?;
      if (name != null && name.isNotEmpty) {
        if (mounted) {
          state = state.map((c) {
            if (c.id == convId) {
              return c.copyWith(title: name);
            }
            return c;
          }).toList();
        }
        // Persist to drift — restored as conversation.title on next boot.
        try {
          await _ref.read(conversationDaoProvider).updateTitle(convId, name);
        } catch (e) {
          debugPrint(
            '[ConversationList] Failed to persist resolved title for '
            '$convId: $e',
          );
        }
      }
    } catch (e) {
      debugPrint(
        '[ConversationList] Failed to resolve display name for '
        '$senderSnowchatId: $e',
      );
    }
  }
}

