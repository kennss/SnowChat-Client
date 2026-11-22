/// @file        community_group_screens_test.dart
/// @description A group made from a community roster, through the app, on
///              two devices at once against the dev server (design
///              2026-11-20-community-roster-v1-removal §4): the host's
///              community, joined by the guest on application and approval;
///              "New group from members" in the expanded roster; the guest
///              listed as known (the host vouched for it: a friend request,
///              a message written to it, a safety number checked) or behind
///              the warning for accounts not verified, with its snowId
///              shown; a v2 group
///              created with the guest invited; the invite taken (or taken
///              by the app for a confirmed friend), the guest confirmed by
///              the host and the two talking both ways; the group ended and
///              the community deleted.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - main(): one test; what it does is chosen by S3_ROLE (host | guest)
///
/// Notes:
///  - Build the test as the app and install it over an onboarded install
///    (`flutter build apk --debug --target=integration_test/...` then
///    `adb install -r`); `flutter test integration_test` uninstalls the app
///    when it ends.
///  - `--dart-define=S3_ROLE=host|guest`, `S3_PEER=<the other account's
///    snowId>`, `S3_TAG=<a name for the run>` (the same on both devices).
///    Start the guest first.
///  - Whether the host vouched for the guest on its device decides which
///    section lists it; the test reads that and takes the path.
///  - It prints steps only: no keys, no group id, no message content beyond
///    its own fixed texts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart'
    show gv2GroupsAvailable;
import 'package:snowchat/core/network/api_endpoints.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/channels/providers/channel_provider.dart';

import 'support/screen_driver.dart';

const _role = String.fromEnvironment('S3_ROLE');
const _peer = String.fromEnvironment('S3_PEER');
const _tag = String.fromEnvironment('S3_TAG', defaultValue: 'run');

const _step = Duration(milliseconds: 400);

void _say(String line) {
  // The test's own progress lines (read from the device log).
  // ignore: avoid_print
  print('S3UI[$_role] $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a group from a community roster ($_role)', (tester) async {
    expect({'host', 'guest'}.contains(_role), isTrue, reason: 'S3_ROLE');
    expect(_peer.length, 36, reason: 'S3_PEER');
    expect(gv2GroupsAvailable, isTrue,
        reason: 'a SERVER_ENV whose group server keys this build pins');

    final community = 's3 com $_tag';
    final title = 's3 group $_tag';
    final ping = 'roster ping $_tag';
    final pong = 'roster pong $_tag';

    final d = ScreenDriver(tester, _say);
    await d.start();
    final container = d.container;
    final me = d.me;
    expect(_peer, isNot(me));
    final store = d.store;
    final api = container.read(apiClientProvider);
    final channels = container.read(channelActionsProvider);
    final until = d.until;
    final shown = d.shown;
    final see = d.see;
    final tap = d.tap;
    final write = d.write;
    final sent = d.sent;
    final groupTitled = d.groupTitled;
    final short =
        '${_peer.substring(0, 10)}...${_peer.substring(_peer.length - 4)}';

    if (_role == 'host') {
      // ---- A community the guest applies to ----
      final created = await channels.createChannel(
        name: community,
        isPublic: true,
        joinPolicy: 'APPROVAL',
      );
      final channelId = created?['channelId'] as String?;
      expect(channelId, isNotNull, reason: 'the community is created');
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

      // ---- "New group from members" in the expanded roster ----
      d.router().go('/contacts?expand=${Uri.encodeQueryComponent(channelId)}');
      await tap('New group from members', find.text('New group from members'));
      await see('the roster picker', find.text('New group · $community'));
      final known = await container
          .read(verifiedIdentityStoreProvider)
          .isVouched(_peer);
      _say('the guest is ${known ? 'known' : 'not verified'} on this device');
      if (known) {
        await see('the known section', find.text('People you know (1)'));
        await see('the guest\'s snowId', find.text(short));
        await tap('Select all', find.text('Select all'));
      } else {
        await see('the not-verified section', find.text('Not verified (1)'));
        expect(shown(find.text(short)), isFalse,
            reason: 'an account not verified is hidden until the warning');
        await tap('show the accounts not verified',
            find.textContaining("haven't verified"));
        await see('the warning', find.text('Accounts you have not verified'));
        await tap('Show them', find.text('Show them'));
        await tap('the guest', find.text(short));
      }
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

      // ---- The guest joins and is confirmed; talk ----
      await until('the guest is a confirmed member', () async {
        final m = await store.memberBySnowId(groupId, _peer);
        return m != null && m.checkState == Gv2MemberCheckState.confirmed
            ? true
            : null;
      });
      await write(ping);
      await sent(groupId, ping);
      await see('the guest\'s answer', find.text(pong),
          within: const Duration(minutes: 3));

      // ---- Clean up ----
      await container.read(gv2RuntimeProvider)!.groups.end(groupId);
      _say('group ended');
      expect(await channels.deleteChannel(channelId), isTrue);
      _say('community deleted');
      _say('PASS');
      return;
    }

    // ================= guest =================
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

    // ---- The invite (or the group, for a confirmed friend) ----
    d.router().go('/chat');
    final invite = find.text('Accept');
    final inList = find.text(title);
    final how = await until('the invite, or the group itself, shows', () {
      if (shown(invite) && shown(inList)) return 'invite';
      if (shown(inList)) return 'accepted';
      return null;
    }, within: const Duration(minutes: 8));
    if (how == 'invite') {
      await see('the invites section', find.text('Group Invites'));
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
    await until('the host confirmed this device', () async {
      final g = await store.group(groupId);
      return g?.membership == Gv2Membership.active ? true : null;
    });
    await see('the host\'s message', find.text(ping),
        within: const Duration(minutes: 3));
    await write(pong);
    await sent(groupId, pong);

    // ---- The host ends the group ----
    await until('the group ended', () async {
      final g = await store.group(groupId);
      return g?.membership == Gv2Membership.ended ? true : null;
    }, within: const Duration(minutes: 3));
    _say('PASS');
  });
}
