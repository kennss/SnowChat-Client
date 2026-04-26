/// @file        image_viewer_screen.dart
/// @description Full-screen image viewer. Pinch-zoom, swipe-to-close, share button, dark background
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-08 enable share/save button in imagePath mode as well)
///
/// @functions
///  - ImageViewerScreen: full-screen image viewer StatefulWidget
///  - _ImageViewerScreenState: manages zoom, drag-to-close, and share
///  - _shareImage(): image sharing (share_plus -> iOS 'Save to Files' / 'Save Image' etc.)

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/constants/colors.dart';
import '../models/message.dart';

class ImageViewerScreen extends StatefulWidget {
  final Message? message;
  final Uint8List? imageBytes;
  final String? imagePath;
  final String? fileName;
  final String heroTag;

  const ImageViewerScreen({
    super.key,
    this.message,
    this.imageBytes,
    this.imagePath,
    this.fileName,
    this.heroTag = 'image_viewer',
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late AnimationController _dragAnimController;
  double _dragOffset = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _dragAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _transformController.dispose();
    _dragAnimController.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100) {
      // Dismiss
      Navigator.of(context).pop();
    } else {
      // Snap back
      setState(() {
        _isDragging = false;
        _dragOffset = 0.0;
      });
    }
  }

  Future<void> _shareImage() async {
    final fileName = widget.message?.metadata?['fileName'] as String? ??
        widget.fileName ??
        'image.jpg';
    final mimeType =
        widget.message?.metadata?['mimeType'] as String? ?? 'image/jpeg';

    // iOS requires sharePositionOrigin for the popover anchor — if omitted,
    // share_plus throws PlatformException("sharePositionOrigin: argument
    // must be set"). Compute a small rect at the top-right of the viewer
    // (where the share button lives). On Android the field is ignored.
    Rect? origin;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final size = box.size;
      origin = Rect.fromLTWH(size.width - 64, 32, 48, 48);
    }

    try {
      // For both path- and bytes-mode we copy the image into a temp file
      // with a clean filename and the right extension. This is critical on
      // iOS: UIActivityViewController inspects the *path's* extension to
      // decide which share targets to expose ("Save Image", "Save to Files",
      // etc.). Our stored attachments live at
      // `snowchat_attachments/{fileId}.{ext}` — the fileId looks like a UUID,
      // not an image name, and the extension comes from the sender's
      // filename which can be missing or wrong, so iOS often refuses to
      // present any image-aware actions and the call throws.
      final tempDir = await getTemporaryDirectory();
      // Sanitize fileName: keep last path segment, replace any illegal chars.
      final cleanName = fileName
          .split('/')
          .last
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final tempPath = '${tempDir.path}/$cleanName';

      if (widget.imagePath != null) {
        // Copy decrypted attachment into a fresh temp path so iOS sees a
        // clean filename + extension.
        await File(widget.imagePath!).copy(tempPath);
      } else if (widget.imageBytes != null) {
        await File(tempPath).writeAsBytes(widget.imageBytes!);
      } else {
        return;
      }

      await Share.shareXFiles(
        [XFile(tempPath, name: cleanName, mimeType: mimeType)],
        sharePositionOrigin: origin,
      );
    } catch (e, st) {
      debugPrint('[ImageViewer] Share failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final opacity = 1.0 - (_dragOffset.abs() / 400).clamp(0.0, 0.6);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(
        children: [
          // Image with gesture handling
          GestureDetector(
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: Center(
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Hero(
                    tag: widget.heroTag,
                    child: _buildViewerImage(),
                  ),
                ),
              ),
            ),
          ),

          // Top bar with close and share
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: AnimatedOpacity(
                opacity: _isDragging ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Row(
                        children: [
                          // Share / Save — needs at least a file path or bytes.
                          // Previously gated only on imageBytes which hid the
                          // button for downloaded attachments (always passed
                          // via imagePath).
                          if (widget.imagePath != null ||
                              widget.imageBytes != null)
                            IconButton(
                              icon: const Icon(
                                Icons.ios_share_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              tooltip: 'Share / Save',
                              onPressed: _shareImage,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // File name at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: AnimatedOpacity(
                opacity: _isDragging ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.message?.metadata?['fileName'] as String? ??
                        widget.fileName ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewerImage() {
    if (widget.imagePath != null) {
      return Image.file(
        File(widget.imagePath!),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    if (widget.imageBytes != null) {
      return Image.memory(
        widget.imageBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 300,
      height: 300,
      color: SnowColors.surfaceVariant,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_rounded,
              size: 64,
              color: SnowColors.textTertiary,
            ),
            SizedBox(height: 8),
            Text(
              'Image preview',
              style: TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
