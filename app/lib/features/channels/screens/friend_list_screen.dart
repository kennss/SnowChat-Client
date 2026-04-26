/// @file        friend_list_screen.dart
/// @description Friend-list screen — Phase 9.1 PERSONAL Channel-based friend-management UI.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-09
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - FriendListScreen: friend list + friend requests + add-friend screen
///  - _buildFriendTile(): render friend item (avatar + name + online status)
///  - _buildFriendRequestSection(): received friend-request section (accept/decline)
///  - _showAddFriendDialog(): SnowChat ID input dialog
///  - _showFriendOptions(): friend options bottom sheet (DM / remove)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';

class FriendListScreen extends ConsumerStatefulWidget {
  const FriendListScreen({super.key});

  @override
  ConsumerState<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends ConsumerState<FriendListScreen> {
  StreamSubscription<Map<String, dynamic>>? _friendRequestSub;
  StreamSubscription<Map<String, dynamic>>? _memberJoinedSub;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.invalidate(personalChannelProvider);
      _listenForFriendEvents();
    });
  }

  void _listenForFriendEvents() {
    final sm = ref.read(socketManagerProvider);

    // Listen for incoming friend requests
    _friendRequestSub = sm.onFriendRequestReceived.listen((data) {
      ref.invalidate(personalChannelProvider);
      ref.invalidate(friendRequestsProvider);
    });

    // Listen for friend request accepted (channel_member_joined with type PERSONAL)
    _memberJoinedSub = sm.onChannelMemberJoined.listen((data) {
      final type = data['type'] as String?;
      if (type == 'PERSONAL') {
        ref.invalidate(personalChannelProvider);
        ref.invalidate(friendRequestsProvider);
      }
    });
  }

  @override
  void dispose() {
    _friendRequestSub?.cancel();
    _memberJoinedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendListProvider);
    final requestsAsync = ref.watch(friendRequestsProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: SnowColors.primary),
            onPressed: () => _showAddFriendDialog(),
          ),
        ],
      ),
      body: friendsAsync.when(
        data: (friends) {
          final requests = requestsAsync.valueOrNull ?? [];
          if (friends.isEmpty && requests.isEmpty) {
            return _buildEmptyState(context);
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(personalChannelProvider);
              ref.invalidate(friendRequestsProvider);
            },
            color: SnowColors.primary,
            backgroundColor: SnowColors.surface,
            child: ListView(
              children: [
                // Incoming friend requests section
                if (requests.isNotEmpty) _buildFriendRequestSection(requests),
                // Friend list section
                if (friends.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SnowSizes.md, vertical: 10),
                    child: Text(
                      'Friends (${friends.length})',
                      style: const TextStyle(
                        color: SnowColors.textTertiary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  for (final friend in friends) _buildFriendTile(friend),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Failed to load friends',
              style: TextStyle(color: SnowColors.textTertiary)),
        ),
      ),
    );
  }

  Widget _buildFriendTile(FriendInfo friend) {
    final presenceService = ref.watch(presenceServiceProvider);
    final isOnline = presenceService.isOnline(friend.snowchatId);

    return InkWell(
      onTap: () {
        // Navigate to DM with this friend
        context.push('/new-chat?recipientId=${friend.snowchatId}');
      },
      onLongPress: () => _showFriendOptions(friend),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SnowSizes.md, vertical: 10),
        child: Row(
          children: [
            // Avatar with online indicator
            Stack(
              children: [
                SnowAvatar(
                  snowId: friend.snowchatId,
                  size: 44,
                  displayName: friend.displayName ?? '',
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: SnowColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: SnowColors.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friend.displayName ??
                        friend.snowchatId.substring(0, 12),
                    style: const TextStyle(
                      color: SnowColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color: isOnline
                          ? SnowColors.success
                          : SnowColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Chat icon
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline_rounded,
                  color: SnowColors.textTertiary, size: 20),
              onPressed: () {
                context.push('/new-chat?recipientId=${friend.snowchatId}');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Incoming friend requests — PERSONAL channels where I have pending membership.
  /// The channelId here is the REQUESTER's PERSONAL channel.
  Widget _buildFriendRequestSection(List<PendingChannel> requests) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: SnowSizes.md, vertical: 10),
          child: Row(
            children: [
              Container(width: 24, height: 1, color: SnowColors.divider),
              const SizedBox(width: 8),
              Text(
                'Friend Requests (${requests.length})',
                style: const TextStyle(
                  color: Colors.amber,
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
        for (final request in requests)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: SnowSizes.md, vertical: 6),
            child: Row(
              children: [
                SnowAvatar(
                  snowId: request.creatorSnowchatId ?? request.id,
                  size: 40,
                  displayName: request.creatorDisplayName ?? '',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.creatorDisplayName ??
                            (request.creatorSnowchatId != null
                                ? request.creatorSnowchatId!.substring(0, 12)
                                : 'Unknown'),
                        style: const TextStyle(
                          color: SnowColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      if (request.appliedAt.isNotEmpty)
                        Text(
                          _formatTimeAgoString(request.appliedAt),
                          style: const TextStyle(
                            color: SnowColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                // Accept button — channelId is the requester's PERSONAL channel
                TextButton(
                  onPressed: () => _acceptFriendRequest(request.id),
                  style: TextButton.styleFrom(
                    backgroundColor: SnowColors.primary.withAlpha(25),
                    foregroundColor: SnowColors.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Accept',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                // Decline button
                TextButton(
                  onPressed: () => _declineFriendRequest(request.id),
                  style: TextButton.styleFrom(
                    backgroundColor: SnowColors.error.withAlpha(25),
                    foregroundColor: SnowColors.error,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Decline',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        const Divider(color: SnowColors.divider, height: 16),
      ],
    );
  }

  void _showFriendOptions(FriendInfo friend) {
    final channelId = ref.read(personalChannelIdProvider);

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
            // Header with friend info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SnowSizes.md),
              child: Row(
                children: [
                  SnowAvatar(
                    snowId: friend.snowchatId,
                    size: 40,
                    displayName: friend.displayName ?? '',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      friend.displayName ??
                          friend.snowchatId.substring(0, 12),
                      style: const TextStyle(
                        color: SnowColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: SnowColors.divider, height: 24),
            // Send message
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded,
                  color: SnowColors.primary),
              title: const Text('Send Message',
                  style: TextStyle(color: SnowColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                context.push('/new-chat?recipientId=${friend.snowchatId}');
              },
            ),
            // Remove friend
            ListTile(
              leading: const Icon(Icons.person_remove_rounded,
                  color: SnowColors.error),
              title: const Text('Remove Friend',
                  style: TextStyle(color: SnowColors.error)),
              onTap: () {
                Navigator.pop(context);
                if (channelId != null) {
                  _removeFriend(channelId, friend);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddFriendDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Add Friend',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your friend\'s SnowChat ID to send a friend request.',
              style: TextStyle(color: SnowColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: SnowColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'snow...',
                hintStyle: const TextStyle(color: SnowColors.textTertiary),
                filled: true,
                fillColor: SnowColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.person_search_rounded,
                    color: SnowColors.textTertiary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(dialogContext, text);
              }
            },
            child: const Text('Send Request',
                style: TextStyle(color: SnowColors.primary)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      final status = await ref.read(friendActionsProvider).addFriend(result);
      if (!mounted) return;

      String message;
      switch (status) {
        case 'pending':
          message = 'Friend request sent!';
        case 'already_friend':
          message = 'Already friends.';
        case 'already_pending':
          message = 'Friend request already pending.';
        default:
          message = 'Failed to send friend request.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: status == 'pending' || status == 'already_friend'
              ? SnowColors.success
              : status == 'already_pending'
                  ? Colors.amber
                  : SnowColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );

      if (status == 'pending') {
        ref.invalidate(personalChannelProvider);
      }
    }
  }

  Future<void> _acceptFriendRequest(String channelId) async {
    final success =
        await ref.read(friendActionsProvider).acceptFriendRequest(channelId);
    if (!mounted) return;

    if (success) {
      ref.invalidate(personalChannelProvider);
      ref.invalidate(friendRequestsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Friend request accepted!'),
          backgroundColor: SnowColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to accept friend request.'),
          backgroundColor: SnowColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _declineFriendRequest(String channelId) async {
    // Decline: leave the requester's PERSONAL channel (removes pending membership)
    final success =
        await ref.read(channelActionsProvider).leaveChannel(channelId);
    if (!mounted) return;

    if (success) {
      ref.invalidate(personalChannelProvider);
      ref.invalidate(friendRequestsProvider);
    }
  }

  Future<void> _removeFriend(String channelId, FriendInfo friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Remove Friend',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Text(
          'Remove "${friend.displayName ?? friend.snowchatId.substring(0, 12)}" from your friends? '
          'Your existing DMs will be kept.',
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
                const Text('Remove', style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(friendActionsProvider)
          .removeFriend(channelId, friend.userId);
      if (success && mounted) {
        ref.invalidate(personalChannelProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Friend removed.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline_rounded,
              size: 64, color: SnowColors.textTertiary),
          const SizedBox(height: SnowSizes.md),
          const Text(
            'No friends yet',
            style: TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: SnowSizes.sm),
          const Text(
            'Add a friend by their SnowChat ID\nto start chatting securely.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SnowColors.textTertiary, fontSize: 14),
          ),
          const SizedBox(height: SnowSizes.sm),
          Text(
            'Tap + to add a friend',
            style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgoString(String dateTimeStr) {
    final dateTime = DateTime.tryParse(dateTimeStr);
    if (dateTime == null) return '';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.month}/${dateTime.day}';
  }
}
