/// @file        conversation_dao.dart
/// @description Conversations data access object. Signal ThreadTable access pattern applied.
///              Reactive watch streams, findOrCreate, read/archive/pin/mute management.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-01
/// @lastUpdated 2026-11-20 (v1 groups removed: a 1:1 room is keyed by the peer's snowId, so
///              findDirectByParticipant() is that row and nothing else; retypeToGroup() and
///              dedupeDirectByPeer() — heals for mis-typed v1 group rows and server-CUID
///              duplicates — are gone with the rows they healed). Earlier 2026-11-12 (retypeToGroup: the raw print() that wrote the group id to the console in every build mode is now a debugPrint without the id). Earlier 2026-08-12 (findDirectByParticipant() gained trustServerCuidRows: on a device still carrying a pre-302 mis-typed group row, the inbound queue drains before loadFromServer's retypeToGroup heal, so a queued sealed 1:1 was still routed into the group room on the first post-upgrade boot (measured on 303: routed 36s before the heal). Receive-path callers pass false until the server group-id set has been synced once this session; the deterministic snow-id room is used instead and dedupeDirectByPeer folds it onto the canonical row on the same pass). Earlier 2026-08-03 (retypeToGroup() heals a group whose local row was mis-created as type='direct' by the group-message listener — that row was indistinguishable from a 1:1 with the sender, so findDirectByParticipant routed 1:1 messages into it and dedupeDirectByPeer merged the receive-first 1:1 room onto it, bleeding 1:1 and group transcripts together; dedupeDirectByPeer now also skips any row carrying a groupId as forward defense). Earlier 2026-08-03 (add public participantIdsOf() wrapping the tolerant _parseParticipants so MessageRepository can resolve the 1:1 peer without a jsonDecode FormatException on the CSV column). Earlier 2026-05-14 (dedupeDirectByPeer merges duplicate direct rows per peer into the canonical server-CUID row — heals the badge-stuck-at-N regression where Sealed Sender phantom rows accumulated unread the UI never surfaced)
///
/// @functions
///  - ConversationDao: conversations DAO class
///  - watchActiveConversations(): reactive stream of active conversation list
///  - watchUnreadConversations(): reactive stream of unread-only conversations
///  - watchTotalUnreadCount(): reactive stream of total unread count (app badge)
///  - watchConversation(): reactive stream for a single conversation's changes
///  - findOrCreate(): fetch or create a conversation
///  - findDirectByParticipant(): the 1:1 room with a peer (keyed by the peer's snowId)
///  - getConversation(): single-row fetch
///  - getAllConversations(): batch fetch all conversations
///  - updateLastMessage(): refresh snippet
///  - incrementUnread(): increment unread count
///  - resetUnread(): reset unread count
///  - deleteConversation(): delete conversation
///  - archiveConversation(): archive
///  - pinConversation(): pin
///  - muteConversation(): toggle mute

import 'dart:convert';

import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/conversations_table.dart';
import '../tables/messages_table.dart';

part 'conversation_dao.g.dart';

@DriftAccessor(tables: [Conversations, LocalMessages])
class ConversationDao extends DatabaseAccessor<SnowDatabase>
    with _$ConversationDaoMixin {
  ConversationDao(super.db);

  // ---------------------------------------------------------------------------
  // Reactive watch streams
  // ---------------------------------------------------------------------------

  /// Live watch of the active conversation list.
  /// Order: pinned conversations first → newest message order.
  /// drift's watch() re-queries automatically when the conversations table changes.
  Stream<List<Conversation>> watchActiveConversations() {
    return (select(conversations)
          ..where((c) => c.isActive.equals(true) & c.isArchived.equals(false))
          ..orderBy([
            // pinned conversations first (pinnedOrder NULL goes last)
            (c) => OrderingTerm(
                expression: c.pinnedOrder,
                mode: OrderingMode.asc,
                nulls: NullsOrder.last),
            // newest message order
            (c) => OrderingTerm(
                expression: c.lastMessageTime,
                mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Live watch of unread conversations only.
  Stream<List<Conversation>> watchUnreadConversations() {
    return (select(conversations)
          ..where((c) =>
              c.isActive.equals(true) &
              c.isArchived.equals(false) &
              c.unreadCount.isBiggerThanValue(0))
          ..orderBy([
            (c) => OrderingTerm(
                expression: c.lastMessageTime,
                mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Watch total unread sum (for the app badge).
  /// Layer 3 of Signal's 3-layer unread model (02-Signal Section 5.1).
  Stream<int> watchTotalUnreadCount() {
    final query = selectOnly(conversations)
      ..where(
          conversations.isActive.equals(true) &
          conversations.isArchived.equals(false))
      ..addColumns([conversations.unreadCount.sum()]);

    return query.watchSingle().map((row) {
      return row.read(conversations.unreadCount.sum()) ?? 0;
    });
  }

  /// Watch changes to a single conversation.
  Stream<Conversation?> watchConversation(String conversationId) {
    return (select(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .watchSingleOrNull();
  }

  // ---------------------------------------------------------------------------
  // CRUD operations
  // ---------------------------------------------------------------------------

  /// Fetch conversation, or create one if absent.
  /// Used when the socket receives a first message from a new conversation peer.
  Future<Conversation> findOrCreate({
    required String id,
    required String type,
    required List<String> participantIds,
    String? title,
    String? groupId,
  }) async {
    final existing = await (select(conversations)
          ..where((c) => c.id.equals(id)))
        .getSingleOrNull();

    if (existing != null) return existing;

    final now = DateTime.now().millisecondsSinceEpoch;
    final companion = ConversationsCompanion.insert(
      id: id,
      type: Value(type),
      title: Value(title),
      participantIds: _encodeParticipants(participantIds),
      groupId: Value(groupId),
      createdAt: now,
      updatedAt: now,
    );
    await into(conversations).insert(companion);

    return (await (select(conversations)
          ..where((c) => c.id.equals(id)))
        .getSingle());
  }

  /// The 1:1 room with [snowchatId]. A 1:1 room's id is the peer's snowId
  /// (since 2026-08-07 the server keeps no conversation ids; rooms keyed
  /// otherwise were removed by the v14 migration), so this is that row when
  /// it is a direct room — never a row that merely lists the peer.
  Future<Conversation?> findDirectByParticipant(String snowchatId) {
    return (select(conversations)
          ..where((c) => c.id.equals(snowchatId) & c.type.equals('direct')))
        .getSingleOrNull();
  }

  /// Single-row conversation fetch.
  Future<Conversation?> getConversation(String conversationId) {
    return (select(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .getSingleOrNull();
  }

  /// Batch fetch all conversations.
  Future<List<Conversation>> getAllConversations() {
    return (select(conversations)
          ..orderBy([
            (c) => OrderingTerm(
                expression: c.lastMessageTime,
                mode: OrderingMode.desc),
          ]))
        .get();
  }

  // ---------------------------------------------------------------------------
  // Conversation metadata updates
  // ---------------------------------------------------------------------------

  /// Refresh snippet. Denormalize last-message info into the conversations table.
  Future<void> updateLastMessage({
    required String conversationId,
    required String text,
    required String senderId,
    required int timestamp,
    String? messageId,
  }) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      lastMessageText: Value(text),
      lastMessageTime: Value(timestamp),
      lastMessageSenderId: Value(senderId),
      lastMessageId: Value(messageId),
      updatedAt: Value(timestamp),
    ));
  }

  /// Increment unread count. Standalone use (when needed outside a MessageDao transaction).
  Future<void> incrementUnread(
    String conversationId, {
    int count = 1,
    bool isMention = false,
  }) async {
    final current = await (select(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .getSingleOrNull();

    if (current == null) return;

    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      unreadCount: Value(current.unreadCount + count),
      unreadSelfMentionCount: Value(
        isMention
            ? current.unreadSelfMentionCount + 1
            : current.unreadSelfMentionCount,
      ),
      isRead: const Value(false),
    ));
  }

  /// Reset unread count. Call after all messages in the chat have been read.
  /// Note: normally MessageDao.markAsRead() handles this inside its transaction.
  /// Use this method only when a forced reset is required.
  Future<void> resetUnread(String conversationId) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(const ConversationsCompanion(
      unreadCount: Value(0),
      unreadSelfMentionCount: Value(0),
      isRead: Value(true),
    ));
  }

  // ---------------------------------------------------------------------------
  // Conversation lifecycle
  // ---------------------------------------------------------------------------

  /// Delete conversation. Related messages are deleted as well.
  Future<void> deleteConversation(String conversationId) async {
    await transaction(() async {
      await (delete(localMessages)
            ..where((m) => m.conversationId.equals(conversationId)))
          .go();
      await (delete(conversations)
            ..where((c) => c.id.equals(conversationId)))
          .go();
    });
  }

  /// Archive.
  Future<void> archiveConversation(String conversationId) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(const ConversationsCompanion(
      isArchived: Value(true),
    ));
  }

  /// Pin.
  Future<void> pinConversation(
    String conversationId, {
    required int order,
  }) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      isPinned: const Value(true),
      pinnedOrder: Value(order),
    ));
  }

  /// Toggle mute.
  Future<void> muteConversation(
    String conversationId, {
    required bool muted,
  }) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      isMuted: Value(muted),
    ));
  }

  /// Refresh conversation display name. Call when the peer's displayName in a
  /// 1:1 chat is resolved via server sync. Persisted in drift so it survives
  /// app restart.
  /// (Previously only in-memory state was updated, which fell back to the
  ///  truncated snow ID after restart → root cause of the bug where the
  ///  outgoing-call screen showed the snow ID instead of the nickname.)
  Future<void> updateTitle(String conversationId, String title) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      title: Value(title),
    ));
  }

  /// Toggle auto-translate.
  Future<void> setAutoTranslate(
    String conversationId, {
    required bool enabled,
  }) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      autoTranslateEnabled: Value(enabled),
    ));
  }

  /// Set per-conversation translation target language. null falls back to global preferredLanguage.
  Future<void> setAutoTranslateTarget(
    String conversationId,
    String? targetLang,
  ) async {
    await (update(conversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(ConversationsCompanion(
      autoTranslateTargetLang: Value(targetLang),
    ));
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _encodeParticipants(List<String> ids) {
    return ids.join(',');
  }

  /// Parse the participantIds column, tolerating both encodings actually
  /// found in the wild: CSV (the current writer) and legacy JSON arrays
  /// (some read paths still use jsonDecode — historical drift).
  List<String> _parseParticipants(String raw) {
    if (raw.isEmpty) return const [];
    if (raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return raw.split(',').where((p) => p.isNotEmpty).toList();
  }

  /// Public tolerant parse of the participantIds column for callers outside the
  /// DAO (e.g. MessageRepository resolving the peer before a 1:1 delete). The
  /// column is written as CSV (_encodeParticipants), so a plain jsonDecode there
  /// threw FormatException and silently skipped the Signal session wipe.
  List<String> participantIdsOf(String raw) => _parseParticipants(raw);
}
