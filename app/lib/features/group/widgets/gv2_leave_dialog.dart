/// @file        gv2_leave_dialog.dart
/// @description The "Leave group" dialog of a group protocol v2 group, shared by the chat screen
///              and the group info screen so both say the same thing: a frozen group is only
///              removed from this device (the server is not told, nothing is taken back); an
///              owner with other members hands the group on; anyone else may also take back
///              their messages.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - askGv2Leave(): show the dialog; returns what was chosen, or null
///  - Gv2LeaveChoice: leave, or leave and take back this account's messages
library;

import 'package:flutter/material.dart';

import '../../../core/storage/tables/gv2_tables.dart';
import '../../../shared/constants/colors.dart';
import '../providers/gv2_group_provider.dart';

/// What the user chose in the leave dialog.
enum Gv2LeaveChoice {
  /// Leave; this account's messages stay with the others.
  leave,

  /// Take back this account's messages for everyone, then leave.
  leaveAndDelete,
}

/// Ask whether to leave [group]. Null when the dialog was dismissed.
Future<Gv2LeaveChoice?> askGv2Leave(
  BuildContext context,
  Gv2GroupView group,
) {
  final frozen = group.row.hold == Gv2Hold.frozen;
  final owner = group.me?.isOwner ?? false;
  final others = group.members.length > 1;
  return showDialog<Gv2LeaveChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: const Text(
        'Leave group',
        style: TextStyle(color: SnowColors.textPrimary),
      ),
      content: Text(
        frozen
            ? 'This group is removed from this device. The server cannot be '
                'trusted with it any more, so it is not told.'
            : owner && others
                ? 'The group is handed to the member who joined first. You '
                    'will leave this group.'
                : 'You can leave the group, or leave and take back all your '
                    'messages for everyone.',
        style: const TextStyle(color: SnowColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: SnowColors.textSecondary),
          ),
        ),
        if (!frozen)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(Gv2LeaveChoice.leaveAndDelete),
            child: const Text(
              'Leave and delete',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(Gv2LeaveChoice.leave),
          child: const Text(
            'Leave',
            style: TextStyle(color: SnowColors.error),
          ),
        ),
      ],
    ),
  );
}
