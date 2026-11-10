/// @file        conversation_list_provider.dart
/// @description Conversation-list state-management Provider — server conversation-list fetch, add/remove conversations, last-message updates, pending group-invite management
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-10 (B-2 §5.7: IdentityBindingInvalidException / IdentityKeyChangedException handled as terminal — logged once, never retried). Earlier 2026-09-04 (sealed delete-chat: extracted the chat_deleted socket handler body into applyPeerChatDeletion(), now shared with MessageQueue.onPeerDeletedChat so the queued sealed control wipes the room + Signal session for a device that was offline when the peer deleted; idempotent for the online peer that gets both paths). Earlier 2026-08-12 (bug #34 residue: _ensureConversationInDrift now retypeToGroup()s on the proof that the id is a group (findOrCreate leaves an existing mis-typed 'direct' row untouched), and loadFromServer sets MessageQueue.groupsSynced=true right after the group retype+mirror pass so the 1:1 receive path stops treating unproven server-CUID rows as canonical during the cold-start window). Earlier 2026-08-06 (conversation-preview sync fixes: (BUG-A group live preview) wired MessageQueue.onGroupMessageDecoded to push the real decrypted group plaintext into the in-memory row (the wire listener only had a "[New message]" placeholder → "No messages yet" until restart), and loadFromServer's group branch now runs _backfillEmptyPreviews so reloads don't clobber it with the server's null snippet. (BUG-B unsend stale preview) added refreshPreviewAfterDelete() — recomputes the preview from localMessages and re-syncs drift + in-memory UNCONDITIONALLY (updatePreview's forward-only guard can't move the preview back to the older surviving message); wired to MessageQueue.onConversationPreviewStale (sealed unsend receiver) and called from the sender + group/non-sealed delete paths). Earlier 2026-08-05 (_backfillEmptyPreviews(): both _hydrateFromCache and loadFromServer now heal a null/empty last-message preview from localMessages via MessageDao.getLatestDisplayableMessage. The server never returns a 1:1 snippet (zero-knowledge) and outgoing messages persisted before the write-path fix left the denormalized drift `conversations` snippet empty, so an outgoing-last conversation showed "No messages yet"; hydrate-side heal also fixes pre-fix rows on upgrade). Earlier 2026-08-04 (GMK re-request is no longer gated by a once-per-session guard — a group whose name can't be decrypted re-requests the GMK on every loadFromServer (event-driven, self-limiting) so a receive-first member heals once a GMK holder is online, instead of staying nameless until app restart). Earlier 2026-08-03 (bug #34: _ensureConversationInDrift (the group-message listener's drift row creator) now creates a real type='group' row (groupId set, empty participants, group title) instead of a 1:1-shaped 'direct' row titled with the sender — that mis-typed row was indistinguishable from a 1:1 with the sender, so findDirectByParticipant routed 1:1 messages into it and dedupeDirectByPeer merged the receive-first 1:1 room onto it, fusing 1:1 + group transcripts on the receiver. loadFromServer now mirrors each server group to drift as type='group' AND heals pre-existing mis-typed rows via retypeToGroup, both BEFORE dedupeDirectByPeer (ordering is load-groups → retype → dedupe, else dedupe merges the still-'direct' group row into the 1:1 room), and collapses any duplicate group state entry by id). Earlier 2026-08-03 (F4(a): addConversation() now write-throughs a direct conversation into drift via ConversationDao.findOrCreate (new _mirrorDirectToDrift helper), not only into in-memory state. The optimistic open-chat insert previously left no drift row, so the Sealed Sender receive path's findDirectByParticipant found nothing and routed the first reply to a separate snow-id room = conversation split (prod "pullman"). Closes the same gap loadFromServer's findOrCreate already closes for server-loaded rows; _schedulePhantomHeal stays as the fallback). Earlier 2026-06-23 (sealed phantom heal: _schedulePhantomHeal() debounce-triggers refresh()+dedupeDirectByPeer when the live sealed-receive path creates a snow-id fallback direct row, so a new peer's first inbound message stops leaving a lingering phantom "CC"-style room + misrouted replies until app restart — field report 2026-06-23). Earlier 2026-06-19 (offline-first: _hydrateFromCache() loads the Drift cache into in-memory state on init so the Chats tab never shows "No conversations yet" while a network loadFromServer() is slow/failing; _listenForReconnect() retries loadFromServer on socket reconnect while !_serverLoaded; _loading in-flight guard. Fixes empty-chat-list-on-unstable-network field report 2026-06-17.). Earlier 2026-05-14 (loadFromServer drift sync now runs ConversationDao.dedupeDirectByPeer afterward to heal Sealed Sender phantom direct rows whose unread counts were stuck in watchTotalUnreadCount's SUM but invisible in the UI)
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
///  - _hydrateFromCache(): offline-first — load Drift-cached conversations into state on init
///  - _listenForReconnect(): retry loadFromServer on socket reconnect while !_serverLoaded
///  - _schedulePhantomHeal(): debounced refresh()+dedupe to merge live snow-id phantom direct rows in-session
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

import '../../../core/crypto/identity_binding_exception.dart';
import '../../../core/crypto/identity_key_changed_exception.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../channels/providers/channel_provider.dart' show myChannelsProvider;
// Phase 6: drift import is needed only for the drift-generated Conversation
// row type, aliased as `db` to avoid colliding with the in-memory model
// `Conversation` from models/conversation.dart.
import '../../../core/storage/database.dart' as db show Conversation;
import '../../../core/crypto/group_metadata_crypto.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/services/message_banner_service.dart';
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
  StreamSubscription<Map<String, dynamic>>? _channelMemberLeftSubscription;
  StreamSubscription<Map<String, dynamic>>? _groupUpdatedSubscription;
  StreamSubscription<Map<String, dynamic>>? _friendRequestSubscription;

  StreamSubscription<Map<String, dynamic>>? _gmkRequestSubscription;
  StreamSubscription<bool>? _connectionSub; // socket reconnect → reload guard
  bool _loading = false; // in-flight guard for loadFromServer (anti-hammer)
  Timer? _phantomHealTimer; // debounced heal for snow-id phantom direct rows

  ConversationListNotifier(this._ref) : super([]) {
    _listenForIncomingMessages();
    _listenForGroupEvents();
    _listenForFriendRequests();
    _listenForGmkRequests();
    _listenForChatDeleted();
    _listenForReconnect();
    // Offline-first: show locally-cached conversations immediately, before and
    // independent of the network loadFromServer(). Without this the list starts
    // empty and a slow/failed server fetch on an unstable network leaves the
    // Chats tab on "No conversations yet" until app restart (field report
    // 2026-06-17) — the UI watches this in-memory state, never the Drift stream.
    _hydrateFromCache();
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

    // Sealed Sender 1:1 — the live socket listener can't update unread /
    // preview because the wire-level envelope hides the sender. MessageQueue
    // fires this callback after unseal + drift insert so the in-memory
    // state mirrors what _listenForIncomingMessages does for non-sealed.
    _ref.read(messageQueueProvider).onSealedMessageDecoded =
        (convId, senderSnowId, preview, msgTime) {
      // Match only direct rows. Group conversations include the sender in
      // their member list (so participantIds.contains() would falsely match),
      // and a sealed 1:1 envelope must never bleed into a group row's
      // preview / unread badge.
      final idx = state.indexWhere((c) =>
          c.type == ConversationType.direct &&
          (c.id == convId || c.participantIds.contains(senderSnowId)));
      final isViewing = MarkReadHelper.isConversationActive(convId);
      if (idx < 0) {
        // First message in a brand-new conversation — surface it now.
        final mySnowId = _ref.read(currentSnowIdProvider) ?? '';
        debugPrint('[DIAG:ConvList] onSealedMessageDecoded: NEW conv $convId '
            'from $senderSnowId');
        final newConv = Conversation(
          id: convId,
          type: ConversationType.direct,
          participantIds: [mySnowId, senderSnowId],
          title: senderSnowId,
          lastMessageText: preview,
          lastMessageTime: msgTime,
          lastMessageSenderId: senderSnowId,
          unreadCount: isViewing ? 0 : 1,
          createdAt: DateTime.now(),
        );
        state = [newConv, ...state];
        _resolveSenderDisplayName(convId, senderSnowId);
        // If this row was created under the snow-id fallback (no canonical
        // server-CUID existed yet — see message_queue _processSealedMessage),
        // it's a phantom: the UI shows it as a separate room (field report
        // 2026-06-23 "CC" room) and its divergent convId can misroute the
        // user's replies. +294's dedupe runs only inside loadFromServer
        // (restart / reconnect), so without this the phantom lingers the whole
        // session. Heal in-session: pull the canonical CUID + dedupeDirectByPeer.
        if (convId.length == 36 && convId.startsWith('snow')) {
          _schedulePhantomHeal();
        }
        return;
      }
      final existing = state[idx];
      final updated = existing.copyWith(
        lastMessageText: preview,
        lastMessageTime: msgTime,
        lastMessageSenderId: senderSnowId,
        unreadCount:
            isViewing ? existing.unreadCount : existing.unreadCount + 1,
      );
      final newList = [...state];
      newList[idx] = updated;
      newList.sort((a, b) => (b.lastMessageTime ?? b.createdAt)
          .compareTo(a.lastMessageTime ?? a.createdAt));
      state = newList;
      debugPrint('[DIAG:ConvList] onSealedMessageDecoded: $convId '
          'unread=${updated.unreadCount} viewing=$isViewing');
    };

    // Push the real decrypted GROUP plaintext into the in-memory preview.
    // The live onGroupMessage socket listener only sees a null wire text (E2EE)
    // and writes a "[New message]" placeholder; drift is correct but the
    // in-memory Chats row stayed a placeholder / "No messages yet" until an app
    // restart re-hydrated from drift. This is the receiver-side live sync
    // (mirrors onSealedMessageDecoded for 1:1). Preview only — unread is already
    // maintained by the onGroupMessage listener + drift, so re-incrementing here
    // would double-count.
    _ref.read(messageQueueProvider).onGroupMessageDecoded =
        (groupId, senderSnowId, preview, msgTime) {
      final idx = state.indexWhere(
          (c) => c.id == groupId || c.groupId == groupId);
      if (idx < 0) return; // not in state yet; loadFromServer backfills it
      // Unconditional overwrite — MessageQueue processes group messages
      // serially in arrival order, so the latest decoded call reflects the
      // newest message, and this callback fires AFTER the onGroupMessage socket
      // listener's "[New message]" placeholder (the queue decode is async). A
      // forward-only time guard would be wrong here: the placeholder listener
      // stamps the server timestamp while we stamp the local receive time, and
      // any clock skew between them would spuriously block the real plaintext.
      final newList = [...state];
      newList[idx] = state[idx].copyWith(
        lastMessageText: preview,
        lastMessageTime: msgTime,
        lastMessageSenderId: senderSnowId,
      );
      newList.sort((a, b) => (b.lastMessageTime ?? b.createdAt)
          .compareTo(a.lastMessageTime ?? a.createdAt));
      state = newList;
    };

    // After a sealed 1:1 unsend physically removes rows, recompute the affected
    // conversation's preview from the durable store (the queue has no
    // conversationList ref, so it signals via this callback).
    _ref.read(messageQueueProvider).onConversationPreviewStale = (convId) {
      refreshPreviewAfterDelete(convId);
    };

    // Phase 8.8: Wire GMK received callback to update specific group name
    // Queued sealed delete-chat control — the offline-durable half of the
    // peer-deleted-this-chat path (the live socket event only reaches a peer
    // who is connected at that moment).
    _ref.read(messageQueueProvider).onPeerDeletedChat =
        (peerSnowId, roomId) async {
      // Drift + Signal session were already wiped by MessageQueue (it must not
      // depend on this callback being wired yet). Only in-memory state left.
      debugPrint('[ConversationList] sealed delete_chat from $peerSnowId '
          '(room=$roomId)');
      removeConversation(roomId);
    };

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
    _channelMemberLeftSubscription?.cancel();
    _groupUpdatedSubscription?.cancel();
    _friendRequestSubscription?.cancel();
    _gmkRequestSubscription?.cancel();
    _connectionSub?.cancel();
    _phantomHealTimer?.cancel();
    super.dispose();
  }

  /// Offline-first hydrate: populate the in-memory list from the local Drift
  /// cache so the Chats tab shows existing conversations immediately, before
  /// (and independent of) the network loadFromServer(). Merge-by-id so it never
  /// clobbers anything a racing loadFromServer() may already have set. Fixes the
  /// "No conversations yet" empty screen on unstable networks (field report
  /// 2026-06-17): the UI renders this in-memory state, never the Drift stream,
  /// so a slow/failed server fetch otherwise showed empty until app restart.
  /// Backfill a null/empty last-message preview from the true message source
  /// (localMessages via MessageDao.getLatestDisplayableMessage). A conversation
  /// snippet can be empty because (a) the server never returns a 1:1 snippet
  /// (zero-knowledge) and (b) outgoing messages persisted before the write path
  /// started refreshing the drift snippet (MessageRepository.persistOutgoingMessage)
  /// left the denormalized `conversations` cache empty. Without this such a
  /// conversation renders as "No messages yet" even though it has messages.
  /// Mutates [conversations] in place (index-replace via copyWith); a no-op for
  /// entries that already have a preview. Safe to call from any load path.
  Future<void> _backfillEmptyPreviews(List<Conversation> conversations) async {
    final messageDao = _ref.read(messageDaoProvider);
    for (var i = 0; i < conversations.length; i++) {
      final conv = conversations[i];
      if (conv.lastMessageText != null && conv.lastMessageText!.isNotEmpty) {
        continue;
      }
      final latest = await messageDao.getLatestDisplayableMessage(conv.id);
      if (latest == null || latest.plaintext.isEmpty) continue;
      conversations[i] = conv.copyWith(
        lastMessageText: latest.plaintext,
        lastMessageTime:
            DateTime.fromMillisecondsSinceEpoch(latest.dateReceived),
        lastMessageSenderId: latest.senderSnowchatId,
      );
    }
  }

  /// Recompute a conversation's last-message preview from the durable message
  /// store after a message was deleted / unsent (delete-for-everyone), and
  /// re-sync BOTH the drift `conversations` snippet and the in-memory state.
  ///
  /// Unlike [updatePreview] this moves the preview BACKWARD — the surviving
  /// newest message is older than the just-deleted one — so it writes
  /// UNCONDITIONALLY (updatePreview's forward-only timestamp guard would reject
  /// it and leave the deleted message's text lingering). Clears the text when
  /// nothing displayable remains. Called from every delete site (sender
  /// delete-for-me/everyone, sealed 1:1 unsend receiver, group/non-sealed
  /// delete receiver) so an unsent last message never stays in the Chats list.
  Future<void> refreshPreviewAfterDelete(String conversationId) async {
    try {
      final messageDao = _ref.read(messageDaoProvider);
      final convDao = _ref.read(conversationDaoProvider);
      final latest =
          await messageDao.getLatestDisplayableMessage(conversationId);

      final idx = state.indexWhere(
          (c) => c.id == conversationId || c.groupId == conversationId);

      // 1. Durable drift snippet. On clear, keep the row's existing time so the
      //    conversation doesn't jump position; set empty text.
      final existingTime = (idx >= 0)
          ? state[idx].lastMessageTime?.millisecondsSinceEpoch
          : null;
      await convDao.updateLastMessage(
        conversationId: conversationId,
        text: latest?.plaintext ?? '',
        senderId: latest?.senderSnowchatId ?? '',
        timestamp: latest?.dateReceived ??
            existingTime ??
            DateTime.now().millisecondsSinceEpoch,
        messageId: latest?.id,
      );

      // 2. In-memory state — unconditional (see doc comment).
      if (idx < 0) return;
      final newList = [...state];
      if (latest != null) {
        newList[idx] = state[idx].copyWith(
          lastMessageText: latest.plaintext,
          lastMessageTime:
              DateTime.fromMillisecondsSinceEpoch(latest.dateReceived),
          lastMessageSenderId: latest.senderSnowchatId,
        );
      } else {
        // Nothing left to preview — clear the text, keep position/time.
        newList[idx] = state[idx].copyWith(lastMessageText: '');
      }
      state = newList;
    } catch (e) {
      debugPrint('[ConversationList] refreshPreviewAfterDelete failed: $e');
    }
  }

  Future<void> _hydrateFromCache() async {
    try {
      final conversationDao = _ref.read(conversationDaoProvider);
      final messageDao = _ref.read(messageDaoProvider);
      final driftRows = await conversationDao.getAllConversations();
      final knownIds = state.map((c) => c.id).toSet();
      final cached = <Conversation>[];
      for (final row in driftRows) {
        if (!row.isActive) continue;
        if (knownIds.contains(row.id)) continue;
        final unread = await messageDao.getUnreadCount(row.id);
        cached.add(Conversation(
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
      if (cached.isEmpty) return;
      // Heal empty previews (outgoing-last rows whose snippet was never
      // persisted before the write-path fix) from the true message source so
      // the Chats list doesn't show "No messages yet" for a chat that has
      // messages. Runs before the mounted re-check below (which guards the
      // post-await `state =`).
      await _backfillEmptyPreviews(cached);
      // Re-check against the CURRENT state at merge time: a racing
      // loadFromServer() may have populated state during our getUnreadCount
      // awaits. Only add cache rows still absent so the race can't dupe.
      final currentIds = state.map((c) => c.id).toSet();
      final fresh = cached.where((c) => !currentIds.contains(c.id)).toList();
      // !mounted: the notifier may have been disposed during the awaits above
      // (getAllConversations / getUnreadCount); `state =` after dispose throws.
      // No await between here and the assignment, so one check suffices.
      if (fresh.isEmpty || !mounted) return;
      final merged = [...fresh, ...state]..sort((a, b) =>
          (b.lastMessageTime ?? b.createdAt)
              .compareTo(a.lastMessageTime ?? a.createdAt));
      state = merged;
      debugPrint('[ConversationList] hydrated ${fresh.length} '
          'conversation(s) from drift cache (offline-first)');
    } catch (e) {
      debugPrint('[ConversationList] cache hydrate failed (non-fatal): $e');
    }
  }

  /// Re-trigger the conversation-list load when the socket reconnects, but ONLY
  /// if a successful server load never happened (`!_serverLoaded`). Recovers the
  /// case where the cold-start load failed on an unstable network: instead of
  /// staying empty until app restart, the list reloads automatically once the
  /// network returns. Guarded so a flapping connection can't hammer the server
  /// or replace a live, already-loaded list (new conversations after a good load
  /// arrive via fetchPending → onSealedMessageDecoded). loadFromServer()'s
  /// _loading guard additionally prevents overlapping reloads.
  void _listenForReconnect() {
    _connectionSub = _ref
        .read(socketManagerProvider)
        .onConnectionChange
        .listen((connected) {
      // Opportunistic retry only: a successful load never happened, none is
      // in-flight, we're still logged in (no post-logout 401 loop), and the
      // notifier is still alive (no state-after-dispose). Once _serverLoaded
      // is true this never fires again — new data then arrives via the live
      // message/group listeners, not a full reload (anti-hammer on flapping).
      if (connected &&
          mounted &&
          !_serverLoaded &&
          !_loading &&
          _ref.read(authTokenProvider) != null) {
        debugPrint('[ConversationList] socket reconnected & not yet loaded — '
            'retrying loadFromServer()');
        loadFromServer();
      }
    });
  }

  /// Load conversations from the server API.
  /// Falls back to mock data on failure.
  Future<void> loadFromServer() async {
    if (_serverLoaded) return;
    // NOTE: _loading is tracked (so the reconnect listener can anti-hammer)
    // but is intentionally NOT part of this guard. Explicit reloads — group
    // member added / invite / GMK / pull-to-refresh, which all do
    // `_serverLoaded = false; loadFromServer()` — must run even while an
    // opportunistic (startup/reconnect) load is in-flight, otherwise a freshly
    // created group could be dropped until the next trigger.
    _loading = true;

    try {
      final apiClient = _ref.read(apiClientProvider);
      final convDao = _ref.read(conversationDaoProvider);

      // Metadata-min Batch 2 (2026-08-07): the server no longer stores 1:1 pairs
      // (Conversation table dropped), so GET /conversations is retired. The 1:1
      // list is rebuilt from the local drift cache — the same source
      // _hydrateFromCache uses, kept current by the receive path (findOrCreate)
      // + outgoing sends. New 1:1 rooms still arrive live via the message
      // listeners and the _drainPendingMessages() drain below (which
      // findOrCreates a room for every message that landed while offline). This
      // is the offline-first list the design (+298) already moved toward — the
      // server can no longer enumerate who-chats-with-whom.
      final driftRows = await convDao.getAllConversations();
      final serverConversations = <Conversation>[]; // direct rows only
      for (final row in driftRows) {
        if (!row.isActive) continue;
        if (row.type == 'group' || row.groupId != null) continue; // groups load below
        serverConversations.add(Conversation(
          id: row.id,
          type: ConversationType.direct,
          participantIds: _decodeParticipants(row.participantIds),
          title: row.title,
          lastMessageText: row.lastMessageText,
          lastMessageTime: row.lastMessageTime != null
              ? DateTime.fromMillisecondsSinceEpoch(row.lastMessageTime!)
              : null,
          lastMessageSenderId: row.lastMessageSenderId,
          // unreadCount populated by _drainPendingMessages from local DB
          createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        ));
      }

      // Filter out locally-deleted (tombstoned) conversations (belt-and-
      // suspenders — deleteChat already removes the drift row; this catches a
      // failed local cleanup or a race).
      final deletedIds = await _loadDeletedConvIds();
      if (deletedIds.isNotEmpty) {
        serverConversations.removeWhere((c) => deletedIds.contains(c.id));
      }

      // Heal empty previews (outgoing-last rows whose snippet predates the
      // write-path fix) from the true message source.
      await _backfillEmptyPreviews(serverConversations);

      state = serverConversations;
      _serverLoaded = true;
      debugPrint(
          '[ConversationList] Loaded ${serverConversations.length} '
          'direct conversation(s) from drift (server pair-list retired)');

      // Load group conversations. This runs BEFORE dedupeDirectByPeer below so
      // that any group whose local row was mis-created as type='direct' (bug
      // #34: the group-message listener's findOrCreate hardcoded 'direct') is
      // retyped to a real group here first. If dedupe ran first, that still-
      // 'direct' group row would be bucketed with the receive-first 1:1 room
      // for the same peer and MERGED — migrating the group's messages into the
      // 1:1 room and deleting the group row. Order is load-groups → retype →
      // dedupe.
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
            } else {
              // GMK missing — re-request on EVERY load, not once per session. A
              // receive-first member's first GMK can fail to decrypt and be
              // dropped, and a GMK holder may have been offline at the previous
              // request; re-requesting each loadFromServer (an event-driven,
              // non-looping refresh: launch / reconnect / manual) heals it once a
              // holder is online + the session exists. Stops as soon as the GMK
              // arrives (gmk != null above) — self-limiting, no request storm
              // (the loop requests each group at most once per load).
              debugPrint('[ConversationList] GMK missing for $groupId — requesting');
              _ref.read(socketManagerProvider).requestGmk(groupId);
            }
          }
          // Fallback: use server 'name' field for pre-Phase 8.8 groups
          groupTitle ??= group['name'] as String?;
          // The server can't return E2EE group plaintext, so its lastMessage
          // text is null. Fall back to the drift conversation row's
          // denormalized snippet (kept current by insertIncoming/insertOutgoing
          // + refreshPreviewAfterDelete) so a reload doesn't blank the preview
          // back to "No messages yet".
          String? previewText =
              (group['lastMessage'] as Map?)?['text'] as String?;
          DateTime? previewTime =
              (group['lastMessage'] as Map?)?['timestamp'] != null
                  ? DateTime.parse(
                      (group['lastMessage'] as Map)['timestamp'] as String)
                  : null;
          if (previewText == null || previewText.isEmpty) {
            // getConversation returns the drift row (last_message_time is an
            // epoch-ms int here, not a DateTime).
            final driftConv = await convDao.getConversation(groupId);
            final driftText = driftConv?.lastMessageText;
            if (driftText != null && driftText.isNotEmpty) {
              previewText = driftText;
              final driftMs = driftConv?.lastMessageTime;
              if (driftMs != null) {
                previewTime = DateTime.fromMillisecondsSinceEpoch(driftMs);
              }
            }
          }
          return Conversation(
            id: group['id'] as String,
            type: ConversationType.group,
            groupId: group['id'] as String,
            channelId: group['channelId'] as String?,
            title: groupTitle,
            participantIds: [],
            lastMessageText: previewText,
            lastMessageTime: previewTime,
            createdAt: DateTime.parse(group['createdAt'] as String),
          );
        }));

        // Persist each server group to drift as a real group row so it exists
        // as type='group' before any message arrives, and heal any pre-existing
        // row mis-created under this group id as type='direct' (bug #34).
        // retype BEFORE the dedupe pass below; matching is by exact group id.
        for (final g in serverGroups) {
          try {
            await convDao.retypeToGroup(id: g.id, title: g.title);
            await convDao.findOrCreate(
              id: g.id,
              type: 'group',
              groupId: g.id,
              participantIds: const [],
              title: g.title,
            );
          } catch (e) {
            debugPrint('[ConversationList] group drift sync failed for '
                '${g.id}: $e');
          }
        }

        // The authoritative group-id set is now known and every mis-typed row
        // under it has been retyped, so a server-CUID direct row can no longer
        // be a disguised group room. Open the receive path's cold-start guard
        // (ConversationDao.findDirectByParticipant / MessageQueue.groupsSynced).
        // Set unconditionally once the group fetch succeeds — a member of zero
        // groups still has a fully-known (empty) group set.
        _ref.read(messageQueueProvider).groupsSynced = true;

        // Backfill each group's last-message preview from localMessages — the
        // server can't return E2EE group plaintext (null snippet), so without
        // this a reload would clobber the live/decoded preview back to
        // "No messages yet". Mirrors the 1:1 serverConversations backfill.
        await _backfillEmptyPreviews(serverGroups);

        // Replace any pre-existing state entry sharing a group id (e.g. a
        // cache-hydrated phantom of the mis-typed direct row) with the
        // authoritative group entry — collapses the duplicate group row.
        final groupIds = serverGroups.map((g) => g.id).toSet();
        state = [
          ...state.where((c) => !groupIds.contains(c.id)),
          ...serverGroups,
        ];
        debugPrint(
            '[ConversationList] Loaded ${serverGroups.length} groups from server');
      } catch (e) {
        debugPrint('[ConversationList] Failed to load groups: $e');
      }

      // Dedupe phantom direct rows accumulated from Sealed Sender's foreign-
      // convId fallback. The just-confirmed server-CUID set is the canonical
      // preference; any other direct row pointing at the same peer is folded
      // into it (messages migrated, unread summed, dup row deleted). Heals
      // the badge-stuck regression where unread sat on a row the UI didn't
      // surface (loadFromServer replaces in-memory state with the server
      // list, hiding the phantom — but its unread still counted toward
      // watchTotalUnreadCount's SUM).
      //
      // MUST run after the group retype above: a mis-typed 'direct' group row
      // would otherwise be merged into the peer's 1:1 room (bug #34).
      try {
        final canonicalIds =
            serverConversations.map((c) => c.id).toSet();
        final mySnow = _ref.read(currentSnowIdProvider) ?? '';
        if (mySnow.isNotEmpty) {
          final merged = await convDao.dedupeDirectByPeer(
            mySnowId: mySnow,
            canonicalIds: canonicalIds,
          );
          if (merged > 0) {
            debugPrint(
                '[ConversationList] dedupe merged $merged dup direct row(s)');
          }
        }
      } catch (e) {
        debugPrint('[ConversationList] dedupe failed (non-fatal): $e');
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
      // Keep current state as fallback — the Drift cache hydrated at startup
      // (and re-attempted on each reconnect while !_serverLoaded) stays visible;
      // we never clear it here, so a transient failure no longer shows empty.
    } finally {
      _loading = false;
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

  /// Debounced reconciliation for snow-id phantom direct rows created on the
  /// live sealed-receive path (a brand-new peer's first inbound sealed message,
  /// before any canonical server-CUID row exists). refresh() re-pulls the
  /// canonical CUID and dedupeDirectByPeer() merges the phantom into it
  /// (migrating its messages + unread), so the phantom "CC"-style room heals in
  /// seconds instead of lingering until app restart, and replies stop being
  /// stranded under the divergent convId. Debounced so a burst of sealed
  /// messages triggers a single heal.
  void _schedulePhantomHeal() {
    _phantomHealTimer?.cancel();
    _phantomHealTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      debugPrint('[ConversationList] healing snow-id phantom row(s) — '
          'refresh() → canonical server-CUID + dedupeDirectByPeer');
      refresh();
    });
  }

  /// Clear pending invites after they have been shown to the user.
  void clearPendingInvites() {
    _pendingInvites = [];
  }

  void addConversation(Conversation conversation) {
    state = [conversation, ...state];
    // F4(a) (2026-08-03): mirror a direct conversation into drift the moment it
    // is optimistically opened — not only when loadFromServer later syncs it.
    // ConversationDao.findDirectByParticipant is the row the Sealed Sender
    // receive path (message_queue._processSealedMessage) resolves against to
    // route an inbound reply. An in-memory-only optimistic insert leaves no
    // drift row, so the first reply to a brand-new 1:1 falls back to a separate
    // snow-id room (the conversation split reproduced in production as
    // "pullman"). This closes the same gap loadFromServer's own findOrCreate
    // already closes for server-loaded rows. Fire-and-forget: the write is local
    // SQLite and completes long before any network reply arrives; on failure
    // loadFromServer mirrors it on the next sync. Group rooms route by groupId,
    // not this table.
    if (conversation.type == ConversationType.direct) {
      unawaited(_mirrorDirectToDrift(conversation));
    }
  }

  /// Write-through a direct conversation into the drift `conversations` table so
  /// ConversationDao.findDirectByParticipant can discover it immediately. See
  /// addConversation() for why this must not wait for loadFromServer.
  Future<void> _mirrorDirectToDrift(Conversation conversation) async {
    try {
      final convDao = _ref.read(conversationDaoProvider);
      await convDao.findOrCreate(
        id: conversation.id,
        type: 'direct',
        participantIds: conversation.participantIds,
        title: conversation.title,
      );
    } catch (e) {
      debugPrint('[ConversationList] addConversation drift mirror failed for '
          '${conversation.id}: $e');
    }
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
  ///
  /// 2026-05-04 fix: 1:1 인 경우 Signal SessionStore 도 함께 wipe — peer 가
  /// 채팅 삭제했다는 건 곧 본인 쪽에서도 fresh start 원한다는 의미이고,
  /// session 남기면 이후 같은 peer 와 메시지 주고받을 때 stale ratchet 으로
  /// session_reset 무한 loop 발생 (deleteConversationLocally 의 동일 fix
  /// 와 mirror).
  void _listenForChatDeleted() {
    final sm = _ref.read(socketManagerProvider);
    sm.onChatDeleted.listen((data) async {
      // 1:1: data['conversationId'] is the DELETER's snowchatId (metadata-min
      // Batch 2 — 1:1 rooms are peer-keyed, so from this side the deleter's
      // snow-id IS the peer). Group: data['groupChatId'].
      final rawId = (data['conversationId'] ?? data['groupChatId']) as String?;
      if (rawId == null) return;
      debugPrint('[ConversationList] chat/group deleted received: $rawId');
      await applyPeerChatDeletion(rawId, isGroup: data['groupChatId'] != null);
    });
  }

  /// Wipe this device's copy of a room the OTHER side deleted.
  ///
  /// One body, two callers:
  ///  - the live `chat_deleted` socket event (peer connected at delete time);
  ///  - MessageQueue.onPeerDeletedChat, fed by the QUEUED sealed delete-chat
  ///    control. That second path is what reaches a device that was offline
  ///    when the peer deleted: the socket event is emitted only to currently
  ///    connected sockets and is never queued, so the delete used to be lost
  ///    outright and the room survived (field-confirmed on real devices,
  ///    2026-09-04).
  ///
  /// Idempotent — an online peer gets both paths and the second is a no-op.
  ///
  /// 2026-05-04: for 1:1 the Signal SessionStore is wiped too. The peer
  /// deleting the chat means both sides want a fresh start; keeping the session
  /// makes the next exchange ratchet against stale state and spin the
  /// session_reset loop (mirrors deleteConversationLocally's fix).
  Future<void> applyPeerChatDeletion(String rawId, {bool isGroup = false}) async {
    final convDao = _ref.read(conversationDaoProvider);

    // Resolve the LOCAL room id. A snow-id-keyed 1:1 room (or a group keyed by
    // groupChatId) matches rawId directly. A LEGACY CUID-keyed 1:1 room does
    // NOT — resolve it by the peer (rawId = deleter's snowchatId) via
    // findDirectByParticipant, else the peer's local copy survives the delete
    // and the "the other person also loses this conversation" promise breaks.
    String roomId = rawId;
    if (!isGroup) {
      try {
        if (await convDao.getConversation(rawId) == null) {
          final direct = await convDao.findDirectByParticipant(rawId);
          if (direct != null) roomId = direct.id;
        }
      } catch (e) {
        debugPrint('[ConversationList] chat_deleted room resolve failed: $e');
      }
    }

    // 1:1: the deleter's snow-id (rawId) IS the peer — wipe that Signal session
    // so the next contact bootstraps a fresh X3DH instead of a stale ratchet.
    final peerSnowIdToWipe = isGroup ? null : rawId;

    // Remove from drift DB (messages + conversation row)
    try {
      await convDao.deleteConversation(roomId);
    } catch (e) {
      debugPrint('[ConversationList] chat_deleted drift cleanup failed: $e');
    }

    if (peerSnowIdToWipe != null) {
      try {
        final sessionMgr = _ref.read(signalSessionManagerProvider);
        await sessionMgr.deleteSessionForPeer(peerSnowIdToWipe);
      } catch (e) {
        debugPrint('[ConversationList] chat_deleted signal session wipe '
            'for $peerSnowIdToWipe failed: $e');
      }
    }

    // Remove from in-memory state
    removeConversation(roomId);
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
  /// 2026-04-28: also fire MessageBannerService for in-app foreground toast
  /// (Friends 탭 외 화면에서도 즉시 알림).
  void _listenForFriendRequests() {
    final sm = _ref.read(socketManagerProvider);
    _friendRequestSubscription = sm.onFriendRequestReceived.listen((data) {
      final current = _ref.read(pendingFriendBadgeProvider);
      _ref.read(pendingFriendBadgeProvider.notifier).state = current + 1;

      final fromSnowchatId = data['fromSnowchatId'] as String? ?? '';
      final fromDisplayName = data['fromDisplayName'] as String? ?? '';
      if (fromSnowchatId.isNotEmpty) {
        MessageBannerService.instance.showFriendRequest(
          fromSnowchatId: fromSnowchatId,
          fromDisplayName: fromDisplayName,
        );
      }
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
      } on IdentityBindingInvalidException catch (idErr) {
        // B-2 §5.7: forged / downgraded / replayed identity — terminal,
        // never retried (the store already raised the security notice).
        debugPrint('[GMK] request_gmk response: identity rejected (${idErr.reason.name}) — terminal');
      } on IdentityKeyChangedException {
        // B-2 §5.5: verified contact awaits re-verification — terminal.
        debugPrint('[GMK] request_gmk response: peer awaits identity re-verification — terminal');
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

      final msgTime = data['serverTimestamp'] != null
          ? DateTime.parse(data['serverTimestamp'] as String)
          : (data['createdAt'] != null
              ? DateTime.parse(data['createdAt'] as String)
              : DateTime.now());

      // Ensure the GROUP conversation exists in drift DB so it shows in list.
      // state[idx] is the known group (matched above) — carry its title so the
      // drift row is a real group, never a 1:1-shaped 'direct' row (bug #34).
      _ensureConversationInDrift(
        conversationId: msgGroupId,
        groupTitle: state[idx].title,
      );

      // Do NOT write a preview here. The server can't supply E2EE group
      // plaintext (data['text'] is null), and a "[New message]" placeholder
      // would clobber the real text — worse, on a re-delivered message the
      // MessageQueue dedupes the duplicate so onGroupMessageDecoded never fires
      // to replace it, leaving the placeholder permanently. The real preview
      // comes from onGroupMessageDecoded (live, post-decrypt) or the drift
      // snippet (hydrate/reload). Here we only bump time + unread.
      final updated = state[idx].copyWith(
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

    // Community kick (real-time). The server directly notifies the KICKED user
    // with youWereRemoved:true (its member-broadcast can't reach a just-deleted
    // member). Drop the community from our lists at once — BOTH the Community tab
    // and the Chats-tab community rows render from myChannelsProvider, a
    // non-autoDispose FutureProvider that will not refetch on its own, so it must
    // be invalidated. (Remaining members instead get the per-room
    // group_member_removed above, which evicts the kicked user from their local
    // Sender-Key membership.) Pop-out-of-room + the notice happen in chat_screen,
    // which has a BuildContext this notifier lacks.
    _channelMemberLeftSubscription = sm.onChannelMemberLeft.listen((data) {
      final youWereRemoved = data['youWereRemoved'] as bool? ?? false;
      final channelId = data['channelId'] as String?;
      if (!youWereRemoved || channelId == null) return;
      debugPrint('[ConversationList] Kicked from community $channelId '
          '— invalidating myChannelsProvider');
      _ref.invalidate(myChannelsProvider);
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
        final existing = state[existingIndex];
        // Never let this 1:1 (private_message) listener clobber a GROUP row's
        // preview with a "[New message]" placeholder — groups own their preview
        // via onGroupMessage (unread/time) + onGroupMessageDecoded (real
        // plaintext) + the drift snippet. A group message's pairwise fallback
        // can arrive here and match the group entry; without this guard it
        // overwrites the real decoded text with the placeholder (and on a
        // re-delivered duplicate the decode is deduped, so it never recovers).
        if (existing.type == ConversationType.group ||
            existing.groupId != null) {
          debugPrint('[DIAG:ConvList] $id SKIP group preview clobber '
              '$serverConvId');
          return;
        }
        debugPrint('[DIAG:ConvList] $id UPDATE existing conv $serverConvId');
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

  /// Ensure a GROUP conversation exists in drift DB for incoming group messages.
  /// Message INSERT + unreadCount is handled by MessageRepository (single source).
  /// This only ensures the conversation record exists.
  ///
  /// This is called ONLY from the group-message listener ([conversationId] is
  /// always a group id). It MUST create a `type='group'` row (groupId set,
  /// participants empty) — matching the group-row shape at
  /// message_queue.dart _insertDecryptionFailedPlaceholder. Creating it as
  /// 'direct' with the sender as peer made it indistinguishable from a 1:1 with
  /// the sender, so findDirectByParticipant routed 1:1 messages into it and
  /// dedupeDirectByPeer merged the receive-first 1:1 room onto it — fusing the
  /// two transcripts (bug #34).
  Future<void> _ensureConversationInDrift({
    required String conversationId,
    String? groupTitle,
  }) async {
    try {
      final conversationDao = _ref.read(conversationDaoProvider);
      // Receiving a group message is proof that conversationId is a group.
      // findOrCreate returns an existing row untouched, so a pre-302 mis-typed
      // 'direct' row would survive here and keep routing the sender's 1:1
      // messages into this room until loadFromServer's heal runs. Retype on
      // the proof instead of waiting for the network pass (bug #34 residue).
      await conversationDao.retypeToGroup(id: conversationId, title: groupTitle);
      await conversationDao.findOrCreate(
        id: conversationId,
        type: 'group',
        groupId: conversationId,
        participantIds: const [],
        title: groupTitle,
      );
    } catch (e) {
      debugPrint('[ConversationList] Drift group findOrCreate failed: $e');
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

