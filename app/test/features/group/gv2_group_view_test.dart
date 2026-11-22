/// @file        gv2_group_view_test.dart
/// @description Tests for what the screens show of a group protocol v2
///              group (gv2_group_provider.dart): where the group stands for
///              the chat, which controls a member of each role gets (the
///              permission table of the change log, design §5.3), the name
///              shown for an account, and the words for a failed change.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (views carry their ciphertext; P5.6: notReady while groups are not running). Earlier 2026-11-20 (server keys other than the build's pause a group)
///
/// @functions
///  - main(): the test groups
///  - _row() / _member() / _view(): a group as a screen gets it
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_events.dart';
import 'package:snowchat/core/group_v2/gv2_groups.dart';
import 'package:snowchat/core/storage/database.dart';
import 'package:snowchat/core/storage/tables/gv2_tables.dart';
import 'package:snowchat/features/group/providers/gv2_group_provider.dart';


/// A member ciphertext (130 lowercase hex characters) made from [name].
String _ct(String name) => [
  for (final c in name.codeUnits) c.toRadixString(16).padLeft(2, '0'),
].join().padRight(130, '0');

const _groupId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

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
  bool known = true,
}) => Gv2MemberView(
  snowId: known ? 'snow${name.padRight(32, '0')}' : null,
  ciphertext: _ct(name),
  role: role,
  confirmed: confirmed,
  unchecked: false,
  reach: Gv2Reach.ok,
  name: name,
  isMe: me,
  joinedRevision: 0,
);

/// A group in which this account has [myRole], with one member of every
/// role beside it.
Gv2GroupView _view({
  int myRole = gv2RoleMember,
  Gv2Membership membership = Gv2Membership.active,
  Gv2Hold hold = Gv2Hold.none,
  bool serverKeysDiffer = false,
  bool ready = true,
}) => Gv2GroupView(
  row: _row(membership: membership, hold: hold),
  serverKeysDiffer: serverKeysDiffer,
  ready: ready,
  members: [
    _member('me', role: myRole, me: true),
    _member('owner', role: gv2RoleOwner),
    _member('admin', role: gv2RoleAdmin),
    _member('member'),
    _member('unconfirmed', confirmed: false),
    _member('unconfirmedadmin', role: gv2RoleAdmin, confirmed: false),
    _member('unreadable', known: false, confirmed: false),
  ],
  invitees: [
    Gv2InviteeView(snowId: 'snowmine', ciphertext: _ct('mine'), name: 'mine', invitedByMe: true),
    Gv2InviteeView(snowId: 'snowtheirs', ciphertext: _ct('theirs'), name: 'theirs', invitedByMe: false),
    Gv2InviteeView(snowId: null, ciphertext: _ct('unreadable'), name: 'unreadable', invitedByMe: true),
  ],
);

Gv2MemberView _of(Gv2GroupView view, String name) =>
    view.members.firstWhere((m) => m.name == name);

void main() {
  group('standing', () {
    test('follows the membership, then the hold', () {
      Gv2Standing of(Gv2Membership m, [Gv2Hold h = Gv2Hold.none]) =>
          _view(membership: m, hold: h).standing;
      expect(of(Gv2Membership.active), Gv2Standing.usable);
      expect(of(Gv2Membership.awaitingConfirm), Gv2Standing.awaitingConfirm);
      expect(of(Gv2Membership.creating), Gv2Standing.creating);
      expect(of(Gv2Membership.invited), Gv2Standing.invited);
      for (final gone in [
        Gv2Membership.left,
        Gv2Membership.removed,
        Gv2Membership.declined,
        Gv2Membership.ended,
      ]) {
        expect(of(gone), Gv2Standing.gone);
        // No longer a member: a hold says nothing more.
        expect(of(gone, Gv2Hold.frozen), Gv2Standing.gone);
      }
      for (final member in [Gv2Membership.active, Gv2Membership.awaitingConfirm]) {
        expect(of(member, Gv2Hold.frozen), Gv2Standing.frozen);
        expect(of(member, Gv2Hold.updateRequired), Gv2Standing.updateRequired);
        expect(of(member, Gv2Hold.withheld), Gv2Standing.withheld);
      }
    });

    test('server keys other than the ones this build trusts pause every '
        'group a member is in; only a freeze says more', () {
      Gv2Standing of(Gv2Membership m, [Gv2Hold h = Gv2Hold.none]) =>
          _view(membership: m, hold: h, serverKeysDiffer: true).standing;
      for (final member in [Gv2Membership.active, Gv2Membership.awaitingConfirm]) {
        expect(of(member), Gv2Standing.serverKeysDiffer);
        expect(of(member, Gv2Hold.withheld), Gv2Standing.serverKeysDiffer);
        expect(of(member, Gv2Hold.updateRequired), Gv2Standing.serverKeysDiffer);
        expect(of(member, Gv2Hold.frozen), Gv2Standing.frozen);
      }
      expect(of(Gv2Membership.removed), Gv2Standing.gone);
      expect(of(Gv2Membership.invited), Gv2Standing.invited);
      // What is written waits for the server to be fixed.
      expect(_view(serverKeysDiffer: true).canWrite, isTrue);
    });

    test('while groups are not running on this device, a member\'s group '
        'is notReady — never gone — and nothing can be written or changed; '
        'what the stored row says of membership and a freeze still holds', () {
      Gv2GroupView of(Gv2Membership m, [Gv2Hold h = Gv2Hold.none]) =>
          _view(membership: m, hold: h, ready: false, myRole: gv2RoleOwner);
      for (final member in [Gv2Membership.active, Gv2Membership.awaitingConfirm]) {
        final v = of(member);
        expect(v.standing, Gv2Standing.notReady);
        expect(of(member, Gv2Hold.withheld).standing, Gv2Standing.notReady);
        expect(of(member, Gv2Hold.frozen).standing, Gv2Standing.frozen);
        expect(v.canWrite, isFalse);
        expect(v.canLeave, isFalse);
        expect(v.canInvite || v.canRename || v.canEnd, isFalse);
        expect(v.members.any(v.canRemove), isFalse);
      }
      expect(of(Gv2Membership.removed).standing, Gv2Standing.gone);
      expect(of(Gv2Membership.invited).standing, Gv2Standing.invited);
    });

    test('something can be written while a member of a group that is not '
        'frozen — also while it cannot be sent yet', () {
      expect(_view().canWrite, isTrue);
      expect(_view(membership: Gv2Membership.awaitingConfirm).canWrite, isTrue);
      expect(_view(hold: Gv2Hold.withheld).canWrite, isTrue);
      expect(_view(hold: Gv2Hold.updateRequired).canWrite, isTrue);
      expect(_view(hold: Gv2Hold.frozen).canWrite, isFalse);
      expect(_view(membership: Gv2Membership.removed).canWrite, isFalse);
      expect(_view(membership: Gv2Membership.invited).canWrite, isFalse);
    });
  });

  group('what each role may do', () {
    test('a member: nothing but leave, and take back its own invite', () {
      final v = _view();
      expect(v.canInvite, isFalse);
      expect(v.canRename, isFalse);
      expect(v.canEnd, isFalse);
      expect(v.canLeave, isTrue);
      for (final m in v.members) {
        expect(v.canRemove(m), isFalse, reason: m.name);
        expect(v.canSetRole(m), isFalse, reason: m.name);
        expect(v.canMakeOwner(m), isFalse, reason: m.name);
      }
      expect(v.canRevoke(v.invitees[0]), isTrue);
      expect(v.canRevoke(v.invitees[1]), isFalse);
    });

    test('an admin: invites, renames, removes members only, takes back any '
        'invite — no roles, no end', () {
      final v = _view(myRole: gv2RoleAdmin);
      expect(v.canInvite, isTrue);
      expect(v.canRename, isTrue);
      expect(v.canEnd, isFalse);
      expect(v.canRemove(_of(v, 'member')), isTrue);
      expect(v.canRemove(_of(v, 'unconfirmed')), isTrue);
      expect(v.canRemove(_of(v, 'admin')), isFalse);
      expect(v.canRemove(_of(v, 'owner')), isFalse);
      expect(v.canRemove(_of(v, 'me')), isFalse);
      for (final m in v.members) {
        expect(v.canSetRole(m), isFalse, reason: m.name);
        expect(v.canMakeOwner(m), isFalse, reason: m.name);
      }
      expect(v.canRevoke(v.invitees[0]), isTrue);
      expect(v.canRevoke(v.invitees[1]), isTrue);
    });

    test('the owner: everything — roles and the group itself only to '
        'accounts this device confirmed', () {
      final v = _view(myRole: gv2RoleOwner);
      expect(v.canInvite, isTrue);
      expect(v.canRename, isTrue);
      expect(v.canEnd, isTrue);
      for (final name in ['admin', 'member', 'unconfirmed', 'unconfirmedadmin']) {
        expect(v.canRemove(_of(v, name)), isTrue, reason: name);
      }
      expect(v.canRemove(_of(v, 'me')), isFalse);
      expect(v.canSetRole(_of(v, 'member')), isTrue);
      expect(v.canSetRole(_of(v, 'admin')), isTrue);
      // An unconfirmed member gets no role; an unconfirmed admin can still
      // be made a member again.
      expect(v.canSetRole(_of(v, 'unconfirmed')), isFalse);
      expect(v.canSetRole(_of(v, 'unconfirmedadmin')), isTrue);
      expect(v.canSetRole(_of(v, 'me')), isFalse);
      expect(v.canMakeOwner(_of(v, 'member')), isTrue);
      expect(v.canMakeOwner(_of(v, 'admin')), isTrue);
      expect(v.canMakeOwner(_of(v, 'unconfirmed')), isFalse);
      expect(v.canMakeOwner(_of(v, 'unconfirmedadmin')), isFalse);
      expect(v.canMakeOwner(_of(v, 'me')), isFalse);
    });

    test('a member whose ciphertext names no account, or an invite that '
        'names none, can only be taken out — and takes a place', () {
      final v = _view(myRole: gv2RoleOwner);
      final unreadable = _of(v, 'unreadable');
      expect(v.canRemove(unreadable), isTrue);
      expect(v.canSetRole(unreadable), isFalse);
      expect(v.canMakeOwner(unreadable), isFalse);
      expect(v.canRevoke(v.invitees[2]), isTrue);
      expect(v.placesTaken, v.members.length + v.invitees.length);
      // An admin removes only plain members (this one is one).
      final admin = _view(myRole: gv2RoleAdmin);
      expect(admin.canRemove(_of(admin, 'unreadable')), isTrue);
    });

    test('nothing changes a group this account is not confirmed in, or that '
        'is on hold — leaving stays possible', () {
      for (final v in [
        _view(myRole: gv2RoleOwner, membership: Gv2Membership.awaitingConfirm),
        _view(myRole: gv2RoleOwner, hold: Gv2Hold.withheld),
        _view(myRole: gv2RoleOwner, hold: Gv2Hold.updateRequired),
        _view(myRole: gv2RoleOwner, hold: Gv2Hold.frozen),
        _view(myRole: gv2RoleOwner, serverKeysDiffer: true),
      ]) {
        expect(v.canInvite, isFalse);
        expect(v.canRename, isFalse);
        expect(v.canEnd, isFalse);
        expect(v.canRemove(_of(v, 'member')), isFalse);
        expect(v.canSetRole(_of(v, 'member')), isFalse);
        expect(v.canMakeOwner(_of(v, 'member')), isFalse);
        expect(v.canRevoke(v.invitees[0]), isFalse);
        expect(v.canLeave, isTrue);
      }
      final gone = _view(myRole: gv2RoleOwner, membership: Gv2Membership.removed);
      expect(gone.canLeave, isFalse);
      expect(gone.canEnd, isFalse);
    });
  });

  group('names', () {
    test('a contact\'s name comes before the looked-up nickname, and that '
        'before the id', () {
      const id = 'snow0123456789abcdef0123456789abcdef';
      expect(
        gv2DisplayName(id, known: {id: 'Mum'}, nickname: 'mum_1970'),
        'Mum',
      );
      expect(gv2DisplayName(id, known: const {}, nickname: 'mum_1970'), 'mum_1970');
      expect(gv2DisplayName(id, known: {id: ''}, nickname: ''), 'snow0123…cdef');
      expect(gv2DisplayName(null, known: const {}), 'Unknown member');
    });

    test('an event is worded once, for the stored line and for the screen', () {
      String? text(String event, {String? title}) => gv2EventText(
        event: event,
        by: 'You',
        about: 'Bob',
        title: title,
      );
      expect(text('created'), 'You created the group');
      expect(text('invited'), 'You invited Bob');
      expect(text('invite_revoked'), 'You took back the invite of Bob');
      expect(text('joined'), 'You joined');
      expect(text('declined'), 'You declined the invite');
      expect(text('removed'), 'You removed Bob');
      expect(text('left'), 'You left');
      expect(text('made_admin'), 'You made Bob an admin');
      expect(text('made_member'), 'You made Bob a member');
      expect(text('owner_changed'), 'You made Bob the owner');
      expect(text('renamed'), 'You renamed the group');
      expect(text('renamed', title: 'Ski'), 'You renamed the group to "Ski"');
      expect(text('ended'), 'You ended the group');
      // A newer build's event: the screen falls back to the stored line.
      expect(text('something_new'), isNull);
    });
  });

  test('a group id of v2 is 64 lowercase hex characters, nothing else', () {
    expect(gv2IsGroupId(_groupId), isTrue);
    expect(gv2IsGroupId(_groupId.toUpperCase()), isFalse);
    expect(gv2IsGroupId(_groupId.substring(1)), isFalse);
    expect(gv2IsGroupId('${_groupId}0'), isFalse);
    expect(gv2IsGroupId('cmhz0a1b20000abcdefghijkl'), isFalse); // a v1 cuid
    expect(gv2IsGroupId('snow0123456789abcdef0123456789abcdef'), isFalse);
    expect(gv2IsGroupId(null), isFalse);
    expect(gv2IsGroupId(42), isFalse);
  });

  test('every reason a change can fail has its own words', () {
    final texts = {
      for (final reason in Gv2GroupFailure.values)
        gv2FailureText(Gv2GroupException(reason)),
    };
    expect(texts, hasLength(Gv2GroupFailure.values.length));
    expect(texts.every((t) => t.isNotEmpty), isTrue);
    expect(gv2FailureText(StateError('x')), isNotEmpty);
  });
}
