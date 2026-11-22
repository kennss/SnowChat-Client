/// @file        gv2_invite_tile.dart
/// @description One invite into a group protocol v2 group that waits for
///              this account's answer, in the Chats list: the group's name,
///              who invited, and Accept / Decline. An invite from a friend
///              whose identity this device confirmed never gets here — it
///              is accepted on its own (design §9.2).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20
///
/// @functions
///  - Gv2InviteTile: the tile
///  - _answer(): accept or decline, showing progress and why it failed
///
/// Notes:
///  - Accepting makes this account a member by the group's change log; the
///    group then appears among the chats. Until a member has confirmed this
///    device, what is written there waits (design §5.5).
///  - The buttons sit in a Wrap, not a Row: a Row of buttons inside the
///    list's scroll view stalled the body's paint before.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/group_v2/gv2_groups.dart';
import '../../../core/storage/tables/gv2_tables.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../providers/gv2_group_provider.dart';

class Gv2InviteTile extends ConsumerStatefulWidget {
  final Gv2InviteView invite;

  /// Called after the invite was accepted (the group is among the chats).
  final void Function(String groupId)? onAccepted;

  const Gv2InviteTile({super.key, required this.invite, this.onAccepted});

  @override
  ConsumerState<Gv2InviteTile> createState() => _Gv2InviteTileState();
}

class _Gv2InviteTileState extends ConsumerState<Gv2InviteTile> {
  bool _busy = false;

  Future<void> _answer({required bool accept}) async {
    final groups = ref.read(gv2RuntimeProvider)?.groups;
    if (groups == null || _busy) return;
    // Read now: this tile leaves the list the moment the answer is stored,
    // and a disposed widget's ref cannot be used.
    final store = ref.read(snowDatabaseProvider).gv2Store;
    final messenger = ScaffoldMessenger.of(context);
    final onAccepted = widget.onAccepted;
    setState(() => _busy = true);
    final groupId = widget.invite.groupId;
    Object? failure;
    try {
      if (accept) {
        await groups.accept(groupId);
      } else {
        await groups.decline(groupId);
      }
    } catch (e) {
      failure = e;
      // The kind of failure only: no group, no account.
      debugPrint('[Gv2Invite] answer failed: ${e.runtimeType} '
          '${e is Gv2GroupException ? e.reason.name : ''}');
    }
    // What counts is where the group stands now: an ACCEPT the server took
    // made this account a member, whatever a later step ran into.
    var joined = false;
    if (accept) {
      try {
        final row = await store.group(groupId);
        joined = row != null &&
            (row.membership == Gv2Membership.awaitingConfirm ||
                row.membership == Gv2Membership.active);
      } catch (_) {
        // This device failed to read its own row: go by the answer.
      }
    }
    if (joined) {
      onAccepted?.call(groupId);
    } else if (failure != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(gv2FailureText(failure)),
          backgroundColor: SnowColors.error,
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final name = (invite.title == null || invite.title!.isEmpty)
        ? 'Group'
        : invite.title!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SnowSizes.md,
        vertical: SnowSizes.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SnowAvatar(
                snowId: invite.groupId,
                size: SnowSizes.avatarMd,
                displayName: name,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Invited by ${invite.inviterName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SnowColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 10, left: 52),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SnowColors.primary,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () => _answer(accept: true),
                    child: const Text(
                      'Accept',
                      style: TextStyle(color: SnowColors.primary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _answer(accept: false),
                    child: const Text(
                      'Decline',
                      style: TextStyle(color: SnowColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
