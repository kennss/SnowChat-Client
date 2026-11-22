/// @file        friend_list_screen_test.dart
/// @description Widget tests for the Friends tab (design 2026-11-22-friend-graph-off-server §5.1):
///              the three sections (Requests received, Friends, Requests sent) with each row's
///              short snowId; each button calls the right action — Accept → accept, Decline →
///              decline, Block (after its confirmation) → blockContact, Resend → resend, Cancel →
///              remove, the friend sheet's Remove (after "Your messages are kept") → remove; an
///              account refused again and again reads "Account unavailable"; the empty state. The
///              friend sheet's "Resend friend request" → resend; Block at the 5,000-account cap
///              says so. The rows come from a FakeContactNotifier — no store, outbox or server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (Resend on a friend; the block cap message)
///
/// @functions
///  - main(): the cases above
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart' show shortSnowId;
import 'package:snowchat/core/contacts/contact_store.dart';
import 'package:snowchat/features/channels/screens/friend_list_screen.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';

import '../contacts/fake_contact_notifier.dart';

const _alice = 'snow0123456789abcdef0123456789abcdef';
const _bob = 'snow1123456789abcdef0123456789abcdef';
const _carol = 'snow2123456789abcdef0123456789abcdef';

void main() {
  late FakeContactNotifier contacts;

  Future<void> show(WidgetTester tester, List<Contact> rows) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    contacts = FakeContactNotifier(rows);
    await tester.pumpWidget(ProviderScope(
      overrides: [contactProvider.overrideWith((ref) => contacts)],
      child: const MaterialApp(home: FriendListScreen()),
    ));
    await tester.pump();
  }

  final rows = [
    contactOf(_alice, name: 'alice', label: ContactLabel.friend),
    contactOf(_bob, name: 'bob', label: ContactLabel.requestReceived),
    contactOf(_carol, label: ContactLabel.requestSent),
  ];

  testWidgets('three sections, each row with its short snowId', (tester) async {
    await show(tester, rows);
    expect(find.text('Requests received (1)'), findsOneWidget);
    expect(find.text('Friends (1)'), findsOneWidget);
    expect(find.text('Requests sent (1)'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    // A row without a name shows the short snowId as its name too.
    expect(find.text(shortSnowId(_carol)), findsNWidgets(2));
    expect(find.text(shortSnowId(_alice)), findsOneWidget);
    expect(find.text(shortSnowId(_bob)), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
    // The sections in order: received, friends, sent.
    final received = tester.getTopLeft(find.text('Requests received (1)')).dy;
    final friends = tester.getTopLeft(find.text('Friends (1)')).dy;
    final sent = tester.getTopLeft(find.text('Requests sent (1)')).dy;
    expect(received < friends && friends < sent, isTrue);
  });

  testWidgets('a received request: Accept, Decline, Block', (tester) async {
    await show(tester, rows);
    await tester.tap(find.byKey(const ValueKey('accept:$_bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('decline:$_bob')));
    await tester.pumpAndSettle();
    expect(contacts.calls, [('accept', _bob), ('decline', _bob)]);

    // Block asks first; Cancel blocks nothing.
    await tester.tap(find.byKey(const ValueKey('block:$_bob')));
    await tester.pumpAndSettle();
    expect(find.text('Block bob?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(contacts.calls, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('block:$_bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Block').last);
    await tester.pumpAndSettle();
    expect(contacts.calls.last, ('blockContact', _bob));
  });

  testWidgets('a sent request: Resend, Cancel', (tester) async {
    await show(tester, rows);
    await tester.tap(find.byKey(const ValueKey('resend:$_carol')));
    await tester.pumpAndSettle();
    expect(find.text('Request sent again.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel:$_carol')));
    await tester.pumpAndSettle();
    expect(contacts.calls, [('resend', _carol), ('remove', _carol)]);
  });

  testWidgets('a friend: the sheet, Remove after "Your messages are kept"',
      (tester) async {
    await show(tester, rows);
    await tester.tap(find.byKey(const ValueKey('more:$_alice')));
    await tester.pumpAndSettle();
    expect(find.text('Send message'), findsOneWidget);
    expect(find.text('Voice call'), findsOneWidget);
    await tester.tap(find.text('Remove friend'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your messages are kept.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(contacts.calls, [('remove', _alice)]);
  });

  testWidgets('a friend: the sheet resends the friend request', (tester) async {
    await show(tester, rows);
    await tester.tap(find.byKey(const ValueKey('more:$_alice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resend-friend:$_alice')));
    await tester.pumpAndSettle();
    expect(contacts.calls, [('resend', _alice)]);
    expect(find.text('Sent again.'), findsOneWidget);
  });

  testWidgets('Block at the cap says so', (tester) async {
    await show(tester, rows);
    contacts.atBlockLimit = true;
    await tester.tap(find.byKey(const ValueKey('block:$_bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Block').last);
    await tester.pumpAndSettle();
    expect(find.text(blockLimitText), findsOneWidget);
    expect(contacts.calls, isEmpty);
  });

  testWidgets('long-press on a friend opens the same sheet', (tester) async {
    await show(tester, rows);
    await tester.longPress(find.byKey(const ValueKey('friend:$_alice')));
    await tester.pumpAndSettle();
    expect(find.text('Remove friend'), findsOneWidget);
  });

  testWidgets('an account refused again and again reads "Account unavailable"',
      (tester) async {
    await show(tester, [
      contactOf(_alice, name: 'alice', label: ContactLabel.friend, unavailable: true),
      contactOf(_bob, name: 'bob', label: ContactLabel.friend),
    ]);
    expect(find.text('Account unavailable'), findsOneWidget);
    final row = find.byKey(const ValueKey('friend:$_alice'));
    expect(find.descendant(of: row, matching: find.text('Account unavailable')),
        findsOneWidget);
  });

  testWidgets('no presence: no "Online", no "Last seen"', (tester) async {
    await show(tester, rows);
    expect(find.textContaining('Online'), findsNothing);
    expect(find.textContaining('Last seen'), findsNothing);
  });

  testWidgets('empty: no friends yet, with an Add friend button', (tester) async {
    await show(tester, const []);
    expect(find.text('No friends yet'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Add friend'), findsOneWidget);
  });

  testWidgets('only requests: the Friends section says none yet', (tester) async {
    await show(tester, [contactOf(_bob, name: 'bob', label: ContactLabel.requestReceived)]);
    expect(find.text('Friends (0)'), findsOneWidget);
    expect(find.textContaining('No friends yet.'), findsOneWidget);
  });
}
