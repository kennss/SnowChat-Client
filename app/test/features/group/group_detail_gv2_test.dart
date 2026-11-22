/// @file        group_detail_gv2_test.dart
/// @description groupDetailProvider for a group protocol v2 group: a
///              read-only view of what this device holds (members as the
///              change log names them, the owner as "creator", confirmed
///              members as accepted, a contact's name first), following the
///              store as it changes, and never a server call. An id that is
///              not a v2 group id is an empty, settled detail.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20 (v1 groups removed: the provider has no actions; a non-v2 id is an empty
///              detail, not a server load)
///
/// @functions
///  - main(): the cases above
///  - _Api: an API client that records any call (and fails it)
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_store.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/group/providers/group_detail_provider.dart';
import 'package:snowchat/features/group/providers/gv2_group_provider.dart';

import '../../core/group_v2/gv2_test_support.dart';

class _Api implements ApiClient {
  final List<Symbol> calls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError('no server in this test');
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late SnowDatabase db;
  late _Api api;
  late ProviderContainer container;
  late Gv2TestGroup g;
  late Gv2TestPerson alice;
  late Gv2TestPerson bob;
  late Gv2TestPerson carol;

  Gv2MemberCheckResult confirmed(Gv2TestPerson p, int joinedRevision) =>
      Gv2MemberCheckResult(
        ciphertext: p.key,
        joinedRevision: joinedRevision,
        state: Gv2MemberCheckState.confirmed,
        snowId: p.snowId,
        accountPublicKey: p.accountPub,
        certIssuedAtMs: 1,
      );

  setUp(() async {
    db = SnowDatabase(NativeDatabase.memory());
    api = _Api();
    g = Gv2TestGroup();
    alice = g.person('alice');
    bob = g.person('bob');
    carol = g.person('carol');
    g.create(alice, invite: [bob, carol], title: 'Snow'); // 0
    g.accept(bob); // 1
    g.accept(carol); // 2
    g.change(alice, [Gv2SetRole(bob.ciphertext, gv2RoleAdmin)]); // 3
    await db.gv2Store.insertCreated(
      masterKey: g.masterKey,
      myCiphertext: alice.ciphertext,
      state: g.states[0],
      headSig: g.headSig(0),
      nowMs: 1,
    );
    for (var r = 1; r <= 3; r++) {
      await db.gv2Store.advance(
        from: g.states[r - 1],
        to: g.states[r],
        headSig: g.headSig(r),
      );
    }
    // Alice and bob confirmed; carol not looked at yet.
    await db.gv2Store.saveMemberChecks(g.id, [
      confirmed(alice, 0),
      confirmed(bob, 1),
    ]);
    container = ProviderContainer(overrides: [
      snowDatabaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWithValue(api),
      gv2KnownNamesProvider.overrideWithValue({bob.snowId: 'Bob (contact)'}),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<GroupDetail> loaded() async {
    final sub = container.listen(groupDetailProvider(g.id), (_, _) {});
    addTearDown(sub.close);
    for (var i = 0; i < 50 && container.read(groupDetailProvider(g.id)).isLoading; i++) {
      await pumpEventQueue();
    }
    return container.read(groupDetailProvider(g.id));
  }

  test('shows the members this device holds, the owner as creator, a '
      'contact\'s name first — and asks the server nothing', () async {
    final detail = await loaded();
    expect(detail.isLoading, isFalse);
    expect(detail.name, 'Snow');
    expect(detail.creatorId, alice.snowId);
    final byId = {for (final m in detail.members) m.snowchatId: m};
    expect(byId.keys, {alice.snowId, bob.snowId},
        reason: 'carol\'s account is not known until she is checked');
    expect(byId[bob.snowId]!.displayName, 'Bob (contact)');
    expect(byId[bob.snowId]!.isAdmin, isTrue);
    expect(byId[bob.snowId]!.status, 'accepted');
    expect(byId[alice.snowId]!.isAdmin, isFalse);
    expect(api.calls, isEmpty);
  });

  test('follows the store: a member checked later appears', () async {
    await loaded();
    await db.gv2Store.saveMemberChecks(g.id, [confirmed(carol, 2)]);
    for (var i = 0; i < 50; i++) {
      await pumpEventQueue();
      if (container.read(groupDetailProvider(g.id)).members.length == 3) break;
    }
    expect(
      container.read(groupDetailProvider(g.id)).members.map((m) => m.snowchatId),
      containsAll([alice.snowId, bob.snowId, carol.snowId]),
    );
    expect(api.calls, isEmpty);
  });

  test('loading again reads the store, without a server call', () async {
    await loaded();
    final notifier = container.read(groupDetailProvider(g.id).notifier);
    await notifier.loadGroup();
    expect(container.read(groupDetailProvider(g.id)).name, 'Snow');
    expect(api.calls, isEmpty);
  });

  test('an id that is not a v2 group id is an empty, settled detail — no '
      'server call', () async {
    const id = 'clx0v1group000000000000001';
    final sub = container.listen(groupDetailProvider(id), (_, _) {});
    addTearDown(sub.close);
    await pumpEventQueue();
    final detail = container.read(groupDetailProvider(id));
    expect(detail.isLoading, isFalse);
    expect(detail.members, isEmpty);
    expect(detail.error, isNull);
    await container.read(groupDetailProvider(id).notifier).loadGroup();
    expect(api.calls, isEmpty);
  });

  test('a group this device does not hold reads as empty, not as an error',
      () async {
    final other = 'cd' * 32;
    final sub = container.listen(groupDetailProvider(other), (_, _) {});
    addTearDown(sub.close);
    for (var i = 0; i < 50 && container.read(groupDetailProvider(other)).isLoading; i++) {
      await pumpEventQueue();
    }
    final detail = container.read(groupDetailProvider(other));
    expect(detail.members, isEmpty);
    expect(detail.error, isNull);
    expect(api.calls, isEmpty);
    expect(gv2IsGroupId(other), isTrue);
  });
}
