/// @file        text_file_viewer_screen.dart
/// @description In-app plaintext viewer (TXT / MD). Used in place of
///              OpenFilex when a received text file is in a disappearing-mode
///              conversation, so the content never reaches an external editor
///              where the recipient could Save / Share it. Same Tier 1
///              pattern as image_viewer_screen / pdf_viewer_screen: Share
///              button hidden when message.expiresAt != null.
///
///              For MD we render the source verbatim (monospace selectable
///              text) rather than pulling flutter_markdown — the source is
///              human-readable enough and keeping the dependency surface
///              tight keeps the viewer's threat model auditable.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-11
/// @lastUpdated 2026-05-11
///
/// @functions
///  - TextFileViewerScreen: full-screen plaintext viewer StatefulWidget
///  - _TextFileViewerScreenState: loads file bytes as utf8, manages share

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/constants/colors.dart';
import '../models/message.dart';

class TextFileViewerScreen extends StatefulWidget {
  /// The chat message backing this file — used to gate Share/Save on
  /// `expiresAt`. May be null for non-chat openings.
  final Message? message;

  /// Absolute path to the decrypted text file on disk.
  final String filePath;

  /// Display name shown in the app bar.
  final String fileName;

  /// Optional MIME (`text/plain`, `text/markdown`, …). Drives the share
  /// extension picked for the temp file.
  final String? mimeType;

  const TextFileViewerScreen({
    super.key,
    this.message,
    required this.filePath,
    required this.fileName,
    this.mimeType,
  });

  @override
  State<TextFileViewerScreen> createState() => _TextFileViewerScreenState();
}

class _TextFileViewerScreenState extends State<TextFileViewerScreen> {
  String? _content;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // utf8.decode tolerates BOM-less text well. Files larger than a few MB
      // would be a UX concern but the disappearing whitelist (sender side)
      // bounds practical sizes to short notes.
      final bytes = await File(widget.filePath).readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      setState(() => _content = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _share() async {
    final cleanName = widget.fileName
        .split('/')
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/$cleanName';

    Rect? origin;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      final size = box.size;
      origin = Rect.fromLTWH(size.width - 64, 32, 48, 48);
    }

    try {
      await File(widget.filePath).copy(tempPath);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(tempPath, name: cleanName, mimeType: widget.mimeType)],
        sharePositionOrigin: origin,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        backgroundColor: SnowColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: SnowColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.fileName,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: SnowColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          // Tier 1 disappearing protection: hide Share when the backing
          // message has an expiry. Save → permanent copy would defeat
          // the TTL promise.
          if (widget.message?.expiresAt == null)
            IconButton(
              icon: const Icon(Icons.ios_share_rounded,
                  color: SnowColors.textPrimary),
              tooltip: 'Share / Save',
              onPressed: _share,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Failed to load file: $_error',
            style: const TextStyle(color: SnowColors.error, fontSize: 14),
          ),
        ),
      );
    }
    if (_content == null) {
      return const Center(
        child: CircularProgressIndicator(color: SnowColors.primary),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        _content!,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 14,
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }
}
