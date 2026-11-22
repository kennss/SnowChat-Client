/// @file        contact_dao.dart
/// @description The rows of the friend list (ContactList), of the names learned from name
///              certificates (PeerNames) and of the contact sync state (ContactSyncStates).
///              Written only through ContactStore, NameCertService and ContactBackup
///              (core/contacts/) — the rules live there, this file only reads and writes rows.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (ensureSyncState(restored:) — the v17 → v18 upgrade makes the row as
///              restored; deleteTombstones() — the rows whose only mark was a contact_removed; the new
///              restoreUnreadable column). Earlier 2026-11-22 (watchSyncState(); patchSyncState() — a write of some columns of the
///              sync state only, so writers that do not share a queue (the name certificate, the
///              backup) never put back a column another one changed meanwhile)
///
/// @functions
///  - ContactDao.watchAll() / allRows() / row(): contact rows
///  - ContactDao.putRow() / deleteRow(): write or remove one contact row
///  - ContactDao.peerName() / allPeerNames() / putPeerName(): per-peer name certificate state
///  - ContactDao.accountsNamed(): the accounts known here under a name (contact rows, certificates)
///  - ContactDao.deleteTombstones(): drop the rows that hold neither mark (kept only until the
///    restore of this install ran)
///  - ContactDao.syncState() / putSyncState() / ensureSyncState(): the single contact sync
///    state row
///  - ContactDao.watchSyncState(): that row, each time it changes
///  - ContactDao.patchSyncState(): write some columns of that row only
library;

import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/contacts_table.dart';

part 'contact_dao.g.dart';

@DriftAccessor(tables: [ContactList, PeerNames, ContactSyncStates])
class ContactDao extends DatabaseAccessor<SnowDatabase> with _$ContactDaoMixin {
  ContactDao(super.db);

  /// Every contact row, by snowId, each time one changes.
  Stream<List<ContactRow>> watchAll() =>
      (select(contactList)..orderBy([(c) => OrderingTerm.asc(c.snowId)]))
          .watch();

  /// Every contact row, by snowId.
  Future<List<ContactRow>> allRows() =>
      (select(contactList)..orderBy([(c) => OrderingTerm.asc(c.snowId)])).get();

  Future<ContactRow?> row(String snowId) =>
      (select(contactList)..where((c) => c.snowId.equals(snowId)))
          .getSingleOrNull();

  /// Insert [row], or replace the row of its snowId — every column, a null
  /// included (a data class alone would leave a column it holds as null
  /// untouched on the update).
  Future<void> putRow(ContactRow row) =>
      into(contactList).insertOnConflictUpdate(row.toCompanion(false));

  Future<void> deleteRow(String snowId) =>
      (delete(contactList)..where((c) => c.snowId.equals(snowId))).go();

  /// Remove every row that holds neither mark (a contact_removed kept for
  /// the restore of this install — ContactList.removedMeAtMs).
  Future<int> deleteTombstones() => (delete(contactList)
        ..where((c) => c.inMyList.equals(false) & c.addedMe.equals(false)))
      .go();

  /// The accounts this device knows under [name] (case-insensitive): contact
  /// rows and names from certificates.
  Future<Set<String>> accountsNamed(String name) async {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return const {};
    final contacts = await (select(contactList)
          ..where((c) => c.nickname.lower().equals(lower)))
        .get();
    final peers = await (select(peerNames)
          ..where((p) => p.name.lower().equals(lower)))
        .get();
    return {
      for (final c in contacts) c.snowId,
      for (final p in peers) p.peer,
    };
  }

  /// Every per-peer name row.
  Future<List<PeerNameRow>> allPeerNames() => select(peerNames).get();

  Future<PeerNameRow?> peerName(String peer) =>
      (select(peerNames)..where((p) => p.peer.equals(peer))).getSingleOrNull();

  Future<void> putPeerName(PeerNameRow row) =>
      into(peerNames).insertOnConflictUpdate(row.toCompanion(false));

  Future<ContactSyncStateRow?> syncState() =>
      select(contactSyncStates).getSingleOrNull();

  /// The sync state row, made on first use: the write period [periodMs]
  /// (drawn once per install by the caller) and the first periodic write one
  /// period after [nowMs]; block replace pending, nothing restored — unless
  /// [restored] (an install upgraded in place: it has no backup to restore,
  /// design §5.10).
  Future<ContactSyncStateRow> ensureSyncState({
    required int periodMs,
    required int nowMs,
    bool restored = false,
  }) =>
      transaction(() async {
        final existing = await syncState();
        if (existing != null) return existing;
        final row = ContactSyncStateRow(
          slot: 0,
          restored: restored,
          etag: null,
          periodMs: periodMs,
          nextWriteAtMs: nowMs + periodMs,
          blocksReplacePending: true,
          blockKeyVersion: null,
          ownNameCert: null,
          ownNameCertAtMs: null,
          restoreNoticeDue: false,
          restoreSavedAtMs: null,
          restoreUnreadable: false,
        );
        await into(contactSyncStates).insert(row);
        return row;
      });

  Future<void> putSyncState(ContactSyncStateRow row) =>
      into(contactSyncStates).insertOnConflictUpdate(row.toCompanion(false));

  /// The sync state row (null before it is made), each time it changes.
  Stream<ContactSyncStateRow?> watchSyncState() =>
      select(contactSyncStates).watchSingleOrNull();

  /// Write only the columns [patch] holds (the row must exist — see
  /// [ensureSyncState]). The other columns keep whatever they hold now.
  Future<void> patchSyncState(ContactSyncStatesCompanion patch) =>
      (update(contactSyncStates)..where((s) => s.slot.equals(0))).write(patch);
}
