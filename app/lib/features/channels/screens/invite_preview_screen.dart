/// @file        invite_preview_screen.dart
/// @description Invite-code preview screen — show channel info + join when entered via deeplink.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-11-20 (v1 groups removed: a community has no rooms — after joining, the Communities tab opens with the community expanded; InviteInfo names it channelId / channelName). Earlier 2026-08-05 ("Channel"→"Community" UI strings). Earlier 2026-08-03 (F6: after joining, await the conversation-list refresh and navigate to the group *chat* by resolving the conversation whose channelId matches (its id is the groupChatId), instead of /chat/{info.groupId} — info.groupId is the channelId, and /chat/{channelId} could not resolve as a group so the first message misrouted into a phantom "??" direct conversation). Earlier 2026-04-26 (header English translation)
///
/// @functions
///  - InvitePreviewScreen: invite-link preview + join button

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
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

    if (!mounted) return;
    if (success) {
      setState(() => _isJoining = false);
      // A community is a member list — it has no chat to open. Land on the
      // Communities tab with the joined community expanded.
      ref.invalidate(myChannelsProvider);
      final channelId =
          ref.read(inviteInfoProvider(widget.code)).valueOrNull?.channelId;
      context.go(channelId == null
          ? '/contacts'
          : '/contacts?expand=${Uri.encodeQueryComponent(channelId)}');
    } else {
      setState(() => _isJoining = false);
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
        title: const Text('Community Invite'),
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
              snowId: info.channelId,
              size: 80,
              displayName: info.channelName ?? '',
            ),
            const SizedBox(height: SnowSizes.lg),
            const Text(
              "You've been invited to",
              style: TextStyle(color: SnowColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: SnowSizes.sm),
            Text(
              info.channelName ?? 'Community',
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
                  : const Text('Join Community'),
            ),
          ],
        ),
      ),
    );
  }
}
