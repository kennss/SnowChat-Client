/// @file        create_channel_screen.dart
/// @description Create-channel screen — icon upload, name, description, category, join policy.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-04-26 (header English translation; channel avatar image pick + server upload implemented)
///
/// @functions
///  - CreateChannelScreen: channel-creation form
///  - _pickAvatar(): pick channel avatar image from gallery
///  - _uploadAvatar(): upload selected image to server and return fileId

import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../app/providers.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../providers/channel_provider.dart';

class CreateChannelScreen extends ConsumerStatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  ConsumerState<CreateChannelScreen> createState() =>
      _CreateChannelScreenState();
}

class _CreateChannelScreenState extends ConsumerState<CreateChannelScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = 'Other';
  String _joinPolicy = 'OPEN';
  bool _isPublic = true;
  bool _isCreating = false;
  File? _avatarFile;
  String? _uploadedAvatarId;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  bool get _isValid => _nameController.text.trim().length >= 2;

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image != null) {
      setState(() {
        _avatarFile = File(image.path);
        _uploadedAvatarId = null;
      });
    }
  }

  /// Upload the selected avatar to the server, returns fileId.
  Future<String?> _uploadAvatar() async {
    if (_avatarFile == null) return null;
    try {
      final bytes = await _avatarFile!.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.postRaw(
        ApiEndpoints.uploadFile,
        bytes: bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'x-content-hash': hash,
        },
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return data['fileId'] as String?;
    } catch (e) {
      debugPrint('[CreateChannel] Avatar upload failed: $e');
      return null;
    }
  }

  Future<void> _createChannel() async {
    if (!_isValid || _isCreating) return;

    setState(() => _isCreating = true);

    try {
      // Upload avatar if selected
      if (_avatarFile != null && _uploadedAvatarId == null) {
        _uploadedAvatarId = await _uploadAvatar();
      }

      final result = await ref.read(channelActionsProvider).createChannel(
        name: _nameController.text.trim(),
        description: _descController.text.trim().isNotEmpty
            ? _descController.text.trim()
            : null,
        isPublic: _isPublic,
        joinPolicy: _joinPolicy,
        category: _selectedCategory,
        avatarUrl: _uploadedAvatarId,
      );

      if (result == null) throw Exception('Create channel failed');

      ref.invalidate(myChannelsProvider);
      ref.read(conversationListProvider.notifier).refresh();

      if (mounted) {
        context.pop();
        context.go('/contacts'); // Navigate to Channels tab
      }
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create channel: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Create Channel'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SnowSizes.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Channel icon
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: SnowColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: SnowColors.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _avatarFile != null
                      ? Image.file(
                          _avatarFile!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        )
                      : const Icon(Icons.camera_alt_rounded,
                          color: SnowColors.textTertiary, size: 32),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _avatarFile != null ? 'Tap to change' : 'Upload Channel Icon',
                style: const TextStyle(
                    color: SnowColors.textTertiary, fontSize: 12),
              ),
            ),

            const SizedBox(height: SnowSizes.lg),

            // Channel name
            const Text('Channel Name *',
                style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: SnowSizes.sm),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              maxLength: 50,
              decoration: const InputDecoration(hintText: 'Enter channel name'),
            ),

            const SizedBox(height: SnowSizes.md),

            // Description
            const Text('Description',
                style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: SnowSizes.sm),
            TextField(
              controller: _descController,
              maxLines: 3,
              maxLength: 500,
              decoration:
                  const InputDecoration(hintText: 'What is this channel about?'),
            ),

            const SizedBox(height: SnowSizes.md),

            // Category
            const Text('Category *',
                style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: SnowSizes.sm),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              dropdownColor: SnowColors.surface,
              style: const TextStyle(color: SnowColors.textPrimary),
              items: channelCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v ?? 'Other'),
            ),

            const SizedBox(height: SnowSizes.lg),

            // Join Policy
            const Text('Join Policy *',
                style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: SnowSizes.sm),
            _buildPolicyOption(
              'OPEN',
              'Open',
              'Anyone can join instantly',
              Icons.public_rounded,
              SnowColors.primary,
            ),
            _buildPolicyOption(
              'APPROVAL',
              'Approval',
              'Admin approval required',
              Icons.how_to_reg_rounded,
              Colors.amber,
            ),
            _buildPolicyOption(
              'INVITE_ONLY',
              'Invite Only',
              'Only via invite link',
              Icons.lock_rounded,
              SnowColors.textTertiary,
            ),

                  const SizedBox(height: SnowSizes.lg),
                ],
              ),
            ),
          ),

          // Fixed bottom button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(SnowSizes.lg),
              child: ElevatedButton(
                onPressed: _isValid && !_isCreating ? _createChannel : null,
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create Channel'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyOption(
      String value, String title, String subtitle, IconData icon, Color color) {
    final selected = _joinPolicy == value;
    return InkWell(
      onTap: () => setState(() {
        _joinPolicy = value;
        _isPublic = value != 'INVITE_ONLY';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: selected ? color.withAlpha(20) : SnowColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : SnowColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: SnowColors.textPrimary,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.normal)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: SnowColors.textTertiary, fontSize: 12)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}
