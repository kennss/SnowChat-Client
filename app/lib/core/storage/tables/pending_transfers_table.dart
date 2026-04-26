/// @file        pending_transfers_table.dart
/// @description Wallet V2 Phase 1 — table that persists in-flight tx for in-chat transfers (P0-1, P0-2).
///              Sender side: pending → sent (after broadcast) → completed / failed / timeout.
///              Recipient side: pending → completed (after verification) / failed / timeout.
///              On app restart, TransferService.recoverPending() looks up RPC getSignatureStatus
///              for status='sent' rows → emits transfer_completed retroactively.
///              The replay set is also auto-persisted via requestId in this table.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-20
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-20)
///
/// @functions
///  - PendingTransfers: drift table class (12 columns, primary = requestId)

import 'package:drift/drift.dart';

/// Persists in-flight state for in-chat transfers.
/// Spec: `Documentation/Dev-plan2/Wallet-V2-Phase1-Chat-Transfer.md` §5.8
///
/// Columns:
///  - `requestId` (PK): UUID v4 (identical on both sides)
///  - `role`: 'sender' | 'recipient' — this device's role
///  - `peerSnowchatId`: peer SnowChat ID
///  - `amount`: lamports / raw smallest units (BigInt-safe String)
///  - `token`: 'SOL' | 'SPL' | 'NFT'
///  - `mint`: SPL/NFT mint address (null for SOL)
///  - `decimals`: SOL=9, USDC=6, NFT=0
///  - `network`: 'devnet' | 'mainnet'
///  - `status`: 'pending' | 'sent' | 'completed' | 'failed' | 'timeout'
///  - `signature`: tx signature (set by sender after broadcast)
///  - `createdAt` / `updatedAt`: ms epoch
class PendingTransfers extends Table {
  TextColumn get requestId => text()();

  TextColumn get role => text()();
  TextColumn get peerSnowchatId => text()();

  /// lamports / raw smallest units. BigInt-safe String (no Float).
  TextColumn get amount => text()();
  TextColumn get token => text()();
  TextColumn get mint => text().nullable()();
  IntColumn get decimals => integer()();
  TextColumn get network => text()();

  /// pending | sent | completed | failed | timeout
  TextColumn get status => text()();

  /// Solana tx signature — set by sender after broadcast.
  /// Used by recoverPending() for RPC getSignatureStatus lookup.
  TextColumn get signature => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {requestId};
}
