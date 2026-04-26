/// @file        address_book_repository.dart
/// @description Wallet address book Repository — thin wrapper over drift
///              `wallet_address_book`. CRUD + last_used update.
///              Phase 6.1 §3.5.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - AddressBookRepository.list(): entry list for owner
///  - AddressBookRepository.add(): add/update new entry
///  - AddressBookRepository.touch(): update last-used timestamp
///  - AddressBookRepository.remove(): delete
library;

import 'package:drift/drift.dart' show Value;

import '../../../core/storage/daos/wallet_address_book_dao.dart';
import '../../../core/storage/database.dart';

class AddressBookEntry {
  const AddressBookEntry({
    required this.id,
    required this.label,
    required this.address,
    required this.network,
    this.note,
    this.lastUsedMs,
  });

  final int id;
  final String label;
  final String address;
  final String network;
  final String? note;
  final int? lastUsedMs;

  factory AddressBookEntry.fromRow(WalletAddressBookData row) {
    return AddressBookEntry(
      id: row.id,
      label: row.label,
      address: row.address,
      network: row.network,
      note: row.note,
      lastUsedMs: row.lastUsedMs,
    );
  }
}

class AddressBookRepository {
  AddressBookRepository(this._dao);

  final WalletAddressBookDao _dao;

  Future<List<AddressBookEntry>> list(String ownerAddress) async {
    final rows = await _dao.list(ownerAddress);
    return rows.map(AddressBookEntry.fromRow).toList();
  }

  Future<void> add({
    required String ownerAddress,
    required String label,
    required String address,
    String network = 'mainnet',
    String? note,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _dao.add(
      WalletAddressBookCompanion.insert(
        ownerAddress: ownerAddress,
        label: label,
        address: address,
        network: Value(network),
        note: Value(note),
        createdAtMs: now,
        lastUsedMs: Value(now),
      ),
    );
  }

  Future<void> touch(int id) => _dao.touch(id);

  Future<void> remove(int id) => _dao.remove(id);
}
