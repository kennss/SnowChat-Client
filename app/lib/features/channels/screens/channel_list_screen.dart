/// @file        channel_list_screen.dart
/// @description Channels tab screen — per-channel member accordion view (Phase 7, COMMUNITY only — Phase 9.1).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - channelUnreadCountProvider: sum unread count per channelId (derived from conversationList)
///  - ChannelListScreen: channel list + member accordion (replaces former ContactListScreen)
///  - _leaveChannel(): leave-channel confirmation + execution
///  - _showChannelOptions(): Manage/Mute/Leave bottom sheet

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../shared/widgets/toast.dart';
import '../../../core/network/api_endpoints.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';

/// Aggregated unread count per channel, derived from conversation list state.
final channelUnreadCountProvider =
    Provider.family<int, String>((ref, channelId) {
  final conversations = ref.watch(conversationListProvider);
  int total = 0;
  for (final c in conversations) {
    if (c.channelId == channelId) {
      total += c.unreadCount;
    }
  }
  return total;
});

class ChannelListScreen extends ConsumerStatefulWidget {
  const ChannelListScreen({super.key});

  @override
  ConsumerState<ChannelListScreen> createState() => _ChannelListScreenState();
}

class _ChannelListScreenState extends ConsumerState<ChannelListScreen> {
  final Set<String> _expandedChannels = {};
  StreamSubscription<Map<String, dynamic>>? _memberJoinedSub;
  StreamSubscription<Map<String, dynamic>>? _memberLeftSub;
  StreamSubscription<Map<String, dynamic>>? _roleChangedSub;
  StreamSubscription<Map<String, dynamic>>? _applicationSub;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.invalidate(myChannelsProvider);
      _listenForMemberChanges();
    });
  }

  void _listenForMemberChanges() {
    final sm = ref.read(socketManagerProvider);
    _memberJoinedSub = sm.onChannelMemberJoined.listen((data) {
      // Skip PERSONAL channel events — those are handled by FriendListScreen
      final type = data['type'] as String?;
      if (type == 'PERSONAL') return;

      // Refresh channel list + detail + pending + discover when any member joins
      ref.invalidate(myChannelsProvider);
      ref.invalidate(pendingChannelsProvider);
      ref.invalidate(channelDiscoverProvider(null));
      final channelId = data['channelId'] as String?;
      if (channelId != null) {
        ref.invalidate(_channelDetailProvider(channelId));
      }

      // Toast for the approved user (I was just accepted into a channel)
      final joinedSnowId = data['snowchatId'] as String?;
      final mySnowId = ref.read(currentSnowIdProvider);
      if (mounted && joinedSnowId == mySnowId) {
        final channelName = data['channelName'] as String? ?? 'a channel';
        SnowToast.show(
          context,
          message: 'You were approved to join $channelName',
          type: ToastType.success,
        );
      }
    });
    _memberLeftSub = sm.onChannelMemberLeft.listen((data) {
      // Skip PERSONAL channel events
      final type = data['type'] as String?;
      if (type == 'PERSONAL') return;

      ref.invalidate(myChannelsProvider);
      final channelId = data['channelId'] as String?;
      if (channelId != null) {
        ref.invalidate(_channelDetailProvider(channelId));
      }
    });
    _roleChangedSub = sm.onChannelMemberRoleChanged.listen((data) {
      ref.invalidate(myChannelsProvider);
    });
    _applicationSub = sm.onChannelApplicationReceived.listen((data) {
      ref.invalidate(myChannelsProvider);
      ref.invalidate(pendingChannelsProvider);
      if (mounted) {
        final name = data['displayName'] as String? ?? 'Someone';
        SnowToast.show(
          context,
          message: '$name applied to join your channel',
          type: ToastType.info,
        );
      }
    });
  }

  @override
  void dispose() {
    _memberJoinedSub?.cancel();
    _memberLeftSub?.cancel();
    _roleChangedSub?.cancel();
    _applicationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(myChannelsProvider);
    final pendingAsync = ref.watch(pendingChannelsProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Channels'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_rounded, color: SnowColors.primary),
            color: SnowColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            tooltip: 'Add channel',
            onSelected: (value) {
              switch (value) {
                case 'browse':
                  context.push('/add-channel');
                case 'create':
                  context.push('/create-channel');
                case 'join_code':
                  context.push('/join-with-code');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'browse',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.explore_rounded, color: SnowColors.primary),
                  title: Text('Browse Channels',
                      style: TextStyle(color: SnowColors.textPrimary)),
                ),
              ),
              PopupMenuItem(
                value: 'create',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.add_circle_rounded, color: SnowColors.primary),
                  title: Text('Create Channel',
                      style: TextStyle(color: SnowColors.textPrimary)),
                ),
              ),
              PopupMenuItem(
                value: 'join_code',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.link_rounded,
                      color: SnowColors.primary),
                  title: Text('Join with Code',
                      style: TextStyle(color: SnowColors.textPrimary)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: channelsAsync.when(
        data: (channels) {
          final pending = pendingAsync.valueOrNull ?? [];
          if (channels.isEmpty && pending.isEmpty) {
            return _buildEmptyState(context);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myChannelsProvider);
              ref.invalidate(pendingChannelsProvider);
            },
            color: SnowColors.primary,
            backgroundColor: SnowColors.surface,
            child: ListView(
              children: [
                for (final channel in channels)
                  _buildChannelSection(channel),
                // Pending section
                if (pending.isNotEmpty) ...[
                  _buildPendingSection(pending),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Failed to load channels',
              style: TextStyle(color: SnowColors.textTertiary)),
        ),
      ),
    );
  }

  Widget _buildChannelSection(ChannelInfo channel) {
    final isExpanded = _expandedChannels.contains(channel.id);
    final unread = ref.watch(channelUnreadCountProvider(channel.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Channel header (tap to expand/collapse)
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedChannels.remove(channel.id);
              } else {
                _expandedChannels.add(channel.id);
                // Refresh member list every time we expand
                ref.invalidate(_channelDetailProvider(channel.id));
              }
            });
          },
          onLongPress: () => _showChannelOptions(channel),
          child: Container(
            // Chats 탭과 동일한 padding/spacing/typography. 채널 아바타가
            // 있으면 (avatarUrl) 32px network image, 없으면 이니셜 fallback.
            padding: const EdgeInsets.symmetric(
                horizontal: SnowSizes.md, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  color: SnowColors.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 6),
                SnowAvatar(
                  snowId: channel.id,
                  size: SnowSizes.avatarMd,
                  displayName: channel.name ?? '',
                  avatarUrl: channel.avatarUrl,
                  authHeader: ref.watch(authHeaderProvider),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${channel.name ?? "Channel"} (${channel.memberCount})',
                    style: const TextStyle(
                      color: SnowColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                // Muted icon
                if (channel.isMuted)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.notifications_off_rounded,
                        color: SnowColors.textTertiary, size: 16),
                  ),
                // Unread badge (when collapsed)
                if (!isExpanded && unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: SnowColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Expanded: member list (fetched from channel detail API)
        if (isExpanded)
          _ChannelMemberList(
            channelId: channel.id,
            channelName: channel.name ?? 'Channel',
          ),

        const Divider(color: SnowColors.divider, height: 1),
      ],
    );
  }

  void _showChannelOptions(ChannelInfo channel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SnowColors.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SnowColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Channel Admin (Owner/Admin only)
            if (channel.isAdmin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded,
                    color: SnowColors.primary),
                title: const Text('Manage Channel',
                    style: TextStyle(color: SnowColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                    '/channel-admin/${channel.id}?name=${Uri.encodeComponent(channel.name ?? 'Channel')}',
                  );
                },
              ),
            // Invite link — admin 무조건, 일반 멤버는 channel.canCreateInvite
            // (서버 권한 체크와 일치). INVITE_ONLY 채널엔 admin 만 보임.
            if (channel.canCreateInvite)
              ListTile(
                leading:
                    const Icon(Icons.link_rounded, color: SnowColors.primary),
                title: const Text('Invite to Channel',
                    style: TextStyle(color: SnowColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                    '/invite-link/${channel.id}?name=${Uri.encodeComponent(channel.name ?? 'Channel')}',
                  );
                },
              ),
            ListTile(
              leading: Icon(
                channel.isMuted
                    ? Icons.notifications_rounded
                    : Icons.notifications_off_rounded,
                color: SnowColors.textSecondary,
              ),
              title: Text(
                channel.isMuted ? 'Unmute Notifications' : 'Mute Notifications',
                style: const TextStyle(color: SnowColors.textPrimary),
              ),
              onTap: () async {
                Navigator.pop(context);
                final success = await ref
                    .read(channelActionsProvider)
                    .muteChannel(channel.id, !channel.isMuted);
                if (success) ref.invalidate(myChannelsProvider);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.exit_to_app_rounded, color: SnowColors.error),
              title: const Text('Leave Channel',
                  style: TextStyle(color: SnowColors.error)),
              onTap: () {
                Navigator.pop(context);
                _leaveChannel(channel);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _leaveChannel(ChannelInfo channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Leave Channel',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Text(
          'Leave "${channel.name}"? You will lose access to all rooms in this channel.',
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                const Text('Leave', style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final success =
          await ref.read(channelActionsProvider).leaveChannel(channel.id);
      if (success && mounted) {
        ref.invalidate(myChannelsProvider);
        ref.read(conversationListProvider.notifier).refresh();
      }
    }
  }

  Widget _buildPendingSection(List<PendingChannel> pending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: SnowSizes.md, vertical: 10),
          child: Row(
            children: [
              Container(width: 24, height: 1, color: SnowColors.divider),
              const SizedBox(width: 8),
              const Text(
                'Pending',
                style: TextStyle(
                  color: SnowColors.textTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(height: 1, color: SnowColors.divider),
              ),
            ],
          ),
        ),
        // Pending channel tiles
        for (final ch in pending)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: SnowSizes.md, vertical: 10),
            child: Row(
              children: [
                const SizedBox(width: 28), // indent to match channel rows
                SnowAvatar(
                  snowId: ch.id,
                  size: 28,
                  displayName: ch.name ?? '',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ch.name ?? 'Channel',
                    style: const TextStyle(
                      color: SnowColors.textSecondary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Awaiting approval',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_rounded,
              size: 64, color: SnowColors.textTertiary),
          const SizedBox(height: SnowSizes.md),
          const Text(
            'No channels yet',
            style: TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SnowSizes.sm),
          const Text(
            'Join a channel to start\nchatting securely.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SnowColors.textTertiary, fontSize: 14),
          ),
          const SizedBox(height: SnowSizes.lg),
          ElevatedButton.icon(
            onPressed: () => context.push('/add-channel'),
            icon: const Icon(Icons.explore_rounded),
            label: const Text('Browse Channels'),
          ),
          const SizedBox(height: SnowSizes.md),
          OutlinedButton.icon(
            onPressed: () => context.push('/create-channel'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create Channel'),
          ),
        ],
      ),
    );
  }
}

/// Channel detail provider (fetches from /channels/:channelId).
final _channelDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, channelId) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get(ApiEndpoints.channelDetail(channelId));
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    debugPrint('[ChannelMemberList] Detail failed: $e');
    return null;
  }
});

/// Fetches and displays members for a single channel accordion section.
class _ChannelMemberList extends ConsumerWidget {
  final String channelId;
  final String channelName;

  const _ChannelMemberList({
    required this.channelId,
    required this.channelName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(_channelDetailProvider(channelId));

    return detailAsync.when(
      data: (detail) {
        if (detail == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Failed to load',
                style: TextStyle(color: SnowColors.textTertiary)),
          );
        }

        final members = (detail['members'] as List?) ?? [];
        final creatorId = detail['creatorId'] as String?;

        // Sort: Owner → Admin → Member
        final sorted = [...members]..sort((a, b) {
            int roleOrder(dynamic m) {
              if (m['user']?['snowchatId'] != null &&
                  m['userId'] == creatorId) return 0;
              if (m['role'] == 'ADMIN') return 1;
              return 2;
            }
            return roleOrder(a).compareTo(roleOrder(b));
          });

        return Column(
          children: sorted.map((m) {
            final user = m['user'] as Map<String, dynamic>? ?? {};
            final snowchatId = user['snowchatId'] as String? ?? '';
            final displayName = user['displayName'] as String?;
            final role = m['role'] as String? ?? 'MEMBER';
            final isOwner = m['userId'] == creatorId;
            final isAdmin = role == 'ADMIN';

            return InkWell(
              onTap: () {
                final myId = ref.read(currentSnowIdProvider);
                if (snowchatId != myId) {
                  context.push('/new-chat?recipientId=$snowchatId');
                }
              },
              child: Padding(
                // DM tile (chat list) 와 같은 vertical padding + avatarMd 사이즈.
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 6),
                child: Row(
                  children: [
                    if (isOwner)
                      const Text('👑 ', style: TextStyle(fontSize: 16))
                    else if (isAdmin)
                      const Text('🛡 ', style: TextStyle(fontSize: 16))
                    else
                      const SizedBox(width: 24),
                    SnowAvatar(
                      snowId: snowchatId,
                      size: SnowSizes.avatarMd,
                      displayName: displayName ?? '',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        displayName ?? snowchatId.substring(0, 12),
                        style: TextStyle(
                          color: SnowColors.textPrimary,
                          fontSize: 16,
                          fontWeight: isOwner || isAdmin
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Error', style: TextStyle(color: SnowColors.textTertiary)),
      ),
    );
  }
}
