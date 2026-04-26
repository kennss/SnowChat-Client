/// @file        image_message_bubble.dart
/// @description Image-message bubble widget. Watches download state via attachmentWatchProvider, renders the local file
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-03)
///
/// @functions
///  - ImageMessageBubble: image-message bubble (ConsumerWidget, attachment watch)
///  - resolveAttachmentPath(): handles both relative and absolute paths, copes with app-container changes

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../shared/constants/colors.dart';
import '../../../core/storage/tables/attachments_table.dart';
import '../models/message.dart';
import '../providers/attachment_provider.dart';
import '../screens/image_viewer_screen.dart';

/// Resolve a stored attachment path to an absolute path.
/// Handles both relative paths (snowchat_attachments/...) and legacy
/// absolute paths. Returns null if the file doesn't exist at any location.
Future<String?> resolveAttachmentPath(String storedPath) async {
  // Try as-is first (absolute path or already resolved)
  if (File(storedPath).existsSync()) return storedPath;

  // Try as relative path under app documents directory
  final dir = await getApplicationDocumentsDirectory();
  final resolved = '${dir.path}/$storedPath';
  if (File(resolved).existsSync()) return resolved;

  // Legacy absolute path with stale container UUID —
  // extract the relative portion (snowchat_attachments/...)
  final marker = 'snowchat_attachments/';
  final idx = storedPath.indexOf(marker);
  if (idx >= 0) {
    final relativePart = storedPath.substring(idx);
    final fallback = '${dir.path}/$relativePart';
    if (File(fallback).existsSync()) return fallback;
  }

  return null; // File truly missing — needs re-download
}

class ImageMessageBubble extends ConsumerWidget {
  final Message message;
  final bool isMine;

  const ImageMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileName =
        message.metadata?['fileName'] as String? ?? message.plaintext;
    final attachments = ref.watch(attachmentWatchProvider(message.id));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.65,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: isMine ? SnowColors.primary : SnowColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image area
                  attachments.when(
                    data: (atts) {
                      if (atts.isEmpty) return _buildShimmer();
                      final att = atts.first;
                      if (att.transferState == TransferState.done &&
                          att.localPath != null) {
                        return _ResolvingImage(
                          storedPath: att.localPath!,
                          messageId: message.id,
                          fileName: fileName,
                          isMine: isMine,
                        );
                      }
                      if (att.transferState == TransferState.failed) {
                        return _buildError();
                      }
                      return _buildShimmer();
                    },
                    loading: () => _buildShimmer(),
                    error: (_, __) => _buildError(),
                  ),
                  // File name + time
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      fileName,
                      style: TextStyle(
                        color: isMine
                            ? Colors.white70
                            : SnowColors.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: SnowColors.surface,
      highlightColor: SnowColors.background,
      child: Container(
        width: double.infinity,
        height: 200,
        color: SnowColors.surface,
      ),
    );
  }

  static Widget _buildError() {
    return Container(
      width: double.infinity,
      height: 200,
      color: SnowColors.surface,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_rounded,
                color: SnowColors.textTertiary, size: 40),
            SizedBox(height: 8),
            Text('Failed to load',
                style:
                    TextStyle(color: SnowColors.textTertiary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Async widget that resolves the stored path (relative/absolute/legacy)
/// and displays the image once resolved.
class _ResolvingImage extends StatefulWidget {
  final String storedPath;
  final String messageId;
  final String fileName;
  final bool isMine;

  const _ResolvingImage({
    required this.storedPath,
    required this.messageId,
    required this.fileName,
    required this.isMine,
  });

  @override
  State<_ResolvingImage> createState() => _ResolvingImageState();
}

class _ResolvingImageState extends State<_ResolvingImage> {
  String? _resolvedPath;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final path = await resolveAttachmentPath(widget.storedPath);
    if (!mounted) return;
    setState(() {
      _resolvedPath = path;
      _notFound = path == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) return ImageMessageBubble._buildError();
    if (_resolvedPath == null) return ImageMessageBubble._buildShimmer();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ImageViewerScreen(
              imagePath: _resolvedPath!,
              fileName: widget.fileName,
            ),
          ),
        );
      },
      child: Hero(
        tag: 'image_${widget.messageId}',
        child: Image.file(
          File(_resolvedPath!),
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => ImageMessageBubble._buildError(),
        ),
      ),
    );
  }
}
