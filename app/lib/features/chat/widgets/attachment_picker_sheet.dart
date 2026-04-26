/// @file        attachment_picker_sheet.dart
/// @description Attachment picker bottom sheet — gallery (multi), camera, file pick, add friend, Send Asset (Wallet V2 Phase F)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-02
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-20 Wallet V2 Phase F: added Send Asset option — 1:1 only)
///
/// @functions
///  - AttachmentPickerSheet: bottom-sheet widget showing attachment-pick options (+ add friend + Send Asset)

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/constants/colors.dart';

/// Bottom sheet for selecting attachments (WhatsApp-style).
/// Supports: Gallery (multi-select), Camera, File picker, Add Friend, Send Asset.
class AttachmentPickerSheet extends StatelessWidget {
  /// Called with list of image file paths (1~10).
  final void Function(List<String> paths) onImagesSelected;

  /// Called with file path, name, and MIME type.
  final void Function(String path, String name, String? mimeType)
      onFileSelected;

  /// Called when user taps "Add Friend". Null = hide option.
  final VoidCallback? onAddFriend;

  /// Called when user taps "Send Asset". Null = hide option (group/channel).
  /// Wallet V2 Phase 1 — shown only in 1:1 rooms (group/channel is a V1 limit).
  final VoidCallback? onSendAsset;

  const AttachmentPickerSheet({
    super.key,
    required this.onImagesSelected,
    required this.onFileSelected,
    this.onAddFriend,
    this.onSendAsset,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: SnowColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildOption(
              context,
              icon: Icons.photo_library_rounded,
              color: SnowColors.primary,
              label: 'Photos & Videos',
              onTap: () => _pickImages(context),
            ),
            _buildOption(
              context,
              icon: Icons.camera_alt_rounded,
              color: Colors.orange,
              label: 'Camera',
              onTap: () => _takePhoto(context),
            ),
            _buildOption(
              context,
              icon: Icons.insert_drive_file_rounded,
              color: Colors.blue,
              label: 'File',
              onTap: () => _pickFile(context),
            ),
            if (onAddFriend != null)
              _buildOption(
                context,
                icon: Icons.person_add_rounded,
                color: SnowColors.primary,
                label: 'Add Friend',
                onTap: () {
                  Navigator.pop(context);
                  onAddFriend!();
                },
              ),
            if (onSendAsset != null)
              _buildOption(
                context,
                icon: Icons.account_balance_wallet_rounded,
                color: SnowColors.primary,
                label: 'Send Asset',
                onTap: () {
                  Navigator.pop(context);
                  onSendAsset!();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }

  Future<void> _pickImages(BuildContext context) async {
    Navigator.pop(context);
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (images.isNotEmpty) {
      final paths = images.take(10).map((f) => f.path).toList();
      onImagesSelected(paths);
    }
  }

  Future<void> _takePhoto(BuildContext context) async {
    Navigator.pop(context);
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (photo != null) {
      onImagesSelected([photo.path]);
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        onFileSelected(
          file.path!,
          file.name,
          _guessMimeType(file.name),
        );
      }
    }
  }

  String? _guessMimeType(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
