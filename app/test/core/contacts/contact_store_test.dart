/// @file        contact_store_test.dart
/// @description The friend list rules (design 2026-11-22-friend-graph-off-server §5.1–§5.4) on a
///              real in-memory database: the label table (friend / request sent / request
///              received, none for a row with neither mark); request and accept add the account
///              and send contact_added, vouched for as the user's own choice; decline hides and
///              sends nothing; cancel / unfriend send contact_removed; received notices only move
///              addedMe (idempotent, a removal clears only addedMe, a hidden request comes back
///              without a notification, the peer's notice vouches for nothing); blocking removes
///              the row; sends refused with USER_NOT_FOUND three times in a row mark the account
///              unavailable (the row stays), a send taken or a notice from it clears that. Re-sync:
///              a contact_added from an account in this user's list is answered once with a
///              contact_added marked as an answer (a lost acceptance, a peer that reinstalled), an
///              answer is never answered; resend works for a friend; a contact_removed before the
///              restore of this install keeps a row with neither mark (for the restore's merge).
///              (Replaces friend_actions_vouch_test.dart — the server's friend actions
///              are gone.)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (the answer to a contact_added; a contact_removed before the restore).
///              Earlier 2026-11-22 (the "Account unavailable" count)
///
/// @functions
///  - main(): the cases above
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/contacts/contact_notice.dart';
import 'package:snowchat/core/contacts/contact_store.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart' show VouchSource;
import 'package:snowchat/core/storage/database.dart';

const _alice = 'snow0123456789abcdef0123456789abcdef';
const _bob = 'snow1123456789abcdef0123456789abcdef';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late SnowDatabase db;
  late List<(String, ContactNotice)> sent;
  late List<(String, VouchSource)> vouched;
  late int clock;
  late ContactStore store;

  setUp(() async {
    db = SnowDatabase(NativeDatabase.memory());
    // The restore of this install ran (the cases below are after it, but
    // the one that says otherwise).
    await db.contactDao.ensureSyncState(periodMs: 1, nowMs: 0, restored: true);
    sent = [];
    vouched = [];
    clock = 1000;
    store = ContactStore(
      dao: db.contactDao,
      send: (peer, notice) async => sent.add((peer, notice)),
      vouch: (id, source) async => vouched.add((id, source)),
      nowMs: () => clock,
    );
  });
  tearDown(() => db.close());

  Future<ContactLabel?> label(String id) async => (await store.entry(id))?.label;

  test('the label table', () {
    expect(contactLabelOf(inMyList: true, addedMe: true), ContactLabel.friend);
    expect(contactLabelOf(inMyList: true, addedMe: false), ContactLabel.requestSent);
    expect(contactLabelOf(inMyList: false, addedMe: true),
        ContactLabel.requestReceived);
    expect(contactLabelOf(inMyList: false, addedMe: false), isNull);
  });

  test('request: in my list ("request sent"), vouched, contact_added sent',
      () async {
    await store.request(_alice, nickname: 'alice');
    expect(await label(_alice), ContactLabel.requestSent);
    expect((await store.entry(_alice))!.nickname, 'alice');
    expect(sent, [(_alice, ContactNotice.added)]);
    expect(vouched, [(_alice, VouchSource.friendRequest)]);
  });

  test('the peer accepts (its contact_added): friend; a repeat changes nothing',
      () async {
    await store.request(_alice);
    expect(await store.onContactAdded(_alice), ContactNoticeEffect.requestAccepted);
    expect(await label(_alice), ContactLabel.friend);
    expect(await store.onContactAdded(_alice), ContactNoticeEffect.none);
    expect(await label(_alice), ContactLabel.friend);
    expect(vouched, hasLength(1), reason: 'the notice vouches for nothing');
  });

  test('a received request; accepting it = adding too (friend, vouched as an '
      'acceptance, contact_added)', () async {
    expect(await store.onContactAdded(_bob), ContactNoticeEffect.requestReceived);
    expect(await label(_bob), ContactLabel.requestReceived);
    expect(vouched, isEmpty);
    expect(await store.onContactAdded(_bob), ContactNoticeEffect.none,
        reason: 'idempotent');
    await store.accept(_bob);
    expect(await label(_bob), ContactLabel.friend);
    expect(sent, [(_bob, ContactNotice.added)]);
    expect(vouched, [(_bob, VouchSource.friendAccepted)]);
  });

  test('a request to an account that had added me makes us friends at once',
      () async {
    await store.onContactAdded(_bob);
    await store.request(_bob);
    expect(await label(_bob), ContactLabel.friend);
    expect(vouched, [(_bob, VouchSource.friendAccepted)]);
  });

  test('decline hides the request and sends nothing; the same request again '
      'brings it back without a notification', () async {
    await store.onContactAdded(_bob);
    clock = 2000;
    await store.decline(_bob);
    final hidden = (await store.entry(_bob))!;
    expect(hidden.isHidden, isTrue);
    expect(hidden.isVisible, isFalse);
    expect(hidden.hiddenAtMs, 2000);
    expect(sent, isEmpty);

    expect(await store.onContactAdded(_bob), ContactNoticeEffect.none,
        reason: 'no notification for a hidden request coming back');
    final back = (await store.entry(_bob))!;
    expect(back.isVisible, isTrue);
    expect(back.label, ContactLabel.requestReceived);
  });

  test('contact_removed clears only addedMe: a friend becomes "request sent"; '
      'a received request goes; idempotent', () async {
    await store.request(_alice);
    await store.onContactAdded(_alice);
    await store.onContactRemoved(_alice);
    expect(await label(_alice), ContactLabel.requestSent);
    await store.onContactRemoved(_alice);
    expect(await label(_alice), ContactLabel.requestSent);

    await store.onContactAdded(_bob);
    await store.onContactRemoved(_bob);
    expect(await store.entry(_bob), isNull);
    // A removal from an account with no row changes nothing.
    await store.onContactRemoved(_bob);
    expect(await store.entry(_bob), isNull);
    // Alice's contact_added (she was in my list) was answered once.
    expect(sent, [(_alice, ContactNotice.added), (_alice, ContactNotice.answer)]);
  });

  test('a contact_added from an account in my list is answered once; an '
      'answer is never answered', () async {
    await store.request(_alice);
    sent.clear();
    // Her acceptance: answered (she may have lost what I told her).
    expect(await store.onContactAdded(_alice), ContactNoticeEffect.requestAccepted);
    expect(sent, [(_alice, ContactNotice.answer)]);
    // Her answer to my answer — never answered back (no ping-pong).
    expect(await store.onContactAdded(_alice, isAnswer: true),
        ContactNoticeEffect.none);
    expect(sent, hasLength(1));
    // A friend that reinstalled without a backup sends contact_added again:
    // answered, so it shows me as a friend at once.
    expect(await store.onContactAdded(_alice), ContactNoticeEffect.none);
    expect(sent, [(_alice, ContactNotice.answer), (_alice, ContactNotice.answer)]);
    // An account not in my list is never answered (a request stays a request).
    await store.onContactAdded(_bob);
    expect(sent.where((x) => x.$1 == _bob), isEmpty);
  });

  test('a lost acceptance comes back: the requester stays "request sent" until '
      'the accepter resends from its friend row', () async {
    // Alice accepted my request; her contact_added was lost. She resends
    // from her friend row; my store answers.
    await store.request(_alice);
    sent.clear();
    await store.onContactAdded(_alice); // the resend arriving
    expect(await label(_alice), ContactLabel.friend);
    expect(sent, [(_alice, ContactNotice.answer)]);
    // resend works on a friend row too.
    await store.resend(_alice);
    expect(sent.last, (_alice, ContactNotice.added));
  });

  test('before the restore of this install a contact_removed keeps a row with '
      'neither mark (for the restore); a later contact_added clears it',
      () async {
    final fresh = SnowDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final early = ContactStore(
      dao: fresh.contactDao,
      send: (_, _) async {},
      vouch: (_, _) async {},
      nowMs: () => 5,
    );
    await early.onContactRemoved(_bob);
    final row = (await early.entry(_bob))!;
    expect(row.inMyList || row.addedMe, isFalse);
    expect(row.isVisible, isFalse);
    expect((await fresh.contactDao.row(_bob))!.removedMeAtMs, 5);
    await early.onContactAdded(_bob);
    expect((await fresh.contactDao.row(_bob))!.removedMeAtMs, isNull);
    expect((await early.entry(_bob))!.label, ContactLabel.requestReceived);
  });

  test('cancel a request: the row goes, contact_removed sent', () async {
    await store.request(_alice);
    await store.remove(_alice);
    expect(await store.entry(_alice), isNull);
    expect(sent.last, (_alice, ContactNotice.removed));
  });

  test('unfriend: out of my list, contact_removed; their mark stays hidden '
      'until they send contact_added again', () async {
    await store.request(_alice);
    await store.onContactAdded(_alice);
    await store.remove(_alice);
    final row = (await store.entry(_alice))!;
    expect(row.inMyList, isFalse);
    expect(row.addedMe, isTrue);
    expect(row.isVisible, isFalse);
    expect(sent.last, (_alice, ContactNotice.removed));
    // Removing again sends nothing more.
    await store.remove(_alice);
    expect(sent.where((s) => s.$2 == ContactNotice.removed), hasLength(1));
  });

  test('resend: contact_added again, only for an account in my list', () async {
    await store.request(_alice);
    await store.resend(_alice);
    expect(sent, [(_alice, ContactNotice.added), (_alice, ContactNotice.added)]);
    await store.onContactAdded(_bob);
    await store.resend(_bob);
    expect(sent, hasLength(2));
  });

  test('blocking (forget) removes the row', () async {
    await store.request(_alice);
    await store.forget(_alice);
    expect(await store.entry(_alice), isNull);
  });

  test('an account key is kept only when it derives the snowId', () async {
    final key = ed.SigningKey(seed: Uint8List.fromList(List.filled(32, 3)));
    final pub = Uint8List.fromList(key.verifyKey.toList());
    final id = KeyDerivation.deriveSnowChatId(pub);
    await store.request(id, accountPub: pub);
    expect((await store.entry(id))!.accountPub, pub);
    await store.request(_alice, accountPub: pub);
    expect((await store.entry(_alice))!.accountPub, isNull);
  });

  test('what is not an account is refused', () async {
    expect(() => store.request('snowXYZ'), throwsArgumentError);
    expect(() => store.onContactAdded('bob'), throwsArgumentError);
  });

  test('the list stream shows every change', () async {
    final seen = <int>[];
    final sub = store.watch().listen((rows) => seen.add(rows.length));
    await store.request(_alice);
    await store.onContactAdded(_bob);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.last, 2);
  });

  test('USER_NOT_FOUND again and again: unavailable; the row stays; a send '
      'taken clears it', () async {
    await store.request(_alice);
    for (var i = 1; i < ContactStore.unavailableAfterFailures; i++) {
      await store.noteRecipientNotFound(_alice);
      expect((await store.entry(_alice))!.isUnavailable, isFalse);
    }
    await store.noteRecipientNotFound(_alice);
    final entry = (await store.entry(_alice))!;
    expect(entry.isUnavailable, isTrue);
    expect(entry.label, ContactLabel.requestSent);
    await store.noteRecipientReached(_alice);
    expect((await store.entry(_alice))!.isUnavailable, isFalse);
    expect((await store.entry(_alice))!.notFoundCount, 0);
  });

  test('a notice from the account clears "unavailable"', () async {
    await store.request(_alice);
    await store.onContactAdded(_alice);
    for (var i = 0; i < ContactStore.unavailableAfterFailures; i++) {
      await store.noteRecipientNotFound(_alice);
    }
    expect((await store.entry(_alice))!.isUnavailable, isTrue);
    expect(await store.onContactAdded(_alice), ContactNoticeEffect.none);
    expect((await store.entry(_alice))!.isUnavailable, isFalse);
  });

  test('an account outside the list is not marked (no row is made)', () async {
    await store.noteRecipientNotFound(_bob);
    await store.noteRecipientReached(_bob);
    expect(await store.entry(_bob), isNull);
  });
}
