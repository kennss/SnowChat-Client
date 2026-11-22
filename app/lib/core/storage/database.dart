/// @file        database.dart
/// @description Drift-based local database. Stores messages, conversations, contacts, and E2EE session state.
///              Schema v2: Signal patterns applied (3-timestamp, read column, denormalized unread count)
///              Schema v8: added IdentityVerifications table (Safety Number 60-digit + TOFU mismatch)
///              Schema v11: group protocol v2 tables (group state: Gv2Groups, Gv2Members, Gv2Pending, Gv2Heads; acting without a login: Gv2ServerKeys, Gv2AuthCredentials, Gv2Endorsements; the local inbox: Gv2InboxRows, Gv2Seen; pairwise messages: Gv2SenderKeys, Gv2KeyDeliveries, Gv2OutboxRows; group messages: Gv2MessageIds) + Gv2Store, Gv2InboxStore, Gv2SenderKeyStore, Gv2OutboxStore
///              Schema v12: group key backup state; Schema v13: gv2_groups.change_sent_at_ms
///              Schema v14: data only — conversations whose id is neither a snowId (1:1) nor a v2
///              group id are removed with their messages and attachment rows (v1 groups gone)
///              Schema v17: direct_outbox (the 1:1 outbox — DirectOutboxDao) and
///              local_messages.peer_client_id with its unique index (a message the sender sent
///              again is stored once)
///              Schema v18: the friend list moves to this device — contact_list, peer_names,
///              contact_sync_state (ContactDao) replace the unused contacts table;
///              blocked_accounts.nickname
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (the v17 → v18 upgrade writes the contact sync state as restored with
///              the block replace pending: an install upgraded in place has no backup to restore and
///              its block list goes to the server as a whole — design §5.10). Earlier 2026-11-22 (v18: contact_list / peer_names / contact_sync_state and ContactDao
///              replace the unused contacts table; blocked_accounts.nickname — design
///              2026-11-22-friend-graph-off-server §5.1, §5.9, §5.10). Earlier 2026-11-21 (v17: direct_outbox + local_messages.peer_client_id / idx_messages_peer_client
///              — the 1:1 outbox and the receiver's duplicate guard). Earlier 2026-11-21 (v16: blocked_accounts — X1, the accounts this user blocked, on this device; BlockListDao). Earlier 2026-11-21 (v15: gv2_heads.stored_at_ms, gv2_groups.my_key_at_ms, gv2_backup_state.write_due_at_ms — the backup write is made at a random time 1–6 h after what changed it). Earlier 2026-11-20 (Schema v14: data only — the conversations of the v1 groups and rooms, and any other conversation whose id is neither a peer's snowId nor a group protocol v2 group id, go with their messages and attachment rows; the files stay). Earlier same day (Schema v13: gv2_groups.change_sent_at_ms — a group change whose answer never came). Earlier 2026-11-20 (Schema v11: group protocol v2 state tables and Gv2Store, then the local inbox tables and Gv2InboxStore, then the verified log points, v4 Sender Keys, key deliveries and the outbox, then the handled message ids; schema v12: gv2_backup_state and gv2_groups.reset_pending — a new version because development devices already carry v11; every schema version is now dumped to drift_schemas/ and the migration is tested against it). Earlier 2026-04-26 (header + inline English translation; previous: 2026-04-20 Schema v9: PendingTransfers + DAO — Wallet V2 Phase 1)
///
/// @functions
///  - SnowDatabase: Drift database main class
///  - _createCustomIndexes(): create partial indexes and composite indexes
///  - keptConversationIdSql(column): SQL condition — a conversation id that is still valid (v14)

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
import 'tables/gv2_tables.dart';
import 'tables/blocked_accounts_table.dart';
import 'tables/direct_outbox_table.dart';

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
import 'daos/block_list_dao.dart';
import 'daos/direct_outbox_dao.dart';
import 'daos/contact_dao.dart';
import '../contacts/contact_backup.dart' show drawContactWritePeriodMs;
import '../group_v2/gv2_inbox_store.dart';
import '../group_v2/gv2_outbox.dart';
import '../group_v2/gv2_sender_key_store.dart';
import '../group_v2/gv2_store.dart';

part 'database.g.dart';

/// The main drift database for SnowChat.
/// Stores decrypted messages, conversations, the friend list, and E2EE session state.
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
    SignalSessions,
    SignalPreKeys,
    LocalAttachments,
    WalletBalances,
    WalletTxCache,
    WalletAddressBook,
    AiMessages,
    IdentityVerifications,
    PendingTransfers,
    Gv2Groups,
    Gv2Members,
    Gv2Pending,
    Gv2ServerKeys,
    Gv2AuthCredentials,
    Gv2Endorsements,
    Gv2InboxRows,
    Gv2Seen,
    Gv2Heads,
    Gv2SenderKeys,
    Gv2KeyDeliveries,
    Gv2OutboxRows,
    Gv2MessageIds,
    Gv2BackupStates,
    BlockedAccounts,
    DirectOutboxJobs,
    ContactList,
    PeerNames,
    ContactSyncStates,
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
    Gv2Store,
    Gv2InboxStore,
    BlockListDao,
    DirectOutboxDao,
    ContactDao,
    Gv2SenderKeyStore,
    Gv2OutboxStore,
  ],
)
class SnowDatabase extends _$SnowDatabase {
  SnowDatabase(super.e);

  @override
  int get schemaVersion => 18;

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
        if (from < 10) {
          // V1 reply-quote fix (2026-05-08) — replyToPreview and
          // replyToSenderId were carried in the encrypted payload and
          // populated on the in-memory Message, but the drift insert
          // paths only stored replyToId. The quote bubble checks
          // `replyToPreview != null` to render, so once drift's watch
          // stream replaced the in-memory message with the persisted
          // version the quote text disappeared. These two nullable
          // columns let the persist / read paths actually round-trip
          // the data.
          await m.addColumn(localMessages, localMessages.replyToPreview);
          await m.addColumn(localMessages, localMessages.replyToSenderId);
        }
        if (from < 11) {
          // Group protocol v2: the state of v2 groups on this device (master
          // key, the last verified point of the change log, members, pending
          // invites). Written only through Gv2Store.
          await m.createTable(gv2Groups);
          await m.createTable(gv2Members);
          await m.createTable(gv2Pending);
          await m.createIndex(idxGv2MembersSnow);
          // What this device holds to act in those groups without a login.
          await m.createTable(gv2ServerKeys);
          await m.createTable(gv2AuthCredentials);
          await m.createTable(gv2Endorsements);
          // The local inbox: envelopes taken off the server queue that wait
          // here to be handled, and digests of the handled ones. Written
          // only through Gv2InboxStore.
          await m.createTable(gv2InboxRows);
          await m.createIndex(idxGv2InboxLane);
          await m.createTable(gv2Seen);
          await m.createIndex(idxGv2SeenRow);
          // Pairwise messages: the verified points of each log (Gv2Store),
          // the v4 Sender Keys and the keys given to each member
          // (Gv2SenderKeyStore), and what waits to be sent (Gv2OutboxStore).
          await m.createTable(gv2Heads);
          await m.createTable(gv2SenderKeys);
          await m.createTable(gv2KeyDeliveries);
          await m.createTable(gv2OutboxRows);
          // Group messages already handled, by local message id
          // (Gv2InboxStore).
          await m.createTable(gv2MessageIds);
        }
        if (from < 12) {
          // Group protocol v2 backup of the group keys: what this device
          // knows of the server's copy, and — per group — whether a group
          // restored from it still has to announce that its keys are gone.
          // (A database below v11 got the column with the table just above.)
          await m.createTable(gv2BackupStates);
          if (from == 11) {
            await m.addColumn(gv2Groups, gv2Groups.resetPending);
          }
        }
        if (from < 13) {
          // Group protocol v2: a change of this device whose answer never
          // came. (A database below v11 got the column with the table.)
          if (from >= 11) {
            await m.addColumn(gv2Groups, gv2Groups.changeSentAtMs);
          }
        }
        if (from < 14) {
          // v1 groups are gone (2026-11-20). A conversation id is now one of
          // two things: the peer's snowId (a 1:1 room) or a group protocol
          // v2 group id. Every other conversation — v1 groups and community
          // rooms (server CUIDs), legacy CUID-keyed 1:1 rooms, an old group
          // row mis-typed as 'direct' that could capture 1:1 routing — goes,
          // with its messages and their attachment rows. Attachment files on
          // disk are not touched (orphans, gone with a reinstall).
          final keepMessage = keptConversationIdSql('conversation_id');
          await customStatement(
            'DELETE FROM local_attachments WHERE message_id IN '
            '(SELECT id FROM local_messages WHERE NOT ($keepMessage))',
          );
          await customStatement(
            'DELETE FROM local_messages WHERE NOT ($keepMessage)',
          );
          await customStatement(
            'DELETE FROM conversations WHERE NOT (${keptConversationIdSql('id')})',
          );
        }
        if (from < 15 && to >= 15) {
          // Group protocol v2: when the delayed write of the backup is due,
          // when a point of a log was stored (old ones are pruned), when this
          // device made its own Sender Key (it is replaced after a while).
          // (A database below v12 / v11 got the columns with the tables.)
          // Bounded by [to] too: the schema tests upgrade to earlier
          // versions.
          if (from >= 12) {
            await m.addColumn(gv2BackupStates, gv2BackupStates.writeDueAtMs);
          }
          if (from >= 11) {
            await m.addColumn(gv2Heads, gv2Heads.storedAtMs);
            await m.addColumn(gv2Groups, gv2Groups.myKeyAtMs);
          }
        }
        if (from < 16 && to >= 16) {
          // X1: the accounts this user blocked, kept on this device.
          await m.createTable(blockedAccounts);
        }
        if (from < 17 && to >= 17) {
          // The 1:1 outbox: a message is sent (and sent again) by a job that
          // outlives the chat screen; the receiver stores a message sent
          // twice once, by the sender's own id for it.
          await m.createTable(directOutboxJobs);
          await m.createIndex(idxDirectOutboxPeer);
          await m.addColumn(localMessages, localMessages.peerClientId);
          await m.createIndex(idxMessagesPeerClient);
        }
        if (from < 18 && to >= 18) {
          // The friend list moves to this device (design 2026-11-22): the
          // one-sided contact list, the names learned from name
          // certificates, and the contact backup state. The old contacts
          // table was never written: it goes. A blocked account keeps its
          // name (a database below v16 got the column with the table).
          await m.deleteTable('contacts');
          await m.createTable(contactList);
          await m.createTable(peerNames);
          await m.createTable(contactSyncStates);
          if (from >= 16) {
            await m.addColumn(blockedAccounts, blockedAccounts.nickname);
          }
          // An install upgraded in place has no contact backup: it never
          // restores (taking "no backup" for a restore would tell the user
          // nothing could be restored). Its block list goes to the server as a
          // whole on the first sync (design §5.10).
          final now = DateTime.now().millisecondsSinceEpoch;
          final period = drawContactWritePeriodMs();
          await into(contactSyncStates).insert(ContactSyncStatesCompanion.insert(
            slot: const Value(0),
            restored: const Value(true),
            periodMs: period,
            nextWriteAtMs: now + period,
            blocksReplacePending: const Value(true),
          ));
        }
        debugPrint('[Perf] 💾 drift onUpgrade complete: ${sw.elapsedMilliseconds}ms');
      },
    );
  }

  /// SQL condition: [column] holds a conversation id that is still valid —
  /// a peer's snowId ("snow" + 32 lowercase hex) or a group protocol v2 group
  /// id (64 lowercase hex). GLOB is case-sensitive, so upper-case hex is not
  /// kept either. Used by the v14 cleanup.
  @visibleForTesting
  static String keptConversationIdSql(String column) =>
      "(length($column) = 36 AND substr($column, 1, 4) = 'snow' "
      "AND substr($column, 5) NOT GLOB '*[^0-9a-f]*') "
      "OR (length($column) = 64 AND $column NOT GLOB '*[^0-9a-f]*')";

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
