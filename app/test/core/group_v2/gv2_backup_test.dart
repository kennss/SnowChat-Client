/// @file        gv2_backup_test.dart
/// @description Group protocol v2 backup of the group keys: the sealed blob
///              (round trip, the documented layout against a golden vector
///              in test/fixtures/gv2_backup_v1.json, what the decoder
///              refuses), the key it is sealed under, and the service — a
///              new install takes its groups in once, afterwards the blob
///              follows the device and is written only when what it should
///              hold has changed.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-19
/// @lastUpdated 2026-11-21 (P5.6: the delayed write — a random 1–6 h, stored, not pushed back, cleared when the list is back). Earlier 2026-11-20
///
/// @functions
///  - main(): format, vector, restore, writing, failures.
///
/// Notes:
///  - GV2_BACKUP_WRITE_VECTORS=1 rewrites the fixture after an INTENDED
///    format change. Every value in it comes from fixed labels.
///  - The service runs on a real in-memory database and a stand-in for the
///    server's two calls that keeps one blob and answers like the route
///    (tag = base64 SHA-256, a write needs the tag of what it replaces).
///  - Group rows are written through the store where the standing allows
///    it (invites, restored groups) and adjusted directly for the standings
///    that need a whole change log — the service reads rows, not logs.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as nacl;
import 'package:snowchat/core/crypto/hkdf.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/group_v2/gv2_backup.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_credentials.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import 'gv2_test_support.dart';

const _fixturePath = 'test/fixtures/gv2_backup_v1.json';

final Uint8List _seed = gv2TestSha('gv2 backup test — account seed');
final Uint8List _key = gv2DeriveBackupKey(_seed);
final Uint8List _nonce = gv2TestBytes('gv2 backup test — nonce', 24);

Gv2BackupEntry _entry(String label, {int revision = 7}) {
  final masterKey = gv2TestSha('gv2 backup test — master key $label');
  return Gv2BackupEntry(
    groupId: ZkGroup.groupParams(masterKey).groupId,
    masterKey: masterKey,
    revision: revision,
    chain: gv2TestSha('gv2 backup test — chain $label'),
    stateHash: gv2TestSha('gv2 backup test — state hash $label'),
  );
}

/// The plaintext of [blob] under [_key].
Uint8List _plain(Uint8List blob) => Uint8List.fromList(
  nacl.SecretBox(_key).decrypt(
    nacl.EncryptedMessage(
      nonce: Uint8List.fromList(blob.sublist(1, 25)),
      cipherText: Uint8List.fromList(blob.sublist(25)),
    ),
  ),
);

/// Seal [plain] as it is (for blobs the encoder would not make).
Uint8List _sealRaw(Uint8List plain, {int version = gv2BackupVersion}) =>
    Uint8List.fromList([
      version,
      ..._nonce,
      ...nacl.SecretBox(_key).encrypt(plain, nonce: _nonce).cipherText,
    ]);

String _tag(Uint8List bytes) => base64Encode(hash.sha256.convert(bytes).bytes);

/// The server's side: one blob, replaced only by a write that names it.
class _Api implements Gv2BackupApi {
  Uint8List? blob;
  int fetches = 0;
  int stores = 0;

  /// What the next calls do instead of answering.
  Object? failWith;

  /// Runs before a store is looked at (someone else writes meanwhile).
  void Function()? beforeStore;

  @override
  Future<Gv2BackupBlob> fetch() async {
    fetches++;
    if (failWith != null) throw failWith!;
    final held = blob;
    return held == null
        ? const Gv2BackupBlob(null, null)
        : Gv2BackupBlob(held, _tag(held));
  }

  @override
  Future<String?> store(Uint8List blob, String? ifMatch) async {
    stores++;
    if (failWith != null) throw failWith!;
    final hook = beforeStore;
    beforeStore = null;
    hook?.call();
    final held = this.blob;
    if ((held == null ? null : _tag(held)) != ifMatch) return null;
    this.blob = blob;
    return _tag(blob);
  }

  List<String> get groupIds => [
    for (final e in gv2OpenBackup(_key, blob!)!) gv2Hex(e.groupId),
  ];
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the key', () {
    test('comes from the account seed alone, under its own label', () {
      expect(
        _key,
        hkdfDerive(
          ikm: _seed,
          salt: Uint8List.fromList(ascii.encode('SnowChat_GV2_Backup_v1')),
          info: Uint8List(0),
          length: 32,
        ),
      );
      expect(gv2DeriveBackupKey(_seed), _key);
      expect(
        gv2DeriveBackupKey(gv2TestSha('another account')),
        isNot(_key),
      );
      // Not the key of anything else derived from the seed.
      expect(
        _key,
        isNot(gv2DeriveMemberSeed(_seed, gv2TestSha('some group'))),
      );
      expect(() => gv2DeriveBackupKey(Uint8List(31)), throwsArgumentError);
    });
  });

  group('the blob', () {
    test('round trip, any number of groups', () {
      for (final count in [0, 1, 2, 31, 32]) {
        final entries = [for (var i = 0; i < count; i++) _entry('$i', revision: i)];
        final opened = gv2OpenBackup(_key, gv2SealBackup(_key, entries))!;
        expect(opened, hasLength(count));
        for (var i = 0; i < count; i++) {
          expect(opened[i].groupId, entries[i].groupId);
          expect(opened[i].masterKey, entries[i].masterKey);
          expect(opened[i].revision, i);
          expect(opened[i].chain, entries[i].chain);
          expect(opened[i].stateHash, entries[i].stateHash);
        }
      }
    });

    test('is the documented layout (golden vector)', () {
      final entries = [_entry('a', revision: 0x01020304), _entry('b', revision: 0)];
      final blob = gv2SealBackup(_key, entries, nonce: _nonce);

      // Assembled by hand from the layout in the design document (§25).
      final plain = Uint8List(4096);
      final view = ByteData.sublistView(plain);
      view.setUint32(0, 2, Endian.big);
      var at = 4;
      for (final e in entries) {
        plain.setAll(at, e.groupId);
        plain.setAll(at + 32, e.masterKey);
        view.setUint32(at + 64, e.revision, Endian.big);
        plain.setAll(at + 68, e.chain);
        plain.setAll(at + 100, e.stateHash);
        at += 132;
      }
      expect(gv2BackupEntryLen, 132);
      expect(_plain(blob), plain);
      expect(blob[0], 0x01);
      expect(blob.sublist(1, 25), _nonce);
      expect(blob.length, 1 + 24 + 16 + 4096);

      final vector = {
        'accountSeed': gv2Hex(_seed),
        'key': gv2Hex(_key),
        'nonce': gv2Hex(_nonce),
        'entries': [
          for (final e in entries)
            {
              'groupId': gv2Hex(e.groupId),
              'masterKey': gv2Hex(e.masterKey),
              'revision': e.revision,
              'chain': gv2Hex(e.chain),
              'stateHash': gv2Hex(e.stateHash),
            },
        ],
        'blobLength': blob.length,
        'blobHead': gv2Hex(Uint8List.fromList(blob.sublist(0, 96))),
        'blobSha256': gv2Hex(
          Uint8List.fromList(hash.sha256.convert(blob).bytes),
        ),
      };
      final file = File(_fixturePath);
      if (Platform.environment['GV2_BACKUP_WRITE_VECTORS'] == '1') {
        file.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(vector)}\n',
        );
      }
      expect(jsonDecode(file.readAsStringSync()), vector);
    });

    test('hides how many groups there are: a size class, a fresh nonce', () {
      final one = gv2SealBackup(_key, [_entry('a')]);
      final many = gv2SealBackup(_key, [for (var i = 0; i < 31; i++) _entry('$i')]);
      expect(one.length, many.length);
      // 31 groups fill 4096 bytes (4 + 31 × 132 = 4096); one more needs the
      // next class.
      final more = gv2SealBackup(_key, [for (var i = 0; i < 32; i++) _entry('$i')]);
      expect(more.length, 1 + 24 + 16 + 8192);
      expect(gv2BackupBuckets, [4096, 8192, 16384, 32768, 65536, 131072]);
      expect(gv2BackupMaxGroups, 992);
      // The same list twice is not the same bytes.
      expect(gv2SealBackup(_key, [_entry('a')]), isNot(one));
    });

    test('the largest list fits; one more group does not', () {
      final entry = _entry('a');
      final full = List.filled(gv2BackupMaxGroups, entry);
      final blob = gv2SealBackup(_key, full);
      expect(blob.length, 1 + 24 + 16 + 131072);
      expect(blob.length, lessThan(256 * 1024)); // the server's limit
      expect(gv2OpenBackup(_key, blob), hasLength(gv2BackupMaxGroups));
      expect(() => gv2SealBackup(_key, [...full, entry]), throwsArgumentError);
    });

    test('what does not open', () {
      final blob = gv2SealBackup(_key, [_entry('a')], nonce: _nonce);
      expect(gv2OpenBackup(_key, blob), hasLength(1));

      // Another account's key.
      expect(gv2OpenBackup(gv2DeriveBackupKey(gv2TestSha('x')), blob), isNull);
      expect(gv2OpenBackup(Uint8List(31), blob), isNull);
      // Any altered byte: version, nonce, body, tag.
      for (final at in [0, 1, 24, 25, 40, 41, 300, blob.length - 1]) {
        final altered = Uint8List.fromList(blob)..[at] ^= 0x01;
        expect(gv2OpenBackup(_key, altered), isNull, reason: 'byte $at');
      }
      // Cut short, or empty.
      expect(gv2OpenBackup(_key, Uint8List(0)), isNull);
      expect(gv2OpenBackup(_key, Uint8List.fromList(blob.sublist(0, 44))), isNull);
      expect(
        gv2OpenBackup(_key, Uint8List.fromList(blob.sublist(0, blob.length - 1))),
        isNull,
      );
    });

    test('what opens but is not a backup', () {
      Uint8List plain(int length, int count, {int? stray}) {
        final out = Uint8List(length);
        ByteData.sublistView(out).setUint32(0, count, Endian.big);
        if (stray != null) out[stray] = 1;
        return out;
      }

      // As the encoder makes it: accepted.
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 0))), isEmpty);
      // A version this code does not know.
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 0), version: 2)), isNull);
      // A length that is no size class.
      expect(gv2OpenBackup(_key, _sealRaw(plain(4095, 0))), isNull);
      expect(gv2OpenBackup(_key, _sealRaw(plain(4100, 0))), isNull);
      expect(gv2OpenBackup(_key, _sealRaw(plain(4, 0))), isNull);
      // More groups than the plaintext holds.
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 32))), isNull);
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 0xFFFFFFFF))), isNull);
      // Padding that is not zero — right after the entries, and at the end.
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 0, stray: 4))), isNull);
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 0, stray: 4095))), isNull);
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 1, stray: 136))), isNull);
      expect(gv2OpenBackup(_key, _sealRaw(plain(4096, 1, stray: 135))), hasLength(1));
    });

    test('an entry has exact lengths', () {
      final e = _entry('a');
      Gv2BackupEntry make({
        Uint8List? groupId,
        Uint8List? masterKey,
        int revision = 1,
        Uint8List? chain,
        Uint8List? stateHash,
      }) => Gv2BackupEntry(
        groupId: groupId ?? e.groupId,
        masterKey: masterKey ?? e.masterKey,
        revision: revision,
        chain: chain ?? e.chain,
        stateHash: stateHash ?? e.stateHash,
      );
      expect(() => make(groupId: Uint8List(31)), throwsArgumentError);
      expect(() => make(masterKey: Uint8List(33)), throwsArgumentError);
      expect(() => make(chain: Uint8List(0)), throwsArgumentError);
      expect(() => make(stateHash: Uint8List(31)), throwsArgumentError);
      expect(() => make(revision: -1), throwsArgumentError);
      expect(() => make(revision: 0x100000000), throwsArgumentError);
      expect(make(revision: 0xFFFFFFFF).revision, 0xFFFFFFFF);
      expect(
        () => gv2SealBackup(_key, [e], nonce: Uint8List(23)),
        throwsArgumentError,
      );
      expect(() => gv2SealBackup(Uint8List(31), [e]), throwsArgumentError);
    });
  });

  group('the service', () {
    late SnowDatabase db;
    late _Api api;
    late int now;
    final me = KeyDerivation.deriveSnowChatId(
      Uint8List.fromList(
        ed.SigningKey(seed: _seed).verifyKey.asTypedList,
      ),
    );

    /// [delay]: how long after a change the write is made (the tests of
    /// what is written: none).
    Gv2Backup backupOf(
      SnowDatabase database, {
      Duration Function()? delay,
    }) => Gv2Backup(
      groups: database.gv2Store,
      api: api,
      key: () async => _key,
      mySnowId: me,
      nowMs: () => now,
      writeDelay: delay ?? () => Duration.zero,
    );
    late Gv2Backup backup;

    setUp(() {
      db = SnowDatabase(NativeDatabase.memory());
      api = _Api();
      now = DateTime.utc(2026, 11, 19, 12).millisecondsSinceEpoch;
      backup = backupOf(db);
    });
    tearDown(() => db.close());

    /// A group row of this device in [membership], as [entry] describes it.
    Future<String> hold(
      Gv2BackupEntry entry, {
      Gv2Membership membership = Gv2Membership.active,
      SnowDatabase? on,
    }) async {
      final database = on ?? db;
      final anchored = membership == Gv2Membership.invited
          ? Gv2Membership.invited
          : Gv2Membership.awaitingConfirm;
      expect(
        await database.gv2Store.insertAnchored(
          groupId: entry.groupId,
          masterKey: entry.masterKey,
          myCiphertext: ZkGroup.encryptMember(
            masterKey: entry.masterKey,
            accountId: gv2AccountIdOfSnowId(me),
          ),
          protocolVersion: gv2ProtocolVersion,
          revision: entry.revision,
          chain: entry.chain,
          stateHash: entry.stateHash,
          membership: anchored,
          inviteSeed: anchored == Gv2Membership.invited
              ? gv2TestSha('invite seed')
              : null,
        ),
        isTrue,
      );
      final id = gv2Hex(entry.groupId);
      if (membership != anchored) {
        await (database.update(database.gv2Groups)
              ..where((g) => g.groupId.equals(id)))
            .write(Gv2GroupsCompanion(membership: Value(membership)));
      }
      return id;
    }

    Future<void> change(String id, Gv2GroupsCompanion to) =>
        (db.update(db.gv2Groups)..where((g) => g.groupId.equals(id))).write(to);

    test('a new install takes its groups from the blob, once', () async {
      final a = _entry('a', revision: 3);
      final b = _entry('b', revision: 9);
      api.blob = gv2SealBackup(_key, [a, b]);

      final outcome = await backup.sync();
      expect(outcome.restored, [gv2Hex(a.groupId), gv2Hex(b.groupId)]);
      expect(outcome.looked, isTrue);
      expect(outcome.reached, isTrue);

      for (final e in [a, b]) {
        final row = (await db.gv2Store.group(gv2Hex(e.groupId)))!;
        expect(row.masterKey, e.masterKey);
        expect(row.revision, e.revision);
        expect(row.chain, e.chain);
        expect(row.stateHash, e.stateHash);
        // A member by the backup's word only: nothing is sent before the
        // log is followed and a member confirms the head.
        expect(row.membership, Gv2Membership.awaitingConfirm);
        expect(row.stateLoaded, isFalse);
        expect(row.resetPending, isTrue);
        expect(row.hold, Gv2Hold.none);
        expect(
          row.myCiphertext,
          gv2Hex(
            ZkGroup.encryptMember(
              masterKey: e.masterKey,
              accountId: gv2AccountIdOfSnowId(me),
            ),
          ),
        );
      }
      expect(api.fetches, 1);

      // A later blob (whoever wrote it) is not taken in again: the device
      // is the truth from now on.
      api.blob = gv2SealBackup(_key, [a, b, _entry('c')]);
      final again = await backup.sync();
      expect(again.restored, isEmpty);
      expect(await db.gv2Store.groups(), hasLength(2));
      expect(api.fetches, lessThanOrEqualTo(2)); // at most the conflict's
      // …and the same holds for a new run of the app.
      expect((await backupOf(db).sync()).restored, isEmpty);
      expect(await db.gv2Store.groups(), hasLength(2));
    });

    test('no blob, or one that does not open: nothing is restored, and the '
        'device\'s own list is written', () async {
      final mine = await hold(_entry('mine'));
      final first = await backup.sync();
      expect(first.restored, isEmpty);
      expect(first.written, isTrue);
      expect(api.groupIds, [mine]);

      // Another install, facing a blob of another key.
      final other = SnowDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      api.blob = gv2SealBackup(gv2DeriveBackupKey(gv2TestSha('x')), [_entry('z')]);
      final outcome = await backupOf(other).sync();
      expect(outcome.restored, isEmpty);
      expect(outcome.looked, isTrue);
      expect(await other.gv2Store.groups(), isEmpty);
      // It replaced what it could not open (nobody can) with its own list.
      expect(outcome.written, isTrue);
      expect(api.groupIds, isEmpty);
    });

    test('a group the device already holds keeps its own anchor; an entry '
        'whose id is not its key\'s is skipped', () async {
      final held = _entry('held', revision: 20);
      final id = await hold(held);
      final stale = Gv2BackupEntry(
        groupId: held.groupId,
        masterKey: held.masterKey,
        revision: 2,
        chain: gv2TestSha('older chain'),
        stateHash: gv2TestSha('older state'),
      );
      final wrongId = Gv2BackupEntry(
        groupId: gv2TestSha('not the id of this key'),
        masterKey: _entry('w').masterKey,
        revision: 1,
        chain: gv2TestSha('c'),
        stateHash: gv2TestSha('s'),
      );
      final fresh = _entry('fresh');
      api.blob = gv2SealBackup(_key, [stale, wrongId, fresh]);

      final outcome = await backup.sync();
      expect(outcome.restored, [gv2Hex(fresh.groupId)]);
      final row = (await db.gv2Store.group(id))!;
      expect(row.revision, 20);
      expect(row.chain, held.chain);
      expect(row.resetPending, isFalse);
      expect(await db.gv2Store.group(gv2Hex(wrongId.groupId)), isNull);
      expect(await db.gv2Store.groups(), hasLength(2));
    });

    test('what is in the list: the groups this account is a member of', () async {
      final active = await hold(_entry('active'));
      final waiting = await hold(
        _entry('waiting'),
        membership: Gv2Membership.awaitingConfirm,
      );
      final frozen = await hold(_entry('frozen'));
      await db.gv2Store.setHold(frozen, Gv2Hold.frozen);
      await hold(_entry('invited'), membership: Gv2Membership.invited);
      for (final m in [
        Gv2Membership.creating,
        Gv2Membership.left,
        Gv2Membership.removed,
        Gv2Membership.declined,
        Gv2Membership.ended,
      ]) {
        await hold(_entry(m.name), membership: m);
      }

      expect((await backup.sync()).written, isTrue);
      expect(api.groupIds, [active, waiting, frozen]..sort());
      // Each with the point this device verified.
      final opened = gv2OpenBackup(_key, api.blob!)!;
      for (final e in opened) {
        final row = (await db.gv2Store.group(gv2Hex(e.groupId)))!;
        expect(e.masterKey, row.masterKey);
        expect(e.revision, row.revision);
        expect(e.chain, row.chain);
        expect(e.stateHash, row.stateHash);
      }
    });

    test('written again only when it should hold something else', () async {
      final a = await hold(_entry('a'));
      expect((await backup.sync()).written, isTrue);
      expect(api.stores, 1);
      final first = api.blob;

      // Nothing changed: no call at all.
      final fetches = api.fetches;
      expect((await backup.sync()).written, isFalse);
      expect(api.stores, 1);
      expect(api.fetches, fetches);

      // The group moved on without a removal (a rename, a join): the anchor
      // in the blob still serves.
      await change(a, const Gv2GroupsCompanion(revision: Value(8)));
      expect((await backup.sync()).written, isFalse);

      // A member was removed: an anchor from before it would let a server
      // hide the removal from the next install.
      await change(a, const Gv2GroupsCompanion(lastRemovalRevision: Value(9)));
      expect((await backup.sync()).written, isTrue);
      expect(api.blob, isNot(first));
      expect(gv2OpenBackup(_key, api.blob!)!.single.revision, 8);
      await change(a, const Gv2GroupsCompanion(lastRemovalRevision: Value(12)));
      expect((await backup.sync()).written, isTrue);
      expect(api.stores, 3);

      // A group more, a group less.
      final b = await hold(_entry('b'));
      expect((await backup.sync()).written, isTrue);
      expect(api.groupIds, [a, b]..sort());
      await change(b, const Gv2GroupsCompanion(membership: Value(Gv2Membership.left)));
      expect((await backup.sync()).written, isTrue);
      expect(api.groupIds, [a]);
      expect(api.stores, 5);

      // The confirmation of the head changes nothing in the list.
      await change(
        a,
        const Gv2GroupsCompanion(membership: Value(Gv2Membership.awaitingConfirm)),
      );
      expect((await backup.sync()).written, isFalse);

      // Otherwise once a week.
      now += const Duration(days: 6).inMilliseconds;
      expect((await backup.sync()).written, isFalse);
      now += const Duration(days: 2).inMilliseconds;
      expect((await backup.sync()).written, isTrue);
      expect(api.stores, 6);
    });

    test('a write is made at a random time 1–6 h after the list changed, not '
        'at once; the due time survives a restart, is not pushed back by '
        'later changes, and what is written is the list as it is then',
        () async {
      const hour = 3600 * 1000;
      var draws = 0;
      Duration delay() {
        draws++;
        return const Duration(hours: 2);
      }

      backup = backupOf(db, delay: delay);
      final a = await hold(_entry('a'));
      final t0 = now;
      var outcome = await backup.sync();
      expect(outcome.looked, isTrue);
      expect(outcome.written, isFalse);
      expect(api.stores, 0);
      expect(await backup.writeDueAtMs(), t0 + 2 * hour);

      // Another group an hour later: the same due time (no new draw).
      now += hour;
      final b = await hold(_entry('b'));
      expect((await backup.sync()).written, isFalse);
      expect(draws, 1);
      expect(await backup.writeDueAtMs(), t0 + 2 * hour);

      // A restart keeps the due time.
      backup = backupOf(db, delay: delay);
      now = t0 + 2 * hour - 1;
      expect((await backup.sync()).written, isFalse);
      now += 1;
      expect((await backup.sync()).written, isTrue);
      expect(api.groupIds, [a, b]..sort(), reason: 'the list as it is now');
      expect(await backup.writeDueAtMs(), isNull);
      expect(draws, 1);
    });

    test('back to what was written before the write was due: nothing is '
        'pending, nothing is written', () async {
      final a = await hold(_entry('a'));
      expect((await backup.sync()).written, isTrue);
      backup = backupOf(db, delay: () => const Duration(hours: 3));
      await change(a, const Gv2GroupsCompanion(membership: Value(Gv2Membership.left)));
      expect((await backup.sync()).written, isFalse);
      expect(await backup.writeDueAtMs(), isNotNull);
      await change(a, const Gv2GroupsCompanion(membership: Value(Gv2Membership.active)));
      expect((await backup.sync()).written, isFalse);
      expect(await backup.writeDueAtMs(), isNull);
      now += const Duration(hours: 4).inMilliseconds;
      expect((await backup.sync()).written, isFalse);
      expect(api.stores, 1);
    });

    test('a due time further away than any delay (the clock was set back) '
        'is drawn again', () async {
      await hold(_entry('a'));
      backup = backupOf(db, delay: () => const Duration(hours: 1));
      expect((await backup.sync()).written, isFalse);
      final due = (await backup.writeDueAtMs())!;
      now -= const Duration(days: 3).inMilliseconds;
      expect((await backup.sync()).written, isFalse);
      expect(await backup.writeDueAtMs(), now + const Duration(hours: 1).inMilliseconds);
      expect(await backup.writeDueAtMs(), lessThan(due));
    });

    test('the delay is drawn between one and six hours', () {
      for (var i = 0; i < 200; i++) {
        final d = gv2BackupWriteDelay();
        expect(d, greaterThanOrEqualTo(gv2BackupWriteDelayMin));
        expect(d, lessThanOrEqualTo(gv2BackupWriteDelayMax));
      }
      expect(gv2BackupWriteDelayMin, const Duration(hours: 1));
      expect(gv2BackupWriteDelayMax, const Duration(hours: 6));
    });

    test('what was written is remembered across runs of the app', () async {
      await hold(_entry('a'));
      expect((await backup.sync()).written, isTrue);
      final state = (await db.gv2Store.backupState())!;
      expect(state.restored, isTrue);
      expect(state.etag, _tag(api.blob!));
      expect(state.fingerprint, hasLength(32));

      final next = backupOf(db);
      final outcome = await next.sync();
      expect(outcome.looked, isTrue);
      expect(outcome.written, isFalse);
      expect(api.stores, 1);
      expect(api.fetches, 1);
    });

    test('the server holds a blob this device did not write: this device\'s '
        'list replaces it, nothing is merged', () async {
      final a = await hold(_entry('a'));
      expect((await backup.sync()).written, isTrue);
      // An earlier install of the account writes meanwhile.
      api.blob = gv2SealBackup(_key, [_entry('theirs')]);
      final b = await hold(_entry('b'));

      final outcome = await backup.sync();
      expect(outcome.written, isTrue);
      expect(outcome.restored, isEmpty);
      expect(api.groupIds, [a, b]..sort());
      expect((await db.gv2Store.backupState())!.etag, _tag(api.blob!));
      expect(await db.gv2Store.groups(), hasLength(2));
      // Settled: the next sync has nothing to do.
      expect((await backup.sync()).written, isFalse);
    });

    test('a blob that keeps changing under the write: given up for now, '
        'tried again later', () async {
      final a = await hold(_entry('a'));
      api.blob = gv2SealBackup(_key, const []);
      // Restores (nothing), then loses the race twice.
      var races = 0;
      void race() {
        races++;
        api.blob = gv2SealBackup(_key, [_entry('race $races')]);
        if (races < 2) api.beforeStore = race;
      }

      api.beforeStore = race;
      final outcome = await backup.sync();
      expect(outcome.written, isFalse);
      expect(outcome.reached, isFalse);
      expect(outcome.looked, isTrue);
      expect(api.stores, 2);
      expect((await db.gv2Store.backupState())!.fingerprint, isNull);

      expect((await backup.sync()).written, isTrue);
      expect(api.groupIds, [a]);
    });

    test('no network: nothing is decided, and the next sync asks again at '
        'once', () async {
      api.blob = gv2SealBackup(_key, [_entry('a')]);
      api.failWith = const Gv2BackupUnreachable();
      final offline = await backup.sync();
      expect(offline.looked, isFalse);
      expect(offline.reached, isFalse);
      expect(offline.restored, isEmpty);
      expect(await db.gv2Store.backupState(), isNull);
      expect(await db.gv2Store.groups(), isEmpty);

      api.failWith = null;
      final online = await backup.sync();
      expect(online.looked, isTrue);
      expect(online.restored, hasLength(1));
      expect(api.fetches, 2);
    });

    test('the server refuses: not asked again for ten minutes', () async {
      api.blob = gv2SealBackup(_key, [_entry('a')]);
      api.failWith = StateError('429');
      expect((await backup.sync()).looked, isFalse);
      expect(api.fetches, 1);

      api.failWith = null;
      now += gv2BackupRetry.inMilliseconds - 1;
      final early = await backup.sync();
      expect(early.looked, isFalse);
      expect(early.reached, isFalse);
      expect(api.fetches, 1);

      now += 1;
      expect((await backup.sync()).restored, hasLength(1));
      expect(api.fetches, 2);
    });

    test('a failed write keeps "looked": the install knows its groups even '
        'when the blob could not be written', () async {
      await hold(_entry('a'));
      expect((await backup.sync()).written, isTrue);
      await hold(_entry('b'));

      api.failWith = const Gv2BackupUnreachable();
      final offline = await backup.sync();
      expect(offline.looked, isTrue);
      expect(offline.reached, isFalse);
      expect(offline.written, isFalse);

      api.failWith = StateError('500');
      final refused = await backup.sync();
      expect(refused.looked, isTrue);
      expect(refused.reached, isFalse);

      api.failWith = null;
      // Still inside the wait after the refusal.
      expect((await backup.sync()).written, isFalse);
      now += gv2BackupRetry.inMilliseconds;
      expect((await backup.sync()).written, isTrue);
      expect(api.groupIds, hasLength(2));
    });

    test('a restore that stopped half way is finished by the next sync', () async {
      final a = _entry('a');
      final b = _entry('b');
      api.blob = gv2SealBackup(_key, [a, b]);
      // The first group is on the device, the note that the restore is done
      // is not (the app stopped in between).
      await hold(a, membership: Gv2Membership.awaitingConfirm);

      final outcome = await backup.sync();
      expect(outcome.restored, [gv2Hex(b.groupId)]);
      expect(await db.gv2Store.groups(), hasLength(2));
      expect((await db.gv2Store.backupState())!.restored, isTrue);
    });

    test('concurrent syncs are one run', () async {
      api.blob = gv2SealBackup(_key, [_entry('a')]);
      final both = await Future.wait([backup.sync(), backup.sync()]);
      expect(both[0].restored, hasLength(1));
      expect(identical(both[0], both[1]), isTrue);
      expect(api.fetches, 1);
    });

    test('more groups than a blob holds: the first ones by id are kept', () async {
      // Rows only: the list is cut, never refused.
      final ids = <String>[];
      await db.batch((batch) {
        for (var i = 0; i < gv2BackupMaxGroups + 3; i++) {
          final id = gv2Hex(gv2TestSha('many $i'));
          ids.add(id);
          batch.insert(
            db.gv2Groups,
            Gv2GroupsCompanion.insert(
              groupId: id,
              masterKey: gv2TestSha('mk $i'),
              myCiphertext: 'ab' * 65,
              protocolVersion: gv2ProtocolVersion,
              membership: Gv2Membership.active,
              revision: i,
              chain: gv2TestSha('chain $i'),
              stateHash: gv2TestSha('state $i'),
              stateLoaded: false,
              titlePayload: Uint8List(0),
            ),
          );
        }
      });
      expect((await backup.sync()).written, isTrue);
      ids.sort();
      expect(api.groupIds, ids.sublist(0, gv2BackupMaxGroups));
    });
  });
}
