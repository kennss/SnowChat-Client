/// @file        wallet_balances_table.dart
/// @description Drift wallet balance cache table — Phase 6.1 §3.1.
///              raw_amount is stored as TEXT to preserve BigInt precision.
///              owner + mint composite primary key.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-08)
///
/// @functions
///  - WalletBalances: drift balance cache table

import 'package:drift/drift.dart';

/// Wallet balance cache — Phase 6.1 §3.1.
///
/// `mintAddress` is 'native' for SOL; otherwise the SPL token mint in Base58.
/// `rawAmount` is stored as TEXT to guarantee BigInt precision (CLAUDE.md BigInt-only rule).
class WalletBalances extends Table {
  TextColumn get ownerAddress => text()();
  TextColumn get mintAddress => text()();
  TextColumn get rawAmount => text()(); // BigInt as string — never INTEGER
  IntColumn get decimals => integer()();
  TextColumn get symbol => text()();
  TextColumn get name => text().nullable()();
  TextColumn get logoUrl => text().nullable()();
  IntColumn get lastUpdatedMs => integer()();

  @override
  Set<Column> get primaryKey => {ownerAddress, mintAddress};
}
