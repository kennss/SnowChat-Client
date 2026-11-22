/// @file        gv2_group_provider.dart
/// @description What the screens show of group protocol v2 groups: the
///              group, its members and its open invites as this device
///              holds them (the local state — nothing here asks the
///              server), with a name for every account, what this account
///              may do there, and the invites waiting for an answer.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (X1: the invites list leaves out invites from blocked accounts; P5.6: member and invitee views carry their ciphertext; one that names no account can be removed or taken back, and counts as a place taken; P5.6: the group rows are read without the runtime — gv2GroupsOnDeviceProvider; a group shown while groups are not running is notReady, never gone). Earlier 2026-11-21 (text for Gv2GroupFailure.rateLimited). Earlier 2026-11-21 (text for Gv2GroupFailure.full). Earlier 2026-11-20 (where the server's keys differ from the ones this build trusts, and whether a group's title commits to them)
///
/// @functions
///  - gv2GroupsOnDeviceProvider: whether this device's groups can be read
///  - gv2GroupsProvider: every v2 group row, as it changes
///  - gv2InvitesProvider: the invites waiting for this account's answer
///  - gv2GroupViewProvider(groupId): one group for a screen (Gv2GroupView)
///  - Gv2GroupView: the group, its members, its open invites and what this
///    account may do (the permission table of the change log, design §5.3)
///  - Gv2MemberView / Gv2InviteeView / Gv2InviteView: rows of those lists
///  - Gv2Standing: where a group stands for the chat screen (usable, waiting
///    for confirmation, on hold, no longer a member)
///  - gv2ServerKeysDifferProvider: whether the server publishes other group
///    keys than this build trusts
///  - gv2TitleKeysMatchProvider(groupId): whether a group's title commits
///    to the keys this build trusts
///  - gv2DisplayName(): contact name → looked-up nickname → short snowId
///  - gv2FailureText(): why a change could not be made, in words
///
/// Notes:
///  - Names are for display only (design §5.7): a contact's or friend's
///    name first, then the nickname looked up from the server, then a short
///    form of the snowId. Who an account IS was decided by its account key
///    (Gv2MemberCheckState.confirmed), never by a name.
///  - The permissions here only decide which controls a screen offers. The
///    change log's rules are enforced when a change is built
///    (gv2_groups.dart) and again by the server and every member.
///  - A member this device could not confirm is shown as such: it receives
///    nothing from this device and can be given no role.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/group_v2/gv2_codec.dart';
import '../../../core/group_v2/gv2_groups.dart';
import '../../../core/group_v2/gv2_trusted_keys.dart' show gv2GroupsAvailable;
import '../../../core/storage/database.dart';
import '../../../core/storage/tables/gv2_tables.dart';
import '../../channels/providers/channel_provider.dart';
import '../../contacts/contact_provider.dart';

/// A member of a group, for a list.
class Gv2MemberView {
  /// The account, or null when the member's ciphertext does not decrypt to
  /// one (it is then shown as unknown and can only be removed).
  final String? snowId;

  /// Its member ciphertext (lowercase hex): what a removal names — also of
  /// a member whose ciphertext names no account.
  final String ciphertext;

  /// 0 member, 1 admin, 2 owner (gv2_codec.dart).
  final int role;

  /// Whether this device confirmed the account behind the member.
  final bool confirmed;

  /// Whether the member has not been looked at yet (a check is pending),
  /// as opposed to having failed it.
  final bool unchecked;
  final Gv2Reach reach;
  final String name;
  final bool isMe;
  final int joinedRevision;

  const Gv2MemberView({
    required this.snowId,
    required this.ciphertext,
    required this.role,
    required this.confirmed,
    required this.unchecked,
    required this.reach,
    required this.name,
    required this.isMe,
    required this.joinedRevision,
  });

  bool get isOwner => role == gv2RoleOwner;
  bool get isAdmin => role == gv2RoleAdmin;
}

/// An account invited into a group that has not answered yet.
class Gv2InviteeView {
  final String? snowId;

  /// Its ciphertext (lowercase hex): what taking the invite back names.
  final String ciphertext;
  final String name;

  /// Whether this account made the invite (it may then take it back).
  final bool invitedByMe;

  const Gv2InviteeView({
    required this.snowId,
    required this.ciphertext,
    required this.name,
    required this.invitedByMe,
  });
}

/// Where a group stands, for the chat screen.
enum Gv2Standing {
  /// A member; messages go out.
  usable,

  /// This device is still creating the group (the server has not answered).
  creating,

  /// A member, but nobody has confirmed the head of the log yet: what is
  /// written waits (design §5.5).
  awaitingConfirm,

  /// The server signed two different logs: read-only, the way out is to
  /// leave.
  frozen,

  /// The log holds something this build cannot read: the app has to be
  /// updated before anything is sent or shown.
  updateRequired,

  /// A member showed that the server keeps changes back: nothing is sent
  /// until this device has them.
  withheld,

  /// The server publishes other group keys than this build trusts: nothing
  /// it issues or signs under them is taken, so groups wait.
  serverKeysDiffer,

  /// Invited, not answered.
  invited,

  /// Not a member any more: left, removed, or the group ended.
  gone,

  /// Groups are not running on this device yet (no connection to the
  /// server since the app started): the group is there, nothing can be
  /// done in it until they are.
  notReady,
}

/// One group for a screen.
class Gv2GroupView {
  final Gv2GroupRow row;
  final List<Gv2MemberView> members;
  final List<Gv2InviteeView> invitees;

  /// The server publishes other group keys than this build trusts.
  final bool serverKeysDiffer;

  /// Whether the group's title commits to the keys this build trusts; false
  /// when it was created under other ones, null when not known.
  final bool? titleKeysMatch;

  /// Whether groups run on this device now (the runtime is up). Without it
  /// the stored rows are shown, and nothing can be changed or sent.
  final bool ready;

  const Gv2GroupView({
    required this.row,
    required this.members,
    required this.invitees,
    this.serverKeysDiffer = false,
    this.titleKeysMatch,
    this.ready = true,
  });

  String get groupId => row.groupId;
  String? get title => row.title;

  Gv2MemberView? get me {
    for (final m in members) {
      if (m.isMe) return m;
    }
    return null;
  }

  int? get myRole => me?.role;

  Gv2Standing get standing {
    switch (row.membership) {
      case Gv2Membership.creating:
        return Gv2Standing.creating;
      case Gv2Membership.invited:
        return Gv2Standing.invited;
      case Gv2Membership.left:
      case Gv2Membership.removed:
      case Gv2Membership.declined:
      case Gv2Membership.ended:
        return Gv2Standing.gone;
      case Gv2Membership.awaitingConfirm:
      case Gv2Membership.active:
        break;
    }
    if (row.hold == Gv2Hold.frozen) return Gv2Standing.frozen;
    if (!ready) return Gv2Standing.notReady;
    if (serverKeysDiffer) return Gv2Standing.serverKeysDiffer;
    switch (row.hold) {
      case Gv2Hold.frozen:
        return Gv2Standing.frozen;
      case Gv2Hold.updateRequired:
        return Gv2Standing.updateRequired;
      case Gv2Hold.withheld:
        return Gv2Standing.withheld;
      case Gv2Hold.none:
        break;
    }
    return row.membership == Gv2Membership.awaitingConfirm
        ? Gv2Standing.awaitingConfirm
        : Gv2Standing.usable;
  }

  /// Whether this account is in the group (whatever holds it back).
  bool get isMember =>
      row.membership == Gv2Membership.active ||
      row.membership == Gv2Membership.awaitingConfirm;

  /// Whether something written now is taken: sent, or kept until the group
  /// can send. Nothing can be written in a frozen group or one this account
  /// is not in, nor while groups are not running on this device.
  bool get canWrite => ready && isMember && row.hold != Gv2Hold.frozen;

  /// Whether this account may change the group at all: a confirmed member
  /// of a group on no hold, with groups running on this device.
  bool get _mayChange =>
      ready &&
      row.membership == Gv2Membership.active &&
      row.hold == Gv2Hold.none &&
      !serverKeysDiffer;

  bool get _ownerOrAdmin =>
      myRole == gv2RoleOwner || myRole == gv2RoleAdmin;

  bool get canInvite => _mayChange && _ownerOrAdmin;
  bool get canRename => _mayChange && _ownerOrAdmin;
  bool get canEnd => _mayChange && myRole == gv2RoleOwner;

  /// Leaving is possible while a member — also on hold (a frozen group is
  /// only erased from this device) — once groups run on this device.
  bool get canLeave => ready && isMember;

  /// An owner removes anyone, an admin removes members — also one whose
  /// ciphertext names no account (it still takes a place in the group).
  bool canRemove(Gv2MemberView member) {
    if (!_mayChange || member.isMe) return false;
    if (myRole == gv2RoleOwner) return true;
    return myRole == gv2RoleAdmin && member.role == gv2RoleMember;
  }

  /// Only the owner changes roles, and only of accounts this device
  /// confirmed (design §5.6). The owner's own role moves by a transfer.
  bool canSetRole(Gv2MemberView member) =>
      _mayChange &&
      myRole == gv2RoleOwner &&
      !member.isMe &&
      member.snowId != null &&
      (member.confirmed || member.isAdmin);

  bool canMakeOwner(Gv2MemberView member) =>
      _mayChange &&
      myRole == gv2RoleOwner &&
      !member.isMe &&
      member.confirmed;

  /// An owner or admin takes back any invite, a member its own.
  bool canRevoke(Gv2InviteeView invitee) =>
      _mayChange && (_ownerOrAdmin || invitee.invitedByMe);

  /// The places taken in the group: members and open invites, those whose
  /// ciphertext names no account included (gv2GroupSizeLimit).
  int get placesTaken => members.length + invitees.length;
}

/// An invite waiting for this account's answer.
class Gv2InviteView {
  final String groupId;
  final String? title;
  final String? inviterSnowId;
  final String inviterName;

  const Gv2InviteView({
    required this.groupId,
    required this.title,
    required this.inviterSnowId,
    required this.inviterName,
  });
}

/// A short form of a snowId, for an account nothing else is known of.
String gv2ShortSnowId(String snowId) => snowId.length > 12
    ? '${snowId.substring(0, 8)}…${snowId.substring(snowId.length - 4)}'
    : snowId;

/// The name shown for [snowId]: a contact's or friend's name, else
/// [nickname] (looked up from the server), else a short form of the id.
String gv2DisplayName(
  String? snowId, {
  required Map<String, String> known,
  String? nickname,
}) {
  if (snowId == null) return 'Unknown member';
  final mine = known[snowId];
  if (mine != null && mine.isNotEmpty) return mine;
  if (nickname != null && nickname.isNotEmpty) return nickname;
  return gv2ShortSnowId(snowId);
}

/// The names this account gave to accounts, or its friends gave themselves:
/// contacts first, then friends.
final gv2KnownNamesProvider = Provider<Map<String, String>>((ref) {
  final names = <String, String>{};
  final friends = ref.watch(friendListProvider).valueOrNull ?? const [];
  for (final f in friends) {
    final name = f.displayName;
    if (name != null && name.isNotEmpty) names[f.snowchatId] = name;
  }
  for (final c in ref.watch(contactProvider)) {
    final name = c.displayName;
    if (name != null && name.isNotEmpty) names[c.snowChatId] = name;
  }
  return names;
});

/// Whether this device's groups can be read: the build runs group protocol
/// v2 and somebody is signed in. The rows are local — reading them does not
/// wait for the runtime (which needs the server); a screen without the
/// runtime shows the group as it is stored and says groups are not ready.
final gv2GroupsOnDeviceProvider = Provider<bool>((ref) {
  if (!gv2GroupsAvailable) return false;
  final snowId = ref.watch(currentSnowIdProvider);
  return snowId != null && snowId.isNotEmpty;
});

/// Every v2 group row of this account's database, as it changes. Empty
/// while the build runs no v2 groups or nobody is signed in.
final gv2GroupsProvider = StreamProvider<List<Gv2GroupRow>>((ref) {
  if (!ref.watch(gv2GroupsOnDeviceProvider)) {
    return Stream.value(const <Gv2GroupRow>[]);
  }
  return ref.watch(snowDatabaseProvider).gv2Store.watchGroups();
});

/// The invites waiting for this account's answer: those the server's log
/// bore out (the state is loaded — an invite that could not be checked yet
/// has no name to show and is settled first; Gv2GroupActions.resume).
final gv2InvitesProvider = Provider<List<Gv2InviteView>>((ref) {
  final groups = ref.watch(gv2GroupsProvider).valueOrNull ?? const [];
  final known = ref.watch(gv2KnownNamesProvider);
  // X1: not one from an account this user blocked (it may have come before
  // the block) — and none until the list is read.
  final blocked = ref.watch(blockedAccountsProvider).valueOrNull;
  if (blocked == null) return const [];
  return [
    for (final g in groups)
      if (g.membership == Gv2Membership.invited &&
          g.stateLoaded &&
          !blocked.contains(g.invitedBySnowId))
        Gv2InviteView(
          groupId: g.groupId,
          title: g.title,
          inviterSnowId: g.invitedBySnowId,
          inviterName: gv2DisplayName(g.invitedBySnowId, known: known),
        ),
  ];
});

/// The rows a group view is made of, as they change. Null while this device
/// holds no such group.
final _gv2GroupRowsProvider = StreamProvider.autoDispose
    .family<
      ({
        Gv2GroupRow row,
        List<Gv2MemberRow> members,
        List<Gv2PendingRow> pending,
      })?,
      String
    >((ref, groupId) {
      if (!ref.watch(gv2GroupsOnDeviceProvider) || !gv2IsGroupId(groupId)) {
        return Stream.value(null);
      }
      final store = ref.watch(snowDatabaseProvider).gv2Store;
      final out =
          StreamController<
            ({
              Gv2GroupRow row,
              List<Gv2MemberRow> members,
              List<Gv2PendingRow> pending,
            })?
          >();
      // The three tables change in one transaction; any of them changing
      // reads all three again, so a view never mixes two states.
      var reading = false;
      var again = false;
      Future<void> read() async {
        if (reading) {
          again = true;
          return;
        }
        reading = true;
        try {
          do {
            again = false;
            final row = await store.group(groupId);
            final value = row == null
                ? null
                : (
                    row: row,
                    members: await store.memberRows(groupId),
                    pending: await store.pendingInvites(groupId),
                  );
            if (!out.isClosed) out.add(value);
          } while (again);
        } catch (e, st) {
          if (!out.isClosed) out.addError(e, st);
        } finally {
          reading = false;
        }
      }

      final subs = [
        store.watchGroup(groupId).listen((_) => read()),
        store.watchMemberRows(groupId).listen((_) => read()),
        store.watchPendingInvites(groupId).listen((_) => read()),
      ];
      ref.onDispose(() {
        for (final s in subs) {
          unawaited(s.cancel());
        }
        unawaited(out.close());
      });
      return out.stream;
    });

/// One group for a screen; null while this device holds no such group.
/// Whether the server publishes other group keys than this build trusts
/// (Gv2Credentials.serverKeysDiffer), as it changes. False without a
/// runtime.
final gv2ServerKeysDifferProvider = StreamProvider<bool>((ref) async* {
  final runtime = ref.watch(gv2RuntimeProvider);
  if (runtime == null) {
    yield false;
    return;
  }
  yield runtime.credentials.serverKeysDiffer;
  yield* runtime.credentials.serverKeysDifferChanges;
});

/// Whether the title of [groupId] commits to the server keys this build
/// trusts (design §6.1): false when the group was created under other keys,
/// null when that is not known (no runtime, no state, a title that does not
/// open). Looked at again when the group changes (a rename writes the
/// current keys).
final gv2TitleKeysMatchProvider = FutureProvider.autoDispose
    .family<bool?, String>((ref, groupId) async {
      final runtime = ref.watch(gv2RuntimeProvider);
      ref.watch(_gv2GroupRowsProvider(groupId));
      if (runtime == null) return null;
      try {
        return await runtime.sync.titleMatchesServerKeys(groupId);
      } catch (_) {
        return null;
      }
    });

final gv2GroupViewProvider = Provider.autoDispose
    .family<AsyncValue<Gv2GroupView?>, String>((ref, groupId) {
      final rows = ref.watch(_gv2GroupRowsProvider(groupId));
      final known = ref.watch(gv2KnownNamesProvider);
      final keysDiffer =
          ref.watch(gv2ServerKeysDifferProvider).valueOrNull ?? false;
      final ready = ref.watch(gv2RuntimeProvider) != null;
      final titleKeysMatch =
          ref.watch(gv2TitleKeysMatchProvider(groupId)).valueOrNull;
      return rows.whenData((data) {
        if (data == null) return null;
        final mine = data.row.myCiphertext;
        final members = [
          for (final m in data.members)
            Gv2MemberView(
              snowId: m.snowId,
              ciphertext: m.ciphertext,
              role: m.role,
              confirmed: m.checkState == Gv2MemberCheckState.confirmed,
              unchecked: m.checkState == Gv2MemberCheckState.unchecked,
              reach: m.reach,
              name: gv2DisplayName(
                m.snowId,
                known: known,
                nickname: m.nickname,
              ),
              isMe: m.ciphertext == mine,
              joinedRevision: m.joinedRevision,
            ),
        ];
        // Owner, admins, members; within a role, this account first and
        // then by name.
        members.sort((a, b) {
          if (a.role != b.role) return b.role.compareTo(a.role);
          if (a.isMe != b.isMe) return a.isMe ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        final invitees = [
          for (final p in data.pending)
            Gv2InviteeView(
              snowId: p.snowId,
              ciphertext: p.ciphertext,
              name: gv2DisplayName(p.snowId, known: known),
              invitedByMe: p.invitedBy == mine,
            ),
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Gv2GroupView(
          row: data.row,
          members: members,
          invitees: invitees,
          serverKeysDiffer: keysDiffer,
          titleKeysMatch: titleKeysMatch,
          ready: ready,
        );
      });
    });

/// Why a change could not be made, for a snack bar.
String gv2FailureText(Object error) {
  if (error is! Gv2GroupException) return 'Something went wrong. Try again.';
  return switch (error.reason) {
    Gv2GroupFailure.notAllowed => 'You cannot do this in this group right now.',
    Gv2GroupFailure.alreadyThere =>
      'This person is already in the group or invited.',
    Gv2GroupFailure.notThere => 'This person is no longer in the group.',
    Gv2GroupFailure.noSuccessor =>
      'Nobody can take over the group yet. Remove the other members or end '
          'the group instead.',
    Gv2GroupFailure.inviteGone => 'This invite is no longer valid.',
    Gv2GroupFailure.rejected => 'The group does not allow this change.',
    Gv2GroupFailure.full =>
      'A group holds up to $gv2GroupSizeLimit people for now.',
    Gv2GroupFailure.rateLimited =>
      'Too many changes to this group right now. Try again in a minute.',
    Gv2GroupFailure.unavailable =>
      'The server could not be reached. Try again.',
    Gv2GroupFailure.busy => 'The group is changing right now. Try again.',
    Gv2GroupFailure.untrusted =>
      'The server answered with something that could not be verified. '
          'Nothing was changed.',
  };
}
