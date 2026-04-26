/// @file        conversation_dao.dart
/// @description Conversations data access object. Signal ThreadTable access pattern applied.
///              Reactive watch streams, findOrCreate, read/archive/pin/mute management.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-01
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-01)
///
/// @functions
///  - ConversationDao: conversations DAO class
///  - watchActiveConversations(): reactive stream of active conversation list
///  - watchUnreadConversations(): reactive stream of unread-only conversations
///  - watchTotalUnreadCount(): reactive stream of total unread count (app badge)
///  - watchConversation(): reactive stream for a single conversation's changes
///  - findOrCreate(): fetch or create a conversation
///  - getConversation(): single-row fetch
///  - getAllConversations(): batch fetch all conversations
///  - updateLastMessage(): refresh snippet
///  - incrementUnread(): increment unread count
///  - resetUnread(): reset unread count
///  - deleteConversation(): delete conversation
///  - archiveConversation(): archive
///  - pinConversation(): pin
///  - muteConversation(): toggle mute

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

  /// Find a direct conversation by participant's snowchat ID.
  /// Returns null if no conversation exists with this participant.
  Future<Conversation?> findDirectByParticipant(String snowchatId) async {
    final all = await (select(conversations)
          ..where((c) => c.type.equals('direct')))
        .get();
    for (final conv in all) {
      if (conv.participantIds.contains(snowchatId)) {
        return conv;
      }
    }
    return null;
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
}
