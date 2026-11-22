/// @file        gv2_screens_test.dart
/// @description Group protocol v2 through the app's screens, on two devices
///              at once against the dev server: the real app is started
///              (its own identity, database, socket and sessions) and its
///              widgets are tapped and typed into — the offline retention
///              setting; create a group, take the invite, talk both ways,
///              a file, rename, make and unmake an admin, take a message
///              back, leave taking one's messages along; then invite again
///              and decline, invite and accept, clear the chat for
///              everyone, remove the member (who is left with a read-only
///              chat and removes it), invite and take the invite back, end
///              the group.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (friend graph off the server: the peer is added to this device's list with a request (ContactNotifier.request)). Earlier 2026-11-21 (accounts are picked with ScreenDriver.pickAccount — through the warning when not vouched for). Earlier 2026-11-20 (asserts the build pins the group server keys — ENABLE_GROUPS_V2 is gone)
///
/// @functions
///  - main(): one test; what it does is chosen by GV2_UI_ROLE (host | guest)
///
/// Notes:
///  - Needs an app that is already onboarded on each device (the test uses
///    the account that is there) and a build for a
///    SERVER_ENV whose group server keys it pins (dev).
///  - `--dart-define=GV2_UI_ROLE=host|guest`, `GV2_UI_PEER=<the other
///    account's snowId>`, `GV2_UI_TAG=<a name for the run>` (the same on
///    both devices; the group is titled with it). Start the guest first.
///  - The app's PIN lock is a screen in front of a session that is already
///    there; the test opens the Chats tab through the router instead of
///    typing a PIN (it holds none).
///  - The two runs wait for each other by what their own screen shows
///    (a message, a new title, a system line) — nothing else connects them.
///  - The file is sent through the chat's notifier (the system file picker
///    is not driven); everything else goes through the widgets.
///  - It prints steps only: no keys, no group id, no message content beyond
///    its own fixed texts.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart'
    show gv2GroupsAvailable;
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/chat/providers/chat_provider.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';
import 'package:snowchat/features/group/providers/gv2_group_provider.dart';
import 'package:snowchat/features/settings/providers/gv2_retention_provider.dart';

import 'support/screen_driver.dart';

const _role = String.fromEnvironment('GV2_UI_ROLE');
const _peer = String.fromEnvironment('GV2_UI_PEER');
const _tag = String.fromEnvironment('GV2_UI_TAG', defaultValue: 'run');

const _step = Duration(milliseconds: 400);
const _ping = 'ping from the host';
const _second = 'second from the host';
const _pong = 'pong from the guest';
const _back = 'back again from the guest';

void _say(String line) {
  // The test's own progress lines (read from the device log).
  // ignore: avoid_print
  print('GV2UI[$_role] $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group protocol v2 through the screens ($_role)', (tester) async {
    expect({'host', 'guest'}.contains(_role), isTrue, reason: 'GV2_UI_ROLE');
    expect(_peer.length, 36, reason: 'GV2_UI_PEER');
    expect(gv2GroupsAvailable, isTrue,
        reason: 'a SERVER_ENV whose group server keys this build pins');

    final title = 'gv2 ui $_tag';
    final renamed = 'gv2 ui $_tag b';
    final fileName = 'gv2-note-$_tag.txt';
    final fileText = 'a note of the screen test $_tag';

    final d = ScreenDriver(tester, _say);
    await d.start();
    final container = d.container;
    final me = d.me;
    expect(_peer, isNot(me));
    final db = d.db;
    final store = d.store;
    GoRouter router() => d.router();
    final until = d.until;
    final shown = d.shown;
    final see = d.see;
    final gone = d.gone;
    final tap = d.tap;
    final scrollTo = d.scrollTo;
    final write = d.write;
    final sent = d.sent;
    final groupTitled = d.groupTitled;

    final names = container.read(gv2KnownNamesProvider);
    String peerName(Gv2GroupView view) =>
        view.members.firstWhere((m) => m.snowId == _peer).name;

    if (_role == 'host') {
      // ---- The offline retention setting (the server's value) ----
      router().go('/settings');
      final tile = find.text('Offline group messages');
      await see('the settings screen', find.text('Read Receipts'));
      await scrollTo('the retention tile', tile);
      await see(
        'the retention as the server holds it',
        find.textContaining('Kept on the server for'),
      );
      final before = await until(
        'the retention value',
        () => container.read(gv2RetentionProvider).valueOrNull,
      );
      final other = before == 7 ? 1 : 7;
      await tap('the retention tile', tile);
      await tap('another period', find.text(gv2RetentionLabel(other)));
      await see(
        'the other period is shown',
        find.textContaining('for ${gv2RetentionLabel(other)}'),
      );
      // Back to what the account had.
      await tap('the retention tile', tile);
      await tap('the period it had', find.text(gv2RetentionLabel(before)));
      await see(
        'the period it had is shown again',
        find.textContaining('for ${gv2RetentionLabel(before)}'),
      );
      router().go('/chat');
      await see('the Chats tab', find.text('SnowChat'));

      // ---- Create a group with the peer invited ----
      if (!container.read(contactProvider).any((c) => c.snowChatId == _peer)) {
        await container.read(contactProvider.notifier).request(_peer);
        _say('the peer was not a contact: requested for this run');
      }
      unawaited(router().push('/create-group'));
      await see('the new group screen', find.text('New Group'));
      await d.pickAccount('the peer in the contact list', _peer);
      await see('one member selected', find.textContaining('1 member selected'));
      await tap('next', find.byIcon(Icons.arrow_forward_rounded));
      final nameField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await see('the name dialog', nameField);
      await tester.enterText(nameField, title);
      await tester.pump(_step);
      await tap('Create', find.text('Create'));
      final group = await until('the group exists on this device', () async {
        final g = await groupTitled(title);
        return g != null && g.membership == Gv2Membership.active ? g : null;
      });
      final groupId = group.groupId;
      await see('its chat is open', find.text('Group chat'));
      await see('its name in the app bar', find.text(title));
      await see('"You created the group"', find.text('You created the group'));

      // ---- The peer joins ----
      await until('the peer is a confirmed member', () async {
        final m = await store.memberBySnowId(groupId, _peer);
        return m != null && m.checkState == Gv2MemberCheckState.confirmed
            ? true
            : null;
      });
      await see('a line says the peer joined', find.textContaining(' joined'));

      // ---- Talk ----
      await write(_ping);
      await sent(groupId, _ping);
      await write(_second);
      await sent(groupId, _second);
      await see('the peer\'s answer', find.text(_pong));

      // ---- A file (encrypted, uploaded, its key inside the message) ----
      final note = File('${Directory.systemTemp.path}/$fileName')
        ..writeAsStringSync(fileText);
      unawaited(
        container
            .read(chatProvider(groupId).notifier)
            .sendFileMessage(
              filePath: note.path,
              fileName: fileName,
              mimeType: 'text/plain',
            ),
      );
      await see('the file in the chat', find.textContaining(fileName));
      await sent(groupId, fileName);

      // ---- Group info: members, rename, admin ----
      await tap('the app bar title', find.text(title));
      await see('group info', find.text('Group Info'));
      await see('two members', find.text('Members (2)'));
      await see('this account marked', find.textContaining('(you)'));
      await see('this account is the owner', find.text('Owner'));
      expect(shown(find.text('Add Members')), isTrue);
      expect(shown(find.text('End group')), isTrue);
      expect(shown(find.text('Leave group')), isTrue);

      await tap('edit name', find.byIcon(Icons.edit_rounded));
      final renameField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await see('the rename dialog', renameField);
      await tester.enterText(renameField, renamed);
      await tester.pump(_step);
      await tap('Save', find.text('Save'));
      await see('the new name on the info screen', find.text(renamed));

      final view =
          container.read(gv2GroupViewProvider(groupId)).valueOrNull ??
          (throw StateError('no view of the group'));
      final peerShown = peerName(view);
      _say('the peer is named from: '
          '${names.containsKey(_peer) ? 'contacts' : 'nickname or id'}');
      await tap('the peer\'s row', find.text(peerShown));
      await tap('Make admin', find.text('Make admin'));
      await see('the peer is an admin', find.text('Admin'));
      await tap('the peer\'s row', find.text(peerShown));
      await tap('Remove as admin', find.text('Remove as admin'));
      await gone('the peer is a member again', find.text('Admin'));

      await tap('back', find.byIcon(Icons.arrow_back_rounded));
      await see('the chat again', find.text('Group chat'));
      await see('the new name in the app bar', find.text(renamed));
      await see(
        'the rename as a line',
        find.text('You renamed the group to "$renamed"'),
      );
      await see('the admin change as a line', find.textContaining(' an admin'));

      // ---- Take a message back ----
      await tester.longPress(find.text(_second).hitTestable().first);
      await tester.pump(_step);
      await tap('Delete for Everyone', find.text('Delete for Everyone'));
      await gone('the message is gone here', find.text(_second));

      // ---- The peer leaves ----
      await see('a line says the peer left', find.textContaining(' left'));
      await until('the peer is no member', () async {
        return await store.memberBySnowId(groupId, _peer) == null ? true : null;
      });

      await gone('the peer took its messages along', find.text(_pong));

      /// From group info: invite the peer through "Add Members".
      Future<void> inviteAgain() async {
        await tap('Add Members', find.text('Add Members'));
        await d.pickAccount('the peer in the contact list', _peer);
        await tap('add', find.byType(FloatingActionButton));
        await see('the peer is listed as invited', find.text('Invited (1)'));
      }

      // ---- Invite again: the peer declines ----
      await tap('the app bar title', find.text(renamed));
      await see('group info', find.text('Group Info'));
      await see('one member', find.text('Members (1)'));
      await inviteAgain();
      // A declined invite is told to nobody: it shows when this device next
      // reads the log — which opening group info does.
      await until<bool>('the peer declined', () async {
        if (!shown(find.text('Invited (1)'))) return true;
        // (A route may still be sliding out: only what can be hit is tapped.)
        final back = find.byIcon(Icons.arrow_back_rounded);
        if (shown(find.text('Group Info')) && shown(back)) {
          await tester.tap(back.hitTestable().first);
          await tester.pump(const Duration(seconds: 1));
        }
        if (shown(find.text('Group chat')) && shown(find.text(renamed))) {
          await tester.tap(find.text(renamed).hitTestable().first);
          await tester.pump(const Duration(seconds: 2));
        }
        await Future<void>.delayed(const Duration(seconds: 4));
        await tester.pump(_step);
        return null;
      });

      // ---- Invite again: the peer accepts and writes ----
      await inviteAgain();
      await see('the peer is a member again', find.text('Members (2)'));
      await tap('back', find.byIcon(Icons.arrow_back_rounded));
      await see('the chat again', find.text('Group chat'));
      await see('a line says the peer declined', find.textContaining(' declined'));
      await see('what the peer wrote', find.text(_back));

      // ---- Clear the chat for everyone ----
      await tap('the menu', find.byIcon(Icons.more_vert_rounded));
      await tap('Clear chat for everyone', find.text('Clear chat for everyone'));
      await tap('Clear', find.widgetWithText(TextButton, 'Clear'));
      await gone('the chat is empty here', find.text(_back));
      await until<bool>('nothing of the chat is stored', () async {
        final rows = await db.messageDao.getMessagesForConversation(groupId);
        return rows.isEmpty ? true : null;
      });

      // ---- Remove the peer ----
      await tap('the app bar title', find.text(renamed));
      await see('group info', find.text('Group Info'));
      await tap('the peer\'s row', find.text(peerShown));
      await tap('Remove from group', find.text('Remove from group'));
      await tap('confirm', find.widgetWithText(TextButton, 'Remove'));
      await see('the peer is out', find.text('Members (1)'));

      // ---- Invite once more and take the invite back ----
      await inviteAgain();
      await tap('Take back', find.text('Take back'));
      await gone('the invite is taken back', find.text('Invited (1)'));

      // ---- End the group ----
      await scrollTo('End group', find.text('End group'));
      await tap('End group', find.text('End group'));
      await see('the confirmation', find.textContaining('ends for everyone'));
      await tap('confirm', find.widgetWithText(TextButton, 'End group'));
      await see('the Chats tab', find.text('SnowChat'));
      await gone('the group left the list', find.text(renamed));
      final ended = await store.group(groupId);
      expect(ended?.membership, Gv2Membership.ended);
      _say('PASS');
      return;
    }

    // ---- guest ----
    final invite = find.text('Accept');
    final inList = find.text(title);
    final how = await until('the invite, or the group itself, shows', () {
      if (shown(invite) && shown(inList)) return 'invite';
      if (shown(inList)) return 'accepted';
      return null;
    }, within: const Duration(minutes: 8));
    if (how == 'invite') {
      await see('the invites section', find.text('Group Invites'));
      await see('who invited', find.textContaining('Invited by '));
      await tap('Accept', invite);
    } else {
      _say('the app accepted the invite by itself (a confirmed friend)');
      await tap('the group in the list', inList);
    }
    final group = await until('this account is in the group', () async {
      final g = await groupTitled(title);
      const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
      return g != null && inside.contains(g.membership) ? g : null;
    });
    final groupId = group.groupId;
    await see('its chat is open', find.text('Group chat'));
    await until('a member confirmed this device', () async {
      final g = await store.group(groupId);
      return g?.membership == Gv2Membership.active ? true : null;
    });
    await gone(
      'no "waiting for a member" strip',
      find.textContaining('Waiting for a member'),
    );

    await see('the host\'s message', find.text(_ping));
    await see('the host\'s second message', find.text(_second));
    await write(_pong);
    await sent(groupId, _pong);

    // ---- The host's file: stored, downloaded and decrypted ----
    await see('the host\'s file in the chat', find.textContaining(fileName));
    final documents = await getApplicationDocumentsDirectory();
    await until<bool>('the file is here, readable', () async {
      final rows = await db.messageDao.getMessagesForConversation(groupId);
      final row = rows.where((m) => m.type == 'file' && m.plaintext == fileName);
      if (row.isEmpty) return null;
      for (final a in await db.attachmentDao.getForMessage(row.first.id)) {
        final path = a.localPath;
        if (path == null || path.isEmpty) continue;
        final file = File(path.startsWith('/') ? path : '${documents.path}/$path');
        if (file.existsSync() && file.readAsStringSync() == fileText) return true;
      }
      return null;
    });

    await see('the new name in the app bar', find.text(renamed));
    await see('the rename as a line', find.textContaining('renamed the group to'));
    await gone('the message the host took back', find.text(_second));
    await until('only that message went', () async {
      final texts = {
        for (final m in await db.messageDao.getMessagesForConversation(groupId))
          m.plaintext,
      };
      return texts.contains(_ping) && !texts.contains(_second) ? true : null;
    });

    await tap('the app bar title', find.text(renamed));
    await see('group info', find.text('Group Info'));
    await see('two members', find.text('Members (2)'));
    await see('this account marked', find.textContaining('(you)'));
    // A member is offered neither invites nor the end of the group.
    expect(shown(find.text('Add Members')), isFalse);
    expect(shown(find.text('End group')), isFalse);
    expect(shown(find.byIcon(Icons.edit_rounded)), isFalse);
    await scrollTo('Leave group', find.text('Leave group'));
    await tap('Leave group', find.text('Leave group'));
    await see('the leave dialog', find.text('Leave'));
    await tap(
      'Leave and delete',
      find.widgetWithText(TextButton, 'Leave and delete'),
    );
    await see('the Chats tab', find.text('SnowChat'));
    await gone('the group left the list', find.text(renamed));
    expect((await store.group(groupId))?.membership, Gv2Membership.left);
    expect(await db.conversationDao.getConversation(groupId), isNull);

    // ---- Invited again: decline ----
    await see(
      'the invite again',
      find.text('Decline'),
      within: const Duration(minutes: 6),
    );
    await see('the group\'s current name on the invite', find.text(renamed));
    await tap('Decline', find.text('Decline'));
    await gone('the invite is gone', find.text('Decline'));
    await until<bool>('the invite was declined', () async {
      return (await store.group(groupId))?.membership == Gv2Membership.declined
          ? true
          : null;
    });

    // ---- Invited a third time: accept, write ----
    await see(
      'the invite a third time',
      find.text('Accept'),
      within: const Duration(minutes: 6),
    );
    await tap('Accept', find.text('Accept'));
    await see('its chat is open', find.text('Group chat'));
    await until<bool>('a member confirmed this device', () async {
      final g = await store.group(groupId);
      return g?.membership == Gv2Membership.active ? true : null;
    });
    // Nothing of the first stay is back.
    expect(shown(find.text(_ping)), isFalse);
    await write(_back);
    await sent(groupId, _back);

    // ---- The host clears the chat, then removes this account ----
    await gone('the host cleared the chat', find.text(_back));
    await see(
      'told that this account is out',
      find.text('You are no longer in this group.'),
    );
    await see(
      'nothing can be written',
      find.text('You cannot send messages to this group.'),
    );
    expect(shown(find.byType(TextField)), isFalse);
    expect((await store.group(groupId))?.membership, Gv2Membership.removed);

    await tap('the app bar title', find.text(renamed));
    await see('group info', find.text('Group Info'));
    expect(shown(find.text('Leave group')), isFalse);
    await tap('Remove chat', find.text('Remove chat'));
    await tap('confirm', find.widgetWithText(TextButton, 'Remove'));
    await see('the Chats tab', find.text('SnowChat'));
    await gone('the group left the list', find.text(renamed));
    expect(await db.conversationDao.getConversation(groupId), isNull);
    _say('PASS');
  });
}
