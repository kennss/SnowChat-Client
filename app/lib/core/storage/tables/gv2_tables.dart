/// @file        gv2_tables.dart
/// @description Drift tables holding the state of group protocol v2 groups on
///              this device (schema v11): one row per group with its master
///              key and the last verified point of its change log, one row
///              per member, one row per pending invite; and what this device
///              holds to act in those groups without a login — the server's
///              public keys, this account's daily auth credentials and the
///              per-member send endorsements. Written only through Gv2Store
///              (core/group_v2/gv2_store.dart), which keeps the tables
///              consistent inside one transaction. And the local inbox:
///              envelopes taken off the server queue (acknowledged at once)
///              that wait here to be handled, and the digests of the ones
///              already handled — written only through Gv2InboxStore
///              (core/group_v2/gv2_inbox_store.dart). And what pairwise
///              messages need: the points of each log this device verified
///              (Gv2Store), the v4 Sender Keys with the keys given to each
///              member (Gv2SenderKeyStore, core/group_v2/
///              gv2_sender_key_store.dart), and the outbox (Gv2OutboxStore,
///              core/group_v2/gv2_outbox.dart). And the ids of the group
///              messages already handled (Gv2InboxStore).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (gv2_heads.stored_at_ms, gv2_groups.my_key_at_ms; P5.6: gv2_backup_state.write_due_at_ms — the delayed backup write). Earlier 2026-11-21 (Gv2InboxKind.invite — an invite kept before its 1:1 message is acknowledged). Earlier 2026-11-20 (schema v13: Gv2Groups.changeSentAtMs)
///
/// @functions
///  - Gv2Groups: one row per group (data class Gv2GroupRow)
///  - Gv2Members: one row per member (data class Gv2MemberRow)
///  - Gv2Pending: one row per pending invite (data class Gv2PendingRow)
///  - Gv2ServerKeys: the server's public keys (data class Gv2ServerKeysRow)
///  - Gv2AuthCredentials: one credential per day (Gv2AuthCredentialRow)
///  - Gv2Endorsements: one endorsement per member (Gv2EndorsementRow)
///  - Gv2InboxRows: one row per received envelope not handled yet (table
///    gv2_inbox, Gv2InboxRow)
///  - Gv2Seen: one row per envelope handled or dropped (Gv2SeenRow)
///  - Gv2Heads: one row per verified point of a log (table gv2_heads)
///  - Gv2SenderKeys: one Sender Key record per (group, sender)
///  - Gv2KeyDeliveries: the key given to a member, per own chain
///  - Gv2OutboxRows: one row per message waiting to be sent (gv2_outbox)
///  - Gv2MessageIds: the group messages already handled (gv2_message_ids)
///  - Gv2BackupStates: what this device knows of its backup (gv2_backup_state)
///  - Gv2Membership / Gv2Hold / Gv2MemberCheckState / Gv2Reach /
///    Gv2InboxKind / Gv2InboxState / Gv2OutboxKind: stored enums
///
/// Notes:
///  - The master key lives in this (SQLCipher-encrypted) database, not in
///    secure storage: the key and the state it belongs to must change in one
///    transaction (design document §11.2).
///  - Identifiers are lowercase hex TEXT: groupId is 64 characters and is also
///    the id of the group's conversation; a member ciphertext is 130
///    characters (the key of the state maps in gv2_codec.dart). Keys, hashes,
///    signatures and payloads are BLOBs.
///  - The enums are stored BY NAME (drift textEnum). Renaming a value is a
///    schema change and needs a migration.
///  - There are no foreign keys (the database does not enable them);
///    Gv2Store deletes dependent rows itself.
///  - Local times (lastSyncAtMs) are this device's clock in milliseconds and
///    never leave the device.
///  - Credential and endorsement times (redemptionTime, expiration) are epoch
///    SECONDS and day-aligned, as zkgroup uses them.
///  - Inbox times (receivedAtMs) are this device's clock in milliseconds;
///    Gv2Seen.day is the local epoch DAY the envelope was handled.
library;

import 'package:drift/drift.dart';

/// Where this account stands in a group.
enum Gv2Membership {
  /// This device made the group and has not yet seen the server accept it:
  /// the revision-0 entry waits in the outbox. The row holds the state that
  /// entry gives (its chain and state hash are known before the server
  /// answers), but no head signature. Nothing is sent or received.
  creating,

  /// Invited over 1:1; neither accepted nor declined yet.
  invited,

  /// A member by the log (accepted, or restored from the backup), but no
  /// confirmed member has yet vouched for the head of the log. Nothing is
  /// sent and no Sender Key is distributed in this state (design §5.5).
  awaitingConfirm,

  /// A member, sending and receiving.
  active,

  /// This account left.
  left,

  /// This account was removed by an admin.
  removed,

  /// This account declined the invite, or the invite was revoked.
  declined,

  /// The group itself ended (deleted by its owner, or the last member left).
  ended,
}

/// A condition that stops normal use of a group whatever the membership.
enum Gv2Hold {
  none,

  /// The server signed two different logs for this group. Read-only; the
  /// only way out is to leave (design §5.5).
  frozen,

  /// The log uses a protocol version or an action this build does not know.
  /// Not a security event: the app has to be updated.
  updateRequired,

  /// A member showed a head of the log signed by the server that is beyond
  /// what the server serves this device: changes are being withheld. This
  /// device no longer knows who is in the group, so it sends neither
  /// messages nor Sender Keys until a sync reaches that head (which releases
  /// the hold). Receiving goes on.
  withheld,
}

/// Outcome of confirming the account behind a member (gv2_member_check.dart).
enum Gv2MemberCheckState {
  /// Not checked yet.
  unchecked,

  /// The account is confirmed. Only these members receive anything.
  confirmed,

  /// The member ciphertext does not decrypt to an account id.
  ciphertext,

  /// The member payload does not open.
  payload,

  /// The account key does not belong to the account id.
  accountId,

  /// A different account key is already pinned for this snowId.
  pinnedKey,

  /// The member certificate does not verify.
  certificate,
}

/// Whether messages to a member arrive.
enum Gv2Reach {
  ok,

  /// The server does not know the account and showed no deletion proof.
  unreachable,

  /// The account's own deletion proof was verified.
  deleted,
}

/// What a received envelope is, by its first byte.
enum Gv2InboxKind {
  /// 0x02: a group envelope (gv2_envelope.dart), opened with a group key.
  group,

  /// 0x01: a sealed sender envelope addressed to this account alone (SKDM,
  /// head confirmation, ...), carried by the group queue (design §7.2).
  pairwise,

  /// An invite message that came on the 1:1 sealed path, already decrypted
  /// there: payload = the certified sender's snowId (36 ASCII) ‖ the invite
  /// bytes. Stored by the 1:1 queue BEFORE it acknowledges the message, so
  /// an invite is kept whether or not the group runtime is up (P5.6).
  invite,
}

/// Where a received envelope is in its handling.
enum Gv2InboxState {
  /// Stored; its group is not known yet.
  received,

  /// Waiting its turn in its lane.
  ready,

  /// Waits for the Sender Key of [Gv2InboxRows.waitFor] in its group.
  waitingKey,

  /// Waits for this device to catch up with the change log of its group.
  waitingSync,
}

/// What an outbox row is sent as.
enum Gv2OutboxKind {
  /// A pairwise message (gv2_pairwise.dart) for [Gv2OutboxRows.recipient]:
  /// encrypted on the 1:1 session and sealed when it is sent, not when it is
  /// queued, so that a failed send burns no more than a session counter.
  pairwise,

  /// A message of this account to the group (gv2_content.dart), kept as
  /// plaintext: it is encrypted with the Sender Key of the moment it is
  /// sent — a key made before a member was removed never encrypts it.
  content,

  /// "The change log has moved": sent after a change of this account was
  /// accepted. Sealed with the head of the moment it is sent.
  changeNotice,

  /// A notice signed with this account's member signing key (for example
  /// member_reset after a restore).
  memberNotice,

  /// The revision-0 entry of a group this device is creating: submitted to
  /// the server until it is known to be accepted (the answer to a create
  /// request can be lost).
  create,

  /// The 1:1 invite message for [Gv2OutboxRows.recipient]: the one-time
  /// invite key, sent over the 1:1 path (the invitee is no member yet and
  /// cannot be reached through the group queue) together with the group's
  /// master key and this device's head of the moment it is sent.
  invite,
}

@DataClassName('Gv2GroupRow')
class Gv2Groups extends Table {
  /// Lowercase hex of the 32-byte group id; also the conversation id.
  TextColumn get groupId => text().withLength(min: 64, max: 64)();

  /// 32-byte group master key. Key material.
  BlobColumn get masterKey => blob()();

  /// This account's member ciphertext in the group (130 hex characters).
  TextColumn get myCiphertext => text().withLength(min: 130, max: 130)();

  /// Protocol version of the log at [revision].
  IntColumn get protocolVersion => integer()();

  TextColumn get membership => textEnum<Gv2Membership>()();

  TextColumn get hold =>
      textEnum<Gv2Hold>().withDefault(Constant(Gv2Hold.none.name))();

  /// What justified [hold] = frozen (the two signed heads) or withheld (the
  /// signed head the server does not serve), kept as evidence. UTF-8 JSON.
  BlobColumn get holdEvidence => blob().nullable()();

  // --- The anchor: the last point of the log this device trusts. A lower
  //     revision is never accepted again. ---

  IntColumn get revision => integer()();

  /// 32-byte chain hash at [revision].
  BlobColumn get chain => blob()();

  /// 32-byte state hash at [revision].
  BlobColumn get stateHash => blob()();

  /// The server's 64-byte signature over (groupId, revision, chain); null
  /// while the anchor comes from an invite or a backup and nothing has been
  /// fetched yet.
  BlobColumn get headSig => blob().nullable()();

  /// False while the member and pending rows do not yet hold the state that
  /// [stateHash] commits to (a fresh invite, a restore, or a repair).
  BoolColumn get stateLoaded => boolean()();

  // --- Parts of the state that are not per member. ---

  /// The log's own "deleted" flag at [revision].
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Sealed title payload, exactly as in the log (state hash input). Empty
  /// until the state is loaded.
  BlobColumn get titlePayload => blob()();

  /// Group name decoded from [titlePayload]; null when it does not open.
  TextColumn get title => text().nullable()();

  // --- This account in the group. ---

  /// One-time invite private seed (32 bytes) while [membership] is invited.
  BlobColumn get inviteSeed => blob().nullable()();

  /// snowId of whoever sent the 1:1 invite.
  TextColumn get invitedBySnowId => text().nullable()();

  /// Revision at which this device's current Sender Key was made; null when
  /// it has none. A removal after this revision forces a new key before the
  /// next send (design §8).
  IntColumn get myKeyRevision => integer().nullable()();

  /// When this device made its current Sender Key (local clock, ms); null
  /// when it has none. A key older than gv2OwnKeyMaxAge is replaced before
  /// the next message: what a stolen device's keys open of what it sent is
  /// bounded in time, not only by the next removal.
  IntColumn get myKeyAtMs => integer().nullable()();

  /// Revision of the latest change that took a member out of the group (a
  /// removal or a leave), as far as this device has followed the log; null
  /// when there was none. Written with the state, so it survives a crash
  /// between applying the change and making a new Sender Key.
  IntColumn get lastRemovalRevision => integer().nullable()();

  /// True for a group taken from the backup (a reinstall) until this device
  /// has told the group that it lost its Sender Keys (member_reset): the
  /// members then give it their keys again and one of them confirms the
  /// head. Kept here so that the notice is sent even when the restore
  /// happened offline. (Schema v12.)
  BoolColumn get resetPending => boolean().withDefault(const Constant(false))();

  /// When the last sync that reached the server's head STARTED, local clock
  /// milliseconds: whatever the server had accepted before then, this
  /// device has. (A group this device created: when it was created.)
  IntColumn get lastSyncAtMs => integer().withDefault(const Constant(0))();

  /// When this device sent a change of its own whose outcome it has not
  /// learned (local clock milliseconds); null when there is none. Set before
  /// the request goes out and cleared by its answer, or by a sync that
  /// started after it: until then this device may not know a change the
  /// server already took — its own removal of a member — and a message
  /// syncs before it goes. (Schema v13.)
  IntColumn get changeSentAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {groupId};
}

@DataClassName('Gv2MemberRow')
@TableIndex(name: 'idx_gv2_members_snow', columns: {#groupId, #snowId})
class Gv2Members extends Table {
  TextColumn get groupId => text().withLength(min: 64, max: 64)();

  /// Member ciphertext, 130 hex characters.
  TextColumn get ciphertext => text().withLength(min: 130, max: 130)();

  // --- From the log (exactly Gv2MemberState). ---

  /// 0 member, 1 admin, 2 owner.
  IntColumn get role => integer()();

  /// 32-byte member signing public key.
  BlobColumn get memberPub => blob()();

  IntColumn get joinedRevision => integer()();

  /// Sealed member payload, exactly as in the log (state hash input).
  BlobColumn get memberPayload => blob()();

  // --- Worked out by this device. ---

  TextColumn get checkState => textEnum<Gv2MemberCheckState>()
      .withDefault(Constant(Gv2MemberCheckState.unchecked.name))();

  /// The account the ciphertext decrypts to; null until it has been
  /// decrypted. Known even when the check then fails.
  TextColumn get snowId => text().nullable()();

  /// Confirmed 32-byte account public key; set only when confirmed.
  BlobColumn get accountPublicKey => blob().nullable()();

  /// Time of the member certificate, Unix milliseconds; set only when
  /// confirmed. A deletion proof is compared with it.
  IntColumn get certIssuedAtMs => integer().nullable()();

  TextColumn get reach =>
      textEnum<Gv2Reach>().withDefault(Constant(Gv2Reach.ok.name))();

  /// Nickname looked up from the server (display only, never identity).
  TextColumn get nickname => text().nullable()();

  /// Local day number (days since the epoch) of the last nickname lookup.
  IntColumn get nicknameFetchedDay => integer().nullable()();

  @override
  Set<Column> get primaryKey => {groupId, ciphertext};
}

@DataClassName('Gv2PendingRow')
class Gv2Pending extends Table {
  TextColumn get groupId => text().withLength(min: 64, max: 64)();

  /// Ciphertext of the invited account, 130 hex characters.
  TextColumn get ciphertext => text().withLength(min: 130, max: 130)();

  // --- From the log (exactly Gv2PendingState). ---

  /// Ciphertext of the member who invited, 130 hex characters.
  TextColumn get invitedBy => text().withLength(min: 130, max: 130)();

  /// 32-byte one-time invite public key.
  BlobColumn get invitePub => blob()();

  /// Revision of the INVITE.
  IntColumn get revision => integer()();

  // --- Worked out by this device. ---

  /// The account the ciphertext decrypts to; null until decrypted.
  TextColumn get snowId => text().nullable()();

  @override
  Set<Column> get primaryKey => {groupId, ciphertext};
}

/// The server's public keys, as this device last fetched them. One row.
@DataClassName('Gv2ServerKeysRow')
class Gv2ServerKeys extends Table {
  /// Always 0: there is one server.
  IntColumn get slot => integer()();

  /// zkgroup server public parameters: credentials and endorsements are
  /// verified against them, presentations are made for them.
  BlobColumn get serverPublicParams => blob()();

  /// 32-byte Ed25519 key the server signs log heads with.
  BlobColumn get headPublicKey => blob()();

  @override
  Set<Column> get primaryKey => {slot};
}

/// This account's auth credentials, one per day. A credential proves "some
/// account the server issued a credential to" without naming it.
@DataClassName('Gv2AuthCredentialRow')
class Gv2AuthCredentials extends Table {
  /// Start of the UTC day the credential is for, epoch seconds.
  IntColumn get redemptionTime => integer()();

  /// The account the credential was issued to. Rows of another account are
  /// never used and are erased when this account stores its own.
  TextColumn get snowId => text()();

  /// The verified credential. Key material.
  BlobColumn get credential => blob()();

  @override
  Set<Column> get primaryKey => {redemptionTime};
}

/// Send endorsements: one per member of a group, verified against this
/// device's own view of the members. Combined into a send token for any
/// subset of them.
@DataClassName('Gv2EndorsementRow')
class Gv2Endorsements extends Table {
  TextColumn get groupId => text().withLength(min: 64, max: 64)();

  /// Member ciphertext, 130 hex characters.
  TextColumn get ciphertext => text().withLength(min: 130, max: 130)();

  /// 33-byte endorsement.
  BlobColumn get endorsement => blob()();

  /// When it stops verifying, epoch seconds (day-aligned).
  IntColumn get expiration => integer()();

  @override
  Set<Column> get primaryKey => {groupId, ciphertext};
}

/// Envelopes taken off the server queue and not handled yet. The server row
/// is acknowledged (deleted) as soon as the envelope is stored here, so an
/// envelope that waits — for a Sender Key, for the change log — waits on
/// this device, not on the server (design §7.4).
@DataClassName('Gv2InboxRow')
@TableIndex(name: 'idx_gv2_inbox_lane', columns: {#groupId, #state})
class Gv2InboxRows extends Table {
  @override
  String get tableName => 'gv2_inbox';

  /// Arrival order on this device: the order rows are handled in. (The
  /// server's sequence number restarts when the queue empties, so it orders
  /// only the rows of one fetch.)
  IntColumn get localId => integer().autoIncrement()();

  /// The server queue row it came in (a UUID). A push notification names
  /// this id.
  TextColumn get serverRowId => text()();

  /// SHA-256 of the envelope as received. The same envelope stored twice —
  /// redelivered after a lost acknowledgement, or replayed — is one row.
  BlobColumn get digest => blob().unique()();

  TextColumn get kind => textEnum<Gv2InboxKind>()();

  /// The received envelope; or, once [unsealed], what its handler kept of
  /// it (a pairwise envelope can be decrypted only once, so a handler that
  /// has to wait keeps the decrypted form). Message content: never log it.
  BlobColumn get payload => blob()();

  BoolColumn get unsealed => boolean().withDefault(const Constant(false))();

  /// The group it belongs to (lowercase hex), once known. Rows of one group
  /// are handled one at a time, in [localId] order.
  TextColumn get groupId => text().withLength(min: 64, max: 64).nullable()();

  TextColumn get state => textEnum<Gv2InboxState>()();

  /// The sender (snowId) whose Sender Key a [Gv2InboxState.waitingKey] row
  /// waits for.
  TextColumn get waitFor => text().nullable()();

  IntColumn get receivedAtMs => integer()();

  /// Failed handling attempts (the handler threw). The row is dropped after
  /// a few.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// Envelopes already handled (or dropped), so that one coming again is not
/// handled twice. Kept for as long as the server can still hand out a row
/// (design §7.3: at most 30 days), then pruned.
@DataClassName('Gv2SeenRow')
@TableIndex(name: 'idx_gv2_seen_row', columns: {#serverRowId})
class Gv2Seen extends Table {
  /// SHA-256 of the envelope as received.
  BlobColumn get digest => blob()();

  /// The server queue row it came in.
  TextColumn get serverRowId => text()();

  /// The conversation it was shown in, when it was shown — what a tap on its
  /// push notification opens.
  TextColumn get conversationId => text().nullable()();

  /// Local epoch day it was handled.
  IntColumn get day => integer()();

  @override
  Set<Column> get primaryKey => {digest};
}

/// Points of a group's change log that this device verified: the chain at
/// each revision it applied. A member's view of the log (a head
/// confirmation, the revision and chain in an envelope header) is compared
/// with the chain this device holds AT THAT revision, which may be behind
/// its own head. Written by Gv2Store together with the anchor.
@DataClassName('Gv2HeadRow')
class Gv2Heads extends Table {
  @override
  String get tableName => 'gv2_heads';

  TextColumn get groupId => text().withLength(min: 64, max: 64)();
  IntColumn get revision => integer()();
  BlobColumn get chain => blob()();

  /// The server's signature over this point, when this device verified one
  /// (the last entry of each stored batch, the anchor of a snapshot, the
  /// head of a group it created). Null for the points in between.
  BlobColumn get headSig => blob().nullable()();

  /// When this device stored the point (local clock, ms). A point other than
  /// the group's current one is pruned once it is older than an envelope
  /// can be (Gv2Store.pruneOld): the table grew with every revision.
  IntColumn get storedAtMs => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {groupId, revision};
}

/// Sender Keys of v2 groups (wire format v4): this device's own, and the
/// ones members gave it. One row per (group, sender); the record holds up to
/// five chains of that sender. Kept in this database, not in the session
/// store file, so that installing a key or moving a chain commits together
/// with the inbox row that caused it.
@DataClassName('Gv2SenderKeyRow')
class Gv2SenderKeys extends Table {
  @override
  String get tableName => 'gv2_sender_keys';

  TextColumn get groupId => text().withLength(min: 64, max: 64)();

  /// The sender's snowId.
  TextColumn get sender => text().withLength(min: 36, max: 36)();

  /// SenderKeyRecord.toJson() as UTF-8. Key material: never log it.
  BlobColumn get record => blob()();

  @override
  Set<Column> get primaryKey => {groupId, sender};
}

/// The Sender Key this device gave a member, per chain of its own key: the
/// exact key (chain id, position, chain key, signing key) — the position it
/// was given from cannot be derived again once the chain has moved on. A
/// member who asks again gets the same key, never an earlier position.
@DataClassName('Gv2KeyDeliveryRow')
class Gv2KeyDeliveries extends Table {
  @override
  String get tableName => 'gv2_key_deliveries';

  TextColumn get groupId => text().withLength(min: 64, max: 64)();

  /// The member's snowId.
  TextColumn get member => text().withLength(min: 36, max: 36)();
  IntColumn get chainId => integer()();

  /// The Sender Key body of the pairwise message (gv2_pairwise.dart). Key
  /// material: never log it.
  BlobColumn get key => blob()();

  /// Local clock, milliseconds.
  IntColumn get deliveredAtMs => integer()();

  @override
  Set<Column> get primaryKey => {groupId, member, chainId};
}

/// What waits to be sent: kept here so that a crash or a lost connection
/// does not lose it, and so that it can wait (for an endorsement, for this
/// device's membership to be confirmed) without anyone holding it in memory.
@DataClassName('Gv2OutboxRow')
class Gv2OutboxRows extends Table {
  @override
  String get tableName => 'gv2_outbox';

  /// Queue order: rows are sent in this order.
  IntColumn get localId => integer().autoIncrement()();

  TextColumn get groupId => text().withLength(min: 64, max: 64)();
  TextColumn get kind => textEnum<Gv2OutboxKind>()();

  /// The recipient's snowId (pairwise and invite rows); null for a row
  /// that goes to the whole group or to the server.
  TextColumn get recipient => text().withLength(min: 36, max: 36).nullable()();

  /// What is sent, by [kind] (layouts in gv2_outbox.dart):
  ///   pairwise      the plaintext pairwise message
  ///   content       messageId(16) ‖ timestampMs(u64) ‖ expiresIn(u32)
  ///                 ‖ silent(1) ‖ the content plaintext
  ///   changeNotice  empty
  ///   memberNotice  the notice payload
  ///   create        the encoded revision-0 entry
  ///   invite        the 32-byte invite private seed
  /// Message content: never log it.
  BlobColumn get payload => blob()();

  /// Local clock, milliseconds.
  IntColumn get createdAtMs => integer()();

  /// Not sent before this time (a backoff after a failed send).
  IntColumn get notBeforeMs => integer().withDefault(const Constant(0))();

  /// Failed sends so far.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// Messages of v2 groups this device has already handled, by local message
/// id (gv2_envelope.dart gv2LocalMessageId). A sender that could not tell
/// whether a send arrived sends the message again under the same id; the
/// second copy must not show the message again — also not after the first
/// was deleted here (unsent, cleared, expired). Kept as long as a sender can
/// still be retrying (the outbox retention), then pruned.
@DataClassName('Gv2MessageIdRow')
class Gv2MessageIds extends Table {
  @override
  String get tableName => 'gv2_message_ids';

  /// The 32-byte local message id.
  BlobColumn get localMessageId => blob()();

  /// Local epoch day it was handled.
  IntColumn get day => integer()();

  @override
  Set<Column> get primaryKey => {localMessageId};
}

/// What this device knows about the server's copy of its group key backup
/// (design §9.8). One row. (Schema v12.)
@DataClassName('Gv2BackupStateRow')
class Gv2BackupStates extends Table {
  @override
  String get tableName => 'gv2_backup_state';

  /// Always 0: there is one backup per account.
  IntColumn get slot => integer()();

  /// True once this install has taken in what the backup held when it first
  /// looked (a reinstall restores its groups from it — once). From then on
  /// this device's own groups are the truth and the backup follows them.
  BoolColumn get restored => boolean().withDefault(const Constant(false))();

  /// The server's tag of the blob this device last wrote or read (base64 of
  /// its SHA-256); null when the server holds none. A write names it, so a
  /// blob written by anyone else meanwhile is not overwritten blindly.
  TextColumn get etag => text().nullable()();

  /// What the last written list was made from (a hash over the member
  /// groups and what makes an anchor worth renewing): the backup is written
  /// again only when this changes.
  BlobColumn get fingerprint => blob().nullable()();

  /// When the pending write of the backup is due (local clock, ms); null
  /// when none is pending. A write is not made when a group was joined or a
  /// member removed but at a random time one to six hours later, so the
  /// time of a write does not tie this account to a change of a group
  /// (decided 2026-11-21). Stored: an app that is closed often would never
  /// reach a delay kept in memory.
  IntColumn get writeDueAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {slot};
}
