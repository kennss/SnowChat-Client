/// @file        conversation_tile.dart
/// @description Conversation-list item widget — avatar, conversation name, last message, time, unread-message badge
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (a 1:1 row's name comes from resolvePeerName — the friend list, the
///              chat's name, a name certificate, the short snowId; never the server). Earlier
///              2026-11-22 (no presence: the online dot and "last seen" are gone — the server keeps
///              and sends no presence). Earlier 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - ConversationTile: ConsumerWidget rendering an individual conversation-list tile

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../models/conversation.dart';
import '../utils/sender_name_resolver.dart';

class ConversationTile extends ConsumerWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentSnowIdProvider) ?? '';
    final otherSnowId = conversation.otherParticipant(myId) ?? conversation.id;
    final title = conversation.type == ConversationType.direct
        ? resolvePeerName(ref, otherSnowId, conversationTitle: conversation.title)
        : conversation.displayName(myId);
    final hasUnread = conversation.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SnowSizes.md,
          vertical: 12,
        ),
        child: Row(
          children: [
            // Avatar (a group carries its mark)
            Stack(
              children: [
                SnowAvatar(
                  snowId: otherSnowId,
                  size: SnowSizes.avatarMd,
                  displayName: title,
                ),
                if (conversation.type == ConversationType.group)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: SnowColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SnowColors.background,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.group_rounded,
                        size: 10,
                        color: SnowColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + time
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: SnowColors.textPrimary,
                            fontSize: 15,
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.lastMessageTime != null)
                        Text(
                          _formatTime(conversation.lastMessageTime!),
                          style: TextStyle(
                            color: hasUnread
                                ? SnowColors.primary
                                : SnowColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Last message + unread badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessageText ?? 'No messages yet',
                          style: TextStyle(
                            color: hasUnread
                                ? SnowColors.textSecondary
                                : SnowColors.textTertiary,
                            fontSize: 14,
                            fontWeight:
                                hasUnread ? FontWeight.w500 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: SnowColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            conversation.unreadCount > 99
                                ? '99+'
                                : '${conversation.unreadCount}',
                            style: const TextStyle(
                              color: SnowColors.background,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final h = time.hour.toString().padLeft(2, '0');
      final m = time.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${time.month}/${time.day}';
  }
}
