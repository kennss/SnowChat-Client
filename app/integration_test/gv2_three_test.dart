/// @file        gv2_three_test.dart
/// @description Group protocol v2 through the app's screens on three
///              devices at once — two Android, one iOS — against the dev
///              server (design §14, "3-device interop"). One group of three:
///              both invitees accept at about the same moment, each device
///              writes and reads the other two (Sender Keys handed between
///              Android and iOS on first contact), the owner makes a member
///              an admin and that admin renames the group, the owner removes
///              the third member — whose device must not get what is said
///              after the removal — and the group ends.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (accounts are picked with ScreenDriver.pickAccount — through the warning when not vouched for). Earlier 2026-11-20 (asserts the build pins the group server keys — ENABLE_GROUPS_V2 is gone)
///
/// @functions
///  - main(): one test; what it does is chosen by GV3_ROLE
///
/// Notes:
///  - Roles (`--dart-define=GV3_ROLE=...`): `owner` creates and runs the
///    group; `admin` is made an admin and renames it, then leaves; `out` is
///    removed. Every run gets the three accounts (`GV3_OWNER`,
///    `GV3_ADMIN`, `GV3_OUT`) and the same `GV3_TAG` (the group's name).
///    Start the two invitees first.
///  - The devices wait for each other by what their own screen shows.
///  - After its removal `out` watches for [_quiet] that nothing said
///    afterwards reaches it, then removes the chat.
///  - It prints steps only: no keys, no group id, no message content beyond
///    its own fixed texts.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart' show gv2RoleAdmin;
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart'
    show gv2GroupsAvailable;
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';
import 'package:snowchat/features/group/providers/gv2_group_provider.dart';

import 'support/screen_driver.dart';

const _role = String.fromEnvironment('GV3_ROLE');
const _owner = String.fromEnvironment('GV3_OWNER');
const _admin = String.fromEnvironment('GV3_ADMIN');
const _out = String.fromEnvironment('GV3_OUT');
const _tag = String.fromEnvironment('GV3_TAG', defaultValue: 'run');

/// How long the removed member watches that nothing reaches it.
const Duration _quiet = Duration(seconds: 90);

const _fromOwner = 'hello from the owner';
const _fromAdmin = 'hello from the admin';
const _fromOut = 'hello from the third';
const _afterRemoval = 'said after the removal';
const _answer = 'the admin heard it';

void _say(String line) {
  // The test's own progress lines (read from the device log).
  // ignore: avoid_print
  print('GV3[$_role] $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group protocol v2 on three devices ($_role)', (tester) async {
    expect({'owner', 'admin', 'out'}.contains(_role), isTrue, reason: 'GV3_ROLE');
    for (final id in [_owner, _admin, _out]) {
      expect(id.length, 36, reason: 'GV3_OWNER / GV3_ADMIN / GV3_OUT');
    }
    expect(gv2GroupsAvailable, isTrue,
        reason: 'a SERVER_ENV whose group server keys this build pins');

    final title = 'gv3 $_tag';
    final renamed = 'gv3 $_tag b';

    final d = ScreenDriver(tester, _say);
    await d.start();
    expect(
      d.me,
      switch (_role) {
        'owner' => _owner,
        'admin' => _admin,
        _ => _out,
      },
      reason: 'this device holds the account of its role',
    );

    /// The name this device shows for [snowId] in the open group.
    String nameOf(String groupId, String snowId) {
      final view = d.container.read(gv2GroupViewProvider(groupId)).valueOrNull;
      return view!.members.firstWhere((m) => m.snowId == snowId).name;
    }

    /// Open group info from the chat (its title is the group's name).
    Future<void> openInfo(String name) async {
      await d.tap('the app bar title', find.text(name));
      await d.see('group info', find.text('Group Info'));
    }

    Future<void> backToChat() async {
      await d.tap('back', find.byIcon(Icons.arrow_back_rounded));
      await d.see('the chat again', find.text('Group chat'));
    }

    if (_role == 'owner') {
      // ---- Create the group with both invited ----
      // The contact list is the server's (who this account can reach); an
      // invitee it does not hold yet is added for the run once it loaded —
      // a load replaces the list.
      final contacts = d.container.read(contactProvider.notifier);
      await d.until('the contacts are loaded', () => contacts.isLoaded ? true : null);
      for (final id in [_admin, _out]) {
        if (!d.container.read(contactProvider).any((c) => c.snowChatId == id)) {
          contacts.addContact(Contact(snowChatId: id, addedAt: DateTime.now()));
          _say('an invitee was not a contact: added for this run');
        }
      }
      unawaited(d.router().push('/create-group'));
      await d.see('the new group screen', find.text('New Group'));
      // (Contacts added for the run are at the end of the list.)
      await d.pickAccount('the admin-to-be', _admin);
      await d.pickAccount('the third', _out);
      await d.see('two selected', find.textContaining('2 members selected'));
      await d.tap('next', find.byIcon(Icons.arrow_forward_rounded));
      final nameField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await d.see('the name dialog', nameField);
      await tester.enterText(nameField, title);
      await tester.pump(ScreenDriver.step);
      await d.tap('Create', find.text('Create'));
      final group = await d.until('the group exists', () async {
        final g = await d.groupTitled(title);
        return g != null && g.membership == Gv2Membership.active ? g : null;
      });
      final groupId = group.groupId;
      await d.see('its chat is open', find.text('Group chat'));

      // ---- Both join (they accept at about the same moment) ----
      for (final id in [_admin, _out]) {
        await d.until('an invitee is a confirmed member', () async {
          final m = await d.store.memberBySnowId(groupId, id);
          return m != null && m.checkState == Gv2MemberCheckState.confirmed
              ? true
              : null;
        });
      }

      // ---- Everyone hears everyone ----
      await d.write(_fromOwner);
      await d.sent(groupId, _fromOwner);
      await d.see('the admin-to-be wrote', find.text(_fromAdmin));
      await d.see('the third wrote', find.text(_fromOut));

      // ---- Make an admin; the admin renames the group ----
      await openInfo(title);
      await d.see('three members', find.text('Members (3)'));
      await d.tap('the admin-to-be', find.text(nameOf(groupId, _admin)));
      await d.tap('Make admin', find.text('Make admin'));
      await d.see('an admin', find.text('Admin'));
      await backToChat();
      await d.see('the admin\'s new name for the group', find.text(renamed));

      // ---- Remove the third, then say something ----
      await openInfo(renamed);
      await d.tap('the third', find.text(nameOf(groupId, _out)));
      await d.tap('Remove from group', find.text('Remove from group'));
      await d.tap('confirm', find.widgetWithText(TextButton, 'Remove'));
      await d.see('two members', find.text('Members (2)'));
      await backToChat();
      await d.write(_afterRemoval);
      await d.sent(groupId, _afterRemoval);
      await d.see('the admin answered', find.text(_answer));

      // ---- The admin leaves; end the group ----
      await d.until('the admin left', () async {
        return await d.store.memberBySnowId(groupId, _admin) == null ? true : null;
      });
      await openInfo(renamed);
      await d.see('one member', find.text('Members (1)'));
      await d.scrollTo('End group', find.text('End group'));
      await d.tap('End group', find.text('End group'));
      await d.tap('confirm', find.widgetWithText(TextButton, 'End group'));
      await d.see('the Chats tab', find.text('SnowChat'));
      expect((await d.store.group(groupId))?.membership, Gv2Membership.ended);
      _say('PASS');
      return;
    }

    // ---- An invitee: accept from the list ----
    await d.see(
      'the invite',
      find.text('Accept'),
      within: const Duration(minutes: 8),
    );
    await d.see('its name on the invite', find.text(title));
    await d.tap('Accept', find.text('Accept'));
    final group = await d.until('this account is in the group', () async {
      final g = await d.groupTitled(title);
      const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
      return g != null && inside.contains(g.membership) ? g : null;
    });
    final groupId = group.groupId;
    await d.see('its chat is open', find.text('Group chat'));
    await d.until('a member confirmed this device', () async {
      return (await d.store.group(groupId))?.membership == Gv2Membership.active
          ? true
          : null;
    });

    await d.see('the owner wrote', find.text(_fromOwner));
    await d.write(_role == 'admin' ? _fromAdmin : _fromOut);
    await d.sent(groupId, _role == 'admin' ? _fromAdmin : _fromOut);
    await d.see(
      'the other invitee wrote',
      find.text(_role == 'admin' ? _fromOut : _fromAdmin),
    );

    if (_role == 'admin') {
      // ---- Made an admin: rename the group ----
      await d.until('this account is an admin', () async {
        return await d.store.myRole(groupId) == gv2RoleAdmin ? true : null;
      });
      await openInfo(title);
      await d.tap('edit name', find.byIcon(Icons.edit_rounded));
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await d.see('the rename dialog', field);
      await tester.enterText(field, renamed);
      await tester.pump(ScreenDriver.step);
      await d.tap('Save', find.text('Save'));
      await d.see('the new name', find.text(renamed));
      await backToChat();

      // ---- The third is removed; what follows reaches the two ----
      await d.see('the owner spoke after the removal', find.text(_afterRemoval));
      await d.write(_answer);
      await d.sent(groupId, _answer);
      await d.until('the third is no member here', () async {
        return await d.store.memberBySnowId(groupId, _out) == null ? true : null;
      });

      // ---- Leave ----
      await openInfo(renamed);
      await d.scrollTo('Leave group', find.text('Leave group'));
      await d.tap('Leave group', find.text('Leave group'));
      await d.tap('Leave', find.widgetWithText(TextButton, 'Leave'));
      await d.see('the Chats tab', find.text('SnowChat'));
      expect((await d.store.group(groupId))?.membership, Gv2Membership.left);
      _say('PASS');
      return;
    }

    // ---- out: the admin's rename arrives; then this account is removed ----
    await d.see('the admin\'s new name for the group', find.text(renamed));
    await d.see(
      'told that this account is out',
      find.text('You are no longer in this group.'),
    );
    await d.see(
      'nothing can be written',
      find.text('You cannot send messages to this group.'),
    );
    expect((await d.store.group(groupId))?.membership, Gv2Membership.removed);
    // What the two say from now on never reaches this device.
    final quietUntil = DateTime.now().add(_quiet);
    while (DateTime.now().isBefore(quietUntil)) {
      final texts = await d.texts(groupId);
      expect(texts.contains(_afterRemoval), isFalse);
      expect(texts.contains(_answer), isFalse);
      await tester.pump(ScreenDriver.step);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _say('ok: nothing said after the removal arrived in ${_quiet.inSeconds}s');
    await openInfo(renamed);
    await d.tap('Remove chat', find.text('Remove chat'));
    await d.tap('confirm', find.widgetWithText(TextButton, 'Remove'));
    await d.see('the Chats tab', find.text('SnowChat'));
    _say('PASS');
  });
}
