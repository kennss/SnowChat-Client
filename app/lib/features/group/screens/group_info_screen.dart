/// @file        group_info_screen.dart
/// @description Group info screen — group name, member list, role badges, member management (add/remove/admin toggle), leave group.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-04-26 (header + inline English translation)
///  - Add Members button navigation implemented (Bug 1)
///  - After leaving group, also pop chat screen + remove from conversation list (Bug 3)
///  - Visual distinction for Pending members (Bug 4)
///  - P0-2: Added "View safety number" entry in member options sheet (channels excluded)
///
/// @functions
///  - GroupInfoScreen: group-info ConsumerStatefulWidget
///  - _showMemberOptions(): show role-based options bottom sheet on member tap
///  - _showEditNameDialog(): group-name edit dialog
///  - _confirmLeaveGroup(): leave-group confirmation dialog
///  - _roleLabel(): return member-role text
///  - _roleBadge(): return member-role icon widget

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../channels/providers/channel_provider.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../providers/group_detail_provider.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  String get _myId => ref.read(currentSnowIdProvider) ?? '';
  StreamSubscription<Map<String, dynamic>>? _memberRemovedSub;
  StreamSubscription<Map<String, dynamic>>? _groupUpdatedSub;
  StreamSubscription<Map<String, dynamic>>? _inviteRejectedSub;
  StreamSubscription<Map<String, dynamic>>? _memberAddedSub;
  StreamSubscription<Map<String, dynamic>>? _ownerChangedSub;
  StreamSubscription<Map<String, dynamic>>? _groupDeletedSub;

  @override
  void initState() {
    super.initState();
    // Auto-refresh member list on socket events
    final sm = ref.read(socketManagerProvider);
    _memberRemovedSub = sm.onGroupMemberRemoved.listen((data) {
      if (data['groupChatId'] == widget.groupId) {
        ref.read(groupDetailProvider(widget.groupId).notifier).loadGroup();
      }
    });
    _groupUpdatedSub = sm.onGroupUpdated.listen((data) {
      if (data['groupChatId'] == widget.groupId) {
        ref.read(groupDetailProvider(widget.groupId).notifier).loadGroup();
      }
    });
    // When an invited member declines, the server emits group_invite_rejected
    // (no group_member_removed for the rejecter). Without this listener the
    // member list stayed stuck on the original member roster.
    _inviteRejectedSub = sm.onGroupInviteRejected.listen((data) {
      if (data['groupId'] == widget.groupId) {
        ref.read(groupDetailProvider(widget.groupId).notifier).loadGroup();
      }
    });
    // New members joining (addMembers / acceptInvite) — same reasoning.
    _memberAddedSub = sm.onGroupMemberAdded.listen((data) {
      if (data['groupChatId'] == widget.groupId) {
        ref.read(groupDetailProvider(widget.groupId).notifier).loadGroup();
      }
    });
    // Ownership transferred — reload to update crown badge.
    _ownerChangedSub = sm.onGroupOwnerChanged.listen((data) {
      if (data['groupChatId'] == widget.groupId) {
        ref.read(groupDetailProvider(widget.groupId).notifier).loadGroup();
      }
    });

    // Auto-pop when group is deleted by owner (room blown up)
    _groupDeletedSub = sm.onChatDeleted.listen((data) {
      final deletedId = (data['conversationId'] ?? data['groupChatId']) as String?;
      if (deletedId == widget.groupId && mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This group has been deleted')),
        );
      }
    });

    // Refresh on every screen open — provider may be cached with stale member data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(groupDetailProvider(widget.groupId).notifier).loadGroup();
      }
    });
  }

  @override
  void dispose() {
    _memberRemovedSub?.cancel();
    _groupUpdatedSub?.cancel();
    _inviteRejectedSub?.cancel();
    _memberAddedSub?.cancel();
    _ownerChangedSub?.cancel();
    _groupDeletedSub?.cancel();
    super.dispose();
  }

  /// Determine the role label for a member.
  String _roleLabel(GroupDetail group, GroupMember member) {
    if (group.isSuperAdmin(member.userId)) return 'superadmin';
    if (member.isAdmin) return 'admin';
    return 'member';
  }

  /// Build a role badge widget (crown for superadmin, shield for admin).
  Widget? _roleBadge(GroupDetail group, GroupMember member) {
    if (group.isSuperAdmin(member.userId)) {
      return const Text(
        '\u{1F451}', // crown
        style: TextStyle(fontSize: 16),
      );
    }
    if (member.isAdmin) {
      return const Text(
        '\u{1F6E1}', // shield
        style: TextStyle(fontSize: 16),
      );
    }
    return null;
  }

  /// Detect whether [groupId] belongs to a channel room (so we can suppress
  /// the Safety Number entry — channel members may not have established a
  /// 1:1 session with each other yet).
  bool _isChannelRoom() {
    final channels = ref.read(myChannelsProvider).valueOrNull ?? [];
    for (final ch in channels) {
      for (final room in ch.rooms) {
        if (room.id == widget.groupId) return true;
      }
    }
    return false;
  }

  /// Show bottom sheet with member actions based on the viewer's role.
  void _showMemberOptions(GroupDetail group, GroupMember member) {
    final myUserId = _myId;

    // No action for self - use "Leave Group" instead
    if (member.userId == myUserId || member.snowchatId == myUserId) return;

    final iAmSuperAdmin = group.isSuperAdmin(myUserId);
    final iAmAdmin = group.isAdmin(myUserId);

    final actions = <Widget>[];

    // P0-2: View Safety Number entry — available to ALL members in
    // non-channel groups (safety review of any peer is universal).
    final isChannel = _isChannelRoom();
    if (!isChannel && member.snowchatId.isNotEmpty) {
      actions.add(
        ListTile(
          leading: const Icon(Icons.verified_user_outlined,
              color: SnowColors.textSecondary),
          title: const Text(
            'View safety number',
            style: TextStyle(color: SnowColors.textPrimary),
          ),
          onTap: () {
            Navigator.of(context).pop();
            final encodedName = Uri.encodeQueryComponent(
                member.displayName ?? member.snowchatId);
            context.push(
              '/safety/${member.snowchatId}?name=$encodedName',
            );
          },
        ),
      );
    }

    // Regular members cannot act on anyone (admin actions below).
    if (!iAmSuperAdmin && !iAmAdmin) {
      // Still show the sheet if Safety Number entry was added.
      if (actions.isEmpty) return;
      _presentMemberSheet(member, actions);
      return;
    }

    // Superadmin can toggle admin status
    if (iAmSuperAdmin) {
      final isTargetAdmin = member.isAdmin;
      actions.add(
        ListTile(
          leading: Icon(
            isTargetAdmin ? Icons.remove_moderator_rounded : Icons.shield_rounded,
            color: SnowColors.textPrimary,
          ),
          title: Text(
            isTargetAdmin ? 'Remove as Admin' : 'Make Admin',
            style: const TextStyle(color: SnowColors.textPrimary),
          ),
          onTap: () async {
            Navigator.of(context).pop();
            final success = await ref
                .read(groupDetailProvider(widget.groupId).notifier)
                .toggleAdmin(member.userId);
            if (!success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to update admin status'),
                  backgroundColor: SnowColors.error,
                ),
              );
            }
          },
        ),
      );
    }

    // Both superadmin and admin can remove members
    // (Admin cannot remove other admins — handled on server, but we skip
    //  showing the option for admin-on-admin to avoid confusion)
    final canRemove = iAmSuperAdmin || (iAmAdmin && !member.isAdmin);
    if (canRemove) {
      actions.add(
        ListTile(
          leading: const Icon(Icons.person_remove_rounded, color: SnowColors.error),
          title: const Text(
            'Remove from Group',
            style: TextStyle(color: SnowColors.error),
          ),
          onTap: () async {
            Navigator.of(context).pop();
            final success = await ref
                .read(groupDetailProvider(widget.groupId).notifier)
                .removeMember(member.userId);
            if (!success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to remove member'),
                  backgroundColor: SnowColors.error,
                ),
              );
            }
          },
        ),
      );
    }

    if (actions.isEmpty) return;
    _presentMemberSheet(member, actions);
  }

  /// Internal: present the member-action bottom sheet.
  void _presentMemberSheet(GroupMember member, List<Widget> actions) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SnowColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SnowSizes.radiusMd)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(SnowSizes.md),
              child: Text(
                member.displayName ?? member.snowchatId,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(color: SnowColors.divider, height: 1),
            ...actions,
            const SizedBox(height: SnowSizes.sm),
          ],
        ),
      ),
    );
  }

  /// Show dialog to edit the group name.
  void _showEditNameDialog(GroupDetail group) {
    String newName = group.name ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Edit Group Name',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: TextField(
          autofocus: true,
          style: const TextStyle(color: SnowColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Group name',
            hintStyle: TextStyle(color: SnowColors.textTertiary),
          ),
          controller: TextEditingController(text: group.name ?? ''),
          onChanged: (v) => newName = v.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: SnowColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final name = newName;
              Navigator.of(ctx).pop();
              if (name.isNotEmpty && mounted) {
                Future.microtask(() async {
                  final success = await ref
                      .read(groupDetailProvider(widget.groupId).notifier)
                      .updateName(name);
                  if (!success && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to update group name'),
                        backgroundColor: SnowColors.error,
                      ),
                    );
                  }
                });
              }
            },
            child: const Text('Save', style: TextStyle(color: SnowColors.primary)),
          ),
        ],
      ),
    );
  }

  /// Confirm and leave the group.
  void _confirmLeaveGroup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Leave Group',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to leave this group? You will no longer receive messages.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: SnowColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Future.microtask(() async {
                if (!mounted) return;
                final success = await ref
                    .read(groupDetailProvider(widget.groupId).notifier)
                    .leaveGroup();
                if (success && mounted) {
                  ref.read(conversationListProvider.notifier).removeConversation(widget.groupId);
                  if (mounted) context.pop(); // pop group info
                  Future.microtask(() {
                    if (context.mounted) context.pop(); // pop chat
                  });
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to leave group'), backgroundColor: SnowColors.error),
                  );
                }
              });
            },
            child: const Text('Leave', style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(groupDetailProvider(widget.groupId));
    final myUserId = _myId;
    final iAmAdmin = group.isAdmin(myUserId);

    // Fallback chain for group name:
    // 1. group.name (from server encryptedName → GMK decrypt, or plain name)
    // 2. Channel room name (from myChannelsProvider)
    // 3. Conversation title (from drift)
    // 4. 'Unnamed Group'
    String? channelRoomName;
    if (group.name == null) {
      final channels = ref.watch(myChannelsProvider).valueOrNull ?? [];
      for (final ch in channels) {
        for (final room in ch.rooms) {
          if (room.id == widget.groupId) {
            channelRoomName = room.isDefaultRoom
                ? (ch.name ?? 'Channel')
                : room.isSystemRoom
                    ? 'System'
                    : room.name;
            break;
          }
        }
        if (channelRoomName != null) break;
      }
    }
    final convTitle = ref.watch(conversationListProvider)
        .where((c) => c.groupId == widget.groupId || c.id == widget.groupId)
        .firstOrNull?.title;
    final displayName = group.name ?? channelRoomName ?? convTitle ?? 'Unnamed Group';

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Group Info'),
      ),
      body: group.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: SnowColors.primary),
            )
          : group.error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: SnowColors.error,
                      ),
                      const SizedBox(height: SnowSizes.md),
                      Text(
                        'Failed to load group info',
                        style: const TextStyle(
                          color: SnowColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: SnowSizes.sm),
                      TextButton(
                        onPressed: () => ref
                            .read(groupDetailProvider(widget.groupId).notifier)
                            .loadGroup(),
                        child: const Text(
                          'Retry',
                          style: TextStyle(color: SnowColors.primary),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  children: [
                    // --- Group avatar + name ---
                    const SizedBox(height: SnowSizes.xl),
                    Center(
                      child: SnowAvatar(
                        snowId: widget.groupId,
                        size: 80,
                        displayName: displayName,
                      ),
                    ),
                    const SizedBox(height: SnowSizes.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              color: SnowColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (iAmAdmin) ...[
                          const SizedBox(width: SnowSizes.sm),
                          GestureDetector(
                            onTap: () => _showEditNameDialog(group),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: SnowSizes.iconSm,
                              color: SnowColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: SnowSizes.xs),
                    Center(
                      child: Text(
                        group.description ?? 'Add description',
                        style: TextStyle(
                          color: group.description != null
                              ? SnowColors.textSecondary
                              : SnowColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    ),

                    const SizedBox(height: SnowSizes.xl),
                    const Divider(color: SnowColors.divider, height: 1),

                    // --- Members header ---
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SnowSizes.md,
                        vertical: SnowSizes.sm,
                      ),
                      child: Text(
                        'Members (${group.members.length})',
                        style: const TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    // --- Add Members (admin only) ---
                    if (iAmAdmin)
                      ListTile(
                        leading: Container(
                          width: SnowSizes.avatarMd,
                          height: SnowSizes.avatarMd,
                          decoration: BoxDecoration(
                            color: SnowColors.primary.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_add_rounded,
                            color: SnowColors.primary,
                            size: SnowSizes.iconMd,
                          ),
                        ),
                        title: const Text(
                          'Add Members',
                          style: TextStyle(
                            color: SnowColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onTap: () async {
                          final existingSnowchatIds = group.members
                              .map((m) => m.snowchatId)
                              .toList();
                          await context.push(
                            '/add-group-members/${widget.groupId}',
                            extra: existingSnowchatIds,
                          );
                          // Refresh group detail after returning
                          ref
                              .read(groupDetailProvider(widget.groupId).notifier)
                              .loadGroup();
                        },
                      ),

                    // --- Member list ---
                    ...group.members.map((member) {
                      final badge = _roleBadge(group, member);
                      final role = _roleLabel(group, member);
                      return ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (badge != null) ...[
                              badge,
                              const SizedBox(width: SnowSizes.xs),
                            ],
                            SnowAvatar(
                              snowId: member.snowchatId,
                              size: SnowSizes.avatarMd,
                              displayName: member.displayName,
                            ),
                          ],
                        ),
                        title: Text(
                          member.displayName ?? member.snowchatId,
                          style: TextStyle(
                            color: member.status == 'pending'
                                ? SnowColors.textTertiary
                                : SnowColors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (member.status == 'pending')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: SnowColors.textTertiary
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Pending',
                                  style: TextStyle(
                                    color: SnowColors.textTertiary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            if (member.status == 'pending' &&
                                role != 'member')
                              const SizedBox(width: 6),
                            if (role != 'member')
                              Text(
                                role,
                                style: const TextStyle(
                                  color: SnowColors.textTertiary,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        onTap: () => _showMemberOptions(group, member),
                      );
                    }),

                    // Leave Group moved to chat screen popup menu (Phase 11)
                    const SizedBox(height: SnowSizes.xl),
                  ],
                ),
    );
  }
}
