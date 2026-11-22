/// @file        contact_status_banner_test.dart
/// @description The bar at the top of a 1:1 chat (design 2026-11-22-friend-graph-off-server §5.7):
///              contactBannerStateOf() for every kind of row, and the widget — not in the list
///              (no row, or a declined request): "Not in your friends" with Add → request and Block
///              → the chat's block flow; a sent request: "Request sent"; a received request:
///              "Wants to be your friend" with Accept → accept and Decline → decline; a friend: no
///              bar; "Account unavailable"; a blocked account: Unblock → unblockContact. Nothing
///              shows before the rows are read.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases above
///  - _entry(): a contact row
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart' show blockedAccountsProvider;
import 'package:snowchat/core/contacts/contact_store.dart';
import 'package:snowchat/features/chat/widgets/contact_status_banner.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';

import '../contacts/fake_contact_notifier.dart';

const _peer = 'snow0123456789abcdef0123456789abcdef';

ContactEntry _entry({
  bool inMyList = false,
  bool addedMe = false,
  int? hiddenAtMs,
  int notFoundCount = 0,
}) =>
    ContactEntry(
      snowId: _peer,
      inMyList: inMyList,
      addedMe: addedMe,
      hiddenAtMs: hiddenAtMs,
      nickname: 'alice',
      nameIssuedAtMs: null,
      accountPub: null,
      notFoundCount: notFoundCount,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

void main() {
  group('contactBannerStateOf', () {
    test('every kind of row', () {
      expect(contactBannerStateOf(entry: null, blocked: false),
          ContactBannerState.notInList);
      expect(contactBannerStateOf(entry: _entry(inMyList: true, addedMe: true), blocked: false),
          ContactBannerState.none);
      expect(contactBannerStateOf(entry: _entry(inMyList: true), blocked: false),
          ContactBannerState.requestSent);
      expect(contactBannerStateOf(entry: _entry(addedMe: true), blocked: false),
          ContactBannerState.requestReceived);
      // A request this user declined: not in the list.
      expect(
          contactBannerStateOf(
              entry: _entry(addedMe: true, hiddenAtMs: 5), blocked: false),
          ContactBannerState.notInList);
      expect(
          contactBannerStateOf(
              entry: _entry(
                  inMyList: true,
                  addedMe: true,
                  notFoundCount: ContactStore.unavailableAfterFailures),
              blocked: false),
          ContactBannerState.unavailable);
      expect(contactBannerStateOf(entry: _entry(inMyList: true, addedMe: true), blocked: true),
          ContactBannerState.blocked);
      expect(contactBannerStateOf(entry: null, blocked: true),
          ContactBannerState.blocked);
    });
  });

  group('ContactStatusBanner', () {
    late FakeContactNotifier contacts;
    late int blockTaps;

    Future<void> show(
      WidgetTester tester, {
      ContactEntry? entry,
      Set<String> blocked = const {},
      Stream<List<ContactEntry>>? rows,
    }) async {
      contacts = FakeContactNotifier(const []);
      blockTaps = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          contactProvider.overrideWith((ref) => contacts),
          contactEntriesProvider.overrideWith(
              (ref) => rows ?? Stream.value([?entry])),
          blockedAccountsProvider.overrideWith((ref) => Stream.value(blocked)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContactStatusBanner(
              peerSnowId: _peer,
              peerName: 'alice',
              onBlock: () => blockTaps++,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('not in the list: Add sends a request, Block runs the chat\'s '
        'block flow', (tester) async {
      await show(tester);
      expect(find.text('Not in your friends'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(contacts.calls, [('request', _peer)]);
      await tester.tap(find.text('Block'));
      await tester.pump();
      expect(blockTaps, 1);
    });

    testWidgets('a declined request reads as not in the list', (tester) async {
      await show(tester, entry: _entry(addedMe: true, hiddenAtMs: 5));
      expect(find.text('Not in your friends'), findsOneWidget);
    });

    testWidgets('a sent request: "Request sent", no action', (tester) async {
      await show(tester, entry: _entry(inMyList: true));
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('a received request: Accept and Decline', (tester) async {
      await show(tester, entry: _entry(addedMe: true));
      expect(find.text('Wants to be your friend'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(contacts.calls, [('accept', _peer), ('decline', _peer)]);
    });

    testWidgets('a friend: no bar', (tester) async {
      await show(tester, entry: _entry(inMyList: true, addedMe: true));
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('an account refused again and again: "Account unavailable"',
        (tester) async {
      await show(tester,
          entry: _entry(
              inMyList: true,
              addedMe: true,
              notFoundCount: ContactStore.unavailableAfterFailures));
      expect(find.textContaining('Account unavailable'), findsOneWidget);
    });

    testWidgets('a blocked account: Unblock', (tester) async {
      await show(tester, blocked: {_peer});
      expect(find.text('You blocked this account'), findsOneWidget);
      await tester.tap(find.text('Unblock'));
      await tester.pump();
      expect(contacts.calls, [('unblockContact', _peer)]);
    });

    testWidgets('nothing before the rows are read (no flash)', (tester) async {
      final rows = StreamController<List<ContactEntry>>();
      addTearDown(rows.close);
      await show(tester, rows: rows.stream);
      expect(find.text('Not in your friends'), findsNothing);
      rows.add(const []);
      await tester.pump();
      await tester.pump();
      expect(find.text('Not in your friends'), findsOneWidget);
    });
  });
}
