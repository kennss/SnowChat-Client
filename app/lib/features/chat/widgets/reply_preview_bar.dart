/// @file        reply_preview_bar.dart
/// @description Reply-preview bar shown above the message input — preview of the reply target message and a close button
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - ReplyPreviewBar: reply-preview bar StatelessWidget

import 'package:flutter/material.dart';
import '../../../shared/constants/colors.dart';
import '../models/message.dart';

class ReplyPreviewBar extends StatelessWidget {
  final Message replyTo;
  final String senderName;
  final VoidCallback onClose;

  const ReplyPreviewBar({
    super.key,
    required this.replyTo,
    required this.senderName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: SnowColors.surfaceVariant,
        border: Border(
          top: BorderSide(color: SnowColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Green left accent bar
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: SnowColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),

          // Reply content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: const TextStyle(
                    color: SnowColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyTo.plaintext,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SnowColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

          // Close button
          GestureDetector(
            onTap: onClose,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: SnowColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
