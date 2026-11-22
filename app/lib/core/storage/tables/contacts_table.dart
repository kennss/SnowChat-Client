/// @file        contacts_table.dart
/// @description The friend list on this device (schema v18 — design
///              Documentation/TO-DO/2026-11-22-friend-graph-off-server-design.md §5.1): a
///              one-sided contact list per account. The server holds no friend relation; what
///              a row says comes from this user's actions (inMyList, hiddenAtMs) and from the
///              peer's sealed notices (addedMe). Also the names learned from name certificates
///              (any peer, not only contacts) and the state of the contact backup.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (v18, before its release: ContactList.removedMeAtMs — a contact_removed
///              received on this install, so a later restore does not bring back the backup's
///              addedMe; ContactSyncStates.restoreUnreadable — the server's backup did not open,
///              nothing was restored or overwritten). Earlier 2026-11-22 (v18, before its release: ContactList.notFoundCount — "Account
///              unavailable"; ContactSyncStates.restoreNoticeDue / restoreSavedAtMs — the one-time
///              restore notice). Earlier 2026-11-22 (v18: the unused Contacts table is replaced by
///              ContactList, PeerNames and ContactSyncStates). Earlier 2026-04-26 (header English
///              translation)
///
/// @functions
///  - ContactList: one row per account in this user's list or that added this user
///    (data class ContactRow)
///  - PeerNames: per peer, the newest verified name certificate received and the newest
///    of this account's own certificates announced to it (data class PeerNameRow)
///  - ContactSyncStates: the single row of the contact backup / block replace / own name
///    certificate state (data class ContactSyncStateRow)
///
/// Notes:
///  - Times are this device's clock in Unix milliseconds, except nameIssuedAtMs /
///    issuedAtMs (the server's issue time inside a name certificate).
///  - accountPub is the peer's 32-byte account public key, stored only after it was checked
///    to derive the snowId (IdentityBindingV1.accountKeyMatchesSnowId).
///  - The peer's server-internal id (CUID) is never stored.
library;

import 'package:drift/drift.dart';

@DataClassName('ContactRow')
class ContactList extends Table {
  @override
  String get tableName => 'contact_list';

  /// The account ("snow" + 32 hex).
  TextColumn get snowId => text().withLength(min: 36, max: 36)();

  /// This user added the account: sent a request, or accepted the account's.
  BoolColumn get inMyList => boolean().withDefault(const Constant(false))();

  /// The account told this user it added them (a sealed contact_added). Opens
  /// nothing — it only changes the label.
  BoolColumn get addedMe => boolean().withDefault(const Constant(false))();

  /// When this user declined the account's request (the row is hidden), or
  /// null. A new contact_added from the account shows the request again.
  IntColumn get hiddenAtMs => integer().nullable()();

  /// The name from the newest verified name certificate, or null.
  TextColumn get nickname => text().nullable()();

  /// Issue time of that certificate (server clock, ms), or null.
  IntColumn get nameIssuedAtMs => integer().nullable()();

  /// The account public key (32 bytes) that derives [snowId], or null.
  BlobColumn get accountPub => blob().nullable()();

  /// Sends to the account the server refused in a row with USER_NOT_FOUND
  /// (reset by a send it took, or by a notice from the account). From
  /// ContactStore.unavailableAfterFailures on, the list shows "Account
  /// unavailable" — the row itself is never removed on the server's word.
  /// Kept on this device only (not in the backup).
  IntColumn get notFoundCount => integer().withDefault(const Constant(0))();

  /// When the account last told this install it removed this user (a sealed
  /// contact_removed), or null — cleared by a later contact_added. The
  /// restore merge reads it: the peer's word on this install is newer than
  /// the backup's addedMe, and a live addedMe=false without it only means "no
  /// word yet". Before the restore of this install ran, a row whose only mark
  /// is this one is kept for it (afterwards such a row goes). Kept on this
  /// device only (not in the backup).
  IntColumn get removedMeAtMs => integer().nullable()();

  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {snowId};
}

@DataClassName('PeerNameRow')
class PeerNames extends Table {
  @override
  String get tableName => 'peer_names';

  /// The peer ("snow" + 32 hex).
  TextColumn get peer => text().withLength(min: 36, max: 36)();

  /// The name of the newest verified certificate the peer sent (null: the
  /// account has no name), or null when none was received.
  TextColumn get name => text().nullable()();

  /// Issue time of that certificate (server clock, ms), or null when none was
  /// received.
  IntColumn get issuedAtMs => integer().nullable()();

  /// Issue time of the newest certificate of this account the server took on
  /// its way to the peer, or null when none was announced yet.
  IntColumn get announcedIssuedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {peer};
}

@DataClassName('ContactSyncStateRow')
class ContactSyncStates extends Table {
  @override
  String get tableName => 'contact_sync_state';

  /// Always 0: one row.
  IntColumn get slot => integer()();

  /// True once this install looked at the contact backup (restored from it,
  /// or found none, or wrote the empty one of a new account). Once.
  BoolColumn get restored => boolean().withDefault(const Constant(false))();

  /// The server's tag of the blob this device last wrote or read (base64 of
  /// its SHA-256); null when the server holds none.
  TextColumn get etag => text().nullable()();

  /// This install's write period (ms), drawn once between 6 and 24 hours.
  IntColumn get periodMs => integer()();

  /// When the next periodic write is due (local clock, ms).
  IntColumn get nextWriteAtMs => integer()();

  /// The server's block tags must be replaced by this device's list
  /// (POST /users/blocks/replace): true at first launch and after a restore.
  BoolColumn get blocksReplacePending =>
      boolean().withDefault(const Constant(true))();

  /// The server's block tag key version last seen in a block / unblock /
  /// replace answer, or null. When an answer shows another version, the
  /// tags are replaced by this device's list once (§5.9).
  IntColumn get blockKeyVersion => integer().nullable()();

  /// This account's own name certificate (bytes as the server issued them),
  /// or null when none was fetched yet.
  BlobColumn get ownNameCert => blob().nullable()();

  /// When [ownNameCert] was fetched (local clock, ms), or null.
  IntColumn get ownNameCertAtMs => integer().nullable()();

  /// The restore of this install ran and the user was not told yet what it
  /// found (the notice of §5.10 — shown once, even after an app restart).
  BoolColumn get restoreNoticeDue =>
      boolean().withDefault(const Constant(false))();

  /// When the restored backup was written (its writer's clock, ms); null
  /// when the restore found no backup.
  IntColumn get restoreSavedAtMs => integer().nullable()();

  /// The server holds a backup this account could not open (another key, or
  /// altered bytes): nothing was restored, the server's block tags were not
  /// replaced and no backup is written over it — [restored] stays false and
  /// every sync tries again; the user is told (§5.10).
  BoolColumn get restoreUnreadable =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {slot};
}
