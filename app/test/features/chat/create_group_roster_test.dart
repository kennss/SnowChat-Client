/// @file        create_group_roster_test.dart
/// @description The group pickers. The new-group screen opened from a
///              community: the roster split into accounts this user vouched
///              for (known) and the others — an account whose key a session
///              proved (the identity latch) but that the user never chose
///              is NOT known; "Select all" takes the known ones
///              only; the unknown ones are listed only after a warning; at
///              most gv2GroupSizeLimit - 1 accounts can be picked (and
///              "Select all" turns to "Clear" there); blocked accounts are
///              not listed; a roster or block list that cannot be loaded
///              offers a retry. From the contacts and on the add-members
///              screen: the same split and warning, existing members left
///              out.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21 (X1: the blocked accounts come from this device's list — no server call, no "without the block list" case). Earlier 2026-11-21 (known = vouched; contacts mode and add members)
///
/// @functions
///  - main(): the cases above
///  - _Api: answers GET /channels/:id with a given roster and GET
///    /users/blocked with a given block list (or fails)
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/blocking/block_list.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';
import 'package:snowchat/core/group_v2/gv2_groups.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/features/chat/screens/create_group_screen.dart';
import 'package:snowchat/features/group/providers/pick_candidates.dart';
import 'package:snowchat/features/group/screens/add_group_members_screen.dart';
import 'package:snowchat/features/group/widgets/account_picker_list.dart';

import '../../core/crypto/identity_test_support.dart';

const _community = 'community-1';

String _snow(int i) => 'snow${i.toRadixString(16).padLeft(32, '0')}';

class _Api implements ApiClient {
  Object? detail;
  bool fail = false;
  final List<String> paths = [];

  _Api(this.detail);

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    paths.add(path);
    if (fail) throw DioException(requestOptions: RequestOptions(path: path));
    return Response<T>(
      data: detail as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not in this test: ${invocation.memberName}');
}

/// This device's block list (X1), as the screens read it.
class _Blocks extends Fake implements BlockList {
  final Set<String> ids;
  _Blocks(this.ids);

  @override
  Future<void> load() async {}

  @override
  Set<String> get blocked => Set.unmodifiable(ids);

  @override
  Future<bool> isBlocked(String snowId) async => ids.contains(snowId);

  @override
  Stream<Set<String>> get changes => const Stream.empty();
}

Map<String, Object?> _roster(Map<int, String> people) => {
      'name': 'Snow (server)',
      'members': [
        for (final e in people.entries)
          {
            'user': {'snowchatId': _snow(e.key), 'displayName': e.value},
          },
      ],
    };

void main() {
  late VerifiedIdentityStore store;

  setUp(() => store = VerifiedIdentityStore(InMemorySecureStorage()));

  Future<_Api> open(
    WidgetTester tester,
    Object? detail, {
    Set<String> blocked = const {},
  }) async {
    final api = _Api(detail);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          blockListProvider.overrideWithValue(_Blocks(blocked)),
          verifiedIdentityStoreProvider.overrideWithValue(store),
          currentSnowIdProvider.overrideWith((_) => _snow(0)),
        ],
        child: const MaterialApp(
          home: CreateGroupScreen(communityId: _community, communityName: 'Snow'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('known accounts are listed and "Select all" takes only them; '
      'the others appear only after a warning', (tester) async {
    await store.vouch(_snow(1), VouchSource.message); // wrote to them
    await store.vouch(_snow(2), VouchSource.friendRequest);
    // A session proved this one's key, but the user never chose it.
    await store.raiseLatch(_snow(3), 9);
    await store.vouch(_snow(4), VouchSource.message); // then blocked
    final api = await open(
      tester,
      _roster({0: 'Me', 1: 'Ann', 2: 'Ben', 3: 'Stranger', 4: 'Blocked'}),
      blocked: {_snow(4)},
    );
    // The blocked accounts are this device's list: no server call for them.
    expect(api.paths, ['/channels/$_community']);
    // The name the roster came with (the link's name is only a stand-in).
    expect(find.text('New group · Snow (server)'), findsOneWidget);
    expect(find.text('Blocked'), findsNothing);
    expect(find.text('People you know (2)'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Ben'), findsOneWidget);
    expect(find.text('Me'), findsNothing);
    expect(find.text('Not verified (1)'), findsOneWidget);
    expect(find.text('Stranger'), findsNothing);
    // Every account shows its snowId (the name is the server's word).
    expect(find.text('${_snow(1).substring(0, 10)}...${_snow(1).substring(32)}'),
        findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 members selected'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    // Cancel keeps them hidden.
    await tester.tap(find.textContaining("haven't verified"));
    await tester.pumpAndSettle();
    expect(find.text(accountPickerWarningTitle), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Stranger'), findsNothing);

    await tester.tap(find.textContaining("haven't verified"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show them'));
    await tester.pumpAndSettle();
    expect(find.text('Stranger'), findsOneWidget);
    await tester.tap(find.text('Stranger'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 members selected'), findsOneWidget);

    // "Clear" unpicks the known ones only.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 member selected'), findsOneWidget);
  });

  testWidgets('no more than gv2GroupSizeLimit - 1 accounts can be picked',
      (tester) async {
    final people = {for (var i = 1; i <= gv2GroupSizeLimit + 10; i++) i: 'P$i'};
    for (final i in people.keys) {
      await store.vouch(_snow(i), VouchSource.message);
    }
    await open(tester, _roster(people));
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('${gv2GroupSizeLimit - 1} members selected'),
      findsOneWidget,
    );
    expect(
      find.text('A group holds up to $gv2GroupSizeLimit people for now.'),
      findsOneWidget,
    );
    // Full: "Select all" has become "Clear", which unpicks them.
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 members selected'), findsOneWidget);
  });

  testWidgets('a roster that cannot be loaded offers a retry', (tester) async {
    final api = _Api(null)..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          blockListProvider.overrideWithValue(_Blocks({})),
          verifiedIdentityStoreProvider.overrideWithValue(store),
          currentSnowIdProvider.overrideWith((_) => _snow(0)),
        ],
        child: const MaterialApp(
          home: CreateGroupScreen(communityId: _community),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the member list."), findsOneWidget);
    api
      ..fail = false
      ..detail = _roster({1: 'Ann'});
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Not verified (1)'), findsOneWidget);
    expect(api.paths, ['/channels/$_community', '/channels/$_community']);
  });

  List<PickCandidate> contacts() => [
        PickCandidate(snowId: _snow(1), name: 'Ann', known: true),
        PickCandidate(snowId: _snow(2), name: 'Ben', known: true),
        PickCandidate(snowId: _snow(3), name: 'Co-member', known: false),
      ];

  testWidgets('from the contacts: the same split; the not verified ones '
      'after the warning', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactPickCandidatesProvider.overrideWith((_) async => contacts()),
        ],
        child: const MaterialApp(home: CreateGroupScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New Group'), findsOneWidget);
    expect(find.text('People you know (2)'), findsOneWidget);
    expect(find.text('Co-member'), findsNothing);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 members selected'), findsOneWidget);
    await tester.tap(find.textContaining("haven't verified"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show them'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Co-member'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 members selected'), findsOneWidget);
  });

  testWidgets('add members: members left out; the same split', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactPickCandidatesProvider.overrideWith((_) async => contacts()),
        ],
        child: MaterialApp(
          home: AddGroupMembersScreen(
            groupId: 'ab' * 32,
            existingMemberSnowchatIds: [_snow(2)],
            placesTaken: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('People you know (1)'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Ben'), findsNothing, reason: 'already a member');
    expect(find.text('Not verified (1)'), findsOneWidget);
    expect(find.text('Co-member'), findsNothing);
    await tester.tap(find.text('Ann'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 member selected'), findsOneWidget);
  });
}
