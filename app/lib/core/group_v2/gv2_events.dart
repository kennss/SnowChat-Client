/// @file        gv2_events.dart
/// @description Group protocol v2 — what an entry of the change log means in
///              words a person reads: who created, invited, joined, left,
///              was removed, got a role, renamed or ended the group. The
///              system lines of a v2 group are made on this device from the
///              verified log (design document §9.6) — the server writes
///              none.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20
///
/// @functions
///  - gv2EventText(): the English wording of an event, by its name
///  - gv2DescribeEntry(): the events of one verified entry
///  - Gv2GroupEvent and its kinds
///
/// Notes:
///  - Accounts are named by snowId: the member ciphertexts of the entry are
///    decrypted with the group master key (zkgroup). That works for members
///    who are gone from the state too — a removal names an account whose
///    row no longer exists. A ciphertext that does not decrypt to an
///    account gives a null snowId ("someone").
///  - Only a VERIFIED entry is described: one the state machine applied.
///    Nothing here checks anything.
///  - The new name of a SET_TITLE is read from the entry's title payload
///    (K_state); null when it does not open.
///  - Nothing here logs.
library;

import 'dart:typed_data';

import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import 'gv2_codec.dart';
import 'gv2_keys.dart';
import 'gv2_member_check.dart';
import 'gv2_payloads.dart';

/// Something that happened in a group. [by] is the account that did it
/// (null when its ciphertext does not decrypt to an account).
sealed class Gv2GroupEvent {
  final String? by;
  const Gv2GroupEvent(this.by);

  /// A short machine name ("created", "invited", ...), stable across
  /// builds: stored with the system line so that a screen can word it.
  String get name;

  /// The account the event is about, when it is about another one.
  String? get about => null;
}

final class Gv2Created extends Gv2GroupEvent {
  final String? title;
  const Gv2Created(super.by, this.title);
  @override
  String get name => 'created';
}

final class Gv2Invited extends Gv2GroupEvent {
  final String? who;
  const Gv2Invited(super.by, this.who);
  @override
  String get name => 'invited';
  @override
  String? get about => who;
}

final class Gv2InviteRevoked extends Gv2GroupEvent {
  final String? who;
  const Gv2InviteRevoked(super.by, this.who);
  @override
  String get name => 'invite_revoked';
  @override
  String? get about => who;
}

final class Gv2Joined extends Gv2GroupEvent {
  const Gv2Joined(super.by);
  @override
  String get name => 'joined';
}

final class Gv2DeclinedInvite extends Gv2GroupEvent {
  const Gv2DeclinedInvite(super.by);
  @override
  String get name => 'declined';
}

final class Gv2Removed extends Gv2GroupEvent {
  final String? who;
  const Gv2Removed(super.by, this.who);
  @override
  String get name => 'removed';
  @override
  String? get about => who;
}

final class Gv2LeftGroup extends Gv2GroupEvent {
  const Gv2LeftGroup(super.by);
  @override
  String get name => 'left';
}

final class Gv2RoleChanged extends Gv2GroupEvent {
  final String? who;

  /// gv2RoleMember or gv2RoleAdmin.
  final int role;
  const Gv2RoleChanged(super.by, this.who, this.role);
  @override
  String get name => role == gv2RoleAdmin ? 'made_admin' : 'made_member';
  @override
  String? get about => who;
}

final class Gv2OwnerChanged extends Gv2GroupEvent {
  final String? to;
  const Gv2OwnerChanged(super.by, this.to);
  @override
  String get name => 'owner_changed';
  @override
  String? get about => to;
}

final class Gv2Renamed extends Gv2GroupEvent {
  final String? title;
  const Gv2Renamed(super.by, this.title);
  @override
  String get name => 'renamed';
}

final class Gv2Ended extends Gv2GroupEvent {
  const Gv2Ended(super.by);
  @override
  String get name => 'ended';
}

/// The events of [entry], a verified entry of the group with [masterKey]
/// and [groupId], in the order of its actions.
List<Gv2GroupEvent> gv2DescribeEntry({
  required Uint8List masterKey,
  required Uint8List groupId,
  required Gv2Entry entry,
}) {
  String? account(Uint8List ciphertext) {
    try {
      return gv2SnowIdOfAccountId(
        ZkGroup.decryptMember(masterKey: masterKey, ciphertext: ciphertext),
      );
    } on ZkGroupException {
      return null;
    }
  }

  String? title() {
    if (entry.titlePayload.isEmpty) return null;
    return gv2OpenTitlePayload(
      gv2DeriveStateKey(masterKey, groupId),
      entry.titlePayload,
    )?.name;
  }

  final by = account(entry.actor);
  return [
    for (final action in entry.actions)
      switch (action) {
        Gv2Create() => Gv2Created(by, title()),
        Gv2Invite(:final target) => Gv2Invited(by, account(target)),
        Gv2RevokeInvite(:final target) => Gv2InviteRevoked(by, account(target)),
        Gv2Accept() => Gv2Joined(by),
        Gv2Decline() => Gv2DeclinedInvite(by),
        Gv2Remove(:final target) => Gv2Removed(by, account(target)),
        Gv2Leave() => Gv2LeftGroup(by),
        Gv2SetRole(:final target, :final role) => Gv2RoleChanged(
          by,
          account(target),
          role,
        ),
        Gv2TransferOwner(:final target) => Gv2OwnerChanged(by, account(target)),
        Gv2SetTitle() => Gv2Renamed(by, title()),
        Gv2DeleteGroup() => Gv2Ended(by),
      },
  ];
}

/// The English wording of the event named [event] (Gv2GroupEvent.name),
/// done by [by] to [about] (display names; for a rename or a creation,
/// [title] is the name given). Null for a name this build does not know.
/// One wording for the line stored with the change and for the screen that
/// shows it with the names the user knows the accounts by.
String? gv2EventText({
  required String event,
  required String by,
  required String about,
  String? title,
}) => switch (event) {
  'created' => '$by created the group',
  'invited' => '$by invited $about',
  'invite_revoked' => '$by took back the invite of $about',
  'joined' => '$by joined',
  'declined' => '$by declined the invite',
  'removed' => '$by removed $about',
  'left' => '$by left',
  'made_admin' => '$by made $about an admin',
  'made_member' => '$by made $about a member',
  'owner_changed' => '$by made $about the owner',
  'renamed' =>
    title == null ? '$by renamed the group' : '$by renamed the group to "$title"',
  'ended' => '$by ended the group',
  _ => null,
};
