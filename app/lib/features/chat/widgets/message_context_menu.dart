/// @file        message_context_menu.dart
/// @description Message context-menu bottom sheet — provides reply, copy text, and delete options
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - showMessageContextMenu(): show the message context-menu bottom sheet
///  - MessageContextMenu: context-menu bottom-sheet widget

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/constants/colors.dart';
import '../models/message.dart';

/// Result of the context menu selection.
enum MessageAction { reply, copy, deleteForMe, deleteForEveryone }

/// Shows a Session-style dark bottom sheet with message actions.
///
/// Returns the selected [MessageAction] or `null` if dismissed.
Future<MessageAction?> showMessageContextMenu(
  BuildContext context, {
  required Message message,
  required bool isMine,
}) {
  return showModalBottomSheet<MessageAction>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => MessageContextMenu(
      message: message,
      isMine: isMine,
      canDeleteForEveryone: isMine,
    ),
  );
}

class MessageContextMenu extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool canDeleteForEveryone;

  const MessageContextMenu({
    super.key,
    required this.message,
    required this.isMine,
    required this.canDeleteForEveryone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SnowColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SnowColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Reply
          _ActionTile(
            icon: Icons.reply_rounded,
            label: 'Reply',
            onTap: () => Navigator.pop(context, MessageAction.reply),
          ),

          // Copy text (only for text messages that are not deleted)
          if (!message.isDeleted && message.type == MessageType.text)
            _ActionTile(
              icon: Icons.copy_rounded,
              label: 'Copy Text',
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.plaintext));
                Navigator.pop(context, MessageAction.copy);
              },
            ),

          const Divider(color: SnowColors.divider, height: 1),

          // Delete for me
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Delete for Me',
            color: SnowColors.error,
            onTap: () => Navigator.pop(context, MessageAction.deleteForMe),
          ),

          // Delete for everyone (own messages only)
          if (canDeleteForEveryone)
            _ActionTile(
              icon: Icons.delete_forever_rounded,
              label: 'Delete for Everyone',
              color: SnowColors.error,
              onTap: () =>
                  Navigator.pop(context, MessageAction.deleteForEveryone),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tileColor = color ?? SnowColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: tileColor, size: 22),
      title: Text(
        label,
        style: TextStyle(color: tileColor, fontSize: 15),
      ),
      onTap: onTap,
      dense: true,
    );
  }
}
