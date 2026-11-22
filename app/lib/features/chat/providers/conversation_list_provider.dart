/// @file        conversation_list_provider.dart
/// @description Conversation-list state-management Provider — the list is rebuilt from drift (1:1 rooms keyed by the peer's snowId, group protocol v2 groups), add/remove conversations, last-message updates
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-23 (no account, conversation or community id in a log line — logRef). Earlier 2026-11-22 (no account or conversation id in a log line — logRef; a pending chat
///              deletion the server answers with 404 USER_NOT_FOUND — the peer is gone — or 400 —
///              it will never take it — is settled instead of tried on every start). Earlier 2026-11-22 (friend graph off the server: a 1:1 peer's name comes from this device —
///              its contact row or its verified name certificate (NameCertService) — never from
///              GET /users/:sender, which told the server who had just written; the list follows a
///              name a certificate changes (onNameChanged); no friend_request_received listener (a
///              request is a sealed contact notice); no live non-sealed socket listener (every 1:1
///              envelope is sealed — onSealedMessageDecoded covers the list); a tombstoned deletion
///              is retried with POST /conversations/delete). Earlier 2026-11-21 (P5.6: a sync of a v2 group's row that a removal or a later sync overtook applies nothing — it put a removed chat back). Earlier 2026-11-21 (a peer's deletion of a 1:1 comes only from the sealed delete_chat control (no socket chat_deleted); onPeerDeletedChat tells an open chat; removeConversation is a no-op after dispose). Earlier 2026-11-20 (v1 groups removed: no server group list, no pending v1 invites, no
///              GMK answers, no Sender Key pre-broadcast or rotation, no mis-typed-row heal
///              or phantom dedupe — a 1:1 room is keyed by the peer's snowId, so the live
///              listener matches the sender's room by id, never a conversation the server
///              names; community kicks still refresh the community list). Earlier: group protocol v2: a v2 group's row is rebuilt from drift like a 1:1
///              room — it is not on the server's group list — follows the group through
///              syncGv2Group(), and is left out of the v1 Sender Key pre-broadcast).
///              Earlier 2026-11-12 (group names resolved through GroupMetadataCrypto.resolveGroupName
///              — a received GMK is a candidate verified against the server-held
///              encryptedName; a stale key now re-requests the GMK too; a new candidate
///              is verified locally against the cached encryptedName, never by a
///              reload; unnamed groups are re-resolved after a load assigns them).
///              Earlier 2026-11-11 (auto-translate setting no longer reset on launch/reconnect:
///              loadFromServer replaced state with direct rows copied without the
///              auto-translate fields, and group rows built from the server never read
///              them. All drift-row rebuilds now go through conversationFromDriftRow();
///              groups take the fields from their drift row). Earlier 2026-11-10 (B-2 §5.7: IdentityBindingInvalidException / IdentityKeyChangedException handled as terminal — logged once, never retried). Earlier 2026-09-04 (sealed delete-chat: extracted the chat_deleted socket handler body into applyPeerChatDeletion(), now shared with MessageQueue.onPeerDeletedChat so the queued sealed control wipes the room + Signal session for a device that was offline when the peer deleted; idempotent for the online peer that gets both paths). Earlier 2026-08-12 (bug #34 residue: _ensureConversationInDrift now retypeToGroup()s on the proof that the id is a group (findOrCreate leaves an existing mis-typed 'direct' row untouched), and loadFromServer sets MessageQueue.groupsSynced=true right after the group retype+mirror pass so the 1:1 receive path stops treating unproven server-CUID rows as canonical during the cold-start window). Earlier 2026-08-06 (conversation-preview sync fixes: (BUG-A group live preview) wired MessageQueue.onGroupMessageDecoded to push the real decrypted group plaintext into the in-memory row (the wire listener only had a "[New message]" placeholder → "No messages yet" until restart), and loadFromServer's group branch now runs _backfillEmptyPreviews so reloads don't clobber it with the server's null snippet. (BUG-B unsend stale preview) added refreshPreviewAfterDelete() — recomputes the preview from localMessages and re-syncs drift + in-memory UNCONDITIONALLY (updatePreview's forward-only guard can't move the preview back to the older surviving message); wired to MessageQueue.onConversationPreviewStale (sealed unsend receiver) and called from the sender + group/non-sealed delete paths). Earlier 2026-08-05 (_backfillEmptyPreviews(): both _hydrateFromCache and loadFromServer now heal a null/empty last-message preview from localMessages via MessageDao.getLatestDisplayableMessage. The server never returns a 1:1 snippet (zero-knowledge) and outgoing messages persisted before the write-path fix left the denormalized drift `conversations` snippet empty, so an outgoing-last conversation showed "No messages yet"; hydrate-side heal also fixes pre-fix rows on upgrade). Earlier 2026-08-04 (GMK re-request is no longer gated by a once-per-session guard — a group whose name can't be decrypted re-requests the GMK on every loadFromServer (event-driven, self-limiting) so a receive-first member heals once a GMK holder is online, instead of staying nameless until app restart). Earlier 2026-08-03 (bug #34: _ensureConversationInDrift (the group-message listener's drift row creator) now creates a real type='group' row (groupId set, empty participants, group title) instead of a 1:1-shaped 'direct' row titled with the sender — that mis-typed row was indistinguishable from a 1:1 with the sender, so findDirectByParticipant routed 1:1 messages into it and dedupeDirectByPeer merged the receive-first 1:1 room onto it, fusing 1:1 + group transcripts on the receiver. loadFromServer now mirrors each server group to drift as type='group' AND heals pre-existing mis-typed rows via retypeToGroup, both BEFORE dedupeDirectByPeer (ordering is load-groups → retype → dedupe, else dedupe merges the still-'direct' group row into the 1:1 room), and collapses any duplicate group state entry by id). Earlier 2026-08-03 (F4(a): addConversation() now write-throughs a direct conversation into drift via ConversationDao.findOrCreate (new _mirrorDirectToDrift helper), not only into in-memory state. The optimistic open-chat insert previously left no drift row, so the Sealed Sender receive path's findDirectByParticipant found nothing and routed the first reply to a separate snow-id room = conversation split (prod "pullman"). Closes the same gap loadFromServer's findOrCreate already closes for server-loaded rows; _schedulePhantomHeal stays as the fallback). Earlier 2026-06-23 (sealed phantom heal: _schedulePhantomHeal() debounce-triggers refresh()+dedupeDirectByPeer when the live sealed-receive path creates a snow-id fallback direct row, so a new peer's first inbound message stops leaving a lingering phantom "CC"-style room + misrouted replies until app restart — field report 2026-06-23). Earlier 2026-06-19 (offline-first: _hydrateFromCache() loads the Drift cache into in-memory state on init so the Chats tab never shows "No conversations yet" while a network loadFromServer() is slow/failing; _listenForReconnect() retries loadFromServer on socket reconnect while !_serverLoaded; _loading in-flight guard. Fixes empty-chat-list-on-unstable-network field report 2026-06-17.). Earlier 2026-05-14 (loadFromServer drift sync now runs ConversationDao.dedupeDirectByPeer afterward to heal Sealed Sender phantom direct rows whose unread counts were stuck in watchTotalUnreadCount's SUM but invisible in the UI)
///
/// @functions
///  - conversationListProvider: StateNotifierProvider supplying the conversation list
///  - conversationFromDriftRow(row): the single drift-row → Conversation mapper (top-level)
///  - ConversationListNotifier: StateNotifier managing conversation-list state
///  - _hydrateFromCache(): offline-first — load Drift-cached conversations into state on init
///  - _listenForReconnect(): retry loadFromServer on socket reconnect while !_serverLoaded
///  - loadFromServer(): rebuild the list from drift, drain the queue, start E2EE
///  - syncGv2Group(groupId): bring the entry of a v2 group in step with this device
///  - addConversation(): add a new conversation
///  - removeConversation(): remove a conversation
///  - updateLastMessage(): update the last message of a conversation
///  - markAsRead(): mark a conversation as read
///  - loadDeletedConvIds(storage): load locally deleted conversation-ID tombstones (top-level)
///  - addDeletedConvId(storage, id): add a deleted conversation-ID tombstone (top-level)
///  - removeDeletedConvId(storage, id): remove a conversation ID from the tombstone (top-level)
///  - _retryPendingDeletions(): retry server DELETE for conversations remaining in the tombstone
///  - _persistIncomingToDrift(): transactional persistence of received messages into the drift DB (SSoT)
///  - _applyKnownName(): a 1:1 peer's name known on this device (contact row, name certificate)
///  - _listenForCommunityEvents(): a kick from a community refreshes the community list

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/contacts/name_cert_service.dart';
import '../../../core/network/api_endpoints.dart';
import '../../channels/providers/channel_provider.dart' show myChannelsProvider;
// Phase 6: drift import is needed only for the drift-generated Conversation
// row type, aliased as `db` to avoid colliding with the in-memory model
// `Conversation` from models/conversation.dart.
import '../../../core/storage/database.dart' as db show Conversation;
import '../models/conversation.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/group_v2/gv2_codec.dart' show gv2IsGroupId;
import 'mark_read_helper.dart';
import '../../../core/diagnostics/log_ref.dart';

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
    debugPrint('[Tombstone] ADDED (total=${ids.length})');
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

// ---------------------------------------------------------------------------
// Drift row → in-memory Conversation (single mapper).
// ---------------------------------------------------------------------------

/// Builds the in-memory [Conversation] for a drift `conversations` row.
///
/// Every path that rebuilds the list from drift (cache hydrate, the
/// loadFromServer direct pass, the post-drain merge) goes through here, so a
/// local-only per-room setting cannot be dropped by one of them. Before this
/// mapper existed, loadFromServer copied the row by hand without the
/// auto-translate fields and then replaced the whole state — the room's
/// auto-translate switch silently turned off on every launch / reconnect even
/// though the row still had it on.
Conversation conversationFromDriftRow(db.Conversation row, {int unreadCount = 0}) {
  return Conversation(
    id: row.id,
    type: row.type == 'group' ? ConversationType.group : ConversationType.direct,
    title: row.title,
    groupId: row.groupId,
    participantIds: row.participantIds.isEmpty
        ? const []
        : row.participantIds.split(',').where((s) => s.isNotEmpty).toList(),
    lastMessageText: row.lastMessageText,
    lastMessageTime: row.lastMessageTime != null
        ? DateTime.fromMillisecondsSinceEpoch(row.lastMessageTime!)
        : null,
    lastMessageSenderId: row.lastMessageSenderId,
    unreadCount: unreadCount,
    autoTranslateEnabled: row.autoTranslateEnabled,
    autoTranslateTargetLang: row.autoTranslateTargetLang,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
  );
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
  StreamSubscription<Map<String, dynamic>>? _channelMemberLeftSubscription;
  /// The 1:1 rooms a peer deleted (their snowIds) — an open chat closes.
  final _peerDeletedChats = StreamController<String>.broadcast();
  Stream<String> get onPeerDeletedChat => _peerDeletedChats.stream;
  StreamSubscription<bool>? _connectionSub; // socket reconnect → reload guard
  bool _loading = false; // in-flight guard for loadFromServer (anti-hammer)

  /// Names from name certificates (read once: a disposed notifier must not
  /// read providers).
  late final NameCertService _names = _ref.read(nameCertServiceProvider);

  void _onNameChanged(String peer) => _applyKnownName(peer, peer);

  ConversationListNotifier(this._ref) : super([]) {
    _listenForCommunityEvents();
    _listenForReconnect();
    // A peer's name changed (a newer name certificate): the drift title is
    // written by NameCertService; the in-memory entry follows.
    _names.onNameChanged = _onNameChanged;
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
        debugPrint('[DIAG:ConvList] onNewConversation: adding ${logRef(convId)} from ${logRef(senderSnowId)}');
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
        _applyKnownName(convId, senderSnowId);
      }
    };

    // Sealed Sender 1:1 — the wire-level envelope hides the sender, so the
    // list cannot follow the socket. MessageQueue fires this callback after
    // unseal + drift insert so the in-memory state follows.
    _ref.read(messageQueueProvider).onSealedMessageDecoded =
        (convId, senderSnowId, preview, msgTime) {
      // A 1:1 room is keyed by the peer's snowId (convId is the sender's).
      // Match direct rows only: a sealed 1:1 envelope never bleeds into a
      // group row's preview / unread badge.
      final idx = state.indexWhere(
          (c) => c.type == ConversationType.direct && c.id == convId);
      final isViewing = MarkReadHelper.isConversationActive(convId);
      if (idx < 0) {
        // First message in a brand-new conversation — surface it now.
        final mySnowId = _ref.read(currentSnowIdProvider) ?? '';
        debugPrint('[DIAG:ConvList] onSealedMessageDecoded: NEW conv ${logRef(convId)} '
            'from ${logRef(senderSnowId)}');
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
        _applyKnownName(convId, senderSnowId);
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
      debugPrint('[DIAG:ConvList] onSealedMessageDecoded: ${logRef(convId)} '
          'unread=${updated.unreadCount} viewing=$isViewing');
    };

    // Push the real decrypted group plaintext (group protocol v2, stored by
    // the v2 message sink) into the in-memory preview. Preview only — the
    // group's unread count follows its drift row (syncGv2Group).
    _ref.read(messageQueueProvider).onGroupMessageDecoded =
        (groupId, senderSnowId, preview, msgTime) {
      final idx = state.indexWhere((c) => c.id == groupId);
      if (idx < 0) return; // not in state yet; syncGv2Group adds it
      // Unconditional overwrite: the queue hands v2 messages over serially in
      // arrival order, so the latest call reflects the newest message.
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

    // Queued sealed delete-chat control — the offline-durable half of the
    // peer-deleted-this-chat path (the live socket event only reaches a peer
    // who is connected at that moment).
    _ref.read(messageQueueProvider).onPeerDeletedChat =
        (peerSnowId, roomId) async {
      // Drift + Signal session were already wiped by MessageQueue (it must not
      // depend on this callback being wired yet). Only in-memory state left.
      debugPrint('[ConversationList] sealed delete_chat from ${logRef(peerSnowId)} '
          '(room=${logRef(roomId)})');
      removeConversation(roomId);
    };

    // Group protocol v2: a group changed on this device (created, joined,
    // renamed, left, removed) — its row in the list follows.
    _ref.read(messageQueueProvider).onGv2GroupChanged = syncGv2Group;
  }

  /// Bring the list's entry of the v2 group [groupId] in step with this
  /// device: there while its conversation row exists (this account is, or
  /// was, in the group and has not removed the chat), with the group's
  /// current name. Nothing is asked of the server.
  Future<void> syncGv2Group(String groupId) async {
    if (!gv2IsGroupId(groupId)) return;
    final generation = (_gv2Generation[groupId] ?? 0) + 1;
    _gv2Generation[groupId] = generation;
    bool overtaken() => _gv2Generation[groupId] != generation;
    try {
      final row =
          await _ref.read(conversationDaoProvider).getConversation(groupId);
      if (!mounted || overtaken()) return;
      final index = state.indexWhere((c) => c.id == groupId);
      if (row == null || !row.isActive) {
        if (index >= 0) state = [...state]..removeAt(index);
        return;
      }
      final unread = await _ref.read(messageDaoProvider).getUnreadCount(groupId);
      if (!mounted || overtaken()) return;
      final fresh = conversationFromDriftRow(row, unreadCount: unread);
      final at = state.indexWhere((c) => c.id == groupId);
      final next = [...state];
      if (at >= 0) {
        next[at] = fresh;
      } else {
        next.add(fresh);
      }
      next.sort((a, b) => (b.lastMessageTime ?? b.createdAt)
          .compareTo(a.lastMessageTime ?? a.createdAt));
      state = next;
    } catch (e) {
      debugPrint('[ConversationList] v2 group sync failed: ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    if (_names.onNameChanged == _onNameChanged) _names.onNameChanged = null;
    _channelMemberLeftSubscription?.cancel();
    _peerDeletedChats.close();
    _connectionSub?.cancel();
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
  /// delete-for-me/everyone, sealed 1:1 unsend receiver, v2 group delete)
  /// so an unsent last message never stays in the Chats list.
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
        cached.add(conversationFromDriftRow(row, unreadCount: unread));
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

  /// Rebuild the conversation list from drift, then drain the server's
  /// pending messages into it and start the E2EE session manager. The
  /// server holds no list of conversations: 1:1 rooms and group protocol v2
  /// groups both live only in drift.
  Future<void> loadFromServer() async {
    if (_serverLoaded) return;
    // NOTE: _loading is tracked (so the reconnect listener can anti-hammer)
    // but is intentionally NOT part of this guard: an explicit reload
    // (pull-to-refresh, `refresh()`) must run even while an opportunistic
    // (startup/reconnect) load is in flight.
    _loading = true;

    try {
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
      final serverConversations = <Conversation>[];
      for (final row in driftRows) {
        if (!row.isActive) continue;
        // A group protocol v2 group is rebuilt from its drift row like a 1:1
        // room: the row exists while this account is in the group.
        // unreadCount populated by _drainPendingMessages from local DB.
        // Built by the shared row mapper so per-room settings (auto-translate)
        // survive this full `state =` replacement.
        serverConversations.add(conversationFromDriftRow(row));
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
          'conversation(s) from drift');

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

  /// Force a reload (drift rebuild + queue drain).
  Future<void> refresh() async {
    _serverLoaded = false;
    await loadFromServer();
  }

  void addConversation(Conversation conversation) {
    state = [conversation, ...state];
    // F4(a) (2026-08-03): mirror a direct conversation into drift the moment it
    // is optimistically opened. Drift is the only list source (loadFromServer
    // rebuilds from it), so an in-memory-only room would vanish on the next
    // reload. Fire-and-forget: the write is local SQLite.
    if (conversation.type == ConversationType.direct) {
      unawaited(_mirrorDirectToDrift(conversation));
    }
  }

  /// Write-through a direct conversation into the drift `conversations` table.
  /// See addConversation() for why this must not wait for loadFromServer.
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
          '${logRef(conversation.id)}: $e');
    }
  }

  void removeConversation(String id) {
    if (!mounted) return;
    // A sync of a v2 group's row under way read it before this: it must not
    // put it back.
    _gv2Generation.update(id, (g) => g + 1, ifAbsent: () => 1);
    state = state.where((c) => c.id != id).toList();
  }

  /// Bumped by every sync of a v2 group's row (syncGv2Group) and by its
  /// removal: a sync whose reads were overtaken applies nothing — it could
  /// put back a row removed between its two reads.
  final Map<String, int> _gv2Generation = {};

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
  /// On success, remove the tombstone. When the server will never take it —
  /// 404 (the peer's account is gone: nothing of the pair is left to delete)
  /// or 400 (not a request it takes) — the tombstone goes too. Any other
  /// failure (no network, a server hiccup) leaves it for the next retry.
  Future<void> _retryPendingDeletions() async {
    final ids = await _loadDeletedConvIds();
    if (ids.isEmpty) return;
    debugPrint('[ConversationList] _retryPendingDeletions: ${ids.length} pending');
    final apiClient = _ref.read(apiClientProvider);
    for (final id in ids.toList()) {
      try {
        await apiClient.post(
          ApiEndpoints.conversationDelete,
          data: {'peerSnowchatId': id},
        );
        await _removeDeletedConvId(id);
        debugPrint('[ConversationList] retry DELETE success');
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 404 || status == 400) {
          await _removeDeletedConvId(id);
          debugPrint('[ConversationList] retry DELETE settled ($status)');
        } else {
          debugPrint('[ConversationList] retry DELETE failed: ${e.type}');
        }
      } catch (e) {
        debugPrint('[ConversationList] retry DELETE failed: ${e.runtimeType}');
      }
    }
  }

  /// Wipe this device's copy of the 1:1 room with [peerSnowId], which the
  /// peer deleted. The room id is the peer's snowId.
  ///
  /// Called by MessageQueue.onPeerDeletedChat, fed by the peer's sealed
  /// delete-chat control — the only signal of a deletion (2026-11-21: the
  /// server's chat_deleted socket event is gone; it was the server's word,
  /// and it raced ahead of the control and wiped the session the control
  /// was encrypted on). Queued like any message, so it also reaches a device
  /// that was offline when the peer deleted. Idempotent.
  ///
  /// 2026-05-04: the Signal SessionStore is wiped too. The peer deleting the
  /// chat means both sides want a fresh start; keeping the session makes the
  /// next exchange ratchet against stale state and spin the session_reset
  /// loop (mirrors deleteConversationLocally's fix).
  Future<void> applyPeerChatDeletion(String peerSnowId) async {
    // Remove from drift DB (messages + conversation row)
    try {
      await _ref.read(conversationDaoProvider).deleteConversation(peerSnowId);
    } catch (e) {
      debugPrint('[ConversationList] chat_deleted drift cleanup failed: $e');
    }

    // Wipe the Signal session so the next contact bootstraps a fresh X3DH
    // instead of a stale ratchet.
    try {
      final sessionMgr = _ref.read(signalSessionManagerProvider);
      await sessionMgr.deleteSessionForPeer(peerSnowId);
    } catch (e) {
      debugPrint('[ConversationList] chat_deleted signal session wipe '
          'for ${logRef(peerSnowId)} failed: $e');
    }

    // Remove from in-memory state
    if (!mounted) return;
    removeConversation(peerSnowId);
    _peerDeletedChats.add(peerSnowId);
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
  /// [conversationId] is the room id: the peer's snowId for a 1:1, the group
  /// id for a v2 group.
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
    } else if (gv2IsGroupId(conversationId)) {
      // A v2 group is never a 1:1 room: its entry comes from its drift row.
      unawaited(syncGv2Group(conversationId));
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
        _applyKnownName(conversationId, otherSnowId);
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
  // Community event listener
  // ---------------------------------------------------------------------------

  /// A kick from a community (real-time). The server notifies the KICKED
  /// user directly with youWereRemoved:true (its member broadcast can't reach
  /// a just-deleted member). Drop the community from our lists at once — the
  /// Community tab renders from myChannelsProvider, a non-autoDispose
  /// FutureProvider that will not refetch on its own, so it must be
  /// invalidated. The notice for an open community screen is shown there
  /// (it has a BuildContext this notifier lacks).
  void _listenForCommunityEvents() {
    final sm = _ref.read(socketManagerProvider);
    _channelMemberLeftSubscription = sm.onChannelMemberLeft.listen((data) {
      final youWereRemoved = data['youWereRemoved'] as bool? ?? false;
      final channelId = data['channelId'] as String?;
      if (!youWereRemoved || channelId == null) return;
      debugPrint('[ConversationList] Kicked from community ${logRef(channelId)} '
          '— invalidating myChannelsProvider');
      _ref.invalidate(myChannelsProvider);
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
        additions.add(conversationFromDriftRow(row, unreadCount: unread));
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
              _applyKnownName(conv.id, peer);
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

  /// The name this device knows for the 1:1 peer [peer] (its contact row or
  /// its newest verified name certificate — NameCertService.nameOf) becomes
  /// the title of the room [convId], in memory and in drift (the VoIP screen
  /// reads it after a restart). Nothing is asked of the server: the name
  /// arrives with the peer's messages. No name known: the title stays.
  Future<void> _applyKnownName(String convId, String peer) async {
    try {
      final name = await _names.nameOf(peer);
      if (name == null || name.isEmpty) return;
      if (mounted) {
        state = [
          for (final c in state) c.id == convId ? c.copyWith(title: name) : c,
        ];
      }
      await _ref.read(conversationDaoProvider).updateTitle(convId, name);
    } catch (e) {
      debugPrint('[ConversationList] name not applied: ${e.runtimeType}');
    }
  }
}

