/// @file        file_message_bubble.dart
/// @description File-message bubble widget. Shows file icon, name, size and provides download/open functionality
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - FileMessageBubble: file-message bubble StatefulWidget
///  - _FileMessageBubbleState: manages download state and file opening
///  - _getFileIcon(): determine file icon based on mimeType
///  - _getFileIconColor(): determine icon color based on mimeType
///  - _downloadAndOpen(): download E2EE-encrypted file, decrypt, save/open
///  - _formatFileSize(): format file size

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../core/storage/tables/attachments_table.dart';
import '../models/message.dart';
import '../providers/attachment_provider.dart';
import 'image_message_bubble.dart' show resolveAttachmentPath;

class FileMessageBubble extends ConsumerStatefulWidget {
  final Message message;
  final bool isMine;

  const FileMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  ConsumerState<FileMessageBubble> createState() => _FileMessageBubbleState();
}

class _FileMessageBubbleState extends ConsumerState<FileMessageBubble> {

  @override
  Widget build(BuildContext context) {
    final metadata = widget.message.metadata;
    final fileName =
        metadata?['fileName'] as String? ?? widget.message.plaintext;
    final mimeType = metadata?['mimeType'] as String? ?? '';
    final fileSize = metadata?['size'] as int?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            widget.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(
              maxWidth: SnowSizes.bubbleMaxWidth,
              minWidth: 200,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: SnowSizes.bubblePaddingH,
              vertical: SnowSizes.bubblePaddingV,
            ),
            decoration: BoxDecoration(
              color:
                  widget.isMine ? SnowColors.bubbleOut : SnowColors.bubbleIn,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(SnowSizes.bubbleRadius),
                topRight: const Radius.circular(SnowSizes.bubbleRadius),
                bottomLeft: Radius.circular(
                    widget.isMine ? SnowSizes.bubbleRadius : 4),
                bottomRight: Radius.circular(
                    widget.isMine ? 4 : SnowSizes.bubbleRadius),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // File icon
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: widget.isMine
                            ? SnowColors.background.withValues(alpha: 0.15)
                            : SnowColors.surfaceLight,
                      ),
                      child: Icon(
                        _getFileIcon(mimeType),
                        size: 24,
                        color: _getFileIconColor(mimeType, widget.isMine),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // File info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.isMine
                                  ? SnowColors.bubbleOutText
                                  : SnowColors.bubbleInText,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            fileSize != null
                                ? _formatFileSize(fileSize)
                                : _getMimeLabel(mimeType),
                            style: TextStyle(
                              color: widget.isMine
                                  ? SnowColors.bubbleOutText
                                      .withValues(alpha: 0.6)
                                  : SnowColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Download button / open (attachment watch)
                    const SizedBox(width: 8),
                    _buildAttachmentButton(),
                  ],
                ),

                const SizedBox(height: 6),

                // Download progress (from attachment watch)
                _buildProgressIndicator(),

                // Time + status
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(widget.message.timestamp),
                      style: TextStyle(
                        color: widget.isMine
                            ? SnowColors.bubbleOutText
                                .withValues(alpha: 0.6)
                            : SnowColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentButton() {
    final attachments = ref.watch(attachmentWatchProvider(widget.message.id));
    return attachments.when(
      data: (atts) {
        if (atts.isEmpty) return _iconButton(Icons.download_rounded);
        final att = atts.first;
        if (att.transferState == TransferState.done && att.localPath != null) {
          return FutureBuilder<String?>(
            future: resolveAttachmentPath(att.localPath!),
            builder: (context, snap) {
              if (snap.data == null) return _iconButton(Icons.download_rounded);
              return GestureDetector(
                onTap: () => OpenFilex.open(snap.data!),
                child: _iconButton(Icons.open_in_new_rounded),
              );
            },
          );
        }
        if (att.transferState == TransferState.started) {
          return SizedBox(
            width: 32, height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.isMine ? SnowColors.bubbleOutText : SnowColors.primary,
              ),
            ),
          );
        }
        if (att.transferState == TransferState.failed) {
          return _iconButton(Icons.refresh_rounded);
        }
        return _iconButton(Icons.download_rounded);
      },
      loading: () => _iconButton(Icons.download_rounded),
      error: (_, __) => _iconButton(Icons.error_outline_rounded),
    );
  }

  Widget _buildProgressIndicator() {
    final attachments = ref.watch(attachmentWatchProvider(widget.message.id));
    return attachments.when(
      data: (atts) {
        if (atts.isNotEmpty && atts.first.transferState == TransferState.started) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                backgroundColor: widget.isMine
                    ? SnowColors.background.withValues(alpha: 0.15)
                    : SnowColors.surfaceLight,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.isMine ? SnowColors.bubbleOutText : SnowColors.primary,
                ),
                minHeight: 2,
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _iconButton(IconData icon) {
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.isMine
            ? SnowColors.background.withValues(alpha: 0.2)
            : SnowColors.primary.withValues(alpha: 0.2),
      ),
      child: Icon(icon, size: 18,
        color: widget.isMine ? SnowColors.bubbleOutText : SnowColors.primary),
    );
  }

  Future<void> _openFile() async {
    debugPrint('[FileMessageBubble] Opening file: ${widget.message.metadata?['fileName']}');
  }

  /// Get the appropriate file icon based on mimeType.
  static IconData _getFileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_rounded;
    if (mimeType.startsWith('video/')) return Icons.videocam_rounded;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack_rounded;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mimeType.contains('word') ||
        mimeType.contains('document') ||
        mimeType.contains('msword')) {
      return Icons.description_rounded;
    }
    if (mimeType.contains('spreadsheet') ||
        mimeType.contains('excel') ||
        mimeType.contains('csv')) {
      return Icons.table_chart_rounded;
    }
    if (mimeType.contains('zip') ||
        mimeType.contains('rar') ||
        mimeType.contains('tar') ||
        mimeType.contains('gzip') ||
        mimeType.contains('compressed')) {
      return Icons.folder_zip_rounded;
    }
    if (mimeType.contains('text/')) return Icons.text_snippet_rounded;
    return Icons.insert_drive_file_rounded;
  }

  /// Get icon color based on file type category.
  static Color _getFileIconColor(String mimeType, bool isMine) {
    if (isMine) return SnowColors.bubbleOutText;

    if (mimeType.startsWith('image/')) return const Color(0xFF4CAF50);
    if (mimeType.startsWith('video/')) return const Color(0xFFE91E63);
    if (mimeType.startsWith('audio/')) return const Color(0xFF9C27B0);
    if (mimeType.contains('pdf')) return const Color(0xFFFF5722);
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return const Color(0xFF2196F3);
    }
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel')) {
      return const Color(0xFF4CAF50);
    }
    if (mimeType.contains('zip') || mimeType.contains('compressed')) {
      return const Color(0xFFFF9800);
    }
    return SnowColors.textSecondary;
  }

  /// Get a human-readable label for the mime type.
  static String _getMimeLabel(String mimeType) {
    if (mimeType.startsWith('image/')) return 'Image';
    if (mimeType.startsWith('video/')) return 'Video';
    if (mimeType.startsWith('audio/')) return 'Audio';
    if (mimeType.contains('pdf')) return 'PDF';
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return 'Document';
    }
    if (mimeType.contains('spreadsheet') || mimeType.contains('excel')) {
      return 'Spreadsheet';
    }
    if (mimeType.contains('zip') || mimeType.contains('compressed')) {
      return 'Archive';
    }
    if (mimeType.isEmpty) return 'File';
    return 'File';
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
