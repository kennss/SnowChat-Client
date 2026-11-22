/// @file        name_certificate_test.dart
/// @description Name certificates (contract §12.3) and NameCertService. Parse: the byte layout,
///              and anything else refused. Verify: a pinned key over the domain label (a wrong
///              key or another label is refused), the authenticated sender as subject, issued
///              within 30 days and not more than 5 minutes ahead. The service: a received
///              certificate renames the peer's contact row and 1:1 title only when newer than the
///              stored one; this account's own certificate is cached, renewed after 7 days, and
///              attached to a peer until the server took one at least as new (markAnnounced).
///              Review fixes: a failed fetch waits (30 s doubling) before the next — no request on
///              every send; the own certificate is checked for signature and subject only and
///              renewed by the local fetch time (a skewed phone clock still sends it);
///              invalidateOwn() after a rename — the next send fetches a new one for every peer,
///              and a fetch that started before the rename stores nothing; forgetAnnounced() — a
///              peer with a new session gets the certificate again; the answer notice.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (fetch backoff, clock skew, invalidateOwn, forgetAnnounced, the answer)
///
/// @functions
///  - main(): the cases above
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/contacts/contact_notice.dart';
import 'package:snowchat/core/contacts/contact_store.dart';
import 'package:snowchat/core/contacts/name_cert_service.dart';
import 'package:snowchat/core/contacts/name_certificate.dart';
import 'package:snowchat/core/storage/database.dart';

import 'name_cert_support.dart';

const _alice = 'snow0123456789abcdef0123456789abcdef';
const _bob = 'snow1123456789abcdef0123456789abcdef';
const _me = 'snow2123456789abcdef0123456789abcdef';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final key = testServerKey();
  final pinned = [Uint8List.fromList(key.verifyKey.asTypedList)];
  final now = DateTime.utc(2026, 11, 22, 12).millisecondsSinceEpoch;

  NameCertificate cert(String snowId, String? name, int issuedAtMs) =>
      NameCertificate.parse(signNameCert(
          key: key, snowId: snowId, name: name, issuedAtMs: issuedAtMs));

  NameCertRejected? rejected(NameCertificate c, {String sender = _alice}) {
    try {
      c.verify(trustedKeys: pinned, expectedSnowId: sender, nowMs: now);
      return null;
    } on NameCertException catch (e) {
      return e.reason;
    }
  }

  group('parse and verify', () {
    test('a good certificate', () {
      final c = cert(_alice, 'Alice 앨리스', now - 1000);
      expect(c.snowId, _alice);
      expect(c.name, 'Alice 앨리스');
      expect(c.issuedAtMs, now - 1000);
      expect(rejected(c), isNull);
      // The base64 round trip is what travels in messages.
      expect(NameCertificate.tryParseBase64(c.base64)!.bytes, c.bytes);
    });

    test('no name is a zero-length name', () {
      final c = cert(_alice, null, now);
      expect(c.name, isNull);
      expect(rejected(c), isNull);
    });

    test('another key: refused', () {
      final other = NameCertificate.parse(signNameCert(
          key: testServerKey(0x07), snowId: _alice, name: 'A', issuedAtMs: now));
      expect(rejected(other), NameCertRejected.signature);
    });

    test('another domain label: refused', () {
      final other = NameCertificate.parse(signNameCert(
          key: key,
          snowId: _alice,
          name: 'A',
          issuedAtMs: now,
          label: 'SnowChat-SenderCert-v1'));
      expect(rejected(other), NameCertRejected.signature);
    });

    test('a changed byte breaks the signature', () {
      final bytes = signNameCert(key: key, snowId: _alice, name: 'Al', issuedAtMs: now);
      bytes[bytes.length - 70] ^= 1; // a byte of the name
      expect(rejected(NameCertificate.parse(bytes)), NameCertRejected.signature);
    });

    test('another account than the sender: refused', () {
      expect(rejected(cert(_bob, 'Bob', now), sender: _alice),
          NameCertRejected.wrongSubject);
    });

    test('older than 30 days: refused; 30 days exactly: taken', () {
      final day = const Duration(days: 1).inMilliseconds;
      expect(rejected(cert(_alice, 'A', now - 30 * day - 1)),
          NameCertRejected.expired);
      expect(rejected(cert(_alice, 'A', now - 30 * day)), isNull);
    });

    test('more than 5 minutes ahead: refused; within: taken', () {
      final minute = const Duration(minutes: 1).inMilliseconds;
      expect(rejected(cert(_alice, 'A', now + 5 * minute + 1)),
          NameCertRejected.future);
      expect(rejected(cert(_alice, 'A', now + 5 * minute)), isNull);
    });

    test('malformed: wrong version, truncated, trailing bytes, not a snowId',
        () {
      final good = signNameCert(key: key, snowId: _alice, name: 'A', issuedAtMs: now);
      expect(() => NameCertificate.parse(Uint8List.fromList([2, ...good.sublist(1)])),
          throwsFormatException);
      expect(() => NameCertificate.parse(good.sublist(0, good.length - 1)),
          throwsFormatException);
      expect(() => NameCertificate.parse(Uint8List.fromList([...good, 0])),
          throwsFormatException);
      expect(
          () => NameCertificate.parse(signNameCert(
              key: key, snowId: 'snowXYZ', name: 'A', issuedAtMs: now)),
          throwsFormatException);
      expect(NameCertificate.tryParseBase64('not base64!'), isNull);
      expect(NameCertificate.tryParseBase64(42), isNull);
    });
  });

  group('NameCertService', () {
    late SnowDatabase db;
    late int clock;
    late int fetches;
    late Uint8List Function() ownCert;
    late NameCertService service;

    setUp(() {
      db = SnowDatabase(NativeDatabase.memory());
      clock = now;
      fetches = 0;
      ownCert = () => signNameCert(key: key, snowId: _me, name: 'Me', issuedAtMs: clock);
      service = NameCertService(
        dao: db.contactDao,
        conversations: db.conversationDao,
        fetchOwn: () async {
          fetches++;
          return ownCert();
        },
        trustedKeys: pinned,
        mySnowId: () => _me,
        nowMs: () => clock,
      );
    });
    tearDown(() => db.close());

    test('a received certificate renames the contact and the 1:1 title, only '
        'when newer than the stored one', () async {
      final store = ContactStore(
        dao: db.contactDao,
        send: (_, _) async {},
        vouch: (_, _) async {},
        nowMs: () => clock,
      );
      await store.request(_alice);
      await db.conversationDao.findOrCreate(
          id: _alice, type: 'direct', participantIds: [_me, _alice], title: _alice);

      expect(await service.receive(_alice, cert(_alice, 'Alice', now - 10).base64),
          isTrue);
      expect((await store.entry(_alice))!.nickname, 'Alice');
      expect((await db.conversationDao.getConversation(_alice))!.title, 'Alice');
      expect(service.cachedName(_alice), 'Alice');

      // An older one: nothing changes.
      expect(await service.receive(_alice, cert(_alice, 'Old', now - 20).base64),
          isFalse);
      expect(await service.nameOf(_alice), 'Alice');
      // The same one again: nothing changes.
      expect(await service.receive(_alice, cert(_alice, 'Alice', now - 10).base64),
          isFalse);
      // A newer one renames.
      expect(await service.receive(_alice, cert(_alice, 'Alicia', now).base64),
          isTrue);
      expect((await store.entry(_alice))!.nickname, 'Alicia');
      expect((await db.conversationDao.getConversation(_alice))!.title, 'Alicia');
    });

    test("another account's certificate or another key: ignored", () async {
      expect(await service.receive(_alice, cert(_bob, 'Bob', now).base64), isFalse);
      final forged = signNameCert(
          key: testServerKey(0x07), snowId: _alice, name: 'Evil', issuedAtMs: now);
      expect(await service.receive(_alice, NameCertificate.parse(forged).base64),
          isFalse);
      expect(await service.nameOf(_alice), isNull);
    });

    test('a name learned before the request names the new contact row',
        () async {
      await service.receive(_alice, cert(_alice, 'Alice', now).base64);
      final store = ContactStore(
        dao: db.contactDao,
        send: (_, _) async {},
        vouch: (_, _) async {},
        nowMs: () => clock,
      );
      await store.onContactAdded(_alice);
      expect((await store.entry(_alice))!.nickname, 'Alice');
    });

    test('own certificate: cached, renewed after 7 days, attached until the '
        'server took one at least as new', () async {
      final first = await service.certToAttach(_alice);
      expect(first, isNotNull);
      expect(fetches, 1);
      // Cached: no second fetch, attached again (not announced yet).
      expect((await service.certToAttach(_alice))!.issuedAtMs, first!.issuedAtMs);
      expect(fetches, 1);
      await service.markAnnounced(_alice, first.issuedAtMs);
      expect(await service.certToAttach(_alice), isNull);
      // A contact_added always carries it.
      expect(await service.certToAttach(_alice, always: true), isNotNull);
      // Another peer still gets it.
      expect(await service.certToAttach(_bob), isNotNull);

      // Eight days later: renewed, and newer than what Alice got.
      clock += const Duration(days: 8).inMilliseconds;
      final renewed = await service.certToAttach(_alice);
      expect(fetches, 2);
      expect(renewed!.issuedAtMs, greaterThan(first.issuedAtMs));
      // An announce of the older one does not lower the mark.
      await service.markAnnounced(_alice, renewed.issuedAtMs);
      await service.markAnnounced(_alice, first.issuedAtMs);
      expect(await service.certToAttach(_alice), isNull);
    });

    test('the server cannot give one: the cached one while still valid, then '
        'none', () async {
      await service.ownCertificate();
      ownCert = () => throw StateError('offline');
      clock += const Duration(days: 10).inMilliseconds;
      expect(await service.ownCertificate(), isNotNull);
      clock += const Duration(days: 25).inMilliseconds;
      expect(await service.ownCertificate(), isNull);
    });

    test('a failed fetch is not tried again before a growing wait', () async {
      ownCert = () => throw StateError('429');
      expect(await service.ownCertificate(), isNull);
      expect(fetches, 1);
      // Every send asks: no request until the wait is over.
      for (var i = 0; i < 5; i++) {
        expect(await service.certToAttach(_alice), isNull);
      }
      expect(fetches, 1);
      clock += const Duration(seconds: 30).inMilliseconds;
      await service.ownCertificate();
      expect(fetches, 2);
      // The wait doubled.
      clock += const Duration(seconds: 30).inMilliseconds;
      await service.ownCertificate();
      expect(fetches, 2);
      clock += const Duration(seconds: 30).inMilliseconds;
      ownCert = () => signNameCert(key: key, snowId: _me, name: 'Me', issuedAtMs: clock);
      expect(await service.ownCertificate(), isNotNull);
      expect(fetches, 3);
    });

    test("a phone clock far off: the own certificate is still taken and sent, "
        'and renewed by the time it was fetched here', () async {
      final serverNow = clock;
      // The phone's clock is 60 days ahead of the server's.
      clock = serverNow + const Duration(days: 60).inMilliseconds;
      ownCert = () => signNameCert(key: key, snowId: _me, name: 'Me', issuedAtMs: serverNow);
      expect(await service.certToAttach(_alice), isNotNull);
      expect(fetches, 1);
      clock += const Duration(days: 6).inMilliseconds;
      expect(await service.certToAttach(_alice), isNotNull);
      expect(fetches, 1, reason: 'fresh by this device\'s own fetch time');
      // 60 days behind instead: taken too.
      final behind = NameCertService(
        dao: db.contactDao,
        conversations: db.conversationDao,
        fetchOwn: () async => signNameCert(
            key: key, snowId: _me, name: 'Me', issuedAtMs: serverNow),
        trustedKeys: pinned,
        mySnowId: () => _me,
        nowMs: () => serverNow - const Duration(days: 60).inMilliseconds,
      );
      await behind.invalidateOwn();
      expect(await behind.ownCertificate(), isNotNull);
    });

    test('a rename: the cached certificate goes, the next send fetches a new '
        'one and carries it to a peer that had the old one', () async {
      final first = (await service.certToAttach(_alice))!;
      await service.markAnnounced(_alice, first.issuedAtMs);
      expect(await service.certToAttach(_alice), isNull);
      clock += 1000;
      ownCert = () => signNameCert(key: key, snowId: _me, name: 'New', issuedAtMs: clock);
      await service.invalidateOwn();
      final renewed = (await service.certToAttach(_alice))!;
      expect(fetches, 2);
      expect(renewed.name, 'New');
    });

    test('a fetch that started before the rename stores nothing', () async {
      final gate = Completer<Uint8List>();
      final slow = NameCertService(
        dao: db.contactDao,
        conversations: db.conversationDao,
        fetchOwn: () => gate.future,
        trustedKeys: pinned,
        mySnowId: () => _me,
        nowMs: () => clock,
      );
      final pending = slow.ownCertificate();
      await pumpEventQueue();
      await slow.invalidateOwn();
      gate.complete(signNameCert(key: key, snowId: _me, name: 'Old', issuedAtMs: clock));
      expect(await pending, isNull);
      expect((await db.contactDao.syncState())?.ownNameCert, isNull);
    });

    test('a peer with a new session gets the certificate again', () async {
      final own = (await service.certToAttach(_alice))!;
      await service.markAnnounced(_alice, own.issuedAtMs);
      expect(await service.certToAttach(_alice), isNull);
      await service.forgetAnnounced(_alice);
      expect(await service.certToAttach(_alice), isNotNull);
      await service.forgetAnnounced(_bob); // no row: nothing
      expect(await db.contactDao.peerName(_bob), isNull);
    });

    test("the server's certificate for another account is not carried",
        () async {
      ownCert = () => signNameCert(key: key, snowId: _bob, name: 'X', issuedAtMs: clock);
      expect(await service.ownCertificate(), isNull);
    });

    test('warmUp reads the known names for a synchronous lookup', () async {
      await service.receive(_alice, cert(_alice, 'Alice', now).base64);
      final fresh = NameCertService(
        dao: db.contactDao,
        conversations: db.conversationDao,
        fetchOwn: () async => ownCert(),
        trustedKeys: pinned,
        mySnowId: () => _me,
      );
      expect(fresh.cachedName(_alice), isNull);
      await fresh.warmUp();
      expect(fresh.cachedName(_alice), 'Alice');
    });

    test('a contact notice names its kind and row', () {
      expect(ContactNotice.added.inner, {'type': 'contact_added', 'v': 1});
      expect(ContactNotice.added.isControl, isFalse);
      expect(ContactNotice.added.carriesNameCert, isTrue);
      expect(ContactNotice.removed.inner, {'type': 'contact_removed', 'v': 1});
      expect(ContactNotice.removed.isControl, isTrue);
      expect(ContactNotice.removed.carriesNameCert, isFalse);
      expect(ContactNotice.answer.inner,
          {'type': 'contact_added', 'v': 1, 'answer': true});
      expect(ContactNotice.answer.isControl, isFalse);
      expect(ContactNotice.answer.carriesNameCert, isTrue);
      expect(contactNoticeIsAnswer(ContactNotice.answer.inner.cast()), isTrue);
      expect(contactNoticeIsAnswer(ContactNotice.added.inner.cast()), isFalse);
    });
  });
}
