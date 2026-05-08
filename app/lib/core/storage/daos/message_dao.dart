/// @file        message_dao.dart
/// @description Local messages data access object. Implements message CRUD using Signal's transaction pattern,
///              reactive watch streams, read marking, outgoing status updates, etc.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-18 P0-2 Safety Number: added insertLocalSystemMessage helper)
///
/// @functions
///  - MessageDao: messages DAO class
///  - watchMessages(): per-conversation reactive message stream
///  - insertIncomingMessage(): incoming message INSERT + conversation UPDATE transaction
///  - insertOutgoingMessage(): outgoing message INSERT + conversation UPDATE transaction
///  - upsertMessage(): insert message or update its state (placeholder replacement)
///  - insertLocalSystemMessage(): helper to insert a local system message (e.g. key change)
///  - markAsRead(): mark-as-read + unreadCount update transaction
///  - markAllRead(): mark all as read
///  - getUnreadCount(): query unread count
///  - updateOutgoingStatus(): update outgoing status (sending -> sent -> delivered -> read)
///  - markRemoteDeleted(): handle remote deletion
///  - getUnnotifiedMessages(): query messages whose notification has not been sent
///  - markNotified(): mark notification as sent
///  - searchMessages(): plaintext message search (case-insensitive, substring match)
///  - getMessagesForConversation(): query messages for a conversation
///  - insertMessage(): insert message (legacy, backward compat)
///  - updatePlaceholder(): replace decryption-failure placeholder with decrypted plaintext (Phase 10 P0-F)
///  - deleteMessage(): delete message
///  - deleteConversationMessages(): delete all messages for a conversation

import 'dart:convert';

import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/messages_table.dart';
import '../tables/conversations_table.dart';

part 'message_dao.g.dart';

@DriftAccessor(tables: [LocalMessages, Conversations])
class MessageDao extends DatabaseAccessor<SnowDatabase>
    with _$MessageDaoMixin {
  MessageDao(super.db);

  // ---------------------------------------------------------------------------
  // Reactive watch streams
  // ---------------------------------------------------------------------------

  /// Live watch of messages for a specific conversation.
  /// When drift detects a table change it re-runs the query and pushes the latest results.
  /// Plays the role of Signal's DatabaseObserver.notifyConversationListeners().
  Stream<List<LocalMessage>> watchMessages(
    String conversationId, {
    int? limit,
  }) {
    final query = select(localMessages)
      ..where((m) => m.conversationId.equals(conversationId))
      ..orderBy([
        (m) => OrderingTerm(
            expression: m.dateReceived, mode: OrderingMode.asc),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    return query.watch();
  }

  // ---------------------------------------------------------------------------
  // Transactional inserts (Signal's core pattern: update message + conversation together)
  // ---------------------------------------------------------------------------

  /// Insert incoming message. Run message INSERT + conversation UPDATE in a single transaction.
  /// This is the heart of data consistency (02-Signal Section 7.2).
  ///
  /// Transaction contents:
  /// 1. INSERT into localMessages (read: false, notified: false)
  /// 2. UPDATE conversations (unreadCount +1, refresh snippet, isRead: false)
  ///
  /// After the transaction commits, drift watch streams fire automatically and refresh the UI.
  Future<void> insertIncomingMessage({
    required LocalMessagesCompanion message,
    required String conversationId,
    required String snippetText,
    required int receivedTimestamp,
    required String senderId,
    required bool mentionsSelf,
    required bool isCurrentlyViewing,
  }) async {
    await transaction(() async {
      // 1. INSERT message (update on conflict — placeholder replacement)
      await into(localMessages).insertOnConflictUpdate(message);

      // 2. Look up conversation
      final current = await (select(conversations)
            ..where((c) => c.id.equals(conversationId)))
          .getSingleOrNull();

      if (current != null) {
        // 3. UPDATE conversation
        final newUnread = isCurrentlyViewing
            ? current.unreadCount // Sticky Thread: don't increment if currently viewing
            : current.unreadCount + 1;
        final newMentionUnread = (mentionsSelf && !isCurrentlyViewing)
            ? current.unreadSelfMentionCount + 1
            : current.unreadSelfMentionCount;

        await (update(conversations)
              ..where((c) => c.id.equals(conversationId)))
            .write(ConversationsCompanion(
          lastMessageText: Value(snippetText),
          lastMessageTime: Value(receivedTimestamp),
          lastMessageSenderId: Value(senderId),
          lastMessageId: Value(message.id.value),
          unreadCount: Value(newUnread),
          unreadSelfMentionCount: Value(newMentionUnread),
          isRead: Value(isCurrentlyViewing),
          isActive: const Value(true),
          updatedAt: Value(receivedTimestamp),
        ));

        // Sticky Thread: if currently viewing, immediately mark the message read too
        if (isCurrentlyViewing) {
          await (update(localMessages)
                ..where((m) => m.id.equals(message.id.value)))
              .write(const LocalMessagesCompanion(
            read: Value(true),
            notified: Value(true),
          ));
        }
      }
    });
  }

  /// Insert outgoing message. Since I sent it: read: true, unreadCount not incremented.
  Future<void> insertOutgoingMessage({
    required LocalMessagesCompanion message,
    required String conversationId,
    required String snippetText,
    required int sentTimestamp,
  }) async {
    await transaction(() async {
      // 1. INSERT message (read: true — my own message is already read)
      await into(localMessages).insertOnConflictUpdate(message);

      // 2. Refresh only the Conversation snippet (do not change unreadCount)
      await (update(conversations)
            ..where((c) => c.id.equals(conversationId)))
          .write(ConversationsCompanion(
        lastMessageText: Value(snippetText),
        lastMessageTime: Value(sentTimestamp),
        lastMessageId: Value(message.id.value),
        isActive: const Value(true),
        updatedAt: Value(sentTimestamp),
      ));
    });
  }

  /// Insert message or refresh its state (placeholder replacement).
  Future<void> upsertMessage(LocalMessagesCompanion message) {
    return into(localMessages).insertOnConflictUpdate(message);
  }

  /// Insert a locally-generated system message into [conversationId].
  ///
  /// Used by [IdentityChangeHandler] (Safety Number key change) and any
  /// future "ephemeral notice" surface that needs to appear in the chat
  /// transcript without a server round-trip. The row is marked as read
  /// (no unread badge bump) and notified=true (no push). [eventType] is
  /// embedded into the JSON metadata so [SystemMessageBubble] can pick a
  /// custom icon (e.g. shield for safety_number_changed).
  ///
  /// Returns the rowid of the inserted row.
  ///
  /// IMPORTANT: never inserts cleartext message content; [text] is the UI
  /// label that's already safe to display (no E2EE plaintext involved).
  Future<int> insertLocalSystemMessage({
    required String conversationId,
    required String text,
    String? eventType,
    Map<String, dynamic>? metadata,
    int? expiresInSeconds,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Stable client-side ID — synthesized so retry / dedupe works at the
    // upsert layer if the same handler fires twice in quick succession.
    final id = 'sys_${eventType ?? 'event'}_$nowMs';

    final mergedMetadata = <String, dynamic>{
      if (eventType != null) 'eventType': eventType,
      if (metadata != null) ...metadata,
    };
    final companion = LocalMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderSnowchatId: const Value(''),
      plaintext: Value(text),
      dateSent: Value(nowMs),
      dateReceived: Value(nowMs),
      type: const Value('system'),
      read: const Value(true),
      notified: const Value(true),
      outgoingStatus: const Value('local_system'),
      // V1.0.1: use a forced 5-minute TTL for missed-call system messages and the like.
      // null/0 means permanent (preserves the existing Safety Number notice behavior).
      expiresIn: expiresInSeconds != null
          ? Value(expiresInSeconds)
          : const Value(0),
      expireStarted: expiresInSeconds != null
          ? Value(nowMs)
          : const Value(0),
      metadata:
          mergedMetadata.isEmpty ? const Value(null) : Value(jsonEncode(mergedMetadata)),
    );
    return into(localMessages).insert(
      companion,
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Phase 10 P0-F: Update a decryption-failed placeholder with recovered plaintext.
  ///
  /// When the original sender responds to a retry request, the receiver calls
  /// this to replace the placeholder content with the actual message text.
  /// Only updates rows where outgoingStatus == 'decryption_failed' to prevent
  /// accidentally overwriting a real message.
  ///
  /// Returns true if a placeholder was found and updated, false otherwise.
  Future<bool> updatePlaceholder(
    String messageId,
    String plaintext,
    String messageType,
  ) async {
    final count = await (update(localMessages)
          ..where((m) =>
              m.id.equals(messageId) &
              m.outgoingStatus.equals('decryption_failed')))
        .write(LocalMessagesCompanion(
      plaintext: Value(plaintext),
      outgoingStatus: const Value('delivered'),
      type: Value(messageType),
      metadata: const Value(null), // Clear retry metadata
    ));
    return count > 0;
  }

  // ---------------------------------------------------------------------------
  // Read status management (Signal's core pattern)
  // ---------------------------------------------------------------------------

  /// Mark messages in a specific conversation as read.
  /// Signal's setMessagesReadSince pattern (02-Signal Section 4.1).
  ///
  /// [upToTimestamp]: mark all unread messages before this point as read.
  /// Returns: the list of messages that were marked read (used for sending read receipts).
  Future<List<LocalMessage>> markAsRead({
    required String conversationId,
    required int upToTimestamp,
  }) async {
    // 1. First fetch the messages that will be marked read (used for sending read receipts)
    final unreadMessages = await (select(localMessages)
          ..where((m) =>
              m.conversationId.equals(conversationId) &
              m.read.equals(false) &
              m.dateReceived.isSmallerOrEqualValue(upToTimestamp)))
        .get();

    if (unreadMessages.isEmpty) return [];

    // 2. Transaction: mark messages read + start expiration timer + refresh conversation
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      // Mark messages as read
      await (update(localMessages)
            ..where((m) =>
                m.conversationId.equals(conversationId) &
                m.read.equals(false) &
                m.dateReceived.isSmallerOrEqualValue(upToTimestamp)))
          .write(const LocalMessagesCompanion(
        read: Value(true),
      ));

      // Signal pattern: start expiration timer at the moment of read
      // expiresIn > 0 && expireStarted == 0 → message whose timer hasn't started yet
      await (update(localMessages)
            ..where((m) =>
                m.conversationId.equals(conversationId) &
                m.expiresIn.isBiggerThanValue(0) &
                m.expireStarted.equals(0) &
                m.dateReceived.isSmallerOrEqualValue(upToTimestamp)))
          .write(LocalMessagesCompanion(
        expireStarted: Value(now),
      ));

      // Recalculate Conversation unreadCount
      final remainingUnread = await _countUnread(conversationId);
      final remainingMentions = await _countUnreadMentions(conversationId);

      await (update(conversations)
            ..where((c) => c.id.equals(conversationId)))
          .write(ConversationsCompanion(
        unreadCount: Value(remainingUnread),
        unreadSelfMentionCount: Value(remainingMentions),
        isRead: Value(remainingUnread == 0),
        lastSeen: Value(upToTimestamp),
        lastScrolled: const Value(0),
      ));
    });

    return unreadMessages;
  }

  /// Mark every unread message across all conversations as read.
  Future<void> markAllRead() async {
    await transaction(() async {
      // All unread messages → read: true
      await (update(localMessages)
            ..where((m) => m.read.equals(false)))
          .write(const LocalMessagesCompanion(
        read: Value(true),
      ));

      // Reset unreadCount on every conversation
      await (update(conversations)
            ..where((c) => c.unreadCount.isBiggerThanValue(0)))
          .write(const ConversationsCompanion(
        unreadCount: Value(0),
        unreadSelfMentionCount: Value(0),
        isRead: Value(true),
      ));
    });
  }

  /// Unread message count for a specific conversation.
  /// Uses the partial index (idx_messages_unread_per_conversation).
  Future<int> getUnreadCount(String conversationId) async {
    return _countUnread(conversationId);
  }

  /// Watch total unread sum (for the app badge).
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

  // ---------------------------------------------------------------------------
  // Outgoing status management
  // ---------------------------------------------------------------------------

  /// Update outgoing message status. Called when a message_status event is received from the server.
  /// sending → sent → delivered → read_by_recipient
  ///
  /// On the sent state, also swaps the local ID for the server messageId.
  Future<void> updateOutgoingStatus(
    String messageId,
    String newStatus, {
    String? serverMessageId,
  }) async {
    if (serverMessageId != null && serverMessageId != messageId) {
      // Local ID → server ID swap: delete the existing row, then re-insert under the new ID
      final existing = await (select(localMessages)
            ..where((m) => m.id.equals(messageId)))
          .getSingleOrNull();
      if (existing != null) {
        await transaction(() async {
          await (delete(localMessages)
                ..where((m) => m.id.equals(messageId)))
              .go();
          await into(localMessages).insertOnConflictUpdate(
            LocalMessagesCompanion(
              id: Value(serverMessageId),
              conversationId: Value(existing.conversationId),
              senderSnowchatId: Value(existing.senderSnowchatId),
              dateSent: Value(existing.dateSent),
              dateReceived: Value(existing.dateReceived),
              dateServer: Value(existing.dateServer),
              plaintext: Value(existing.plaintext),
              type: Value(existing.type),
              read: Value(existing.read),
              outgoingStatus: Value(newStatus),
              metadata: Value(existing.metadata),
              expiresIn: Value(existing.expiresIn),
              expireStarted: Value(existing.expireStarted),
              replyToId: Value(existing.replyToId),
              // 2026-05-08 schema v10 — carry the denormalized quote
              // fields across the local→server ID swap. Without this, a
              // sent message loses its reply quote the moment the ACK
              // arrives and the drift watch reloads the new row.
              replyToPreview: Value(existing.replyToPreview),
              replyToSenderId: Value(existing.replyToSenderId),
              senderDisplayName: Value(existing.senderDisplayName),
            ),
          );
        });
      }
    } else {
      await (update(localMessages)
            ..where((m) => m.id.equals(messageId)))
          .write(LocalMessagesCompanion(
        outgoingStatus: Value(newStatus),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Remote delete
  // ---------------------------------------------------------------------------

  /// Mark a message as remote-deleted. Erase the body and set the remoteDeleted flag.
  Future<void> markRemoteDeleted(String messageId) async {
    await (update(localMessages)
          ..where((m) => m.id.equals(messageId)))
        .write(const LocalMessagesCompanion(
      plaintext: Value('This message was deleted'),
      remoteDeleted: Value(true),
    ));
  }

  // ---------------------------------------------------------------------------
  // Notification tracking
  // ---------------------------------------------------------------------------

  /// Fetch messages that have not yet had a notification sent. Messages with read=false AND notified=false.
  Future<List<LocalMessage>> getUnnotifiedMessages() {
    return (select(localMessages)
          ..where(
              (m) => m.read.equals(false) & m.notified.equals(false))
          ..orderBy([
            (m) => OrderingTerm(
                expression: m.dateReceived, mode: OrderingMode.asc),
          ]))
        .get();
  }

  /// Mark notification as sent. Sets notified=true on the given list of message IDs.
  Future<void> markNotified(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    await (update(localMessages)
          ..where((m) => m.id.isIn(messageIds)))
        .write(const LocalMessagesCompanion(
      notified: Value(true),
    ));
  }

  // ---------------------------------------------------------------------------
  // Legacy methods (preserved for backward compatibility)
  // ---------------------------------------------------------------------------

  /// Search messages by plaintext content.
  ///
  /// Case-insensitive partial match against the `plaintext` column.
  /// Results are ordered by dateReceived descending (newest first).
  /// E2EE means this search is LOCAL ONLY -- the server has no plaintext.
  ///
  /// [query] -- the search text (must be non-empty).
  /// [limit] -- max results to return (default 50).
  Future<List<LocalMessage>> searchMessages(
    String query, {
    int limit = 50,
  }) {
    final pattern = '%$query%';
    return (select(localMessages)
          ..where((m) => m.plaintext.like(pattern))
          ..orderBy([
            (m) => OrderingTerm(
                  expression: m.dateReceived,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .get();
  }

  /// Get all messages for a conversation, ordered by dateReceived ascending.
  Future<List<LocalMessage>> getMessagesForConversation(
    String conversationId, {
    int? limit,
  }) {
    final query = select(localMessages)
      ..where((m) => m.conversationId.equals(conversationId))
      ..orderBy([
        (m) => OrderingTerm(
              expression: m.dateReceived,
              mode: OrderingMode.asc,
            ),
      ]);
    if (limit != null) {
      query.limit(limit);
    }
    return query.get();
  }

  /// Insert or replace a message (legacy convenience method).
  Future<void> insertMessage(LocalMessagesCompanion message) {
    return into(localMessages).insertOnConflictUpdate(message);
  }

  /// Get a single message by ID (for deduplication check).
  Future<LocalMessage?> getMessageById(String messageId) {
    return (select(localMessages)
          ..where((m) => m.id.equals(messageId)))
        .getSingleOrNull();
  }

  /// Delete a message by ID.
  Future<int> deleteMessage(String messageId) {
    return (delete(localMessages)..where((m) => m.id.equals(messageId))).go();
  }

  /// Delete all messages in a conversation.
  Future<int> deleteConversationMessages(String conversationId) {
    return (delete(localMessages)
          ..where((m) => m.conversationId.equals(conversationId)))
        .go();
  }

  // ---------------------------------------------------------------------------
  // Expiring messages (Signal ExpiringMessageManager pattern)
  // ---------------------------------------------------------------------------

  /// Get all messages with active expiration timers.
  /// Used on app startup to re-schedule pending deletions.
  Future<List<LocalMessage>> getExpiringMessages() {
    return (select(localMessages)
          ..where((m) =>
              m.expiresIn.isBiggerThanValue(0) &
              m.expireStarted.isBiggerThanValue(0)))
        .get();
  }

  // ---------------------------------------------------------------------------
  // Data repair
  // ---------------------------------------------------------------------------

  /// Fix own outgoing messages that were incorrectly stored with read=false.
  /// Previous code versions may have stored them without proper read flag.
  /// Own messages should always be read=true (you wrote them, you read them).
  Future<void> fixOwnMessagesReadStatus(String mySnowId) async {
    await customStatement(
      'UPDATE local_messages SET read = 1 '
      'WHERE sender_snowchat_id = ? AND read = 0',
      [mySnowId],
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<int> _countUnread(String conversationId) async {
    final count = await customSelect(
      'SELECT COUNT(*) AS c FROM local_messages '
      'WHERE conversation_id = ? AND read = 0',
      variables: [Variable.withString(conversationId)],
    ).getSingle();
    return count.read<int>('c');
  }

  Future<int> _countUnreadMentions(String conversationId) async {
    final count = await customSelect(
      'SELECT COUNT(*) AS c FROM local_messages '
      'WHERE conversation_id = ? AND read = 0 AND mentions_self = 1',
      variables: [Variable.withString(conversationId)],
    ).getSingle();
    return count.read<int>('c');
  }
}
