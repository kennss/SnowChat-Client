/// @file        add_friend_screen_test.dart
/// @description Widget tests for Add Friend by nickname (design 2026-11-22-friend-graph-off-server
///              §5.1, §5.5): the found account shows "@nick" with its short snowId; when another
///              account this device knows already goes by that name, a warning names both short
///              snowIds; an account already a friend / asked already shows that instead of the send
///              button, one that asked this user offers "Accept"; a rate-limited lookup and a
///              failed one are told apart from "no one"; sending calls requestFound and says
///              "Request sent". The lookup and the list are fakes — no server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - _Lookup: a ContactLookup answering from the test
///  - _NoBlocks: a block list with nothing blocked
///  - main(): the cases above
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:snowchat/app/providers.dart'
    show blockListProvider, contactLookupProvider, currentSnowIdProvider, shortSnowId;
import 'package:snowchat/core/blocking/block_list.dart';
import 'package:snowchat/core/contacts/contact_lookup.dart';
import 'package:snowchat/core/contacts/contact_store.dart';
import 'package:snowchat/features/channels/screens/add_friend_screen.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';

import '../contacts/fake_contact_notifier.dart';

const _me = 'snowffffffffffffffffffffffffffffffff';
const _found = 'snow0123456789abcdef0123456789abcdef';
const _other = 'snow1123456789abcdef0123456789abcdef';

class _Lookup implements ContactLookup {
  NickLookupResult answer = NickLookupResult(
    account: FoundAccount(
      snowId: _found,
      accountPub: Uint8List(32),
      displayName: 'alice',
    ),
  );

  @override
  Future<NickLookupResult> byNick(String nick) async => answer;

  @override
  Future<ResolveResult> resolve(String snowId) async =>
      const ResolveResult(notFound: true);
}

class _NoBlocks extends Fake implements BlockList {
  @override
  Future<void> load() async {}

  @override
  Set<String> get blocked => const {};
}

void main() {
  late FakeContactNotifier contacts;
  late _Lookup lookup;

  Future<void> show(WidgetTester tester, {List<Contact> rows = const []}) async {
    contacts = FakeContactNotifier(rows);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
        GoRoute(path: '/add', builder: (_, _) => const AddFriendScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        contactProvider.overrideWith((ref) => contacts),
        contactLookupProvider.overrideWithValue(lookup),
        blockListProvider.overrideWithValue(_NoBlocks()),
        currentSnowIdProvider.overrideWith((ref) => _me),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    router.push('/add');
    await tester.pumpAndSettle();
  }

  /// Type [nick] and let the debounced lookup run.
  Future<void> type(WidgetTester tester, String nick) async {
    await tester.enterText(find.byType(TextField), nick);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  setUp(() => lookup = _Lookup());

  testWidgets('the found account: @nick with its short snowId, no warning',
      (tester) async {
    await show(tester);
    await type(tester, 'alice');
    expect(find.text('@alice'), findsOneWidget);
    expect(find.text(shortSnowId(_found)), findsOneWidget);
    expect(find.textContaining('already goes by this name'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Send Friend Request'),
        findsOneWidget);
  });

  testWidgets('a name another known account has: the warning names both short '
      'snowIds', (tester) async {
    await show(tester);
    contacts.takenBy = _other;
    await type(tester, 'alice');
    final warning = find.textContaining('already goes by this name');
    expect(warning, findsOneWidget);
    final text = tester.widget<Text>(warning).data!;
    expect(text, contains(shortSnowId(_found)));
    expect(text, contains(shortSnowId(_other)));
  });

  testWidgets('send: requestFound, then "Request sent"', (tester) async {
    await show(tester);
    await type(tester, 'alice');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Friend Request'));
    await tester.pumpAndSettle();
    expect(contacts.calls, [('requestFound', _found)]);
    expect(find.text('Request sent.'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('already a friend: no send button', (tester) async {
    await show(tester, rows: [contactOf(_found, label: ContactLabel.friend)]);
    await type(tester, 'alice');
    expect(find.text('Already your friend.'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('asked already: no send button', (tester) async {
    await show(tester, rows: [contactOf(_found, label: ContactLabel.requestSent)]);
    await type(tester, 'alice');
    expect(find.textContaining('Request sent already'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('an account that asked: the button accepts', (tester) async {
    await show(tester,
        rows: [contactOf(_found, label: ContactLabel.requestReceived)]);
    await type(tester, 'alice');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Accept Friend Request'));
    await tester.pumpAndSettle();
    expect(contacts.calls, [('requestFound', _found)]);
    expect(find.text('You are now friends.'), findsOneWidget);
  });

  testWidgets('rate limited, failed and not found read differently',
      (tester) async {
    await show(tester);
    lookup.answer = const NickLookupResult(rateLimited: true);
    await type(tester, 'alice');
    expect(find.textContaining('Too many lookups'), findsOneWidget);

    lookup.answer = const NickLookupResult(failed: true);
    await type(tester, 'alicia');
    expect(find.textContaining('Could not look this nickname up'), findsOneWidget);

    lookup.answer = const NickLookupResult();
    await type(tester, 'alison');
    expect(find.text('No one is using that nickname.'), findsOneWidget);
  });
}
