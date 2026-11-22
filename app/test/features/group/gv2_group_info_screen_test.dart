/// @file        gv2_group_info_screen_test.dart
/// @description Widget tests for Gv2GroupInfoScreen: the controls each role
///              gets (owner: rename, add members, end; member: leave only),
///              the note for each standing (frozen, withheld, update
///              required, server keys not the trusted ones) and for a group
///              created under other server keys, an unconfirmed member's
///              mark, the open invites, a group this account left (remove
///              chat, nothing else), a group not on this device, and the
///              leave dialog of a frozen group (the server is not told).
///              The group comes from gv2GroupViewProvider; no runtime.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (views carry their ciphertext; P5.6: groups that cannot be read, or are not running yet). Earlier 2026-11-20
///
/// @functions
///  - main(): the cases above
///  - _row() / _member() / _view(): a group as the screen gets it
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/group/providers/gv2_group_provider.dart';
import 'package:snowchat/features/group/screens/gv2_group_info_screen.dart';

final String _groupId = 'ab' * 32;


/// A member ciphertext (130 lowercase hex characters) made from [name].
String _ct(String name) => [
  for (final c in name.codeUnits) c.toRadixString(16).padLeft(2, '0'),
].join().padRight(130, '0');

Gv2GroupRow _row({
  Gv2Membership membership = Gv2Membership.active,
  Gv2Hold hold = Gv2Hold.none,
}) => Gv2GroupRow(
  groupId: _groupId,
  masterKey: Uint8List(32),
  myCiphertext: 'a' * 130,
  protocolVersion: 1,
  membership: membership,
  hold: hold,
  revision: 3,
  chain: Uint8List(32),
  stateHash: Uint8List(32),
  stateLoaded: true,
  deleted: false,
  titlePayload: Uint8List(0),
  title: 'Snow',
  resetPending: false,
  lastSyncAtMs: 0,
);

Gv2MemberView _member(
  String name, {
  int role = gv2RoleMember,
  bool me = false,
  bool confirmed = true,
}) => Gv2MemberView(
  snowId: 'snow${name.padRight(32, '0')}',
  ciphertext: _ct(name),
  role: role,
  confirmed: confirmed,
  unchecked: false,
  reach: Gv2Reach.ok,
  name: name,
  isMe: me,
  joinedRevision: 0,
);

Gv2GroupView _view({
  int myRole = gv2RoleMember,
  Gv2Membership membership = Gv2Membership.active,
  Gv2Hold hold = Gv2Hold.none,
  bool serverKeysDiffer = false,
  bool? titleKeysMatch,
}) => Gv2GroupView(
  row: _row(membership: membership, hold: hold),
  members: [
    _member('me', role: myRole, me: true),
    if (myRole != gv2RoleOwner) _member('owner', role: gv2RoleOwner),
    _member('dana'),
    _member('eve', confirmed: false),
  ],
  invitees: [
    Gv2InviteeView(snowId: 'snowinvited', ciphertext: _ct('invited'), name: 'invited', invitedByMe: true),
  ],
  serverKeysDiffer: serverKeysDiffer,
  titleKeysMatch: titleKeysMatch,
);

void main() {
  Future<void> show(
    WidgetTester tester,
    Gv2GroupView? view, {
    bool onDevice = true,
  }) async {
    // Tall enough for the whole list, its actions at the end included.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gv2RuntimeProvider.overrideWithValue(null),
          gv2GroupsOnDeviceProvider.overrideWithValue(onDevice),
          gv2GroupViewProvider.overrideWith(
            (ref, groupId) => AsyncValue.data(view),
          ),
        ],
        child: MaterialApp(home: Gv2GroupInfoScreen(groupId: _groupId)),
      ),
    );
    await tester.pump();
  }

  testWidgets('the owner may rename, add members, leave and end', (
    tester,
  ) async {
    await show(tester, _view(myRole: gv2RoleOwner));
    expect(find.text('Snow'), findsOneWidget);
    expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    expect(find.text('Add Members'), findsOneWidget);
    expect(find.text('Leave group'), findsOneWidget);
    expect(find.text('End group'), findsOneWidget);
  });

  testWidgets('a member may only leave', (tester) async {
    await show(tester, _view());
    expect(find.byIcon(Icons.edit_rounded), findsNothing);
    expect(find.text('Add Members'), findsNothing);
    expect(find.text('End group'), findsNothing);
    expect(find.text('Leave group'), findsOneWidget);
  });

  testWidgets('an unconfirmed member is marked, and the open invites are '
      'listed', (tester) async {
    await show(tester, _view(myRole: gv2RoleOwner));
    expect(find.text('Not verified'), findsOneWidget);
    expect(find.text('invited'), findsOneWidget);
  });

  final notes = <String, Gv2GroupView>{
    'The server showed two different histories': _view(
      myRole: gv2RoleOwner,
      hold: Gv2Hold.frozen,
    ),
    'The server is holding back changes': _view(
      myRole: gv2RoleOwner,
      hold: Gv2Hold.withheld,
    ),
    'Update SnowChat': _view(
      myRole: gv2RoleOwner,
      hold: Gv2Hold.updateRequired,
    ),
    'The server is not using the keys this app trusts': _view(
      myRole: gv2RoleOwner,
      serverKeysDiffer: true,
    ),
    'created under other server keys': _view(
      myRole: gv2RoleOwner,
      titleKeysMatch: false,
    ),
  };
  for (final MapEntry(key: words, value: view) in notes.entries) {
    testWidgets('a note says "$words"; nothing but leaving is offered while '
        'the group is held', (tester) async {
      await show(tester, view);
      expect(find.textContaining(words), findsOneWidget);
      final held = view.standing != Gv2Standing.usable;
      expect(find.text('Add Members'), held ? findsNothing : findsOneWidget);
      expect(find.text('End group'), held ? findsNothing : findsOneWidget);
      expect(find.text('Leave group'), findsOneWidget);
    });
  }

  testWidgets('a usable group carries no note', (tester) async {
    await show(tester, _view(myRole: gv2RoleOwner, titleKeysMatch: true));
    for (final words in notes.keys) {
      expect(find.textContaining(words), findsNothing);
    }
  });

  testWidgets('a group this account was removed from offers only removing '
      'the chat', (tester) async {
    await show(tester, _view(membership: Gv2Membership.removed));
    expect(find.text('You are no longer in this group.'), findsOneWidget);
    expect(find.text('Remove chat'), findsOneWidget);
    expect(find.text('Leave group'), findsNothing);
    expect(find.textContaining('Members ('), findsNothing);
  });

  testWidgets('a group not on this device says so', (tester) async {
    await show(tester, null);
    expect(find.text('This group is not on this device.'), findsOneWidget);
  });

  testWidgets('where the groups cannot be read yet, no group is said to be '
      'missing', (tester) async {
    await show(tester, null, onDevice: false);
    expect(find.text('This group is not on this device.'), findsNothing);
    expect(
      find.text('Groups are not running on this device yet.'),
      findsOneWidget,
    );
  });

  testWidgets('a group shown while groups are not running: says so, offers '
      'no change and no removing of the chat', (tester) async {
    final v = _view(myRole: gv2RoleOwner);
    await show(
      tester,
      Gv2GroupView(
        row: v.row,
        members: v.members,
        invitees: v.invitees,
        ready: false,
      ),
    );
    expect(find.textContaining('Groups are not running on this device yet'),
        findsOneWidget);
    for (final action in [
      'Add Members',
      'Leave group',
      'End group',
      'Remove chat',
    ]) {
      expect(find.text(action), findsNothing, reason: action);
    }
    expect(find.textContaining('Members ('), findsOneWidget);
  });

  testWidgets('leaving a frozen group: the server is not told, and there is '
      'no taking messages back', (tester) async {
    await show(tester, _view(myRole: gv2RoleOwner, hold: Gv2Hold.frozen));
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    expect(find.textContaining('it is not told'), findsOneWidget);
    expect(find.textContaining('take back'), findsNothing);
  });

  testWidgets('leaving a usable group offers taking this account\'s messages '
      'back', (tester) async {
    await show(tester, _view());
    await tester.tap(find.text('Leave group'));
    await tester.pumpAndSettle();
    expect(find.textContaining('take back all'), findsOneWidget);
  });
}
