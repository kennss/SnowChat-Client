/// @file        database.dart
/// @description Drift-based local database. Stores messages, conversations, contacts, and E2EE session state.
///              Schema v2: Signal patterns applied (3-timestamp, read column, denormalized unread count)
///              Schema v8: added IdentityVerifications table (Safety Number 60-digit + TOFU mismatch)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-20 Schema v9: PendingTransfers + DAO — Wallet V2 Phase 1)
///
/// @functions
///  - SnowDatabase: Drift database main class
///  - _createCustomIndexes(): create partial indexes and composite indexes

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

// Import table definitions
import 'tables/messages_table.dart';
import 'tables/conversations_table.dart';
import 'tables/contacts_table.dart';
import 'tables/sessions_table.dart';
import 'tables/attachments_table.dart';
import 'tables/wallet_balances_table.dart';
import 'tables/wallet_tx_cache_table.dart';
import 'tables/wallet_address_book_table.dart';
import 'tables/ai_messages_table.dart';
import 'tables/identity_verifications_table.dart';
import 'tables/pending_transfers_table.dart';

// Import DAOs
import 'daos/message_dao.dart';
import 'daos/conversation_dao.dart';
import 'daos/attachment_dao.dart';
import 'daos/wallet_balance_dao.dart';
import 'daos/wallet_tx_cache_dao.dart';
import 'daos/wallet_address_book_dao.dart';
import 'daos/ai_message_dao.dart';
import 'daos/identity_verification_dao.dart';
import 'daos/pending_transfer_dao.dart';

part 'database.g.dart';

/// The main drift database for SnowChat.
/// Stores decrypted messages, conversations, contacts, and E2EE session state.
///
/// Schema v2 changes:
///  - LocalMessages: 9 → 21 columns (Signal 3-timestamp, read, receipts, etc.)
///  - Conversations: 12 → 20 columns (isRead, lastSeen, archive, pin order, etc.)
///  - Custom partial indexes for unread queries
///  - ConversationDao added
///
/// Note: Run `dart run build_runner build` to generate database.g.dart.
@DriftDatabase(
  tables: [
    LocalMessages,
    Conversations,
    Contacts,
    SignalSessions,
    SignalPreKeys,
    LocalAttachments,
    WalletBalances,
    WalletTxCache,
    WalletAddressBook,
    AiMessages,
    IdentityVerifications,
    PendingTransfers,
  ],
  daos: [
    MessageDao,
    ConversationDao,
    AttachmentDao,
    WalletBalanceDao,
    WalletTxCacheDao,
    WalletAddressBookDao,
    AiMessageDao,
    IdentityVerificationDao,
    PendingTransferDao,
  ],
)
class SnowDatabase extends _$SnowDatabase {
  SnowDatabase(super.e);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      // Phase 8.7 round 3: enforce SQLite durability on every connection
      // open. The default `journal_mode = DELETE / synchronous = NORMAL`
      // pair lets the writer return from `commit()` before fsync(), so a
      // process kill between drift insert and our outgoing ACK can leave
      // the row uncommitted on disk while the server has already marked
      // the message as `acked` — the message is then permanently lost.
      //
      // FULL syncs after every transaction commit; WAL gives crash-safe
      // append semantics. Both PRAGMAs are connection-scoped, so they MUST
      // be re-applied in beforeOpen (not just onCreate / onUpgrade).
      beforeOpen: (details) async {
        await customStatement('PRAGMA journal_mode = WAL');
        await customStatement('PRAGMA synchronous = FULL');
      },
      onCreate: (m) async {
        final sw = Stopwatch()..start();
        await m.createAll();
        debugPrint('[Perf] 💾 drift onCreate createAll: ${sw.elapsedMilliseconds}ms');
        sw.reset();
        await _createCustomIndexes();
        await _createAttachmentIndexes();
        await _createWalletIndexes();
        debugPrint('[Perf] 💾 drift onCreate indexes: ${sw.elapsedMilliseconds}ms');
      },
      onUpgrade: (m, from, to) async {
        final sw = Stopwatch()..start();
        debugPrint('[Perf] 💾 drift onUpgrade start: v$from → v$to');
        if (from < 2) {
          // === add messages table columns ===
          await m.addColumn(localMessages, localMessages.dateSent);
          await m.addColumn(localMessages, localMessages.dateReceived);
          await m.addColumn(localMessages, localMessages.dateServer);
          await m.addColumn(localMessages, localMessages.read);
          await m.addColumn(localMessages, localMessages.outgoingStatus);
          await m.addColumn(localMessages, localMessages.hasDeliveryReceipt);
          await m.addColumn(localMessages, localMessages.hasReadReceipt);
          await m.addColumn(localMessages, localMessages.notified);
          await m.addColumn(localMessages, localMessages.expiresIn);
          await m.addColumn(localMessages, localMessages.expireStarted);
          await m.addColumn(localMessages, localMessages.remoteDeleted);
          await m.addColumn(localMessages, localMessages.mentionsSelf);
          await m.addColumn(localMessages, localMessages.replyToId);
          await m.addColumn(localMessages, localMessages.senderDisplayName);

          // === add conversations table columns ===
          await m.addColumn(conversations, conversations.lastMessageId);
          await m.addColumn(conversations, conversations.unreadSelfMentionCount);
          await m.addColumn(conversations, conversations.isRead);
          await m.addColumn(conversations, conversations.lastSeen);
          await m.addColumn(conversations, conversations.lastScrolled);
          await m.addColumn(conversations, conversations.isArchived);
          await m.addColumn(conversations, conversations.isActive);
          await m.addColumn(conversations, conversations.pinnedOrder);
          await m.addColumn(conversations, conversations.groupId);

          // === migrate existing data ===
          // Convert existing timestamp into dateReceived/dateSent.
          // Note: SQLite cannot change a column's type via ALTER TABLE.
          // Keep the existing timestamp column, but copy its data into the new columns.
          await customStatement('''
            UPDATE local_messages
            SET date_received = CAST(strftime('%s', timestamp) AS INTEGER) * 1000,
                date_sent = CAST(strftime('%s', timestamp) AS INTEGER) * 1000,
                read = 1,
                outgoing_status = CASE
                  WHEN status = 'read' THEN 'read_by_recipient'
                  ELSE COALESCE(status, 'sent')
                END,
                notified = 1
            WHERE date_received = 0 OR date_received IS NULL
          ''');

          // Initialize read state on existing conversations
          await customStatement('''
            UPDATE conversations
            SET is_read = CASE WHEN unread_count = 0 THEN 1 ELSE 0 END,
                is_active = 1
          ''');

          // === create indexes ===
          await _createCustomIndexes();
        }
        if (from < 3) {
          // Phase 3.5: create Attachment table
          await m.createTable(localAttachments);
          await _createAttachmentIndexes();
        }
        if (from < 4) {
          // Phase 6.1 §3.1/§3.2/§3.5: create wallet cache / transaction / address book tables
          await m.createTable(walletBalances);
          await m.createTable(walletTxCache);
          await m.createTable(walletAddressBook);
          await _createWalletIndexes();
        }
        if (from < 5) {
          // Phase 10: AI messages table
          await m.createTable(aiMessages);
        }
        if (from < 6) {
          // Phase 10: per-conversation auto-translate setting
          await m.addColumn(
              conversations, conversations.autoTranslateEnabled);
        }
        if (from < 7) {
          // Phase 10: per-conversation translation target language (null falls back to global preferredLanguage)
          await m.addColumn(
              conversations, conversations.autoTranslateTargetLang);
        }
        if (from < 8) {
          // P0-2 Safety Number: per-peer verification + TOFU mismatch latch.
          await m.createTable(identityVerifications);
        }
        if (from < 9) {
          // Wallet V2 Phase 1: persist in-flight tx for in-chat transfers (P0-1, P0-2).
          // recoverPending() looks up RPC results for status='sent' rows.
          await m.createTable(pendingTransfers);
        }
        debugPrint('[Perf] 💾 drift onUpgrade complete: ${sw.elapsedMilliseconds}ms');
      },
    );
  }

  /// Signal partial index pattern (02-Signal Section 2.3, 10.2).
  /// Indexes optimized for unread queries, notification lookup, conversation list sort, etc.
  Future<void> _createCustomIndexes() async {
    // 1. Unread-only partial index (optimizes unread count queries)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_messages_unread_per_conversation
      ON local_messages (conversation_id) WHERE read = 0
    ''');
    // 2. Notification-target lookup (composite index)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_messages_unnotified
      ON local_messages (read, notified, conversation_id)
    ''');
    // 3. Multi-device sync (identify message by sender + timestamp pair)
    await customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_sender_timestamp
      ON local_messages (sender_snowchat_id, date_sent, conversation_id)
    ''');
    // 4. Per-conversation message lookup (chronological order, chat-screen scroll)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_messages_conversation_time
      ON local_messages (conversation_id, date_received)
    ''');
    // 5. Conversation list sort (active + newest order)
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_conversations_active_time
      ON conversations (is_active, last_message_time DESC)
    ''');
  }

  /// Wallet cache indexes for Phase 6.1 Step 2.
  Future<void> _createWalletIndexes() async {
    // Balance: per-owner latest lookup
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_wallet_balances_owner
      ON wallet_balances (owner_address, last_updated_ms DESC)
    ''');
    // Transaction cache: per-owner chronological
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_wallet_tx_cache_owner_time
      ON wallet_tx_cache (owner_address, block_time DESC)
    ''');
    // Address book: per-owner most-recently-used order
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_wallet_address_book_owner
      ON wallet_address_book (owner_address, last_used_ms DESC)
    ''');
  }

  /// Attachment indexes for Phase 3.5.
  Future<void> _createAttachmentIndexes() async {
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_attachments_message
      ON local_attachments (message_id)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_attachments_pending
      ON local_attachments (transfer_state) WHERE transfer_state = 2
    ''');
  }
}
