/// @file        direct_community_screens_test.dart
/// @description 1:1 chats, friends and communities through the app, on two
///              devices at once against the dev server (design
///              2026-11-20-community-roster-v1-removal §3.3): who may start a
///              1:1 (strangers may not; community co-members and friends
///              may; a kicked member no longer may), a community joined by
///              application and approval and opened expanded on the
///              Communities tab, a 1:1 started from the roster and talked in
///              both ways — each message stored in its SENDER's room, the
///              peer's snowId, and nowhere else — and a 1:1 the peer deletes
///              leaving this device too.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21 (acceptFriendRequest takes the request). Earlier 2026-11-21 (texts carry the run's tag)
///
/// @functions
///  - main(): one test; what it does is chosen by S2_ROLE (host | guest)
///  - _findOrCreate(): the server's answer to "may this account start a 1:1"
///  - _roomsHolding(): the conversations whose messages hold a text
///
/// Notes:
///  - Build the test as the app and install it over an onboarded install
///    (`flutter build apk --debug --target=integration_test/...` then
///    `adb install -r`); `flutter test integration_test` uninstalls the app
///    when it ends.
///  - `--dart-define=S2_ROLE=host|guest`, `S2_PEER=<the other account's
///    snowId>`, `S2_TAG=<a name for the run>` (the same on both devices).
///    Start the guest first.
///  - The host owns the community; the guest applies, talks, is kicked,
///    asks to be friends. The host deletes the 1:1 at the end.
///  - The two accounts must not be friends when it starts: the host ends an
///    existing friendship first (and the guest waits for that).
///  - It prints steps only: no keys, no message content beyond its own
///    fixed texts.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/network/api_endpoints.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/features/channels/providers/channel_provider.dart';
import 'package:snowchat/features/chat/providers/chat_provider.dart';
import 'package:snowchat/features/chat/screens/chat_screen.dart';
import 'package:snowchat/features/chat/widgets/conversation_tile.dart';
import 'package:snowchat/shared/widgets/snow_avatar.dart';

import 'support/screen_driver.dart';

const _role = String.fromEnvironment('S2_ROLE');
const _peer = String.fromEnvironment('S2_PEER');
const _tag = String.fromEnvironment('S2_TAG', defaultValue: 'run');


void _say(String line) {
  // The test's own progress lines (read from the device log).
  // ignore: avoid_print
  print('S2UI[$_role] $line');
}

/// The server's answer to POST /conversations/find-or-create for [peer]:
/// its status code (200 allowed, 403 refused).
Future<int> _findOrCreate(ApiClient api, String peer) async {
  try {
    final r = await api.post<dynamic>(
      ApiEndpoints.conversationFindOrCreate,
      data: {'recipientSnowchatId': peer},
    );
    return r.statusCode ?? 0;
  } on DioException catch (e) {
    return e.response?.statusCode ?? -1;
  }
}

/// The ids of the conversations whose stored messages hold [text].
Future<Set<String>> _roomsHolding(SnowDatabase db, String text) async {
  final rooms = <String>{};
  for (final c in await db.conversationDao.getAllConversations()) {
    final rows = await db.messageDao.getMessagesForConversation(c.id);
    if (rows.any((m) => m.plaintext == text)) rooms.add(c.id);
  }
  return rooms;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1:1, friends and communities through the screens ($_role)',
      (tester) async {
    expect({'host', 'guest'}.contains(_role), isTrue, reason: 'S2_ROLE');
    expect(_peer.length, 36, reason: 'S2_PEER');

    final community = 's2 com $_tag';
    // Texts of this run only (an earlier run left its own in the same room).
    final hello = 'hello from the guest $_tag';
    final reply = 'reply from the host $_tag';
    final friendsNow = 'friends now $_tag';

    final d = ScreenDriver(tester, _say);
    await d.start();
    final container = d.container;
    final me = d.me;
    expect(_peer, isNot(me));
    final db = d.db;
    final api = container.read(apiClientProvider);
    final channels = container.read(channelActionsProvider);
    final friends = container.read(friendActionsProvider);
    final until = d.until;
    final see = d.see;
    final tap = d.tap;

    Future<bool> friendsWithPeer() async {
      container.invalidate(personalChannelProvider);
      final list = await container.read(friendListProvider.future);
      return list.any((f) => f.snowchatId == _peer);
    }

    Future<int> mayStart() => _findOrCreate(api, _peer);

    /// The 1:1 room with the peer holds [text], written by [sender], and no
    /// other conversation does.
    Future<void> storedInPeerRoom(String text, String sender) => until<bool>(
          '"$text" stored in the room of the peer, and nowhere else',
          () async {
            final rows = await db.messageDao.getMessagesForConversation(_peer);
            final there =
                rows.any((m) => m.plaintext == text && m.senderSnowchatId == sender);
            if (!there) return null;
            final rooms = await _roomsHolding(db, text);
            expect(rooms, {_peer}, reason: 'the rooms holding "$text"');
            final room = await db.conversationDao.getConversation(_peer);
            expect(room?.type, 'direct');
            return true;
          },
        );

    if (_role == 'host') {
      // ---- A clean start: not friends ----
      if (await friendsWithPeer()) {
        final channelId = container.read(personalChannelIdProvider);
        final list = await container.read(friendListProvider.future);
        final peer = list.firstWhere((f) => f.snowchatId == _peer);
        expect(channelId, isNotNull);
        expect(await friends.removeFriend(channelId!, peer.userId), isTrue);
        _say('ended the old friendship');
      }

      // ---- A community the guest has to apply to ----
      final created = await channels.createChannel(
        name: community,
        isPublic: true,
        joinPolicy: 'APPROVAL',
      );
      final channelId = created?['channelId'] as String?;
      expect(channelId, isNotNull, reason: 'the community is created');
      expect(created!.containsKey('defaultRoomId'), isFalse,
          reason: 'a community has no room');
      _say('community created');

      final guestUserId = await until('the guest\'s application', () async {
        final r = await api.get<dynamic>('/channels/$channelId');
        final pending = (r.data['pendingMembers'] as List?) ?? const [];
        for (final m in pending) {
          if ((m as Map)['user']?['snowchatId'] == _peer) {
            return m['userId'] as String;
          }
        }
        return null;
      });
      expect(await channels.approveApplication(channelId!, guestUserId), isTrue);
      _say('application approved');

      // ---- The guest's 1:1, started from the roster ----
      await storedInPeerRoom(hello, _peer);
      d.router().go('/chat');
      await see('the Chats tab', find.text('SnowChat'));
      await tap(
        'the 1:1 with the guest',
        find.byWidgetPredicate(
            (w) => w is ConversationTile && w.conversation.id == _peer),
      );
      await see('"$hello" in the chat', find.text(hello));
      await d.write(reply);
      await storedInPeerRoom(reply, me);

      // ---- Kicked: no longer a co-member ----
      expect(await channels.kickMember(channelId, guestUserId), isTrue);
      _say('guest kicked');

      // ---- Friends ----
      final request = await until('the guest\'s friend request', () async {
        container.invalidate(friendRequestsProvider);
        final pending = await container.read(friendRequestsProvider.future);
        for (final r in pending) {
          if (r.creatorSnowchatId == _peer) return r;
        }
        return null;
      });
      expect(await friends.acceptFriendRequest(request), isTrue);
      _say('friend request accepted');
      await until('friends may start a 1:1 (host side)',
          () async => await mayStart() == 200 ? true : null);

      // ---- The guest says so in the 1:1; then the host deletes it ----
      await storedInPeerRoom(friendsNow, _peer);
      await container.read(chatProvider(_peer).notifier).deleteChat();
      _say('1:1 deleted');
      expect(await db.conversationDao.getConversation(_peer), isNull);

      expect(await channels.deleteChannel(channelId), isTrue);
      _say('community deleted');
      _say('PASS');
      return;
    }

    // ================= guest =================
    await until('not friends with the host',
        () async => await friendsWithPeer() ? null : true);
    expect(await mayStart(), 403, reason: 'strangers may not start a 1:1');
    _say('a stranger may not start a 1:1');

    // ---- Apply to the host's community; approved ----
    final channelId = await until('the community is found', () async {
      final r = await api.get<dynamic>(
          '${ApiEndpoints.channelSearch}?q=${Uri.encodeQueryComponent(community)}');
      for (final c in (r.data['channels'] as List?) ?? const []) {
        if ((c as Map)['name'] == community) return c['id'] as String;
      }
      return null;
    });
    final applied = await channels.applyToChannel(channelId);
    _say('applied: $applied');
    await until('the application is approved', () async {
      container.invalidate(myChannelsProvider);
      final mine = await container.read(myChannelsProvider.future);
      return mine.any((c) => c.id == channelId) ? true : null;
    });
    expect(await mayStart(), 200, reason: 'co-members may start a 1:1');

    // ---- The Communities tab, opened with it expanded ----
    d.router().go('/contacts?expand=${Uri.encodeQueryComponent(channelId)}');
    final hostInRoster = find.ancestor(
      of: find.byWidgetPredicate((w) => w is SnowAvatar && w.snowId == _peer),
      matching: find.byType(InkWell),
    );
    await see('the host in the expanded roster', hostInRoster);
    await tap('the host in the roster', hostInRoster.first);
    // (A pushed route is not the router's location: look at the screen.)
    await until(
      'the 1:1 opens under the host\'s snowId',
      () => find
              .byWidgetPredicate(
                  (w) => w is ChatScreen && w.conversationId == _peer)
              .evaluate()
              .isNotEmpty
          ? true
          : null,
    );
    await d.write(hello);
    await storedInPeerRoom(hello, me);
    await see('"$reply" in the chat', find.text(reply));
    await storedInPeerRoom(reply, _peer);

    // ---- Kicked ----
    await until('the community left the list', () async {
      container.invalidate(myChannelsProvider);
      final mine = await container.read(myChannelsProvider.future);
      return mine.any((c) => c.id == channelId) ? null : true;
    });
    expect(await mayStart(), 403, reason: 'a kicked member is no co-member');
    _say('a kicked member may not start a 1:1');

    // ---- Friends ----
    final status = await friends.addFriend(_peer);
    _say('friend request: $status');
    await until('friends may start a 1:1 (guest side)',
        () async => await mayStart() == 200 ? true : null);
    // Still in the 1:1 opened from the roster (the kick closed nothing).
    await until(
      'the 1:1 with the host is still open',
      () => find
              .byWidgetPredicate(
                  (w) => w is ChatScreen && w.conversationId == _peer)
              .hitTestable()
              .evaluate()
              .isNotEmpty
          ? true
          : null,
    );
    await d.write(friendsNow);
    await storedInPeerRoom(friendsNow, me);

    // ---- The host deletes the 1:1: it leaves this device too ----
    await until('the 1:1 is gone from this device', () async {
      final room = await db.conversationDao.getConversation(_peer);
      return room == null ? true : null;
    });
    final left = await db.messageDao.getMessagesForConversation(_peer);
    expect(left, isEmpty, reason: 'its messages went with it');
    _say('PASS');
  });
}
