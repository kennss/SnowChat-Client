/// @file        gv2_roundtrip_test.dart
/// @description Group protocol v2 on a device, without screens: the real app
///              is started (its own identity, database, socket, 1:1
///              sessions, native zkgroup) and driven through its providers —
///              one device creates a group and invites the other, the other
///              takes the invite in over the sealed 1:1 path, accepts, is
///              confirmed, and the two exchange a message each way. Run it
///              on two emulators at once, one per role, against the dev
///              server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (asserts the build pins the group server keys — ENABLE_GROUPS_V2 is gone)
///
/// @functions
///  - main(): one test; what it does is chosen by GV2_E2E_ROLE.
///
/// Notes:
///  - Needs an app that is already onboarded on the device (the test uses
///    the account that is there; it creates none) and a build for a
///    SERVER_ENV whose group server keys it pins (dev).
///  - Roles (`--dart-define=GV2_E2E_ROLE=...`):
///      whoami  print this device's account id (to pass to the other run)
///      create  create a group inviting GV2_E2E_PEER, wait until the peer
///              is a confirmed member, send "ping", wait for "pong"
///      join    wait for the invite to that group, accept it (unless the
///              app accepted it by itself), wait to be confirmed, wait for
///              "ping", answer "pong"
///      backup  (one device, no peer) write the group key backup to the
///              server, read it back and open it with the key from the
///              recovery phrase: it must list exactly the groups this
///              account is a member of, each at the head this device holds;
///              then write it again against a tag the server no longer
///              holds (the conflict a second install causes)
///    GV2_E2E_TAG names the run: both devices use the same tag, and the
///    group is titled with it.
///  - Example (two shells; ids from two whoami runs):
///      flutter test integration_test/gv2_roundtrip_test.dart -d emulator-5556 \
///        --dart-define=GV2_E2E_ROLE=join \
///        --dart-define=GV2_E2E_PEER=CREATOR_ID --dart-define=GV2_E2E_TAG=t1
///      flutter test integration_test/gv2_roundtrip_test.dart -d emulator-5554 \
///        --dart-define=GV2_E2E_ROLE=create \
///        --dart-define=GV2_E2E_PEER=JOINER_ID --dart-define=GV2_E2E_TAG=t1
///  - It prints steps and counts only: no keys, no message content beyond
///    the fixed ping/pong, no group id.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:snowchat/core/group_v2/gv2_trusted_keys.dart'
    show gv2GroupsAvailable;
import 'package:snowchat/app/app.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/group_v2/gv2_backup.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_content.dart';
import 'package:snowchat/core/group_v2/gv2_runtime.dart';
import 'package:snowchat/core/messaging/gv2_message_sink.dart';
import 'package:snowchat/core/network/gv2_backup_client.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/main.dart' as app;

const _role = String.fromEnvironment('GV2_E2E_ROLE');
const _peer = String.fromEnvironment('GV2_E2E_PEER');
const _tag = String.fromEnvironment('GV2_E2E_TAG', defaultValue: 'run');

const _step = Duration(milliseconds: 500);

void _say(String line) {
  // The test's own progress lines (read from the runner's output).
  // ignore: avoid_print
  print('GV2E2E[$_role] $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('group protocol v2 round trip ($_role)', (tester) async {
    expect(
      {'whoami', 'create', 'join', 'backup'}.contains(_role),
      isTrue,
      reason: 'set GV2_E2E_ROLE to whoami, create, join or backup',
    );

    app.main();
    await tester.pump(const Duration(seconds: 2));

    /// Keep the app's frames going until [done] says so.
    Future<T> until<T>(
      String what,
      FutureOr<T?> Function() done, {
      Duration within = const Duration(minutes: 4),
    }) async {
      final deadline = DateTime.now().add(within);
      while (DateTime.now().isBefore(deadline)) {
        final value = await done();
        if (value != null) {
          _say('ok: $what');
          return value;
        }
        await tester.pump(_step);
        await Future<void>.delayed(_step);
      }
      fail('timed out waiting for: $what');
    }

    final container = await until('the app is up', () {
      final found = find.byType(SnowChatApp);
      if (found.evaluate().isEmpty) return null;
      return ProviderScope.containerOf(tester.element(found));
    });

    final me = await until(
      'an account is signed in',
      () => container.read(currentSnowIdProvider),
      within: const Duration(minutes: 2),
    );

    if (_role == 'whoami') {
      _say('snowId=$me');
      return;
    }

    expect(gv2GroupsAvailable, isTrue,
        reason: 'a SERVER_ENV whose group server keys this build pins');
    if (_role != 'backup') {
      expect(_peer.length, 36, reason: 'set GV2_E2E_PEER to the other account');
      expect(_peer, isNot(me));
    }

    final Gv2Runtime runtime = await until(
      'group protocol v2 is running',
      () => container.read(gv2RuntimeProvider),
    );
    await until(
      'the socket is connected',
      () => container.read(socketManagerProvider).isConnected ? true : null,
    );
    final db = container.read(snowDatabaseProvider);
    final store = db.gv2Store;
    final title = 'gv2 e2e $_tag';

    Future<Gv2GroupRow?> groupNamed() async {
      for (final g in await store.groups()) {
        if (g.title == title) return g;
      }
      return null;
    }

    Future<bool> has(String groupId, String text) async {
      final rows = await db.messageDao.getMessagesForConversation(groupId);
      return rows.any(
        (m) => m.plaintext == text && m.senderSnowchatId == _peer,
      );
    }

    Future<void> send(String groupId, String text) => runtime.messaging.send(
      groupId,
      Gv2MessageContent(Gv2AppMessagePayload(text: text).encode()),
    );

    Future<bool> nothingQueued() async =>
        (await db.gv2OutboxStore.allRows()).isEmpty;

    if (_role == 'backup') {
      await runtime.pump();
      final first = await runtime.backup.sync();
      expect(first.looked, isTrue);
      expect(first.reached, isTrue);

      const member = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
      final mine = {
        for (final g in await store.groups())
          if (member.contains(g.membership)) g.groupId: g,
      };
      final client = Gv2BackupClient(container.read(apiClientProvider));
      final key = await container
          .read(identityManagerProvider)
          .deriveGroupBackupKey();
      final held = await client.fetch();
      expect(held.blob, isNotNull);
      expect(held.etag, (await store.backupState())!.etag);
      final entries = gv2OpenBackup(key, held.blob!);
      expect(entries, isNotNull);
      expect({for (final e in entries!) gv2Hex(e.groupId)}, mine.keys.toSet());
      for (final e in entries) {
        final row = mine[gv2Hex(e.groupId)]!;
        expect(e.masterKey, row.masterKey);
        expect(e.revision, lessThanOrEqualTo(row.revision));
      }
      _say('the server holds this account\'s list: groups=${entries.length} '
          'bytes=${held.blob!.length}');

      // Another install wrote meanwhile: this device's tag is stale.
      final other = await client.store(
        gv2SealBackup(key, const []),
        held.etag,
      );
      expect(other, isNotNull);
      expect(await client.store(held.blob!, held.etag), isNull);
      await store.saveBackupState(
        restored: true,
        etag: held.etag,
        fingerprint: null,
      );
      final again = await runtime.backup.sync();
      expect(again.written, isTrue);
      final now = await client.fetch();
      expect(now.etag, (await store.backupState())!.etag);
      final rewritten = gv2OpenBackup(key, now.blob!)!;
      expect(
        {for (final e in rewritten) gv2Hex(e.groupId)},
        mine.keys.toSet(),
      );
      for (final e in rewritten) {
        expect(e.revision, mine[gv2Hex(e.groupId)]!.revision);
      }
      _say('PASS groups=${rewritten.length}');
      return;
    }

    if (_role == 'create') {
      final groupId = await runtime.groups.create(title: title, invite: [_peer]);
      _say('created (stored on this device)');
      await until('the server signed the group\'s head', () async {
        final g = await store.group(groupId);
        return g?.membership == Gv2Membership.active ? true : null;
      });
      await until('the peer accepted and its account is confirmed', () async {
        final m = await store.memberBySnowId(groupId, _peer);
        return m?.checkState == Gv2MemberCheckState.confirmed ? true : null;
      }, within: const Duration(minutes: 6));
      await send(groupId, 'ping $_tag');
      await until('ping left the outbox', () async {
        return await nothingQueued() ? true : null;
      });
      await until('pong arrived from the peer', () async {
        return await has(groupId, 'pong $_tag') ? true : null;
      });
      final conversation = await db.conversationDao.getConversation(groupId);
      expect(conversation, isNotNull);
      expect(conversation!.type, 'group');
      expect(conversation.title, title);
      _say('PASS revision=${(await store.group(groupId))!.revision} '
          'members=${(await store.confirmedMembers(groupId)).length}');
      return;
    }

    // join
    final invited = await until('the invite arrived and holds', () async {
      final g = await groupNamed();
      return g != null && g.stateLoaded ? g : null;
    }, within: const Duration(minutes: 6));
    expect(invited.invitedBySnowId, _peer);
    final groupId = invited.groupId;
    if (invited.membership == Gv2Membership.invited) {
      await runtime.groups.accept(groupId);
      _say('accepted');
    } else {
      _say('the app accepted it by itself');
    }
    await until('a member confirmed the head', () async {
      final g = await store.group(groupId);
      return g?.membership == Gv2Membership.active ? true : null;
    });
    await until('ping arrived from the peer', () async {
      return await has(groupId, 'ping $_tag') ? true : null;
    });
    await send(groupId, 'pong $_tag');
    await until('pong left the outbox', () async {
      return await nothingQueued() ? true : null;
    });
    // No 1:1 room was made out of the invite message.
    final direct = await db.conversationDao.findDirectByParticipant(_peer);
    _say('PASS revision=${(await store.group(groupId))!.revision} '
        'members=${(await store.confirmedMembers(groupId)).length} '
        'directRoomWithInviter=${direct != null}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
