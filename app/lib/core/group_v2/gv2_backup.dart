/// @file        gv2_backup.dart
/// @description Group protocol v2 — the backup of this account's group keys
///              (design document §9.8; format in §25). The server lists no
///              groups for an account, so a reinstall could not find them:
///              the list of (group, master key, a verified point of its log)
///              is sealed under a key derived from the recovery phrase and
///              kept on the server as one opaque, padded blob. A new install
///              takes its groups from it once; from then on the blob follows
///              the device.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-19
/// @lastUpdated 2026-11-21 (P5.6: a write of the blob is made at a random time one to six hours after what changed the list — the due time is stored; writeDueAtMs()). Earlier 2026-11-20
///
/// @functions
///  - gv2SealBackup() / gv2OpenBackup(): the blob
///  - Gv2BackupEntry: one group in the list
///  - Gv2BackupApi / Gv2BackupBlob / Gv2BackupUnreachable: the server's two
///    calls (login required)
///  - Gv2Backup.sync(): restore once, then keep the blob in step
///  - Gv2BackupOutcome: what a sync did
///  - gv2BackupWriteDelay(): when a write that became due is made
///
/// Notes:
///  - Blob (big-endian integers):
///      blob  = version 0x01 ‖ nonce(24) ‖ XSalsa20-Poly1305(K_backup, nonce, plain)
///      plain = count(u32) ‖ entry × count ‖ zero padding
///      entry = groupId(32) ‖ masterKey(32) ‖ revision(u32) ‖ chain(32)
///              ‖ stateHash(32)                                    132 B
///    The plaintext is padded to one of [gv2BackupBuckets]: the server sees
///    a size class, not how many groups an account is in.
///  - What is in the list: the groups this account is a member of (by the
///    log — confirmed or waiting for confirmation), each with the head this
///    device verified. Not invites, not groups being created, not groups it
///    left. A frozen group stays in the list with the last point this
///    device verified: a later install judges the server's log again from
///    there, and only a group this device holds can be left.
///  - Restoring happens ONCE per install: the first sync that reaches the
///    server takes in every listed group this device does not hold, as a
///    member waiting for confirmation, flagged to announce that its Sender
///    Keys are gone (member_reset). Nothing in the blob is believed beyond
///    that: the state at each anchor is fetched and verified like an
///    invite's, and a member has to confirm the head before this device
///    sends (a server handing out an old blob only moves the starting point
///    back — design §9.8).
///  - Afterwards the device is the truth. The blob is written again when
///    the set of groups changes, when a member was removed from one (an
///    anchor from before a removal widens what a rollback could hide), and
///    otherwise once a week — not with every change of every group.
///  - Not at once: the write is made at a random time one to six hours
///    after the list changed (decided 2026-11-21), so the server cannot tie
///    the time of an account's write to the change of a group (a join, a
///    removal). The due time is stored and survives a restart; what is
///    written is the list as it is then. The price: a group joined in the
///    last hours may be missing from the backup when the device is lost.
///  - A write names the tag of the blob it replaces. When the server holds
///    another (written by an earlier install of this account), this device
///    takes the new tag and writes again: after its restore it does not
///    merge.
///  - The server stores no time and no counter with the blob.
///  - When the server answers with an error, it is not asked again for
///    [gv2BackupRetry]; when it cannot be reached at all, the next sync
///    asks again (that fails fast, and the device may be back online).
///  - Key material (master keys): nothing here logs.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pinenacl/x25519.dart' as nacl;
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_codec.dart';
import 'gv2_credentials.dart';
import 'gv2_keys.dart';
import 'gv2_store.dart';

/// First byte of a backup blob.
const int gv2BackupVersion = 0x01;

/// One group in the plaintext.
const int gv2BackupEntryLen =
    gv2GroupIdLen + gv2MasterKeyLen + 4 + 2 * gv2HashLen;

/// Plaintext sizes a backup is padded to.
const List<int> gv2BackupBuckets = [4096, 8192, 16384, 32768, 65536, 131072];

/// The most groups a backup holds (the largest bucket; the server takes
/// blobs up to 256 KiB).
const int gv2BackupMaxGroups = (131072 - 4) ~/ gv2BackupEntryLen;

/// The anchors in the blob are renewed at least this often.
const Duration gv2BackupRenewEvery = Duration(days: 7);

/// After the server refused a backup call, how long until the next one.
const Duration gv2BackupRetry = Duration(minutes: 10);

/// A write of the blob is made this long after what changed the list, at
/// the earliest ([gv2BackupWriteDelayMax] at the latest; uniform between).
const Duration gv2BackupWriteDelayMin = Duration(hours: 1);
const Duration gv2BackupWriteDelayMax = Duration(hours: 6);

/// A random delay in [gv2BackupWriteDelayMin, gv2BackupWriteDelayMax].
Duration gv2BackupWriteDelay() {
  final span = gv2BackupWriteDelayMax.inMilliseconds -
      gv2BackupWriteDelayMin.inMilliseconds;
  return gv2BackupWriteDelayMin +
      Duration(milliseconds: Random.secure().nextInt(span + 1));
}

const int _nonceLen = 24;
const int _macLen = 16;

final Random _random = Random.secure();

/// One group in the backup: its master key and a point of its log this
/// device verified.
class Gv2BackupEntry {
  final Uint8List groupId;
  final Uint8List masterKey;
  final int revision;
  final Uint8List chain;
  final Uint8List stateHash;

  Gv2BackupEntry({
    required Uint8List groupId,
    required Uint8List masterKey,
    required this.revision,
    required Uint8List chain,
    required Uint8List stateHash,
  }) : groupId = _exact(groupId, gv2GroupIdLen, 'groupId'),
       masterKey = _exact(masterKey, gv2MasterKeyLen, 'masterKey'),
       chain = _exact(chain, gv2HashLen, 'chain'),
       stateHash = _exact(stateHash, gv2HashLen, 'stateHash') {
    if (revision < 0 || revision > 0xFFFFFFFF) {
      throw ArgumentError('gv2 backup: revision out of range');
    }
  }
}

/// Seal [entries] under [key] (K_backup). [nonce] fixes the nonce; tests
/// only.
Uint8List gv2SealBackup(
  Uint8List key,
  List<Gv2BackupEntry> entries, {
  Uint8List? nonce,
}) {
  if (entries.length > gv2BackupMaxGroups) {
    throw ArgumentError('gv2 backup: too many groups');
  }
  final used = 4 + entries.length * gv2BackupEntryLen;
  final plain = Uint8List(gv2BackupBuckets.firstWhere((b) => b >= used));
  final view = ByteData.sublistView(plain);
  view.setUint32(0, entries.length, Endian.big);
  var at = 4;
  for (final e in entries) {
    plain.setAll(at, e.groupId);
    at += gv2GroupIdLen;
    plain.setAll(at, e.masterKey);
    at += gv2MasterKeyLen;
    view.setUint32(at, e.revision, Endian.big);
    at += 4;
    plain.setAll(at, e.chain);
    at += gv2HashLen;
    plain.setAll(at, e.stateHash);
    at += gv2HashLen;
  }
  final usedNonce = nonce ?? _randomBytes(_nonceLen);
  if (usedNonce.length != _nonceLen) {
    throw ArgumentError('gv2 backup: nonce must be $_nonceLen bytes');
  }
  final box = nacl.SecretBox(
    _exact(key, gv2SymmetricKeyLen, 'key'),
  ).encrypt(plain, nonce: usedNonce);
  return Uint8List.fromList([gv2BackupVersion, ...usedNonce, ...box.cipherText]);
}

/// The entries of [blob], or null when it does not open under [key] or is
/// not laid out as above. Never throws.
List<Gv2BackupEntry>? gv2OpenBackup(Uint8List key, Uint8List blob) {
  if (key.length != gv2SymmetricKeyLen ||
      blob.length < 1 + _nonceLen + _macLen + 4 ||
      blob[0] != gv2BackupVersion) {
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
  if (!gv2BackupBuckets.contains(plain.length)) return null;
  final view = ByteData.sublistView(plain);
  final count = view.getUint32(0, Endian.big);
  final used = 4 + count * gv2BackupEntryLen;
  if (count > gv2BackupMaxGroups || used > plain.length) return null;
  for (var i = used; i < plain.length; i++) {
    if (plain[i] != 0) return null;
  }
  final entries = <Gv2BackupEntry>[];
  var at = 4;
  Uint8List take(int length) {
    final part = Uint8List.fromList(plain.sublist(at, at + length));
    at += length;
    return part;
  }

  for (var i = 0; i < count; i++) {
    final groupId = take(gv2GroupIdLen);
    final masterKey = take(gv2MasterKeyLen);
    final revision = view.getUint32(at, Endian.big);
    at += 4;
    entries.add(
      Gv2BackupEntry(
        groupId: groupId,
        masterKey: masterKey,
        revision: revision,
        chain: take(gv2HashLen),
        stateHash: take(gv2HashLen),
      ),
    );
  }
  return entries;
}

/// What the server holds.
class Gv2BackupBlob {
  /// Null when the server holds none.
  final Uint8List? blob;

  /// The server's tag of [blob]; null with no blob.
  final String? etag;
  const Gv2BackupBlob(this.blob, this.etag);
}

/// Thrown by a [Gv2BackupApi] when the server gave no answer at all (no
/// network, a timeout).
class Gv2BackupUnreachable implements Exception {
  const Gv2BackupUnreachable();
}

/// The server's two backup calls (they carry the account's login). Both
/// throw [Gv2BackupUnreachable] when the server cannot be reached, and
/// anything else when it answers with an error.
abstract interface class Gv2BackupApi {
  Future<Gv2BackupBlob> fetch();

  /// Replace the blob tagged [ifMatch] (null: none exists yet) with [blob].
  /// Returns the new tag, or null when the server holds another blob.
  Future<String?> store(Uint8List blob, String? ifMatch);
}

/// What a sync did.
class Gv2BackupOutcome {
  /// Groups taken from the backup now (lowercase hex ids): they wait for
  /// their state, for the reset notice and for a member's confirmation.
  final List<String> restored;

  /// Whether the blob was written.
  final bool written;

  /// Whether this install has looked at the backup by now (in this sync or
  /// an earlier one): only then does it know which groups it is in.
  final bool looked;

  /// False when a call to the server failed: what was not done is tried by
  /// a later sync.
  final bool reached;

  const Gv2BackupOutcome({
    this.restored = const [],
    this.written = false,
    this.looked = true,
    this.reached = true,
  });
}

class Gv2Backup {
  final Gv2Store _groups;
  final Gv2BackupApi _api;
  final Future<Uint8List> Function() _key;
  final String _me;
  final int Function() _nowMs;
  final Duration Function() _writeDelay;

  Future<Gv2BackupOutcome>? _running;
  int _notBeforeMs = 0;

  /// [key] returns K_backup (IdentityManager.deriveGroupBackupKey);
  /// [mySnowId] is this device's account.
  Gv2Backup({
    required Gv2Store groups,
    required Gv2BackupApi api,
    required Future<Uint8List> Function() key,
    required String mySnowId,
    int Function()? nowMs,
    Duration Function()? writeDelay,
  }) : _groups = groups,
       _api = api,
       _key = key,
       _me = mySnowId,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _writeDelay = writeDelay ?? gv2BackupWriteDelay;

  /// When the pending write is due (local clock, ms), or null. For the
  /// runtime's wake-up timer.
  Future<int?> writeDueAtMs() async =>
      (await _groups.backupState())?.writeDueAtMs;

  /// Restore from the backup (once per install), then write the blob when
  /// what it should hold has changed. Concurrent calls share one run. Never
  /// throws for what a server or a network can cause.
  Future<Gv2BackupOutcome> sync() =>
      _running ??= _sync().whenComplete(() => _running = null);

  Future<Gv2BackupOutcome> _sync() async {
    var state = await _groups.backupState();
    var looked = state != null && state.restored;
    var restored = const <String>[];
    Gv2BackupOutcome failed() =>
        Gv2BackupOutcome(restored: restored, looked: looked, reached: false);
    if (_nowMs() < _notBeforeMs) return failed();
    try {
      final key = await _key();
      if (!looked) {
        final remote = await _api.fetch();
        restored = await _restore(key, remote.blob);
        await _groups.saveBackupState(
          restored: true,
          etag: remote.etag,
          fingerprint: null,
        );
        state = (await _groups.backupState())!;
        looked = true;
      }

      final members = await _memberGroups();
      if (members.length > gv2BackupMaxGroups) {
        // More groups than a blob holds: the first ones (by id) are kept.
        members.removeRange(gv2BackupMaxGroups, members.length);
      }
      final fingerprint = _fingerprint(members);
      final now = _nowMs();
      var due = state.writeDueAtMs;
      if (_same(state.fingerprint, fingerprint)) {
        // Back to what was written: nothing is pending.
        if (due != null) {
          await _groups.saveBackupState(
            restored: true,
            etag: state.etag,
            fingerprint: state.fingerprint,
          );
        }
        return Gv2BackupOutcome(restored: restored);
      }
      // The list changed: the write is made later, at a random time. A due
      // time further away than any delay (the clock was set back) is drawn
      // again.
      if (due == null || due > now + gv2BackupWriteDelayMax.inMilliseconds) {
        due = now + _writeDelay().inMilliseconds;
        await _groups.saveBackupState(
          restored: true,
          etag: state.etag,
          fingerprint: state.fingerprint,
          writeDueAtMs: due,
        );
      }
      if (now < due) return Gv2BackupOutcome(restored: restored);
      final blob = gv2SealBackup(key, [
        for (final g in members)
          Gv2BackupEntry(
            groupId: gv2Unhex(g.groupId),
            masterKey: g.masterKey,
            revision: g.revision,
            chain: g.chain,
            stateHash: g.stateHash,
          ),
      ]);
      var etag = await _api.store(blob, state.etag);
      if (etag == null) {
        // The server holds a blob this device did not write (an earlier
        // install of this account). This device restored already: its own
        // groups are the truth.
        final remote = await _api.fetch();
        etag = await _api.store(blob, remote.etag);
        if (etag == null) return failed();
      }
      await _groups.saveBackupState(
        restored: true,
        etag: etag,
        fingerprint: fingerprint,
      );
      return Gv2BackupOutcome(restored: restored, written: true);
    } on Gv2BackupUnreachable {
      return failed();
    } catch (_) {
      // The server refused, or answered with something else than a backup
      // call's answer.
      _notBeforeMs = _nowMs() + gv2BackupRetry.inMilliseconds;
      return failed();
    }
  }

  /// Take in the groups of [blob] this device does not hold. Returns their
  /// ids.
  Future<List<String>> _restore(Uint8List key, Uint8List? blob) async {
    final entries = blob == null ? null : gv2OpenBackup(key, blob);
    if (entries == null) return const []; // none, or not this account's
    final restored = <String>[];
    for (final e in entries) {
      final Uint8List mine;
      try {
        // The group id is whatever the master key gives.
        if (!_sameBytes(
          ZkGroup.groupParams(e.masterKey).groupId,
          e.groupId,
        )) {
          continue;
        }
        mine = ZkGroup.encryptMember(
          masterKey: e.masterKey,
          accountId: gv2AccountIdOfSnowId(_me),
        );
      } on ZkGroupException {
        continue;
      }
      final stored = await _groups.insertAnchored(
        groupId: e.groupId,
        masterKey: e.masterKey,
        myCiphertext: mine,
        protocolVersion: gv2ProtocolVersion,
        revision: e.revision,
        chain: e.chain,
        stateHash: e.stateHash,
        membership: Gv2Membership.awaitingConfirm,
        resetPending: true,
      );
      if (stored) restored.add(gv2Hex(e.groupId));
    }
    return restored;
  }

  /// The groups this account is a member of by the log, by group id.
  Future<List<Gv2GroupRow>> _memberGroups() async {
    const member = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
    return [
      for (final g in await _groups.groups())
        if (member.contains(g.membership)) g,
    ]..sort((a, b) => a.groupId.compareTo(b.groupId));
  }

  /// What decides whether the blob is written again: which groups, the last
  /// removal known in each, and the week.
  Uint8List _fingerprint(List<Gv2GroupRow> members) {
    final b = BytesBuilder();
    final week = _nowMs() ~/ gv2BackupRenewEvery.inMilliseconds;
    b.add(_u64(week));
    for (final g in members) {
      b.add(gv2Unhex(g.groupId));
      b.add(_u64((g.lastRemovalRevision ?? -1) + 1));
    }
    return Uint8List.fromList(hash.sha256.convert(b.takeBytes()).bytes);
  }
}

Uint8List _u64(int value) {
  final out = Uint8List(8);
  ByteData.sublistView(out).setUint64(0, value, Endian.big);
  return out;
}

Uint8List _randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _random.nextInt(256);
  }
  return out;
}

Uint8List _exact(Uint8List bytes, int length, String what) {
  if (bytes.length != length) {
    throw ArgumentError('gv2 backup: $what must be $length bytes');
  }
  return bytes;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _same(Uint8List? a, Uint8List b) => a != null && _sameBytes(a, b);
