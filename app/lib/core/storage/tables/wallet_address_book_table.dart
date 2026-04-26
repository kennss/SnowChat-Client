/// @file        wallet_address_book_table.dart
/// @description Drift wallet address book table — Phase 6.1 §3.5.
///              User-saved transfer targets (label + Solana address). Used for
///              suggestion and prefill on the transfer screen.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-08)
///
/// @functions
///  - WalletAddressBook: drift address book table

import 'package:drift/drift.dart';

/// Wallet address book — Phase 6.1 §3.5.
class WalletAddressBook extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get ownerAddress => text()(); // which wallet's address book this row belongs to
  TextColumn get label => text()();
  TextColumn get address => text()();
  TextColumn get network => text().withDefault(const Constant('mainnet'))();
  TextColumn get note => text().nullable()();
  IntColumn get createdAtMs => integer()();
  IntColumn get lastUsedMs => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {ownerAddress, address},
      ];
}
