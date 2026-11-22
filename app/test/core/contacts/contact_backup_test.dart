/// @file        contact_backup_test.dart
/// @description The contact backup (design 2026-11-22 §5.10, contract §12.5). The format: the
///              golden vector in test/fixtures/contact_backup_v1.json is checked independently —
///              the key by an HKDF computed here with package:crypto, the blob by opening it with
///              pinenacl directly (utf8 JSON, then 0x00 up to the bucket). Padding buckets from 4
///              to 256 KiB, a JSON too large refused, a blob with another key / version / padding
///              not opened. The sync on a real database and a fake server: a new install restores
///              once and merges into rows made before the restore (a notice that arrived first is
///              kept), restored accounts of the list are vouched / pinned, restored blocks are
///              taken in and the server's tags replaced; blocked accounts are not restored as
///              contacts; a 409 is answered by writing again under the tag in its body; the
///              periodic write happens only when due and even without a change; a new account
///              writes its empty backup at once and keeps the block replace due (an identity
///              registered again keeps this device's blocks); a write before the restore restores
///              first; a changed block tag key version replaces the tags once — learned from a block
///              answer or from the backup fetch, once per run. The restore notice: due after the
///              restore (with the backup's date, or none found) until dismissed; a new account has
///              none; the own name certificate's write does not undo it. Review fixes: a backup that
///              does not open is not "no backup" (nothing restored, replaced or written; told;
///              retryRestore); the merge takes the backup's addedMe unless the peer said "removed"
///              on this install, and drops the rows of accounts the restore blocks; a block / unblock
///              makes the write due 1–10 minutes later (writeSoon), not at once.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (review fixes: unreadable backup, merge of addedMe, blocked rows dropped,
///              writeSoon, key version from the fetch, markNewAccount keeps the replace due).
///              Earlier 2026-11-22 (the restore notice)
///
/// @functions
///  - _Server: the server's two calls with etag / ifMatch / 409 semantics
///  - main(): the cases above
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/x25519.dart' as nacl;
import 'package:snowchat/core/contacts/contact_backup.dart';
import 'package:snowchat/core/contacts/contact_store.dart';
import 'package:snowchat/core/storage/database.dart';

const _alice = 'snow0123456789abcdef0123456789abcdef';
const _bob = 'snow1123456789abcdef0123456789abcdef';
const _mallory = 'snow2123456789abcdef0123456789abcdef';
const _carol = 'snow3123456789abcdef0123456789abcdef';

Uint8List _unhex(String h) => Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16),
    ]);

String _tag(Uint8List blob) => base64Encode(hash.sha256.convert(blob).bytes);

/// The server: one blob, its tag, 409 when ifMatch is not the stored tag.
class _Server implements ContactBackupApi {
  Uint8List? blob;
  bool down = false;
  int fetches = 0;
  int? keyVersion;
  final List<String?> writes = [];

  String? get etag => blob == null ? null : _tag(blob!);

  @override
  Future<ContactBackupBlob> fetch() async {
    if (down) throw const ContactBackupUnreachable();
    fetches++;
    return ContactBackupBlob(blob, etag, blockKeyVersion: keyVersion);
  }

  @override
  Future<String> store(Uint8List b, String? ifMatch) async {
    if (down) throw const ContactBackupUnreachable();
    writes.add(ifMatch);
    if (ifMatch != etag) throw ContactBackupConflict(etag);
    blob = b;
    return etag!;
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('format', () {
    final fixture = jsonDecode(
        File('test/fixtures/contact_backup_v1.json').readAsStringSync()) as Map;

    test('the key: HKDF-SHA256(seed, salt "SnowChat_Contacts_Backup_v1", no info)',
        () {
      final seed = _unhex(fixture['accountSeed'] as String);
      // RFC 5869 by hand: PRK = HMAC(salt, IKM); OKM = HMAC(PRK, info || 0x01).
      final prk = hash.Hmac(hash.sha256, utf8.encode('SnowChat_Contacts_Backup_v1'))
          .convert(seed)
          .bytes;
      final okm = hash.Hmac(hash.sha256, prk).convert([0x01]).bytes;
      expect(deriveContactBackupKey(seed), okm);
      expect(deriveContactBackupKey(seed), _unhex(fixture['key'] as String));
    });

    test('the golden blob: sealed the same, opened by pinenacl to the JSON and '
        'zero padding', () {
      final key = _unhex(fixture['key'] as String);
      final nonce = _unhex(fixture['nonce'] as String);
      final blob = _unhex(fixture['blob'] as String);
      expect(blob[0], 0x01);
      expect(blob.sublist(1, 25), nonce);
      final plain = nacl.SecretBox(key).decrypt(nacl.EncryptedMessage(
        nonce: nonce,
        cipherText: blob.sublist(25),
      ));
      final json = utf8.encode(fixture['json'] as String);
      expect(plain.length, fixture['bucket']);
      expect(plain.sublist(0, json.length), json);
      expect(plain.sublist(json.length).every((b) => b == 0), isTrue);

      final opened = openContactBackup(key, blob)!;
      expect(opened.savedAtMs, 1795000000000);
      expect(opened.contacts.map((c) => c.snowId), [_alice, _bob]);
      expect(opened.contacts.first.nickname, 'alice');
      expect(opened.contacts.last.hiddenAtMs, 1794000000000);
      expect(opened.blocks.single.snowId, _mallory);
      expect(opened.blocks.single.nickname, 'mallory');
      // Sealing the same plaintext with the same nonce gives the same bytes.
      expect(sealContactBackup(key, opened, nonce: nonce), blob);
    });

    ContactBackupPlain many(int n) => ContactBackupPlain(
          savedAtMs: 1,
          contacts: [
            for (var i = 0; i < n; i++)
              ContactBackupContact(
                snowId: 'snow${i.toRadixString(16).padLeft(32, '0')}',
                inMyList: true,
                addedMe: false,
                nickname: 'a fairly long nickname $i',
              ),
          ],
          blocks: const [],
        );

    test('padded to the smallest bucket from 4 to 256 KiB', () {
      final key = Uint8List(32);
      int size(int n) => sealContactBackup(key, many(n)).length - 1 - 24 - 16;
      expect(size(0), 4096);
      expect(size(30), 8192);
      expect(size(600), 131072);
      expect(size(1200), 262144);
      expect(() => sealContactBackup(key, many(2000)), throwsArgumentError);
    });

    test('another key, version or padding: not opened', () {
      final key = Uint8List.fromList(List.filled(32, 1));
      final blob = sealContactBackup(key, many(1));
      expect(openContactBackup(Uint8List(32), blob), isNull);
      expect(openContactBackup(key, Uint8List.fromList([2, ...blob.sublist(1)])), isNull);
      // A plaintext whose padding is not all zero.
      final nonce = Uint8List(24);
      final bad = Uint8List(4096)..setAll(0, utf8.encode('{"v":1}'))..[4000] = 1;
      final box = nacl.SecretBox(key).encrypt(bad, nonce: nonce);
      expect(
          openContactBackup(key, Uint8List.fromList([1, ...nonce, ...box.cipherText])),
          isNull);
    });
  });

  group('sync', () {
    late SnowDatabase db;
    late _Server server;
    late Map<String, String?> blocked;
    late List<String> replaced;
    late bool replaceOk;
    late List<(String, Uint8List?)> restoredMarks;
    late int clock;
    late ContactBackup backup;
    late ContactStore store;
    final key = Uint8List.fromList(List.filled(32, 7));

    setUp(() {
      db = SnowDatabase(NativeDatabase.memory());
      server = _Server();
      blocked = {};
      replaced = [];
      replaceOk = true;
      restoredMarks = [];
      clock = 1000000;
      backup = ContactBackup(
        dao: db.contactDao,
        api: server,
        key: () async => key,
        hooks: ContactBackupHooks(
          blockedAccounts: () async => Map.of(blocked),
          mergeBlocks: (b) async {
            for (final e in b.entries) {
              blocked.putIfAbsent(e.key, () => e.value);
            }
          },
          replaceServerBlocks: () async {
            replaced.add(blocked.keys.join(','));
            return replaceOk;
          },
          restoredInMyList: (id, pub) async => restoredMarks.add((id, pub)),
        ),
        nowMs: () => clock,
      );
      store = ContactStore(
        dao: db.contactDao,
        send: (_, _) async {},
        vouch: (_, _) async {},
        nowMs: () => clock,
      );
    });
    tearDown(() => db.close());

    Uint8List blobOf(List<ContactBackupContact> contacts,
            [List<ContactBackupBlock> blocks = const []]) =>
        sealContactBackup(
            key,
            ContactBackupPlain(savedAtMs: 500, contacts: contacts, blocks: blocks));

    test('a new install restores once, merged into what arrived before it; '
        'then the tags are replaced', () async {
      server.blob = blobOf([
        const ContactBackupContact(
            snowId: _alice, inMyList: true, addedMe: true, nickname: 'alice'),
        // The backup says Bob had added me; since then Bob said he removed
        // me (the live row has addedMe false) — the live word wins.
        const ContactBackupContact(snowId: _bob, inMyList: true, addedMe: true),
        const ContactBackupContact(snowId: _carol, inMyList: false, addedMe: true),
        // Blocked: not restored as a contact.
        const ContactBackupContact(snowId: _mallory, inMyList: true, addedMe: true),
      ], [
        const ContactBackupBlock(snowId: _mallory, nickname: 'mallory'),
      ]);
      // Arrived before the restore: Bob's request and then his removal…
      await store.request(_bob);
      await store.onContactAdded(_bob);
      await store.onContactRemoved(_bob);
      // …and a new request from Carol.
      await store.onContactAdded(_carol);

      expect(await backup.sync(), isTrue);
      expect(backup.lastRestore!.found, isTrue);
      expect(backup.lastRestore!.savedAtMs, 500);
      expect((await store.entry(_alice))!.label, ContactLabel.friend);
      expect((await store.entry(_alice))!.nickname, 'alice');
      expect((await store.entry(_bob))!.label, ContactLabel.requestSent);
      expect((await store.entry(_carol))!.label, ContactLabel.requestReceived);
      expect(await store.entry(_mallory), isNull);
      expect(blocked, {_mallory: 'mallory'});
      expect(replaced, [_mallory]);
      expect(restoredMarks.map((m) => m.$1).toSet(), {_alice, _bob});

      // Once: a second sync does not fetch again.
      final fetches = server.fetches;
      await backup.sync();
      expect(server.fetches, fetches);
      expect(replaced, hasLength(1));
    });

    test('no backup: nothing restored, reported; the tags are still replaced',
        () async {
      await backup.sync();
      expect(backup.lastRestore!.found, isFalse);
      expect(replaced, ['']);
    });

    test('the restore notice: due with the backup\'s date until dismissed',
        () async {
      server.blob = blobOf(const [
        ContactBackupContact(snowId: _alice, inMyList: true, addedMe: true),
      ]);
      final notices = <ContactRestoreReport?>[];
      final sub = backup.watchRestoreNotice().listen(notices.add);
      await backup.sync();
      await pumpEventQueue();
      expect(notices.last,
          const ContactRestoreReport(found: true, savedAtMs: 500));
      // A later write of the own name certificate leaves it due.
      await db.contactDao.patchSyncState(
          ContactSyncStatesCompanion(ownNameCert: Value(Uint8List(3))));
      await pumpEventQueue();
      expect(notices.last,
          const ContactRestoreReport(found: true, savedAtMs: 500));
      await backup.dismissRestoreNotice();
      await pumpEventQueue();
      expect(notices.last, isNull);
      // Once: the next sync restores nothing and tells nothing.
      await backup.sync();
      await pumpEventQueue();
      expect(notices.last, isNull);
      await sub.cancel();
    });

    test('the restore notice when no backup was found', () async {
      await backup.sync();
      expect(await backup.watchRestoreNotice().first,
          const ContactRestoreReport(found: false));
    });

    test('a new account has no restore notice', () async {
      await backup.markNewAccount();
      await backup.sync();
      expect(await backup.watchRestoreNotice().first, isNull);
    });

    test('a replace the server refused is tried again by the next sync',
        () async {
      replaceOk = false;
      expect(await backup.sync(), isFalse);
      replaceOk = true;
      expect(await backup.sync(), isTrue);
      expect(replaced, hasLength(2));
    });

    test('the periodic write: not before it is due; when due, even with no '
        'change; then the next one a period later', () async {
      await backup.sync();
      expect(server.writes, isEmpty);
      final due = await backup.nextWriteAtMs();
      final period = due - clock;
      expect(period, greaterThanOrEqualTo(const Duration(hours: 6).inMilliseconds));
      expect(period, lessThanOrEqualTo(const Duration(hours: 24).inMilliseconds));

      clock = due - 1;
      await backup.sync();
      expect(server.writes, isEmpty);
      clock = due;
      await backup.sync();
      expect(server.writes, hasLength(1));
      expect(await backup.nextWriteAtMs(), due + period);
      final first = server.blob;

      clock = due + period;
      await backup.sync();
      expect(server.writes, hasLength(2), reason: 'written without a change');
      expect(server.blob, isNot(first), reason: 'a fresh nonce and time');
    });

    test('a 409 is answered by writing again under the tag in its body',
        () async {
      await backup.sync();
      // Another install of this account wrote meanwhile.
      final other = blobOf(const []);
      server.blob = other;
      await store.request(_alice);
      clock = await backup.nextWriteAtMs();
      expect(await backup.sync(), isTrue);
      expect(server.writes, [null, _tag(other)]);
      final opened = openContactBackup(key, server.blob!)!;
      expect(opened.contacts.single.snowId, _alice);
    });

    test('a new account writes its empty backup at once, without a fetch',
        () async {
      await backup.markNewAccount();
      expect(server.fetches, 0);
      expect(server.writes, [null]);
      final opened = openContactBackup(key, server.blob!)!;
      expect(opened.contacts, isEmpty);
      expect(opened.blocks, isEmpty);
      // Nothing to restore afterwards (the one fetch of the run only reads
      // the block tag key version); the replace stays due — an identity
      // registered again (a server reset) keeps this device's blocks.
      blocked[_mallory] = null;
      await backup.sync();
      expect(server.fetches, 1);
      expect(server.writes, [null]);
      expect(replaced, [_mallory]);
      expect(await store.entry(_alice), isNull);
    });

    test('a block / unblock makes the write due 1–10 minutes later (kept as '
        'the next due time), never sooner than the restore', () async {
      server.blob = blobOf([
        const ContactBackupContact(snowId: _alice, inMyList: true, addedMe: true),
      ]);
      var rearmed = 0;
      backup.onWriteDueChanged = () => rearmed++;
      blocked[_mallory] = null;
      await backup.writeSoon();
      expect(rearmed, 1);
      expect(server.writes, isEmpty, reason: 'not at the moment of the block');
      final due = await backup.nextWriteAtMs();
      expect(due - clock,
          inInclusiveRange(const Duration(minutes: 1).inMilliseconds,
              const Duration(minutes: 10).inMilliseconds));
      // A sync before then restores (never a write over an unread backup)
      // but does not write yet.
      await backup.sync();
      expect(server.fetches, 1);
      expect(server.writes, isEmpty);
      clock = due;
      await backup.sync();
      expect(server.writes, hasLength(1));
      final opened = openContactBackup(key, server.blob!)!;
      expect(opened.contacts.single.snowId, _alice);
      expect(opened.blocks.single.snowId, _mallory);
      // A later block with a write due sooner anyway does not push it out.
      final next = await backup.nextWriteAtMs();
      clock = next - 1000;
      await backup.writeSoon();
      expect(await backup.nextWriteAtMs(), next);
      expect(rearmed, 1);
    });

    test('a backup that does not open is not "no backup": nothing restored, '
        'replaced or written; told; tried again', () async {
      server.blob = sealContactBackup(
        Uint8List.fromList(List.filled(32, 9)), // another key
        const ContactBackupPlain(savedAtMs: 1, contacts: [], blocks: []),
      );
      final kept = server.blob;
      blocked[_mallory] = null;
      expect(await backup.sync(), isFalse);
      expect(replaced, isEmpty, reason: 'the server tags are not emptied');
      expect(server.writes, isEmpty);
      expect((await db.contactDao.syncState())!.restored, isFalse);
      expect(await backup.watchRestoreNotice().first,
          const ContactRestoreReport(found: false, unreadable: true));
      // A write that comes due writes nothing over it.
      clock = await backup.nextWriteAtMs();
      await backup.writeSoon();
      expect(await backup.sync(), isFalse);
      expect(server.writes, isEmpty);
      expect(server.blob, kept);

      // The user tries again once the server holds a backup that opens.
      server.blob = blobOf(const [
        ContactBackupContact(snowId: _alice, inMyList: true, addedMe: true),
      ]);
      expect(await backup.retryRestore(), isTrue);
      expect((await store.entry(_alice))!.label, ContactLabel.friend);
      expect(replaced, [_mallory]);
      expect(await backup.watchRestoreNotice().first,
          const ContactRestoreReport(found: true, savedAtMs: 500));
    });

    test('the merge: a live addedMe=false is no word unless the peer said '
        '"removed" on this install; a hidden request stays hidden', () async {
      server.blob = blobOf([
        // Bob added me (backup); on this install I re-added him before the
        // restore and his acceptance never came again.
        const ContactBackupContact(snowId: _bob, inMyList: true, addedMe: true),
        // Carol had added me and I declined (hidden).
        const ContactBackupContact(
            snowId: _carol, inMyList: false, addedMe: true, hiddenAtMs: 400),
        // Alice had added me; on this install she said she removed me.
        const ContactBackupContact(snowId: _alice, inMyList: false, addedMe: true),
      ]);
      await store.request(_bob);
      await store.onContactRemoved(_alice);
      expect(await store.entry(_alice), isNotNull,
          reason: 'kept with neither mark until the restore ran');
      expect((await store.entry(_alice))!.isVisible, isFalse);
      await backup.sync();
      expect((await store.entry(_bob))!.label, ContactLabel.friend);
      final carol = (await store.entry(_carol))!;
      expect(carol.hiddenAtMs, 400);
      expect(carol.isVisible, isFalse);
      expect(await store.entry(_alice), isNull,
          reason: 'the peer\'s "removed" wins; the row with no mark goes');
      // After the restore a "removed" of an account not in the list leaves
      // no row.
      await store.onContactAdded(_mallory);
      await store.onContactRemoved(_mallory);
      expect(await store.entry(_mallory), isNull);
    });

    test('the restore drops the row of an account it blocks — also one a '
        'notice made before the restore', () async {
      server.blob = blobOf(const [], const [
        ContactBackupBlock(snowId: _mallory, nickname: 'mallory'),
      ]);
      await store.onContactAdded(_mallory);
      expect(await store.entry(_mallory), isNotNull);
      await backup.sync();
      expect(await store.entry(_mallory), isNull);
      expect(blocked, {_mallory: 'mallory'});
    });

    test('the block tag key version comes with the backup fetch, once per run',
        () async {
      server.keyVersion = 1;
      await backup.sync(); // the restore's fetch carries it
      expect((await db.contactDao.syncState())!.blockKeyVersion, 1);
      replaced.clear();
      // The key is rotated; a new run learns it from its first fetch.
      server.keyVersion = 2;
      final again = ContactBackup(
        dao: db.contactDao,
        api: server,
        key: () async => key,
        hooks: ContactBackupHooks(
          blockedAccounts: () async => Map.of(blocked),
          mergeBlocks: (_) async {},
          replaceServerBlocks: () async {
            replaced.add('again');
            return true;
          },
          restoredInMyList: (_, _) async {},
        ),
        nowMs: () => clock,
      );
      final fetches = server.fetches;
      await again.sync();
      expect(server.fetches, fetches + 1);
      expect(replaced, ['again']);
      expect((await db.contactDao.syncState())!.blockKeyVersion, 2);
      await again.sync();
      expect(server.fetches, fetches + 1, reason: 'once per run');
      expect(replaced, ['again']);
    });

    test('the sync state is written column by column: the name certificate '
        'written meanwhile is kept', () async {
      server.blob = blobOf(const []);
      await db.contactDao.ensureSyncState(periodMs: 1000, nowMs: clock);
      await db.contactDao.patchSyncState(
          ContactSyncStatesCompanion(ownNameCert: Value(Uint8List(5))));
      await backup.sync();
      clock = await backup.nextWriteAtMs();
      await backup.sync();
      final state = (await db.contactDao.syncState())!;
      expect(state.ownNameCert, Uint8List(5));
      expect(state.restored, isTrue);
    });

    test('a changed block tag key version replaces the tags once', () async {
      await backup.sync();
      replaced.clear();
      await backup.noteBlockKeyVersion(1);
      expect(replaced, isEmpty, reason: 'the first version seen is stored');
      await backup.noteBlockKeyVersion(1);
      expect(replaced, isEmpty);
      await backup.noteBlockKeyVersion(2);
      expect(replaced, hasLength(1));
      await backup.noteBlockKeyVersion(2);
      expect(replaced, hasLength(1));
      expect((await db.contactDao.syncState())!.blockKeyVersion, 2);
    });

    test('no server: nothing is done, and the next sync does it', () async {
      server.down = true;
      expect(await backup.sync(), isFalse);
      server.down = false;
      expect(await backup.sync(), isTrue);
    });
  });
}
