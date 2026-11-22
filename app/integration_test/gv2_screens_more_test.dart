/// @file        gv2_screens_more_test.dart
/// @description Group protocol v2 through the app's screens, on two devices
///              at once against the dev server — what the first screen test
///              (gv2_screens_test.dart) did not reach: an invite taken
///              without asking (the two accounts become friends first), an
///              image, a voice message and a disappearing message, handing
///              the group over, the owner leaving (the group passes to the
///              member who joined first), and the strips a group shows on
///              hold — withheld, update required, frozen — with the frozen
///              group's leave.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (accounts are picked with ScreenDriver.pickAccount — through the warning when not vouched for). Earlier 2026-11-21 (acceptFriendRequest takes the request). Earlier 2026-11-20 (asserts the build pins the group server keys — ENABLE_GROUPS_V2 is gone)
///
/// @functions
///  - main(): one test; what it does is chosen by GV2_UI_ROLE (host | guest)
///
/// Notes:
///  - Same set-up as gv2_screens_test.dart: an onboarded app on each device,
///    a SERVER_ENV whose group server keys the build pins (dev), `GV2_UI_ROLE`, `GV2_UI_PEER`,
///    `GV2_UI_TAG`. Start the guest first.
///  - A group on hold cannot be made with an honest server (that is the
///    point of the holds). The host puts its OWN copy of the group on each
///    hold through its store — what is checked is what the screen does with
///    it, not how a hold comes about (the protocol tests cover that). The
///    hold is put on after the guest has left, so nobody else is affected.
///  - The two accounts are made friends through the app's friend requests
///    (the host asks, the guest accepts), as a user would before an invite
///    can be taken without asking. They stay friends after the run.
///  - Image, voice and file are sent through the chat's notifier (the system
///    pickers and the recorder are not driven); the bytes the guest decrypts
///    are compared with what was sent.
///  - It prints steps only: no keys, no group id, no message content beyond
///    its own fixed texts.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart'
    show gv2GroupsAvailable;
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/channels/providers/channel_provider.dart';
import 'package:snowchat/features/chat/providers/chat_provider.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';
import 'package:snowchat/features/group/providers/gv2_group_provider.dart';

import 'support/screen_driver.dart';

const _role = String.fromEnvironment('GV2_UI_ROLE');
const _peer = String.fromEnvironment('GV2_UI_PEER');
const _tag = String.fromEnvironment('GV2_UI_TAG', defaultValue: 'run');

const _step = Duration(milliseconds: 400);
const _hello = 'hello from the host';
const _fleeting = 'this one disappears';
const _answer = 'answer from the guest';
const _ttlSeconds = 30;

/// A 1×1 PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Half a second of 8 kHz 8-bit mono silence as a WAV file.
Uint8List _wav() {
  const samples = 4000;
  final data = ByteData(44 + samples);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 8000, Endian.little);
  data.setUint16(32, 1, Endian.little);
  data.setUint16(34, 8, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setUint8(44 + i, 128);
  }
  return data.buffer.asUint8List();
}

void _say(String line) {
  // The test's own progress lines (read from the device log).
  // ignore: avoid_print
  print('GV2UI[$_role] $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group protocol v2 through the screens, more ($_role)', (
    tester,
  ) async {
    expect({'host', 'guest'}.contains(_role), isTrue, reason: 'GV2_UI_ROLE');
    expect(_peer.length, 36, reason: 'GV2_UI_PEER');
    expect(gv2GroupsAvailable, isTrue,
        reason: 'a SERVER_ENV whose group server keys this build pins');
    final title = 'gv2 more $_tag';
    final imageName = 'gv2-dot-$_tag.png';

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
    final friends = container.read(friendActionsProvider);

    /// Whether the peer is among this account's friends (the server's list).
    Future<bool> friendsWithPeer() async {
      container.invalidate(personalChannelProvider);
      final list = await container.read(friendListProvider.future);
      return list.any((f) => f.snowchatId == _peer);
    }

    /// The bytes of the attachment of the message [text] in [groupId], once
    /// it is downloaded and decrypted here.
    Future<Uint8List> received(String groupId, String text) async {
      final documents = await getApplicationDocumentsDirectory();
      return until<Uint8List>('"$text" is here, decrypted', () async {
        final rows = await db.messageDao.getMessagesForConversation(groupId);
        for (final m in rows.where((m) => m.plaintext == text)) {
          for (final a in await db.attachmentDao.getForMessage(m.id)) {
            final path = a.localPath;
            if (path == null || path.isEmpty) continue;
            final file =
                File(path.startsWith('/') ? path : '${documents.path}/$path');
            if (file.existsSync()) return file.readAsBytesSync();
          }
        }
        return null;
      });
    }

    Future<int?> roleOf(String groupId, String snowId) async =>
        (await store.memberBySnowId(groupId, snowId))?.role;

    if (_role == 'host') {
      // ---- Friends first (an invite from a friend is taken by itself) ----
      if (!await friendsWithPeer()) {
        final status = await friends.addFriend(_peer);
        _say('friend request: $status');
        await until(
          'the peer accepted the friend request',
          () async => await friendsWithPeer() ? true : null,
          within: const Duration(minutes: 4),
        );
      } else {
        _say('already friends');
      }
      if (!container.read(contactProvider).any((c) => c.snowChatId == _peer)) {
        container.read(contactProvider.notifier).addContact(
          Contact(snowChatId: _peer, addedAt: DateTime.now()),
        );
      }

      // ---- A group with the peer invited ----
      router().go('/chat');
      await see('the Chats tab', find.text('SnowChat'));
      unawaited(router().push('/create-group'));
      await see('the new group screen', find.text('New Group'));
      await d.pickAccount('the peer in the contact list', _peer);
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
      await until('the peer is a confirmed member', () async {
        final m = await store.memberBySnowId(groupId, _peer);
        return m != null && m.checkState == Gv2MemberCheckState.confirmed
            ? true
            : null;
      }, within: const Duration(minutes: 4));
      await see('a line says the peer joined', find.textContaining(' joined'));

      // ---- An image and a voice message ----
      final chat = container.read(chatProvider(groupId).notifier);
      final temp = Directory.systemTemp.path;
      final image = File('$temp/$imageName')..writeAsBytesSync(_png);
      unawaited(chat.sendFileMessage(
        filePath: image.path,
        fileName: imageName,
        mimeType: 'image/png',
      ));
      await sent(groupId, imageName);
      final voice = File('$temp/gv2-voice-$_tag.wav')..writeAsBytesSync(_wav());
      unawaited(chat.sendVoiceMessage(audioPath: voice.path, durationSeconds: 1));
      await sent(groupId, 'Voice message');
      await write(_hello);
      await sent(groupId, _hello);

      // ---- A disappearing message ----
      chat.setDisappearingTimer(_ttlSeconds);
      await write(_fleeting);
      await sent(groupId, _fleeting);
      chat.setDisappearingTimer(null);
      await gone(
        'the disappearing message went here',
        find.text(_fleeting),
        within: const Duration(seconds: _ttlSeconds * 3),
      );
      await see('the guest\'s answer', find.text(_answer));

      // ---- Hand the group over ----
      await tap('the app bar title', find.text(title));
      await see('group info', find.text('Group Info'));
      final peerShown = container
          .read(gv2GroupViewProvider(groupId))
          .valueOrNull!
          .members
          .firstWhere((m) => m.snowId == _peer)
          .name;
      await tap('the peer\'s row', find.text(peerShown));
      await tap('Make owner', find.text('Make owner'));
      await tap('confirm', find.widgetWithText(TextButton, 'Hand over'));
      await until('the peer owns the group', () async {
        return await roleOf(groupId, _peer) == gv2RoleOwner ? true : null;
      });
      expect(await roleOf(groupId, me), isNot(gv2RoleOwner));
      await gone('no "End group" for a former owner', find.text('End group'));

      // ---- The new owner leaves: the group comes back here ----
      await until('this account owns the group again', () async {
        return await roleOf(groupId, me) == gv2RoleOwner ? true : null;
      }, within: const Duration(minutes: 4));
      await until('the peer is gone', () async {
        return await store.memberBySnowId(groupId, _peer) == null ? true : null;
      });
      await see('"End group" again', find.text('End group'));
      await tap('back', find.byIcon(Icons.arrow_back_rounded));
      await see('the chat again', find.text('Group chat'));
      await see('a line says the peer left', find.textContaining(' left'));

      // ---- The strips of a group on hold (this device's copy) ----
      Future<void> strip(Gv2Hold hold, String words) async {
        await store.setHold(
          groupId,
          hold,
          evidence: hold == Gv2Hold.withheld
              ? Uint8List.fromList(utf8.encode(jsonEncode({
                  'kind': 'withheld',
                  'source': 'screen test',
                  'heldRevision': 0,
                  'served': const {},
                })))
              : null,
        );
        await see('the strip: $words', find.textContaining(words));
        await store.setHold(groupId, Gv2Hold.none);
        await gone('the strip went', find.textContaining(words));
      }

      await strip(Gv2Hold.withheld, 'holding back changes');
      await strip(Gv2Hold.updateRequired, 'Update SnowChat');

      await store.setHold(
        groupId,
        Gv2Hold.frozen,
        evidence: Uint8List.fromList(utf8.encode(jsonEncode({
          'kind': 'two_heads',
          'source': 'screen test',
        }))),
      );
      await see(
        'the frozen strip',
        find.textContaining('two different histories'),
      );
      await gone('nothing can be written', find.byType(TextField));
      await tap('the app bar title', find.text(title));
      await see('group info', find.text('Group Info'));
      expect(shown(find.text('Add Members')), isFalse);
      await scrollTo('Leave group', find.text('Leave group'));
      await tap('Leave group', find.text('Leave group'));
      await see(
        'the frozen leave: the server is not told',
        find.textContaining('it is not told'),
      );
      expect(shown(find.textContaining('take back')), isFalse);
      await tap('Leave', find.widgetWithText(TextButton, 'Leave'));
      await see('the Chats tab', find.text('SnowChat'));
      await gone('the group left the list', find.text(title));
      expect(await db.conversationDao.getConversation(groupId), isNull);
      _say('PASS');
      return;
    }

    // ---- guest ----
    // The host's friend request.
    if (!await friendsWithPeer()) {
      final request = await until('the host\'s friend request', () async {
        container.invalidate(friendRequestsProvider);
        final pending = await container.read(friendRequestsProvider.future);
        for (final p in pending) {
          if (p.creatorSnowchatId == _peer) return p;
        }
        return null;
      }, within: const Duration(minutes: 4));
      expect(await friends.acceptFriendRequest(request), isTrue);
      _say('friend request accepted');
    } else {
      _say('already friends');
    }

    // The invite is taken without asking: a friend whose identity is bound.
    // It may show as an invite for a moment; nothing here taps it.
    final inList = find.text(title);
    await see('the group in the list', inList, within: const Duration(minutes: 8));
    final group = await until('this account is in the group, untouched', () async {
      final g = await groupTitled(title);
      const inside = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
      return g != null && inside.contains(g.membership) ? g : null;
    }, within: const Duration(minutes: 2));
    final groupId = group.groupId;
    await gone('the invite is no longer offered', find.text('Accept'));
    await tap('the group in the list', inList);
    await see('its chat is open', find.text('Group chat'));
    await until('a member confirmed this device', () async {
      final g = await store.group(groupId);
      return g?.membership == Gv2Membership.active ? true : null;
    });

    // ---- The host's image and voice message, decrypted ----
    expect(await received(groupId, imageName), _png);
    expect(await received(groupId, 'Voice message'), _wav());
    final rows = await db.messageDao.getMessagesForConversation(groupId);
    expect(rows.firstWhere((m) => m.plaintext == 'Voice message').type, 'voice');
    await see('the host\'s text', find.text(_hello));

    // ---- The disappearing message: shown, then gone ----
    await see('the disappearing message', find.text(_fleeting));
    final fleeting = (await db.messageDao.getMessagesForConversation(groupId))
        .firstWhere((m) => m.plaintext == _fleeting);
    expect(fleeting.expiresIn, _ttlSeconds);
    await gone(
      'the disappearing message went',
      find.text(_fleeting),
      within: const Duration(seconds: _ttlSeconds * 3),
    );
    expect(
      (await db.messageDao.getMessagesForConversation(groupId))
          .any((m) => m.plaintext == _fleeting),
      isFalse,
    );
    await write(_answer);
    await sent(groupId, _answer);

    // ---- Handed the group: leave it, it goes to the member who joined first ----
    await until('this account owns the group', () async {
      return await roleOf(groupId, me) == gv2RoleOwner ? true : null;
    }, within: const Duration(minutes: 4));
    await see('a line about the hand-over', find.textContaining('owner'));
    await tap('the app bar title', find.text(title));
    await see('group info', find.text('Group Info'));
    await see('"End group" for the owner', find.text('End group'));
    await scrollTo('Leave group', find.text('Leave group'));
    await tap('Leave group', find.text('Leave group'));
    await see(
      'told the group is handed on',
      find.textContaining('handed to the member who joined first'),
    );
    await tap('Leave', find.widgetWithText(TextButton, 'Leave'));
    await see('the Chats tab', find.text('SnowChat'));
    await gone('the group left the list', inList);
    expect((await store.group(groupId))?.membership, Gv2Membership.left);
    _say('PASS');
  });
}
