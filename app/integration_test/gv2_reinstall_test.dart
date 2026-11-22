/// @file        gv2_reinstall_test.dart
/// @description Group protocol v2 across a reinstall, through the screens,
///              against the dev server (design §9.8, §14 "recovery"). A
///              disposable install (a simulator made for the test) joins a
///              group of two Android devices; the app is removed while
///              something is said in the group; it is installed again and
///              restored from its recovery phrase — the group comes back
///              from the key backup, the members confirm the new install
///              and talk with it again. Then the account is deleted (it
///              leaves the group) and registered again with the same
///              phrase, and the owner invites it back.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (friend graph off the server: an invitee is added to this device's list with a request (ContactNotifier.request); the identity directory is POST /keys/identity/fetch). Earlier 2026-11-21 (accounts are picked with ScreenDriver.pickAccount — through the warning when not vouched for). Earlier 2026-11-20 (asserts the build pins the group server keys — ENABLE_GROUPS_V2 is gone)
///
/// @functions
///  - main(): one test; what it does is chosen by GV4_ROLE
///
/// Notes:
///  - Roles (`--dart-define=GV4_ROLE=...`): `owner` and `member` (the two
///    Android devices; one run each spans the whole scenario), `before`
///    (the first install: joins, talks, waits until the key backup holds
///    the group) and `after` (the install made after the app was removed:
///    restores, talks, deletes the account, registers again, accepts the
///    owner's new invite). Accounts: `GV4_OWNER`, `GV4_MEMBER`,
///    `GV4_AGAIN` (the reinstalled one); `GV4_TAG` names the group.
///  - The first install must have been onboarded with its phrase copied to
///    the device's clipboard (qa_onboard_test.dart with QA_BACKUP=true).
///    The new install cannot paste it itself: iOS asks the user before an
///    app reads what another install put on the clipboard, and that prompt
///    cannot show while the app's own notification prompt is up (the
///    paste is refused, "Operation not authorized"). So the runner moves
///    the clipboard into the new app's temporary directory
///    ([_phraseFile]: `xcrun simctl pbpaste` straight into the app's
///    container, `Library/Caches` — what path_provider calls the temporary
///    directory on iOS; it lands nowhere else), and `after` reads it once,
///    deletes it and TYPES it into the restore field — the user's other
///    way. The phrase is never printed.
///  - The app is removed between `before` and `after` by the runner (it is
///    not something the app can do). The owner says [_whileAway] that long
///    after `before` said goodbye ([_awayAfter]).
///  - It prints steps only: no keys, no phrase, no group id, no message
///    content beyond its own fixed texts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart'
    show gv2GroupsAvailable;
import 'package:snowchat/app/app.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/app/router.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:snowchat/core/crypto/sender_key.dart' show SenderKeyRecord;
import 'package:snowchat/core/group_v2/gv2_pairwise.dart' show Gv2SenderKeyBody;
import 'package:snowchat/core/network/api_endpoints.dart';
import 'package:snowchat/core/storage/database.dart' show SnowDatabase;
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';
import 'package:snowchat/main.dart' as app;

import 'support/screen_driver.dart';

const _role = String.fromEnvironment('GV4_ROLE');
const _owner = String.fromEnvironment('GV4_OWNER');
const _member = String.fromEnvironment('GV4_MEMBER');
const _again = String.fromEnvironment('GV4_AGAIN');
const _tag = String.fromEnvironment('GV4_TAG', defaultValue: 'run');
const _nickname = String.fromEnvironment('QA_NICKNAME');

/// The nickname of the second registration (a deleted account's nickname
/// is held back for a while before anyone may take it again).
const _nicknameAgain = String.fromEnvironment('QA_NICKNAME_AGAIN');
const _pin = String.fromEnvironment('QA_PIN');

const _fromOwner = 'first from the owner';
const _fromMember = 'first from the member';
const _fromBefore = 'first from the install before';
const _goodbye = 'the install before says goodbye';
const _whileAway = 'said while the app was removed';
const _back = 'back after the reinstall';
const _ownerWelcome = 'welcome back from the owner';
const _memberWelcome = 'welcome back from the member';
const _again2 = 'here again after registering again';

/// The phrase the runner puts into the new install's temporary directory.
const _phraseFile = 'qa_phrase.txt';

/// How long after the goodbye the owner speaks: after the runner removed the
/// app (within seconds of `before` ending), well before the new install —
/// built, started and restored — is back.
const Duration _awayAfter = Duration(seconds: 20);

void _say(String line) {
  // The test's own progress lines (read from the device log).
  // ignore: avoid_print
  print('GV4[$_role] $line');
}

/// The Sender Key states [db] holds for [sender] in [groupId]: chain id
/// (last four digits) and iteration — numbers only, never key material.
Future<String> _keyStates(SnowDatabase db, String groupId, String sender) async {
  final row = await (db.select(db.gv2SenderKeys)..where(
        (k) => k.groupId.equals(groupId) & k.sender.equals(sender),
      ))
      .getSingleOrNull();
  if (row == null) return 'none';
  final record = SenderKeyRecord.fromJson(
    jsonDecode(utf8.decode(row.record)) as Map<String, dynamic>,
  );
  return [
    for (final st in record.states) '${st.chainId % 10000}@${st.iteration}',
  ].join(',');
}

/// The key positions [db] recorded as given to [member] in [groupId].
Future<String> _given(SnowDatabase db, String groupId, String member) async {
  final rows = await (db.select(db.gv2KeyDeliveries)..where(
        (k) => k.groupId.equals(groupId) & k.member.equals(member),
      ))
      .get();
  return [
    for (final r in rows)
      if (Gv2SenderKeyBody.decode(r.key) case final b?)
        '${b.chainId % 10000}@${b.iteration}',
  ].join(',');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group protocol v2 across a reinstall ($_role)', (tester) async {
    expect(
      {'owner', 'member', 'before', 'after'}.contains(_role),
      isTrue,
      reason: 'GV4_ROLE',
    );
    for (final id in [_owner, _member, _again]) {
      expect(id.length, 36, reason: 'GV4_OWNER / GV4_MEMBER / GV4_AGAIN');
    }
    expect(gv2GroupsAvailable, isTrue,
        reason: 'a SERVER_ENV whose group server keys this build pins');
    final title = 'gv4 $_tag';
    final d = ScreenDriver(tester, _say);

    if (_role == 'after') {
      await _after(tester, d, title);
      return;
    }

    await d.start();

    Future<void> openInfo() async {
      await d.tap('the app bar title', find.text(title));
      await d.see('group info', find.text('Group Info'));
    }

    if (_role == 'owner') {
      // The contact list is this device's: an invitee it does not hold yet
      // is added for the run with a friend request.
      for (final id in [_member, _again]) {
        if (!d.container.read(contactProvider).any((c) => c.snowChatId == id)) {
          await d.container.read(contactProvider.notifier).request(id);
        }
      }
      unawaited(d.router().push('/create-group'));
      await d.see('the new group screen', find.text('New Group'));
      for (final id in [_member, _again]) {
        await d.pickAccount('an invitee', id);
      }
      await d.tap('next', find.byIcon(Icons.arrow_forward_rounded));
      final nameField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await d.see('the name dialog', nameField);
      await tester.enterText(nameField, title);
      await tester.pump(ScreenDriver.step);
      await d.tap('Create', find.text('Create'));
      final groupId = (await d.until('the group exists', () async {
        final g = await d.groupTitled(title);
        return g != null && g.membership == Gv2Membership.active ? g : null;
      })).groupId;
      await d.see('its chat is open', find.text('Group chat'));
      // What is said before someone joins never reaches them.
      for (final id in [_member, _again]) {
        await d.until(
          'an invitee is a confirmed member',
          () async {
            final m = await d.store.memberBySnowId(groupId, id);
            return m != null && m.checkState == Gv2MemberCheckState.confirmed
                ? true
                : null;
          },
          within: const Duration(minutes: 8),
        );
      }
      await d.write(_fromOwner);
      await d.sent(groupId, _fromOwner);
      await d.see('the member wrote', find.text(_fromMember));
      await d.see('the first install wrote', find.text(_fromBefore));
      await d.see('the first install said goodbye', find.text(_goodbye));

      // ---- The app is removed over there; say something meanwhile ----
      await tester.pump(_awayAfter);
      await Future<void>.delayed(_awayAfter);
      _say('own key before: ${await _keyStates(d.db, groupId, _owner)}; '
          'given to the first install: ${await _given(d.db, groupId, _again)}');
      await d.write(_whileAway);
      await d.sent(groupId, _whileAway);
      _say('own key after: ${await _keyStates(d.db, groupId, _owner)}');

      // ---- The new install is back ----
      await d.see(
        'the reinstalled account wrote',
        find.text(_back),
        within: const Duration(minutes: 15),
      );
      _say('given to the new install: ${await _given(d.db, groupId, _again)}');
      await d.write(_ownerWelcome);
      await d.sent(groupId, _ownerWelcome);

      // ---- The account is deleted: it leaves; it registers again ----
      await d.until(
        'the deleted account left',
        () async =>
            await d.store.memberBySnowId(groupId, _again) == null ? true : null,
        within: const Duration(minutes: 10),
      );
      await d.see('a line says it left', find.textContaining(' left'));
      // The account registers again over there (a restore and a profile):
      // until it has, an invite has nobody to go to.
      // The directory first has no such account (deleted), then has it again.
      final api = d.container.read(apiClientProvider);
      Future<bool> listed() async {
        try {
          await api.post<Object?>(
            ApiEndpoints.identityFetch,
            data: {'snowchatId': _again},
          );
          return true;
        } catch (_) {
          return false;
        }
      }

      await d.until(
        'the account is deleted',
        () async => await listed() ? null : true,
        within: const Duration(minutes: 5),
      );
      await d.until(
        'the account is registered again',
        () async => await listed() ? true : null,
        within: const Duration(minutes: 10),
      );
      await openInfo();
      await d.tap('Add Members', find.text('Add Members'));
      await d.pickAccount('the account again', _again);
      await d.tap('add', find.byType(FloatingActionButton));
      await d.see('invited again', find.text('Invited (1)'));
      await d.until(
        'it is a confirmed member again',
        () async {
          final m = await d.store.memberBySnowId(groupId, _again);
          return m != null && m.checkState == Gv2MemberCheckState.confirmed
              ? true
              : null;
        },
        within: const Duration(minutes: 10),
      );
      await d.tap('back', find.byIcon(Icons.arrow_back_rounded));
      await d.see(
        'it wrote again',
        find.text(_again2),
        within: const Duration(minutes: 5),
      );
      _say('PASS');
      return;
    }

    // ---- member / before: accept and talk ----
    await d.see(
      'the invite',
      find.text('Accept'),
      within: const Duration(minutes: 8),
    );
    await d.see('its name on the invite', find.text(title));
    await d.tap('Accept', find.text('Accept'));
    final groupId = (await d.until('in the group', () async {
      final g = await d.groupTitled(title);
      const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
      return g != null && inside.contains(g.membership) ? g : null;
    })).groupId;
    await d.see('its chat is open', find.text('Group chat'));
    await d.until('a member confirmed this device', () async {
      return (await d.store.group(groupId))?.membership == Gv2Membership.active
          ? true
          : null;
    });
    await d.see('the owner wrote', find.text(_fromOwner));

    if (_role == 'member') {
      await d.write(_fromMember);
      await d.sent(groupId, _fromMember);
      await d.see('the first install said goodbye', find.text(_goodbye));
      await d.see(
        'the reinstalled account wrote',
        find.text(_back),
        within: const Duration(minutes: 15),
      );
      await d.write(_memberWelcome);
      await d.sent(groupId, _memberWelcome);
      await d.see(
        'it wrote again after registering again',
        find.text(_again2),
        within: const Duration(minutes: 20),
      );
      _say('PASS');
      return;
    }

    // ---- before: talk, then wait until the key backup holds the group ----
    await d.write(_fromBefore);
    await d.sent(groupId, _fromBefore);
    await d.see('the member wrote', find.text(_fromMember));
    final runtime = d.container.read(gv2RuntimeProvider)!;
    await d.until('the key backup holds this group', () async {
      final outcome = await runtime.backup.sync();
      final state = await d.store.backupState();
      return outcome.reached && state?.fingerprint != null ? true : null;
    });
    await d.write(_goodbye);
    await d.sent(groupId, _goodbye);
    _say('PASS');
  });
}

/// The install made after the app was removed: restore from the phrase on
/// the clipboard, find the group again, talk; delete the account; register
/// again with the same phrase; accept the owner's new invite and talk.
Future<void> _after(WidgetTester tester, ScreenDriver d, String title) async {
  expect(_nickname.length, inInclusiveRange(2, 20), reason: 'QA_NICKNAME');
  expect(
    _nicknameAgain.length,
    inInclusiveRange(2, 20),
    reason: 'QA_NICKNAME_AGAIN',
  );
  expect(RegExp(r'^\d{4,6}$').hasMatch(_pin), isTrue, reason: 'QA_PIN');
  app.main();
  await tester.pump(const Duration(seconds: 2));

  ProviderContainer container() => ProviderScope.containerOf(
    tester.element(find.byType(SnowChatApp)),
  );

  // The phrase, from the runner (see the notes): read once, then deleted.
  final tmp = await getTemporaryDirectory();
  final file = File('${tmp.path}/$_phraseFile');
  final phrase = await d.until(
    'the phrase from the runner',
    () async {
      if (!file.existsSync()) return null;
      final text = file.readAsStringSync().trim();
      return text.split(RegExp(r'\s+')).length >= 12 ? text : null;
    },
    within: const Duration(minutes: 3),
  );
  file.deleteSync();

  /// Welcome → "Restore from Backup" → the phrase typed → Restore → (a
  /// profile when the device holds none) → Chats. Returns the account.
  Future<String> restore({required String nickname}) async {
    await d.tap('Restore from Backup', find.text('Restore from Backup'));
    final field = find.byType(TextField);
    await d.see('the phrase field', field);
    await tester.enterText(field.first, phrase);
    await tester.pump(ScreenDriver.step);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(ScreenDriver.step);
    await d.tap('Restore', find.widgetWithText(ElevatedButton, 'Restore'));
    final where = await d.until('restored', () {
      if (d.shown(find.text('Set Up Profile'))) return 'profile';
      if (container().read(currentSnowIdProvider) != null &&
          d.shown(find.text('SnowChat'))) {
        return 'chats';
      }
      return null;
    });
    if (where == 'profile') {
      // An account the server still holds keeps its nickname (shown, not
      // asked for): then only the PIN and its confirmation are fields.
      final fields = find.byType(TextField);
      final count = await d.until(
        'the profile form',
        () => fields.evaluate().length >= 2 ? fields.evaluate().length : null,
      );
      var at = 0;
      if (count >= 3) {
        await tester.enterText(fields.at(at++), nickname);
        await tester.pump(ScreenDriver.step);
      }
      await tester.enterText(fields.at(at++), _pin);
      await tester.pump(ScreenDriver.step);
      await tester.enterText(fields.at(at), _pin);
      await tester.pump(ScreenDriver.step);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(ScreenDriver.step);
      await d.tap('Continue', find.text('Continue'));
    }
    return d.until('signed in', () => container().read(currentSnowIdProvider));
  }

  await d.see('a fresh install', find.text('Create New Identity'));
  expect(
    await restore(nickname: _nickname),
    _again,
    reason: 'the phrase gives the same account',
  );
  await d.until(
    'group protocol v2 is running',
    () => container().read(gv2RuntimeProvider),
  );
  final store = container().read(snowDatabaseProvider).gv2Store;
  final messages = container().read(snowDatabaseProvider).messageDao;

  // ---- The group comes back from the key backup ----
  final groupId = (await d.until(
    'the group is back from the key backup',
    () async {
      for (final g in await store.groups()) {
        if (g.title == title) return g;
      }
      return null;
    },
    within: const Duration(minutes: 6),
  )).groupId;
  await d.until('this device was confirmed again', () async {
    final g = await store.group(groupId);
    return g?.membership == Gv2Membership.active && !g!.resetPending
        ? true
        : null;
  }, within: const Duration(minutes: 6));
  await d.see('the group in the list', find.text(title));
  await d.tap('the group', find.text(title));
  await d.see('its chat is open', find.text('Group chat'));
  final db = container().read(snowDatabaseProvider);
  _say('owner key held after the reset: '
      '${await _keyStates(db, groupId, _owner)}');
  await d.write(_back);
  await d.see('the owner answered', find.text(_ownerWelcome));
  _say('owner key held later: ${await _keyStates(db, groupId, _owner)}');
  await d.see('the member answered', find.text(_memberWelcome));
  // What the first install had read is not here (the history is not
  // restored).
  final texts = {
    for (final m in await messages.getMessagesForConversation(groupId))
      m.plaintext,
  };
  for (final gone in [_fromOwner, _fromMember, _fromBefore, _goodbye]) {
    expect(texts.contains(gone), isFalse, reason: 'not restored: $gone');
  }
  _say('ok: nothing the first install had read is shown');
  // What was said while the app was away waited on the server for this
  // account. Whether it opens depends on which key its sender gives — the
  // one given to the first install, when the key request reaches it before
  // the reset does (the design decision this records is the owner's).
  _say('said while away: ${texts.contains(_whileAway) ? 'shown' : 'not shown'}');

  // ---- Delete the account (it leaves the group first) ----
  container().read(isLockedProvider.notifier).state = false;
  container().read(routerProvider).go('/settings');
  await d.see('the settings screen', find.text('Read Receipts'));
  await d.scrollTo('Delete Account', find.text('Delete Account'));
  await d.tap('Delete Account', find.text('Delete Account'));
  await d.tap('Delete', find.widgetWithText(TextButton, 'Delete'));
  await d.see(
    'the app is new again',
    find.text('Create New Identity'),
    within: const Duration(minutes: 3),
  );

  // ---- Register again with the same phrase ----
  expect(
    await restore(nickname: _nicknameAgain),
    _again,
    reason: 'the same account id again',
  );
  await d.until(
    'group protocol v2 is running again',
    () => container().read(gv2RuntimeProvider),
  );
  await d.see(
    'the owner\'s new invite',
    find.text('Accept'),
    within: const Duration(minutes: 10),
  );
  await d.tap('Accept', find.text('Accept'));
  await d.see('its chat is open', find.text('Group chat'));
  final store2 = container().read(snowDatabaseProvider).gv2Store;
  await d.until('confirmed', () async {
    return (await store2.group(groupId))?.membership == Gv2Membership.active
        ? true
        : null;
  }, within: const Duration(minutes: 6));
  await d.write(_again2);
  _say('PASS');
}
