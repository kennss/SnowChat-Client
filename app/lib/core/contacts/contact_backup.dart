/// @file        contact_backup.dart
/// @description The contact backup (design 2026-11-22-friend-graph-off-server §5.10, contract
///              §12.5): the friend list and the block list, sealed under a key derived from the
///              recovery phrase and kept on the server as one opaque, padded blob, so a reinstall
///              gets them back. Written at a per-install random period between 6 and 24 hours
///              whether or not anything changed (the time of a write must not tell when a
///              contact was added), immediately on a block or an unblock, and empty at sign-up.
///              Restored once on a new install — merged into whatever arrived before it — and
///              then the server's block tags are replaced by this device's list.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (review fixes: every write of the sync state is a patch of its own columns
///              (the name certificate writes the same row); a backup the server holds that does not
///              open is not "no backup" — nothing is restored, replaced or written over it, every sync
///              tries again and the user is told (ContactBackupUnreadable, retryRestore()); the merge
///              takes the backup's addedMe unless the peer said "removed" on this install
///              (removedMeAtMs) and drops the rows of accounts the restore blocks; markNewAccount keeps
///              the block replace due (an account registered again keeps its device's blocks); the
///              block tag key version is read from the backup fetch once per run; a block or an
///              unblock makes the next write due 1–10 minutes later (writeSoon — not at the moment
///              the server sees the block tag change), not at once). Earlier 2026-11-22 (the restore notice: a restore marks it due on this device —
///              watchRestoreNotice() / dismissRestoreNotice() — so the user is told once what it
///              found, even across an app restart; ContactRestoreReport has value equality)
///
/// @functions
///  - deriveContactBackupKey(): HKDF-SHA256(account seed, salt "SnowChat_Contacts_Backup_v1")
///  - sealContactBackup() / openContactBackup(): the blob
///  - ContactBackupPlain / ContactBackupContact / ContactBackupBlock: what the blob holds
///  - mergeRestoredContact(): a backed-up row merged into the row this device has
///  - drawContactWritePeriodMs(): the per-install write period
///  - ContactBackupApi / ContactBackupBlob / ContactBackupUnreachable: the server's two calls
///  - ContactBackupHooks: what a restore and a write need from the block list and the identity store
///  - ContactBackup.sync(): restore once, the block tag key version once per run, replace the block
///    tags when due, the periodic write
///  - ContactBackup.writeSoon(): a block / unblock — the next write 1–10 minutes from now
///  - ContactBackup.retryRestore(): the user asks to try a backup that did not open again
///  - ContactBackup.onWriteDueChanged: the next write moved closer (the runner re-arms its timer)
///  - ContactBackup.markNewAccount(): a new account: nothing to restore, an empty backup now
///  - ContactBackupUnreadable: the server holds a backup that does not open
///  - ContactBackup.noteBlockKeyVersion(): the server's block tag key version changed → replace once
///  - ContactBackupConflict: the server holds another blob (409, its tag in the answer)
///  - ContactRestoreReport: what the restore found (the screen shows its date)
///  - ContactBackup.watchRestoreNotice() / dismissRestoreNotice(): the restore notice not shown yet
///
/// Notes:
///  - Blob: 0x01 ‖ nonce(24) ‖ XSalsa20-Poly1305(key, nonce, plain); plain = UTF-8 JSON
///    followed by 0x00 bytes up to the smallest of 4, 8, 16, 32, 64, 128, 256 KiB it fits in.
///    JSON: {"v":1,"savedAtMs":…,"contacts":[{"snowId","inMyList","addedMe","hiddenAtMs",
///    "accountPub","nickname","nameIssuedAtMs"}…],"blocks":[{"snowId","nickname"}…]};
///    accountPub is lowercase hex (64 characters) or null. JSON text never holds a 0x00 byte
///    (jsonEncode escapes it), so the first 0x00 ends it.
///  - A write names the tag of the blob it replaces; when the server holds another (409 — an
///    earlier install of this account; the answer carries the server's tag), this device,
///    restored already, takes that tag and writes again: after its restore the device is the
///    truth.
///  - The server can hand out an older blob or say there is none: entries cannot be invented
///    (authenticated encryption under the recovery phrase's key), only rolled back.
///  - Nothing here logs an account or a key.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:pinenacl/x25519.dart' as nacl;

import '../crypto/hkdf.dart';
import '../crypto/identity_binding.dart';
import '../storage/daos/contact_dao.dart';
import '../storage/database.dart';

/// First byte of a contact backup blob.
const int contactBackupVersion = 0x01;

/// The HKDF salt of the contact backup key (another key than the group key
/// backup's, so a format change of one never touches the other).
const String contactBackupSalt = 'SnowChat_Contacts_Backup_v1';

/// Plaintext sizes a backup is padded to.
const List<int> contactBackupBuckets = [
  4096,
  8192,
  16384,
  32768,
  65536,
  131072,
  262144,
];

/// The write period of an install is drawn once in this range.
const Duration contactBackupPeriodMin = Duration(hours: 6);
const Duration contactBackupPeriodMax = Duration(hours: 24);

/// After the server refused a backup call, how long until the next one.
const Duration contactBackupRetry = Duration(minutes: 10);

/// A block or an unblock makes the next write due after a random wait in
/// this range — not at the moment the server takes the block tag (in the
/// database, a tag row and a backup row written together would sit side by
/// side).
const Duration contactBackupSoonMin = Duration(minutes: 1);
const Duration contactBackupSoonMax = Duration(minutes: 10);

const int _nonceLen = 24;
const int _macLen = 16;
const int _keyLen = 32;

final Random _random = Random.secure();

/// The key that seals this account's contact backup: HKDF-SHA256 with the
/// account seed (32 bytes) as input, the label [contactBackupSalt] as salt
/// and no info.
Uint8List deriveContactBackupKey(Uint8List accountSeed) {
  if (accountSeed.length != 32) {
    throw ArgumentError('contact backup: account seed must be 32 bytes');
  }
  return hkdfDerive(
    ikm: accountSeed,
    salt: Uint8List.fromList(utf8.encode(contactBackupSalt)),
    info: Uint8List(0),
    length: _keyLen,
  );
}

/// A random write period for a new install (ms).
int drawContactWritePeriodMs() {
  final min = contactBackupPeriodMin.inMilliseconds;
  final span = contactBackupPeriodMax.inMilliseconds - min;
  return min + _random.nextInt(span + 1);
}

/// One contact row in the backup.
class ContactBackupContact {
  final String snowId;
  final bool inMyList;
  final bool addedMe;
  final int? hiddenAtMs;
  final Uint8List? accountPub;
  final String? nickname;
  final int? nameIssuedAtMs;

  const ContactBackupContact({
    required this.snowId,
    required this.inMyList,
    required this.addedMe,
    this.hiddenAtMs,
    this.accountPub,
    this.nickname,
    this.nameIssuedAtMs,
  });

  factory ContactBackupContact.fromRow(ContactRow r) => ContactBackupContact(
        snowId: r.snowId,
        inMyList: r.inMyList,
        addedMe: r.addedMe,
        hiddenAtMs: r.hiddenAtMs,
        accountPub: r.accountPub,
        nickname: r.nickname,
        nameIssuedAtMs: r.nameIssuedAtMs,
      );

  Map<String, Object?> toJson() => {
        'snowId': snowId,
        'inMyList': inMyList,
        'addedMe': addedMe,
        'hiddenAtMs': hiddenAtMs,
        'accountPub': accountPub == null ? null : _hex(accountPub!),
        'nickname': nickname,
        'nameIssuedAtMs': nameIssuedAtMs,
      };

  /// Null for an entry that is not well formed (it is skipped).
  static ContactBackupContact? fromJson(Object? json) {
    if (json is! Map) return null;
    final snowId = json['snowId'];
    final inMyList = json['inMyList'];
    final addedMe = json['addedMe'];
    final hidden = json['hiddenAtMs'];
    final pub = json['accountPub'];
    final nick = json['nickname'];
    final issued = json['nameIssuedAtMs'];
    if (snowId is! String || !IdentityBindingV1.isValidSnowId(snowId)) return null;
    if (inMyList is! bool || addedMe is! bool) return null;
    if (hidden != null && hidden is! int) return null;
    if (nick != null && nick is! String) return null;
    if (issued != null && issued is! int) return null;
    Uint8List? key;
    if (pub is String) {
      key = _unhex(pub);
      // A key that does not derive the snowId is dropped, not the entry.
      if (!IdentityBindingV1.accountKeyMatchesSnowId(key, snowId)) key = null;
    }
    return ContactBackupContact(
      snowId: snowId,
      inMyList: inMyList,
      addedMe: addedMe,
      hiddenAtMs: hidden as int?,
      accountPub: key,
      nickname: nick as String?,
      nameIssuedAtMs: issued as int?,
    );
  }
}

/// One blocked account in the backup.
class ContactBackupBlock {
  final String snowId;
  final String? nickname;
  const ContactBackupBlock({required this.snowId, this.nickname});

  Map<String, Object?> toJson() => {'snowId': snowId, 'nickname': nickname};

  static ContactBackupBlock? fromJson(Object? json) {
    if (json is! Map) return null;
    final snowId = json['snowId'];
    final nick = json['nickname'];
    if (snowId is! String || !IdentityBindingV1.isValidSnowId(snowId)) return null;
    if (nick != null && nick is! String) return null;
    return ContactBackupBlock(snowId: snowId, nickname: nick as String?);
  }
}

/// What a backup holds.
class ContactBackupPlain {
  /// When it was written (the writer's clock, ms).
  final int savedAtMs;
  final List<ContactBackupContact> contacts;
  final List<ContactBackupBlock> blocks;

  const ContactBackupPlain({
    required this.savedAtMs,
    required this.contacts,
    required this.blocks,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'savedAtMs': savedAtMs,
        'contacts': [for (final c in contacts) c.toJson()],
        'blocks': [for (final b in blocks) b.toJson()],
      };
}

/// Seal [plain] under [key]. [nonce] fixes the nonce; tests only. Throws
/// ArgumentError when the JSON does not fit the largest bucket.
Uint8List sealContactBackup(
  Uint8List key,
  ContactBackupPlain plain, {
  Uint8List? nonce,
}) {
  if (key.length != _keyLen) throw ArgumentError('contact backup: key');
  final json = utf8.encode(jsonEncode(plain.toJson()));
  final bucket = contactBackupBuckets.where((b) => b >= json.length).firstOrNull;
  if (bucket == null) throw ArgumentError('contact backup: too large');
  final padded = Uint8List(bucket)..setAll(0, json);
  final usedNonce = nonce ?? _randomBytes(_nonceLen);
  if (usedNonce.length != _nonceLen) {
    throw ArgumentError('contact backup: nonce must be $_nonceLen bytes');
  }
  final box = nacl.SecretBox(key).encrypt(padded, nonce: usedNonce);
  return Uint8List.fromList(
      [contactBackupVersion, ...usedNonce, ...box.cipherText]);
}

/// What [blob] holds, or null when it does not open under [key] or is not
/// laid out as above. Entries that are not well formed are skipped. Never
/// throws.
ContactBackupPlain? openContactBackup(Uint8List key, Uint8List blob) {
  if (key.length != _keyLen ||
      blob.length < 1 + _nonceLen + _macLen ||
      blob[0] != contactBackupVersion) {
    return null;
  }
  final Uint8List plain;
  try {
    plain = Uint8List.fromList(
      nacl.SecretBox(key).decrypt(
        nacl.EncryptedMessage(
          nonce: Uint8List.fromList(blob.sublist(1, 1 + _nonceLen)),
          cipherText: Uint8List.fromList(blob.sublist(1 + _nonceLen)),
        ),
      ),
    );
  } catch (_) {
    return null; // another key, or altered bytes
  }
  if (!contactBackupBuckets.contains(plain.length)) return null;
  var end = plain.indexOf(0);
  if (end < 0) end = plain.length;
  for (var i = end; i < plain.length; i++) {
    if (plain[i] != 0) return null;
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(plain.sublist(0, end)));
  } catch (_) {
    return null;
  }
  if (json is! Map || json['v'] != 1) return null;
  final saved = json['savedAtMs'];
  final contacts = json['contacts'];
  final blocks = json['blocks'];
  if (saved is! int || contacts is! List || blocks is! List) return null;
  return ContactBackupPlain(
    savedAtMs: saved,
    contacts: [
      for (final c in contacts) ?ContactBackupContact.fromJson(c),
    ],
    blocks: [
      for (final b in blocks) ?ContactBackupBlock.fromJson(b),
    ],
  );
}

/// The row this device keeps after the backed-up [b] is merged into [live]
/// (the row it has, possibly created by a notice that arrived before the
/// restore). What arrived on this install is newer than the backup — but a
/// mark this install never heard about is not a "no":
///  - inMyList: either (the user's own choices, then and now);
///  - addedMe: the live row's when the peer said "removed" on this install
///    (removedMeAtMs), else either (a live false only means no word yet —
///    a lost acceptance, a peer that wrote nothing since);
///  - hiddenAtMs: the live row's when the peer said "added" on this install
///    (that shows a declined request again), else the live one or the
///    backup's;
///  - name: the newer certificate's;
///  - account key: the live row's, else the backup's.
ContactRow mergeRestoredContact(ContactRow? live, ContactBackupContact b, int nowMs) {
  if (live == null) {
    return ContactRow(
      snowId: b.snowId,
      inMyList: b.inMyList,
      addedMe: b.addedMe,
      hiddenAtMs: b.hiddenAtMs,
      nickname: b.nickname,
      nameIssuedAtMs: b.nameIssuedAtMs,
      accountPub: b.accountPub,
      notFoundCount: 0,
      removedMeAtMs: null,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
    );
  }
  final backupNameNewer = b.nameIssuedAtMs != null &&
      (live.nameIssuedAtMs == null || b.nameIssuedAtMs! > live.nameIssuedAtMs!);
  final peerSaidRemoved = live.removedMeAtMs != null;
  return ContactRow(
    snowId: live.snowId,
    inMyList: live.inMyList || b.inMyList,
    addedMe: peerSaidRemoved ? live.addedMe : (live.addedMe || b.addedMe),
    hiddenAtMs: live.addedMe ? live.hiddenAtMs : (live.hiddenAtMs ?? b.hiddenAtMs),
    nickname: backupNameNewer ? b.nickname : live.nickname,
    nameIssuedAtMs: backupNameNewer ? b.nameIssuedAtMs : live.nameIssuedAtMs,
    accountPub: live.accountPub ?? b.accountPub,
    notFoundCount: live.notFoundCount,
    removedMeAtMs: live.removedMeAtMs,
    createdAtMs: live.createdAtMs,
    updatedAtMs: nowMs,
  );
}

/// What the server holds.
class ContactBackupBlob {
  /// Null when the server holds none.
  final Uint8List? blob;

  /// The server's tag of [blob]; null with no blob.
  final String? etag;

  /// The server's block tag key version (contract §12.1 `keyVersion`), or
  /// null when the answer did not carry one.
  final int? blockKeyVersion;

  const ContactBackupBlob(this.blob, this.etag, {this.blockKeyVersion});
}

/// Thrown by a [ContactBackupApi] when the server gave no answer at all.
class ContactBackupUnreachable implements Exception {
  const ContactBackupUnreachable();
}

/// The server holds a backup this account cannot open (another key, or
/// altered bytes). Not "no backup": nothing is restored, the server's block
/// tags are not replaced and nothing is written over it.
class ContactBackupUnreadable implements Exception {
  const ContactBackupUnreadable();
}

/// Thrown by [ContactBackupApi.store] when the server holds another blob
/// than the one named (409 BACKUP_CONFLICT). [etag] is the server's tag of
/// what it holds (null: it holds none, or the answer did not say).
class ContactBackupConflict implements Exception {
  final String? etag;
  const ContactBackupConflict(this.etag);
}

/// The server's two backup calls (GET / PUT /contacts-backup). Both throw
/// [ContactBackupUnreachable] when the server cannot be reached, and
/// anything else when it answers with an error.
abstract interface class ContactBackupApi {
  Future<ContactBackupBlob> fetch();

  /// Replace the blob tagged [ifMatch] (null: none exists yet) with [blob].
  /// Returns the new tag; throws [ContactBackupConflict] when the server
  /// holds another blob (409).
  Future<String> store(Uint8List blob, String? ifMatch);
}

/// What a restore and a write need outside the contact table.
class ContactBackupHooks {
  /// The blocked accounts this device holds (snowId → nickname): written
  /// into the backup.
  final Future<Map<String, String?>> Function() blockedAccounts;

  /// Take in the backed-up blocks this device has no row of (BlockList).
  final Future<void> Function(Map<String, String?> blocks) mergeBlocks;

  /// Replace the server's block tags by this device's list (POST
  /// /users/blocks/replace). Returns whether the server took it.
  final Future<bool> Function() replaceServerBlocks;

  /// A restored account in this user's list: it was chosen on an earlier
  /// install — vouched for again, its account key pinned.
  final Future<void> Function(String snowId, Uint8List? accountPub)
      restoredInMyList;

  const ContactBackupHooks({
    required this.blockedAccounts,
    required this.mergeBlocks,
    required this.replaceServerBlocks,
    required this.restoredInMyList,
  });
}

/// What the restore of this install found.
class ContactRestoreReport {
  /// Whether the server held a backup this account could open.
  final bool found;

  /// When that backup was written (its writer's clock, ms), or null.
  final int? savedAtMs;

  /// The server held a backup that did not open: nothing was restored yet,
  /// and it is tried again ([ContactBackup.retryRestore]).
  final bool unreadable;

  const ContactRestoreReport({
    required this.found,
    this.savedAtMs,
    this.unreadable = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ContactRestoreReport &&
      other.found == found &&
      other.savedAtMs == savedAtMs &&
      other.unreadable == unreadable;

  @override
  int get hashCode => Object.hash(found, savedAtMs, unreadable);
}

class ContactBackup {
  final ContactDao _dao;
  final ContactBackupApi _api;
  final Future<Uint8List> Function() _key;
  final ContactBackupHooks _hooks;
  final int Function() _nowMs;

  ContactBackup({
    required ContactDao dao,
    required ContactBackupApi api,
    required Future<Uint8List> Function() key,
    required ContactBackupHooks hooks,
    int Function()? nowMs,
  })  : _dao = dao,
        _api = api,
        _key = key,
        _hooks = hooks,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  Future<void> _tail = Future<void>.value();
  int _notBeforeMs = 0;

  /// Whether this run read the block tag key version from the server yet
  /// (once per run — the restore's fetch counts).
  bool _keyVersionRead = false;

  /// What this install's restore found (null until it ran in this process).
  ContactRestoreReport? lastRestore;

  /// Called when the next write became due sooner ([writeSoon]): the runner
  /// that waits for [nextWriteAtMs] re-arms.
  void Function()? onWriteDueChanged;

  /// Runs [action] after everything queued before it (one backup operation
  /// at a time).
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<ContactSyncStateRow> _state() => _dao.ensureSyncState(
        periodMs: drawContactWritePeriodMs(),
        nowMs: _nowMs(),
      );

  /// Write some columns of the sync state (made first when missing). Never
  /// the whole row: the name certificate writes the same row on its own.
  Future<void> _patch(ContactSyncStatesCompanion patch) async {
    await _state();
    await _dao.patchSyncState(patch);
  }

  /// When the next periodic write is due (local clock, ms).
  Future<int> nextWriteAtMs() async => (await _state()).nextWriteAtMs;

  /// What the restore of this install found while the user was not told
  /// yet (null otherwise), each time that changes. Survives an app restart:
  /// the notice is due until [dismissRestoreNotice]. A backup that did not
  /// open reads `unreadable`.
  Stream<ContactRestoreReport?> watchRestoreNotice() => _dao
      .watchSyncState()
      .map((s) {
        if (s == null || !s.restoreNoticeDue) return null;
        if (s.restoreUnreadable) {
          return const ContactRestoreReport(found: false, unreadable: true);
        }
        return ContactRestoreReport(
          found: s.restoreSavedAtMs != null,
          savedAtMs: s.restoreSavedAtMs,
        );
      })
      .distinct();

  /// The user saw the restore notice: it is not shown again.
  Future<void> dismissRestoreNotice() => _serial(() => _patch(
        const ContactSyncStatesCompanion(restoreNoticeDue: Value(false)),
      ));

  /// Restore from the backup (once per install), read the block tag key
  /// version (once per run), replace the server's block tags when that is
  /// pending, and make the periodic write when it is due. Returns whether
  /// everything due was done. Never throws for what a server or a network
  /// can cause.
  Future<bool> sync() => _serial(_sync);

  /// The user asks to try a backup that did not open again: it is fetched
  /// now (no waiting out an earlier failure), and a failure is told again.
  Future<bool> retryRestore() => _serial(() async {
        _notBeforeMs = 0;
        await _patch(const ContactSyncStatesCompanion(
          restoreUnreadable: Value(false),
          restoreNoticeDue: Value(false),
        ));
        return _sync();
      });

  Future<bool> _sync() async {
    if (_nowMs() < _notBeforeMs) return false;
    try {
      var state = await _state();
      if (!state.restored) {
        await _restore();
        state = await _state();
      } else if (!_keyVersionRead) {
        // The server's block tag key may have been rotated since the last
        // run: its version comes with the backup fetch.
        final remote = await _api.fetch();
        await _takeKeyVersion(remote.blockKeyVersion);
        state = await _state();
      }
      if (state.blocksReplacePending) {
        if (await _hooks.replaceServerBlocks()) {
          await _patch(const ContactSyncStatesCompanion(
            blocksReplacePending: Value(false),
          ));
        }
        state = await _state();
      }
      final now = _nowMs();
      // A due time further away than a period (the clock was set back) is
      // drawn from now again.
      if (state.nextWriteAtMs > now + state.periodMs) {
        await _patch(ContactSyncStatesCompanion(
          nextWriteAtMs: Value(now + state.periodMs),
        ));
        state = await _state();
      }
      if (now >= state.nextWriteAtMs) {
        await _write();
        await _patch(ContactSyncStatesCompanion(
          nextWriteAtMs: Value(_nowMs() + state.periodMs),
        ));
        state = await _state();
      }
      return !state.blocksReplacePending;
    } on ContactBackupUnreachable {
      return false;
    } on ContactBackupUnreadable {
      return false;
    } catch (e) {
      debugPrint('[ContactBackup] sync failed: ${e.runtimeType}');
      _notBeforeMs = _nowMs() + contactBackupRetry.inMilliseconds;
      return false;
    }
  }

  /// A block or an unblock: the backup is written soon — at a random time
  /// between [contactBackupSoonMin] and [contactBackupSoonMax] from now
  /// (kept as the next due time, so an app closed meanwhile writes it at its
  /// next start), or sooner when a write is due sooner anyway.
  Future<void> writeSoon() => _serial(() async {
        try {
          final state = await _state();
          final min = contactBackupSoonMin.inMilliseconds;
          final span = contactBackupSoonMax.inMilliseconds - min;
          final due = _nowMs() + min + _random.nextInt(span + 1);
          if (due >= state.nextWriteAtMs) return;
          await _patch(ContactSyncStatesCompanion(nextWriteAtMs: Value(due)));
          onWriteDueChanged?.call();
        } catch (e) {
          debugPrint('[ContactBackup] write not scheduled: ${e.runtimeType}');
        }
      });

  /// A new account: there is nothing to restore, and the (empty) backup is
  /// written now — the server learns that a backup exists at sign-up, not
  /// when the first contact is added. The block replace stays due: an
  /// account registered again with this device's identity (a server reset)
  /// keeps the blocks this device holds — the next sync puts them on the
  /// server. Not reaching the server leaves the write due at once.
  Future<void> markNewAccount() => _serial(() async {
        await _patch(ContactSyncStatesCompanion(
          restored: const Value(true),
          restoreUnreadable: const Value(false),
          blocksReplacePending: const Value(true),
          nextWriteAtMs: Value(_nowMs()),
        ));
        await _dao.deleteTombstones();
        try {
          await _write();
          final after = await _state();
          await _patch(ContactSyncStatesCompanion(
            nextWriteAtMs: Value(_nowMs() + after.periodMs),
          ));
        } catch (e) {
          debugPrint('[ContactBackup] first write failed: ${e.runtimeType}');
        }
      });

  /// The server's block tag key version [keyVersion] was in an answer. When
  /// it differs from the one last seen, the server's tags are replaced by
  /// this device's list once (they were made under another key); the version
  /// is stored either way. Never throws.
  Future<void> noteBlockKeyVersion(int keyVersion) => _serial(() async {
        try {
          if (!await _takeKeyVersion(keyVersion)) return;
          final state = await _state();
          if (!state.restored || !state.blocksReplacePending) return;
          if (await _hooks.replaceServerBlocks()) {
            await _patch(const ContactSyncStatesCompanion(
              blocksReplacePending: Value(false),
            ));
          }
        } catch (e) {
          debugPrint('[ContactBackup] key version not noted: ${e.runtimeType}');
        }
      });

  /// Store the server's block tag key version [keyVersion] (null: the
  /// answer had none). Returns whether it changed from a version seen
  /// before — then the block replace is due.
  Future<bool> _takeKeyVersion(int? keyVersion) async {
    _keyVersionRead = true;
    if (keyVersion == null) return false;
    final state = await _state();
    if (state.blockKeyVersion == keyVersion) return false;
    final changed = state.blockKeyVersion != null;
    await _patch(ContactSyncStatesCompanion(
      blockKeyVersion: Value(keyVersion),
      blocksReplacePending: Value(state.blocksReplacePending || changed),
    ));
    return changed;
  }

  /// Take in what the backup holds, merged into the rows this install has
  /// already (notices that arrived before the restore are kept), then mark
  /// the server's block tags for replacement. A backup that does not open
  /// throws [ContactBackupUnreadable] and changes nothing but the notice.
  Future<void> _restore() async {
    final remote = await _api.fetch();
    await _takeKeyVersion(remote.blockKeyVersion);
    final key = await _key();
    final blob = remote.blob;
    final plain = blob == null ? null : openContactBackup(key, blob);
    if (blob != null && plain == null) {
      final state = await _state();
      if (!state.restoreUnreadable) {
        // Told once per failure (retryRestore() clears it).
        await _patch(const ContactSyncStatesCompanion(
          restoreUnreadable: Value(true),
          restoreNoticeDue: Value(true),
        ));
      }
      throw const ContactBackupUnreadable();
    }
    final restoredInMyList = <ContactRow>[];
    if (plain != null) {
      await _hooks.mergeBlocks({for (final b in plain.blocks) b.snowId: b.nickname});
      await _dao.transaction(() async {
        final now = _nowMs();
        for (final c in plain.contacts) {
          final merged = mergeRestoredContact(await _dao.row(c.snowId), c, now);
          if (!merged.inMyList && !merged.addedMe) continue;
          await _dao.putRow(merged);
          if (c.inMyList) restoredInMyList.add(merged);
        }
      });
    }
    // A blocked account has no row (blocking removes it): neither one the
    // backup brought nor one a notice made before the block came back.
    final blocked = await _hooks.blockedAccounts();
    for (final snowId in blocked.keys) {
      await _dao.deleteRow(snowId);
    }
    restoredInMyList.removeWhere((r) => blocked.containsKey(r.snowId));
    // Rows kept only for this merge (a "removed" with no mark left) go.
    await _dao.deleteTombstones();
    for (final r in restoredInMyList) {
      try {
        await _hooks.restoredInMyList(r.snowId, r.accountPub);
      } catch (_) {
        // The mark is only for the group pickers: a failure loses nothing.
      }
    }
    lastRestore = ContactRestoreReport(
      found: plain != null,
      savedAtMs: plain?.savedAtMs,
    );
    await _patch(ContactSyncStatesCompanion(
      restored: const Value(true),
      restoreUnreadable: const Value(false),
      etag: Value(remote.etag),
      blocksReplacePending: const Value(true),
      // The user is told once what this restore found (§5.10).
      restoreNoticeDue: const Value(true),
      restoreSavedAtMs: Value(plain?.savedAtMs),
    ));
  }

  /// Seal the list as it is now and store it, replacing the blob of the
  /// stored tag (once more under the server's tag after a 409). Only after
  /// the restore of this install: a backup is never overwritten unread.
  Future<void> _write() async {
    final state = await _state();
    if (!state.restored) return;
    final rows = await _dao.allRows();
    final blocks = await _hooks.blockedAccounts();
    final plain = ContactBackupPlain(
      savedAtMs: _nowMs(),
      contacts: [
        for (final r in rows)
          if (r.inMyList || r.addedMe) ContactBackupContact.fromRow(r),
      ],
      blocks: [
        for (final e in blocks.entries)
          ContactBackupBlock(snowId: e.key, nickname: e.value),
      ],
    );
    final blob = sealContactBackup(await _key(), plain);
    String etag;
    try {
      etag = await _api.store(blob, state.etag);
    } on ContactBackupConflict catch (conflict) {
      // The server holds a blob this device did not write (an earlier
      // install). This install restored already: its list is the truth.
      // The 409 names the server's tag; without it the tag is fetched.
      final current = conflict.etag ?? (await _api.fetch()).etag;
      etag = await _api.store(blob, current);
    }
    await _patch(ContactSyncStatesCompanion(etag: Value(etag)));
  }
}

Uint8List _randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List? _unhex(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-f]*$').hasMatch(hex)) return null;
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(2 * i, 2 * i + 2), radix: 16);
  }
  return out;
}
