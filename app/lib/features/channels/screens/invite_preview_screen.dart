/// @file        invite_preview_screen.dart
/// @description Invite-code preview screen — show channel info + join when entered via deeplink.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - InvitePreviewScreen: invite-link preview + join button

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';

class InvitePreviewScreen extends ConsumerStatefulWidget {
  final String code;
  const InvitePreviewScreen({super.key, required this.code});

  @override
  ConsumerState<InvitePreviewScreen> createState() =>
      _InvitePreviewScreenState();
}

class _InvitePreviewScreenState extends ConsumerState<InvitePreviewScreen> {
  bool _isJoining = false;

  Future<void> _join() async {
    setState(() => _isJoining = true);
    final success =
        await ref.read(channelActionsProvider).joinViaInvite(widget.code);
    setState(() => _isJoining = false);

    if (success && mounted) {
      ref.read(conversationListProvider.notifier).refresh();
      // Navigate to the channel
      final info = ref.read(inviteInfoProvider(widget.code)).valueOrNull;
      if (info != null) {
        context.go('/chat/${info.groupId}');
      } else {
        context.go('/contacts'); // fallback to channels tab
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to join. Link may be expired.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inviteAsync = ref.watch(inviteInfoProvider(widget.code));

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/contacts'),
        ),
        title: const Text('Channel Invite'),
      ),
      body: inviteAsync.when(
        data: (info) {
          if (info == null) {
            return const Center(
              child: Text(
                'Invalid or expired invite link.',
                style: TextStyle(color: SnowColors.textTertiary, fontSize: 16),
              ),
            );
          }
          return _buildContent(info);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Failed to load invite',
              style: TextStyle(color: SnowColors.textTertiary)),
        ),
      ),
    );
  }

  Widget _buildContent(InviteInfo info) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SnowSizes.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SnowAvatar(
              snowId: info.groupId,
              size: 80,
              displayName: info.groupName ?? '',
            ),
            const SizedBox(height: SnowSizes.lg),
            const Text(
              "You've been invited to",
              style: TextStyle(color: SnowColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: SnowSizes.sm),
            Text(
              info.groupName ?? 'Channel',
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: SnowSizes.sm),
            Text(
              '${info.memberCount} members${info.category != null ? ' • ${info.category}' : ''}',
              style: const TextStyle(
                  color: SnowColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: SnowSizes.xxl),
            ElevatedButton(
              onPressed: _isJoining ? null : _join,
              child: _isJoining
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Join Channel'),
            ),
          ],
        ),
      ),
    );
  }
}
