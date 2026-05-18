/// @file        pdf_viewer_screen.dart
/// @description In-app PDF viewer (pdfx PdfViewPinch). Used in place of
///              OpenFilex when a received PDF is in a disappearing-mode
///              conversation, so the file never reaches an external system
///              viewer where the recipient could Save / Share it. Same Tier 1
///              pattern as image_viewer_screen: Share button hidden when
///              message.expiresAt != null.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-11
/// @lastUpdated 2026-05-11
///
/// @functions
///  - PdfViewerScreen: full-screen PDF viewer StatefulWidget
///  - _PdfViewerScreenState: manages PdfControllerPinch lifecycle and share

library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../models/message.dart';

class PdfViewerScreen extends StatefulWidget {
  /// The chat message backing this PDF — used to gate Share/Save on
  /// `expiresAt`. May be null for non-chat openings (currently no such
  /// callers, kept optional for symmetry with ImageViewerScreen).
  final Message? message;

  /// Absolute path to the decrypted PDF file on disk.
  final String pdfPath;

  /// Display name shown at the bottom.
  final String fileName;

  const PdfViewerScreen({
    super.key,
    this.message,
    required this.pdfPath,
    required this.fileName,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.pdfPath),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    // Same temp-file pattern as image_viewer_screen so iOS UIActivityViewController
    // exposes PDF-aware share targets ("Save to Files", "Print", etc.) based
    // on extension. Our stored attachments live at snowchat_attachments/{uuid}
    // with no .pdf extension after decryption — iOS would refuse to present
    // PDF actions otherwise.
    final cleanName = widget.fileName
        .split('/')
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/$cleanName'
        '${cleanName.toLowerCase().endsWith('.pdf') ? '' : '.pdf'}';

    Rect? origin;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final size = box.size;
      origin = Rect.fromLTWH(size.width - 64, 32, 48, 48);
    }

    try {
      await File(widget.pdfPath).copy(tempPath);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(tempPath, name: cleanName, mimeType: 'application/pdf')],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PdfViewPinch(
              controller: _controller,
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),
          ),

          // Top bar — close + (conditional) share
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
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
                    // Tier 1 disappearing protection: hide Share when the
                    // backing message has an expiry. Save → permanent copy
                    // would defeat the TTL promise.
                    if (widget.message?.expiresAt == null)
                      IconButton(
                        icon: const Icon(
                          Icons.ios_share_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                        tooltip: 'Share / Save',
                        onPressed: _share,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // File name caption
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.fileName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
