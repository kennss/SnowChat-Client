/// @file        conversation_list_screen.dart
/// @description Conversation-list screen — channel accordion (group rooms) + Direct Messages section (independent 1:1 DMs)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-08 independent group section)
///
/// @functions
///  - ConversationListScreen: channel group-room accordion + Direct Messages independent section
///  - _buildDmSection(): show 1:1 DMs as an independent section
///  - _showPendingInvites(): show pending group-invite dialog

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/deeplink_handler.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../group/widgets/group_invite_dialog.dart';
import '../../channels/models/channel.dart';
import '../../channels/providers/channel_provider.dart';
import '../../channels/screens/channel_list_screen.dart' show channelUnreadCountProvider;
import '../models/conversation.dart';
import '../providers/conversation_list_provider.dart';
import '../widgets/conversation_tile.dart';
import '../../ai/widgets/ai_chat_tile.dart';

class ConversationListScreen extends ConsumerStatefulWidget {
  const ConversationListScreen({super.key});

  @override
  ConsumerState<ConversationListScreen> createState() =>
      _ConversationListScreenState();
}

class _ConversationListScreenState
    extends ConsumerState<ConversationListScreen> {
  StreamSubscription<Map<String, dynamic>>? _groupInviteSubscription;
  StreamSubscription<Map<String, dynamic>>? _groupInviteRejectedSubscription;
  bool _pendingInvitesChecked = false;

  @override
  void initState() {
    super.initState();
    // Listen for real-time group invites via socket
    final sm = ref.read(socketManagerProvider);
    _groupInviteSubscription = sm.onGroupInvite.listen((data) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => GroupInviteDialog(inviteData: data),
        );
      }
    });

    // Listen for invite rejections — surface a toast on the creator's
    // (and other members') screen so they know who declined.
    _groupInviteRejectedSubscription =
        sm.onGroupInviteRejected.listen((data) {
      if (!mounted) return;
      final rejectedBy = data['rejectedBy'] as Map?;
      final name = (rejectedBy?['displayName'] as String?) ??
          (rejectedBy?['snowchatId'] as String?) ??
          'Someone';
      final groupName = (data['groupName'] as String?) ?? 'the group';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: SnowColors.surface,
          content: Text(
            '$name declined to join $groupName',
            style: const TextStyle(color: SnowColors.textPrimary),
          ),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Refresh the list so member-count / sender-key state updates.
      ref.read(conversationListProvider.notifier).refresh();
    });

    // Show pending invites after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPendingInvites();
      _drainPendingDeeplink();
    });

    // Auto background-download AI model (on WiFi) + auto-init when model is installed
    _initAI();
  }

  @override
  void dispose() {
    _groupInviteSubscription?.cancel();
    _groupInviteRejectedSubscription?.cancel();
    super.dispose();
  }

  /// AI model initialization strategy (Phase 10.x update).
  /// Translation uses a platform-specific dedicated engine — Gemma not required.
  ///   iOS: Apple Translation API
  ///   Android: Google ML Kit (on-device NMT)
  /// Gemma is used only for AI chat + summarization → lazy-load on both platforms (on AI-chat entry).
  /// Lightens app cold-start.
  Future<void> _initAI() async {
    // Both platforms: skip Gemma auto-init/download — lazy-load from AI chat
    return;
  }

  /// Phase 1 deeplink: if app launched FROM snowchat://invite/<code> while not
  /// yet onboarded (or pre-router race), DeeplinkHandler queued the code.
  /// Drain on /chat mount — this is the first stable post-onboarding screen.
  void _drainPendingDeeplink() {
    final code = DeeplinkHandler.instance.consumePending();
    if (code != null && mounted) {
      context.push('/invite/$code');
    }
  }

  /// Show pending group invites loaded from the server (one at a time).
  void _showPendingInvites() {
    if (_pendingInvitesChecked) return;
    _pendingInvitesChecked = true;

    final notifier = ref.read(conversationListProvider.notifier);
    final invites = notifier.pendingInvites;
    if (invites.isNotEmpty) {
      // Show the first pending invite
      showDialog(
        context: context,
        builder: (_) => GroupInviteDialog(inviteData: invites.first),
      );
      notifier.clearPendingInvites();
    }
  }

  final Set<String> _expandedChannels = {};

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(myChannelsProvider);
    final conversations = ref.watch(conversationListProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text(
          'SnowChat',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: SnowColors.primary),
            onPressed: () => context.push('/message-search'),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: SnowColors.primary),
            onPressed: () => context.push('/new-chat'),
          ),
        ],
      ),
      body: channelsAsync.when(
        data: (channels) {
          if (channels.isEmpty && conversations.isEmpty) {
            return _buildEmptyState(context);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myChannelsProvider);
              await ref.read(conversationListProvider.notifier).refresh();
            },
            color: SnowColors.primary,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: SnowSizes.sm),
              children: [
                // ── SnowChat AI ── (pinned at top)
                const AiChatTile(),
                const Divider(color: SnowColors.divider, height: 1),

                // Channel sections (group rooms only)
                for (final channel in channels)
                  _buildChannelSection(channel),

                // ── Group Chats ── section (independent groups, not nested
                // under any channel). Without this section, groups created
                // via "New Group" land in state but never reach the UI.
                ..._buildGroupSection(conversations),

                // ── Direct Messages ── section
                ..._buildDmSection(conversations),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Failed to load',
              style: TextStyle(color: SnowColors.textTertiary)),
        ),
      ),
    );
  }

  /// Render the standalone "Group Chats" section.
  ///
  /// Includes only groups WITHOUT a parent channel (`channelId == null`).
  /// Channel rooms are intentionally excluded — they're rendered nested
  /// inside `_buildChannelSection` based on `myChannelsProvider`. Showing
  /// them here too would create duplicates.
  List<Widget> _buildGroupSection(List<Conversation> conversations) {
    final groups = conversations
        .where((c) =>
            c.type == ConversationType.group && c.channelId == null)
        .toList()
      ..sort((a, b) => (b.lastMessageTime ?? b.createdAt)
          .compareTo(a.lastMessageTime ?? a.createdAt));
    if (groups.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SnowSizes.md, vertical: 10),
        child: Row(
          children: [
            Container(width: 24, height: 1, color: SnowColors.divider),
            const SizedBox(width: 8),
            const Text(
              'Group Chats',
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
      ...groups.map((g) => ConversationTile(
            conversation: g,
            onTap: () => context.push('/chat/${g.id}'),
          )),
    ];
  }

  List<Widget> _buildDmSection(List<Conversation> conversations) {
    final dms =
        conversations.where((c) => c.type == ConversationType.direct).toList();
    if (dms.isEmpty) return [];

    return [
      // Section header
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SnowSizes.md, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 1,
              color: SnowColors.divider,
            ),
            const SizedBox(width: 8),
            const Text(
              'Direct Messages',
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
      // DM tiles
      ...dms.map((dm) => ConversationTile(
            conversation: dm,
            onTap: () => context.push('/chat/${dm.id}'),
          )),
    ];
  }

  Widget _buildChannelSection(ChannelInfo channel) {
    final isExpanded = _expandedChannels.contains(channel.id);
    final unread = ref.watch(channelUnreadCountProvider(channel.id));

    return Column(
      children: [
        // Channel header — tap to expand/collapse
        InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedChannels.remove(channel.id);
              } else {
                _expandedChannels.add(channel.id);
              }
            });
          },
          child: Container(
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Expanded: list rooms
        if (isExpanded) ...[
          // Default room (Channel Group)
          if (channel.defaultRoom != null)
            _buildRoomTile(
              icon: Icons.groups_rounded,
              iconColor: SnowColors.primary,
              title: '${channel.name ?? "Channel"} Group',
              roomId: channel.defaultRoom!.id,
            ),
          // System room (admin only)
          if (channel.systemRoom != null && channel.isAdmin)
            _buildRoomTile(
              icon: Icons.settings_rounded,
              iconColor: SnowColors.textTertiary,
              title: channel.systemRoom!.name,
              roomId: channel.systemRoom!.id,
            ),
          // User-created rooms
          for (final room in channel.userRooms)
            _buildRoomTile(
              icon: Icons.chat_rounded,
              iconColor: SnowColors.textSecondary,
              title: room.name,
              roomId: room.id,
            ),
        ],

        const Divider(color: SnowColors.divider, height: 0.5),
      ],
    );
  }

  Widget _buildRoomTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String roomId,
  }) {
    // Find unread count for this room from conversation list
    final conversations = ref.watch(conversationListProvider);
    final roomConv = conversations.where((c) => c.groupId == roomId).firstOrNull;
    final roomUnread = roomConv?.unreadCount ?? 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 40),
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(title,
          style: TextStyle(
            color: SnowColors.textPrimary,
            fontSize: 15,
            fontWeight: roomUnread > 0 ? FontWeight.w600 : FontWeight.normal,
          )),
      trailing: roomUnread > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: SnowColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                roomUnread > 99 ? '99+' : '$roomUnread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
      onTap: () => context.push('/chat/$roomId'),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: SnowColors.textTertiary,
          ),
          const SizedBox(height: SnowSizes.md),
          const Text(
            'No conversations yet',
            style: TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: SnowSizes.sm),
          const Text(
            'Start a new chat to begin messaging',
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: SnowSizes.lg),
          ElevatedButton.icon(
            onPressed: () => context.push('/new-chat'),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New Chat'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 44),
            ),
          ),
        ],
      ),
    );
  }
}
