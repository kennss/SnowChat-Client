/// @file        channel_list_screen.dart
/// @description Communities tab screen — leads with discovery (search + trending feed via CommunityExplore); the user's own communities render as a header above it, so a new account never hits the old two-button dead-end. Per-community member accordion + Manage/Mute/Leave options (Phase 7, COMMUNITY only — Phase 9.1).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-08-05 (onboarding: tab is now explore-first — empty state replaced by embedded CommunityExplore (search + trending discover); "My Communities" header above the feed; "+" menu drops redundant Browse (tab is the browse) keeping Create/Join-with-code; "Channel"→"Community" rename throughout). Earlier 2026-06-25 (member-count refresh on resume; member tap → openDirectChatWith). Earlier 2026-04-26 (header English translation)
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
import '../../chat/services/start_direct_chat.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';
import '../widgets/community_explore.dart';

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

class _ChannelListScreenState extends ConsumerState<ChannelListScreen>
    with WidgetsBindingObserver {
  final Set<String> _expandedChannels = {};
  StreamSubscription<Map<String, dynamic>>? _memberJoinedSub;
  StreamSubscription<Map<String, dynamic>>? _memberLeftSub;
  StreamSubscription<Map<String, dynamic>>? _roleChangedSub;
  StreamSubscription<Map<String, dynamic>>? _applicationSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.invalidate(myChannelsProvider);
      _listenForMemberChanges();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On foreground, re-pull the channel list so the per-channel "(N)" member
    // counts catch up on any channel_member_joined/_left events missed while
    // backgrounded — those socket events are fire-and-forget to currently-
    // online sockets and are NOT replayed on reconnect. Without this, initState
    // invalidates only once (the Channels tab is kept alive), so each member's
    // count freezes at their first-load (≈ join-time) value — field report
    // 2026-06-25 (WAAO: every member saw their own join-time count). The server
    // returns a live count (channels.ts /my → _count.members), so a fresh fetch
    // is always correct.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(myChannelsProvider);
      ref.invalidate(pendingChannelsProvider);
    }
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
        final channelName = data['channelName'] as String? ?? 'a community';
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
          message: '$name applied to join your community',
          type: ToastType.info,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        title: const Text('Communities'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_rounded, color: SnowColors.primary),
            color: SnowColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            tooltip: 'Add community',
            onSelected: (value) {
              switch (value) {
                case 'create':
                  context.push('/create-channel');
                case 'join_code':
                  context.push('/join-with-code');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'create',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.add_circle_rounded, color: SnowColors.primary),
                  title: Text('Create Community',
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
      // The tab always leads with discovery (search + trending feed). A user's
      // own communities render as the header ABOVE the discover feed, so a
      // brand-new account never hits a dead-end — it lands on a live list of
      // communities to join. (onboarding fix, design 2026-08-05.)
      body: channelsAsync.when(
        data: (channels) {
          final pending = pendingAsync.valueOrNull ?? [];
          return CommunityExplore(
            header: _buildMyCommunitiesHeader(channels, pending),
          );
        },
        loading: () => const CommunityExplore(),
        error: (_, __) => const CommunityExplore(),
      ),
    );
  }

  /// "My Communities" + pending, rendered above the discover feed. Null when the
  /// user belongs to nothing yet (→ discover feed shows on its own).
  Widget? _buildMyCommunitiesHeader(
      List<ChannelInfo> channels, List<PendingChannel> pending) {
    if (channels.isEmpty && pending.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(SnowSizes.md, 12, SnowSizes.md, 4),
          child: Text(
            'My Communities',
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final channel in channels) _buildChannelSection(channel),
        if (pending.isNotEmpty) _buildPendingSection(pending),
      ],
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
                    '${channel.name ?? "Community"} (${channel.memberCount})',
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
            channelName: channel.name ?? 'Community',
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
                title: const Text('Manage Community',
                    style: TextStyle(color: SnowColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                    '/channel-admin/${channel.id}?name=${Uri.encodeComponent(channel.name ?? 'Community')}',
                  );
                },
              ),
            // Invite link — admin 무조건, 일반 멤버는 channel.canCreateInvite
            // (서버 권한 체크와 일치). INVITE_ONLY 채널엔 admin 만 보임.
            if (channel.canCreateInvite)
              ListTile(
                leading:
                    const Icon(Icons.link_rounded, color: SnowColors.primary),
                title: const Text('Invite to Community',
                    style: TextStyle(color: SnowColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                    '/invite-link/${channel.id}?name=${Uri.encodeComponent(channel.name ?? 'Community')}',
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
              title: const Text('Leave Community',
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
        title: const Text('Leave Community',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Text(
          'Leave "${channel.name}"? You will lose access to this community.',
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
                    ch.name ?? 'Community',
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
                if (snowchatId.isNotEmpty && snowchatId != myId) {
                  // Tap a channel member → open the 1:1 directly: find an
                  // existing direct conversation, else find-or-create on the
                  // server → /chat/{id}. Same path the Friends list uses. The
                  // old '/new-chat?recipientId=…' push was silently ignored by
                  // NewChatScreen, dumping the user on a generic picker (a
                  // group-create button + an unscoped all-contacts list) where
                  // they had to hunt for the member again — field report
                  // 2026-06-25.
                  openDirectChatWith(
                    context: context,
                    ref: ref,
                    recipientSnowchatId: snowchatId,
                    recipientDisplayName: displayName,
                  );
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
