/// @file        wallet_tx_cache_table.dart
/// @description Drift wallet transaction classification cache table — Phase 6.1 §3.2.
///              Only finalized transactions are cached (effectively immutable). The
///              parser_version column triggers re-parsing when the parser changes.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-08)
///
/// @functions
///  - WalletTxCache: drift transaction cache table

import 'package:drift/drift.dart';

/// Transaction classification cache — only finalized signatures are persisted.
class WalletTxCache extends Table {
  TextColumn get signature => text()();
  TextColumn get ownerAddress => text()();

  /// ParsedTxType.name (solSend / solReceive / splSend / splReceive / unknown)
  TextColumn get type => text()();

  /// BigInt as string (lamports for SOL, raw smallest unit for SPL)
  TextColumn get amountLamports => text().nullable()();
  TextColumn get counterparty => text().nullable()();
  TextColumn get tokenMint => text().nullable()();
  TextColumn get feeLamports => text().nullable()();

  IntColumn get blockTime => integer().nullable()();
  IntColumn get parserVersion => integer().withDefault(const Constant(1))();
  IntColumn get cachedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {signature, ownerAddress};
}
