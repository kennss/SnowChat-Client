/// @file        invite_link_screen.dart
/// @description Invite-link management screen — link creation, QR code, code copy, share, expiry/usage settings.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - InviteLinkScreen: invite-link create/manage screen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../providers/channel_provider.dart';

class InviteLinkScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String channelName;

  const InviteLinkScreen({
    super.key,
    required this.groupId,
    required this.channelName,
  });

  @override
  ConsumerState<InviteLinkScreen> createState() => _InviteLinkScreenState();
}

class _InviteLinkScreenState extends ConsumerState<InviteLinkScreen> {
  Map<String, dynamic>? _inviteData;
  bool _isLoading = false;
  int _expiresInHours = 168; // 7 days default
  int? _maxUses;

  @override
  void initState() {
    super.initState();
    _generateLink();
  }

  Future<void> _generateLink() async {
    setState(() => _isLoading = true);
    final result = await ref.read(channelActionsProvider).createInviteLink(
          widget.groupId,
          expiresInHours: _expiresInHours,
          maxUses: _maxUses,
        );
    setState(() {
      _inviteData = result;
      _isLoading = false;
    });
  }

  Future<void> _deactivate() async {
    await ref.read(channelActionsProvider).deactivateInviteLink(widget.groupId);
    setState(() => _inviteData = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite link deactivated')),
      );
    }
  }

  String get _code => _inviteData?['code'] as String? ?? '';
  String get _url => _inviteData?['url'] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Invite Link'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _inviteData == null
              ? _buildNoLink()
              : _buildLinkContent(),
    );
  }

  Widget _buildNoLink() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.link_off_rounded,
              size: 48, color: SnowColors.textTertiary),
          const SizedBox(height: SnowSizes.md),
          const Text('No active invite link',
              style: TextStyle(color: SnowColors.textTertiary)),
          const SizedBox(height: SnowSizes.lg),
          ElevatedButton(
            onPressed: _generateLink,
            child: const Text('Generate Link'),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SnowSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Share link
          const Text('Share Link',
              style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: SnowSizes.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: SnowColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _url,
                    style: const TextStyle(
                        color: SnowColors.primary,
                        fontFamily: 'monospace',
                        fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded,
                      color: SnowColors.primary, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _url));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied!')),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: SnowSizes.md),

          // Share buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Share.share(
                      'Join ${widget.channelName} on SnowChat!\n$_url',
                      subject: 'SnowChat Invite',
                    );
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Share via...'),
                ),
              ),
            ],
          ),

          const SizedBox(height: SnowSizes.xl),
          const Divider(color: SnowColors.divider),
          const SizedBox(height: SnowSizes.lg),

          // QR Code
          const Text('QR Code',
              style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: SnowSizes.md),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _url,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),

          const SizedBox(height: SnowSizes.xl),
          const Divider(color: SnowColors.divider),
          const SizedBox(height: SnowSizes.lg),

          // Code text
          const Text('Or share code directly:',
              style:
                  TextStyle(color: SnowColors.textSecondary, fontSize: 13)),
          const SizedBox(height: SnowSizes.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _code,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    color: SnowColors.primary, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copied!')),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: SnowSizes.xl),
          const Divider(color: SnowColors.divider),
          const SizedBox(height: SnowSizes.lg),

          // Settings
          const Text('Settings',
              style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: SnowSizes.md),

          // Expires
          DropdownButtonFormField<int>(
            value: _expiresInHours,
            dropdownColor: SnowColors.surface,
            style: const TextStyle(color: SnowColors.textPrimary),
            decoration: const InputDecoration(labelText: 'Expires after'),
            items: const [
              DropdownMenuItem(value: 24, child: Text('1 day')),
              DropdownMenuItem(value: 168, child: Text('7 days')),
              DropdownMenuItem(value: 720, child: Text('30 days')),
              DropdownMenuItem(value: 0, child: Text('Never')),
            ],
            onChanged: (v) => setState(() => _expiresInHours = v ?? 168),
          ),

          const SizedBox(height: SnowSizes.md),

          // Max uses
          DropdownButtonFormField<int?>(
            value: _maxUses,
            dropdownColor: SnowColors.surface,
            style: const TextStyle(color: SnowColors.textPrimary),
            decoration: const InputDecoration(labelText: 'Max uses'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Unlimited')),
              DropdownMenuItem(value: 10, child: Text('10 uses')),
              DropdownMenuItem(value: 50, child: Text('50 uses')),
              DropdownMenuItem(value: 100, child: Text('100 uses')),
            ],
            onChanged: (v) => setState(() => _maxUses = v),
          ),

          const SizedBox(height: SnowSizes.xl),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _generateLink,
                  child: const Text('Regenerate'),
                ),
              ),
              const SizedBox(width: SnowSizes.md),
              Expanded(
                child: OutlinedButton(
                  onPressed: _deactivate,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: SnowColors.error),
                  child: const Text('Deactivate'),
                ),
              ),
            ],
          ),

          const SizedBox(height: SnowSizes.lg),
        ],
      ),
    );
  }
}
