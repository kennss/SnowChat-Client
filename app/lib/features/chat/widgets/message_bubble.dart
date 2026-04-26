/// @file        message_bubble.dart
/// @description Message bubble widget — renders text/voice/image/file messages in outgoing/incoming style, includes reply-quote, deletion state, link preview
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-12 Phase 10 P0-B: added decryptionFailed state icon)
///
/// @functions
///  - MessageBubble: StatelessWidget rendering chat-message bubbles (delegates voice -> VoiceMessageBubble, image -> ImageMessageBubble, file -> FileMessageBubble)

import 'package:flutter/material.dart';
import '../../../core/network/link_preview_service.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../models/message.dart';
import 'file_message_bubble.dart';
import 'image_message_bubble.dart';
import 'link_preview_widget.dart';
import 'voice_message_bubble.dart';

/// Sender role for incoming bubble color differentiation.
enum SenderRole { none, admin, owner }

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final SenderRole senderRole;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapReply;
  final LinkPreviewService? linkPreviewService;

  /// Auto-translation result (memory only — passed in from outside).
  final String? translatedText;

  /// Whether translation is currently loading.
  final bool isTranslating;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderRole = SenderRole.none,
    this.onLongPress,
    this.onTapReply,
    this.linkPreviewService,
    this.translatedText,
    this.isTranslating = false,
  });

  /// Whether this file message contains an image based on mimeType or fileName extension.
  bool get _isImageFile {
    final mimeType = message.metadata?['mimeType'] as String? ?? '';
    if (mimeType.startsWith('image/')) return true;
    // Fallback: check fileName extension (when server metadata lacks mimeType)
    final fileName = message.metadata?['fileName'] as String? ?? message.plaintext;
    final ext = fileName.split('.').last.toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'svg'}
        .contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    // Delegate to VoiceMessageBubble for voice messages
    if (message.type == MessageType.voice) {
      return GestureDetector(
        onLongPress: onLongPress,
        child: VoiceMessageBubble(message: message, isMine: isMine),
      );
    }

    // Delegate to ImageMessageBubble for image file messages
    if (message.type == MessageType.file && _isImageFile) {
      return GestureDetector(
        onLongPress: onLongPress,
        child: ImageMessageBubble(message: message, isMine: isMine),
      );
    }

    // Delegate to FileMessageBubble for non-image file messages
    if (message.type == MessageType.file) {
      return GestureDetector(
        onLongPress: onLongPress,
        child: FileMessageBubble(message: message, isMine: isMine),
      );
    }

    // Detect URLs for link preview
    final urls = LinkPreviewService.extractUrls(message.plaintext);
    final firstUrl = urls.isNotEmpty ? urls.first : null;

    // Time + status widget (displayed outside bubble, LINE/KakaoTalk style)
    final timeStatus = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (isMine) _buildStatusIcon(),
          const SizedBox(height: 2),
          Text(
            _formatTime(message.timestamp),
            style: const TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Sent: time+status LEFT of bubble
            if (isMine) ...[
              timeStatus,
              const SizedBox(width: 4),
            ],
            // Bubble
            Container(
              constraints: const BoxConstraints(
                maxWidth: SnowSizes.bubbleMaxWidth,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: SnowSizes.bubblePaddingH,
                vertical: SnowSizes.bubblePaddingV,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? SnowColors.bubbleOut
                    : senderRole == SenderRole.owner
                        ? const Color(0xFF1E3A5F) // deep blue
                        : senderRole == SenderRole.admin
                            ? const Color(0xFF1A3A2A) // deep green
                            : SnowColors.bubbleIn,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(SnowSizes.bubbleRadius),
                  topRight: const Radius.circular(SnowSizes.bubbleRadius),
                  bottomLeft: Radius.circular(isMine ? SnowSizes.bubbleRadius : 4),
                  bottomRight:
                      Radius.circular(isMine ? 4 : SnowSizes.bubbleRadius),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reply/quote preview
                  if (message.replyToPreview != null)
                    _buildReplyQuote(context),

                  // Message text (deleted or normal)
                  if (message.isDeleted)
                    Text(
                      'This message was deleted',
                      style: TextStyle(
                        color: isMine
                            ? SnowColors.bubbleOutText.withValues(alpha: 0.6)
                            : SnowColors.textTertiary,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    Text(
                      message.plaintext,
                      style: TextStyle(
                        color: isMine
                            ? SnowColors.bubbleOutText
                            : SnowColors.bubbleInText,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),

                  // Auto-translation result (incoming messages only, memory only)
                  if (!isMine && !message.isDeleted && translatedText != null && translatedText!.isNotEmpty) ...[
                    const Divider(height: 12, thickness: 0.5, color: SnowColors.divider),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.translate, size: 12, color: Color(0xFF00D2FF)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            translatedText!,
                            style: const TextStyle(
                              color: Color(0xFF00D2FF),
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (!isMine && !message.isDeleted && isTranslating) ...[
                    const Divider(height: 12, thickness: 0.5, color: SnowColors.divider),
                    const Row(
                      children: [
                        Icon(Icons.translate, size: 12, color: SnowColors.textTertiary),
                        SizedBox(width: 4),
                        Text('...', style: TextStyle(color: SnowColors.textTertiary, fontSize: 13)),
                      ],
                    ),
                  ],

                  // Link preview (only for non-deleted messages with URLs)
                  if (!message.isDeleted &&
                      firstUrl != null &&
                      linkPreviewService != null)
                    LinkPreviewWidget(
                      url: firstUrl,
                      previewService: linkPreviewService!,
                    ),
                ],
              ),
            ),
            // Received: time RIGHT of bubble
            if (!isMine) ...[
              const SizedBox(width: 4),
              timeStatus,
            ],
          ],
        ),
      ),
    );
  }

  /// Build the quoted/reply preview above the message text.
  Widget _buildReplyQuote(BuildContext context) {
    return GestureDetector(
      onTap: onTapReply,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMine
              ? SnowColors.bubbleOutText.withValues(alpha: 0.08)
              : SnowColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: const Border(
            left: BorderSide(color: SnowColors.primary, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender name of the quoted message
            if (message.replyToSenderId != null)
              Text(
                _shortId(message.replyToSenderId!),
                style: const TextStyle(
                  color: SnowColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            Text(
              message.replyToPreview!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMine
                    ? SnowColors.bubbleOutText.withValues(alpha: 0.7)
                    : SnowColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shorten a SnowChat ID for display in reply quote.
  String _shortId(String snowId) {
    if (snowId.length > 10) {
      return '${snowId.substring(0, 10)}...';
    }
    return snowId;
  }

  Widget _buildStatusIcon() {
    // Outside bubble on dark background — gray for pending, blue for read
    const statusColor = SnowColors.textTertiary;
    switch (message.status) {
      case MessageStatus.sending:
        return const Icon(Icons.schedule_rounded, size: 14, color: statusColor);
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded, size: 14, color: statusColor);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded, size: 14, color: statusColor);
      case MessageStatus.read:
        return const Icon(Icons.done_all_rounded,
            size: 14, color: Color(0xFF53BDEB)); // WhatsApp blue — visible on dark bg
      case MessageStatus.failed:
        return const Icon(Icons.error_outline_rounded,
            size: 14, color: SnowColors.error);
      case MessageStatus.decryptionFailed:
        return const Icon(Icons.lock_outline_rounded,
            size: 14, color: SnowColors.textTertiary);
    }
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
