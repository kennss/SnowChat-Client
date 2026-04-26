/// @file        channel_info_screen.dart
/// @description Channel intro + join screen — channel info display + join/apply button.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-04-26 (header English translation; remove discover dependency -> independent fetch, pop after apply)
///
/// @functions
///  - _channelInfoProvider: independently fetch channel detail
///  - ChannelInfoScreen: channel intro + join-policy-specific button

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../core/network/api_endpoints.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';

/// Fetch channel info independently (not from discover cache).
final _channelInfoProvider =
    FutureProvider.autoDispose.family<ChannelInfo?, String>((ref, channelId) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    // Try discover endpoint first (has summary info)
    final res = await apiClient.get(ApiEndpoints.channelDiscover);
    final list = (res.data['channels'] as List?) ?? [];
    for (final c in list) {
      final map = Map<String, dynamic>.from(c as Map);
      if (map['id'] == channelId) return ChannelInfo.fromJson(map);
    }
    // Fallback: fetch channel detail directly
    final detailRes = await apiClient.get(ApiEndpoints.channelDetail(channelId));
    final data = Map<String, dynamic>.from(detailRes.data as Map);
    return ChannelInfo.fromJson(data);
  } catch (e) {
    debugPrint('[ChannelInfo] Fetch failed: $e');
    return null;
  }
});

class ChannelInfoScreen extends ConsumerStatefulWidget {
  final String groupId;
  const ChannelInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<ChannelInfoScreen> createState() => _ChannelInfoScreenState();
}

class _ChannelInfoScreenState extends ConsumerState<ChannelInfoScreen> {
  bool _isJoining = false;
  String? _statusMessage;

  Future<void> _joinOpen() async {
    setState(() => _isJoining = true);
    final success =
        await ref.read(channelActionsProvider).joinPublicChannel(widget.groupId);
    setState(() => _isJoining = false);
    if (success && mounted) {
      ref.invalidate(myChannelsProvider);
      ref.invalidate(channelDiscoverProvider(null));
      ref.read(conversationListProvider.notifier).refresh();
      context.pop();
      context.go('/contacts'); // Go to Channels tab
    }
  }

  Future<void> _apply() async {
    setState(() => _isJoining = true);
    final status =
        await ref.read(channelActionsProvider).applyToChannel(widget.groupId);
    ref.invalidate(channelDiscoverProvider(null));
    setState(() => _isJoining = false);
    if (mounted && (status == 'pending' || status == 'already_pending')) {
      context.pop(); // Return to add channel screen
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'pending'
              ? 'Application submitted! Waiting for approval.'
              : 'You already applied. Waiting for approval.'),
          backgroundColor: SnowColors.primary,
        ),
      );
    } else if (mounted) {
      setState(() {
        switch (status) {
          case 'already_member':
            _statusMessage = 'You are already a member.';
            break;
          default:
            _statusMessage = 'Application failed. Please try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final channelAsync = ref.watch(_channelInfoProvider(widget.groupId));

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: channelAsync.when(
        data: (channel) {
          if (channel == null) {
            return const Center(
              child: Text('Channel not found',
                  style: TextStyle(color: SnowColors.textTertiary)),
            );
          }
          return _buildContent(channel);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Failed to load',
              style: TextStyle(color: SnowColors.textTertiary)),
        ),
      ),
    );
  }

  Widget _buildContent(ChannelInfo channel) {
    return Padding(
      padding: const EdgeInsets.all(SnowSizes.lg),
      child: Column(
        children: [
          const SizedBox(height: SnowSizes.xl),
          // Avatar
          SnowAvatar(
            snowId: channel.id,
            size: 80,
            displayName: channel.name ?? '',
          ),
          const SizedBox(height: SnowSizes.md),
          // Name
          Text(
            channel.name ?? 'Channel',
            style: const TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: SnowSizes.sm),
          // Info
          Text(
            '${channel.memberCount} members${channel.category != null ? ' • ${channel.category}' : ''}',
            style:
                const TextStyle(color: SnowColors.textTertiary, fontSize: 14),
          ),
          const SizedBox(height: SnowSizes.lg),
          const Divider(color: SnowColors.divider),
          const SizedBox(height: SnowSizes.md),

          // Join policy display
          _buildPolicyBadge(channel.joinPolicy),

          const SizedBox(height: SnowSizes.xl),

          // Status message
          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SnowColors.primaryBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage!,
                style: const TextStyle(
                    color: SnowColors.primary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: SnowSizes.md),
          ],

          // Action button
          if (_statusMessage == null) _buildActionButton(channel.joinPolicy),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildPolicyBadge(JoinPolicy policy) {
    final IconData icon;
    final Color color;
    final String text;

    switch (policy) {
      case JoinPolicy.open:
        icon = Icons.public_rounded;
        color = SnowColors.primary;
        text = 'Open — Anyone can join';
        break;
      case JoinPolicy.approval:
        icon = Icons.how_to_reg_rounded;
        color = Colors.amber;
        text = 'Approval — Admin approval required';
        break;
      case JoinPolicy.inviteOnly:
        icon = Icons.lock_rounded;
        color = SnowColors.textTertiary;
        text = 'Invite Only — Invite link required';
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color, fontSize: 14)),
      ],
    );
  }

  Widget _buildActionButton(JoinPolicy policy) {
    // Check if already a member
    final myChannels = ref.watch(myChannelsProvider).valueOrNull ?? [];
    final alreadyJoined = myChannels.any((c) => c.id == widget.groupId);

    if (alreadyJoined) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SnowColors.primaryBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('You are already a member of this channel.',
            style: TextStyle(color: SnowColors.primary, fontSize: 14),
            textAlign: TextAlign.center),
      );
    }

    switch (policy) {
      case JoinPolicy.open:
        return ElevatedButton(
          onPressed: _isJoining ? null : _joinOpen,
          child: _isJoining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Join Channel'),
        );
      case JoinPolicy.approval:
        return ElevatedButton(
          onPressed: _isJoining ? null : _apply,
          child: _isJoining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Apply to Join'),
        );
      case JoinPolicy.inviteOnly:
        return const Text(
          'This channel requires an invite link to join.',
          style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
          textAlign: TextAlign.center,
        );
    }
  }
}
