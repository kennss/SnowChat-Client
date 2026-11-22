/// @file        blocked_peer_prompt.dart
/// @description Before this user starts a chat or a call with an account it blocked: say so and
///              offer to unblock, instead of letting the request fail ("Failed to start
///              conversation" — the server refuses a 1:1 when either side blocked the other, and
///              a call to a blocked account rings nowhere useful). The decision is this device's
///              block list (BlockList), so it is right offline too.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - confirmUnblockIfBlocked(): true when the account is not blocked or the user unblocked it

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../shared/constants/colors.dart';
import 'contact_provider.dart';

/// Whether a chat or call with [snowId] may go ahead: true when this user has
/// not blocked it, or when it was blocked and the user chose to unblock it in
/// the dialog (the unblock is on this device at once and sent to the server
/// before this returns — BlockList). False when the user kept the block, or
/// [context] went away.
Future<bool> confirmUnblockIfBlocked({
  required BuildContext context,
  required WidgetRef ref,
  required String snowId,
  String? displayName,
}) async {
  final blockList = ref.read(blockListProvider);
  await blockList.load();
  if (!blockList.blocked.contains(snowId)) return true;
  if (!context.mounted) return false;
  final name = (displayName != null && displayName.isNotEmpty)
      ? displayName
      : (snowId.length > 12 ? snowId.substring(0, 12) : snowId);
  final unblock = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SnowColors.surface,
      title: Text(
        'You blocked $name',
        style: const TextStyle(color: SnowColors.textPrimary),
      ),
      content: const Text(
        'Unblock to send messages and call again. What they sent while '
        'blocked does not come back.',
        style: TextStyle(color: SnowColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: SnowColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text(
            'Unblock',
            style: TextStyle(color: SnowColors.primary),
          ),
        ),
      ],
    ),
  );
  if (unblock != true) return false;
  await ref.read(contactProvider.notifier).unblockContact(snowId);
  return context.mounted;
}
