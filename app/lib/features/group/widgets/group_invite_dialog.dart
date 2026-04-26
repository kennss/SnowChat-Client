/// @file        group_invite_dialog.dart
/// @description Group invite accept/reject dialog widget. Shows invite info and handles API calls.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - GroupInviteDialog: ConsumerWidget showing group-invite info and accept/reject buttons
///  - _accept(): call accept-invite API and refresh conversation list
///  - _reject(): call reject-invite API

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart' show routerProvider;
import '../../../core/network/api_endpoints.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../chat/providers/conversation_list_provider.dart';

/// Modal dialog that displays group invite information and provides
/// accept/reject actions. Expects [inviteData] with keys:
/// { groupId, groupName, invitedBy: { snowchatId, displayName }, invitedAt, memberCount }
class GroupInviteDialog extends ConsumerWidget {
  final Map<String, dynamic> inviteData;

  const GroupInviteDialog({super.key, required this.inviteData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupName = inviteData['groupName'] as String? ?? 'Group';
    final inviter = inviteData['invitedBy'] as Map?;
    final inviterName = inviter?['displayName'] as String? ?? 'Someone';
    final memberCount = inviteData['memberCount'] as int? ?? 0;
    final groupId = inviteData['groupId'] as String;
    final autoJoined = inviteData['autoJoined'] as bool? ?? false;

    return AlertDialog(
      backgroundColor: SnowColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        autoJoined ? 'Added to Group' : 'Group Invitation',
        style: const TextStyle(color: SnowColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SnowAvatar(snowId: groupId, size: 64, displayName: groupName),
          const SizedBox(height: 16),
          Text(
            groupName,
            style: const TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$memberCount members',
            style: const TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            autoJoined
                ? '$inviterName added you to this group'
                : '$inviterName invited you',
            style: const TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
      actions: [
        // Reject — for both auto-joined and pending invites the user can
        // decline. Server (rejectInvite) handles the status='accepted' case
        // by transitioning to 'rejected' and bumping senderKeyEpoch.
        TextButton(
          onPressed: () => _reject(context, ref, groupId),
          child: const Text(
            'Reject',
            style: TextStyle(color: SnowColors.error),
          ),
        ),
        // Accept — autoJoined case opens the chat immediately; pending case
        // calls the accept endpoint first then opens.
        ElevatedButton(
          onPressed: () => autoJoined
              ? _openGroup(context, ref, groupId)
              : _accept(context, ref, groupId),
          style: ElevatedButton.styleFrom(backgroundColor: SnowColors.primary),
          child: const Text(
            'Accept',
            style: TextStyle(color: SnowColors.background),
          ),
        ),
      ],
    );
  }

  void _openGroup(BuildContext context, WidgetRef ref, String groupId) {
    // Resolve GoRouter through Riverpod (NOT GoRouter.of(context)). The
    // dialog is rendered inside an Overlay which doesn't reliably propagate
    // InheritedGoRouter, so context-based lookups silently throw an
    // assertion and abort the whole handler — that's why the previous
    // attempts left the dialog hanging on the screen with no response.
    final router = ref.read(routerProvider);
    Navigator.of(context).pop();
    // ignore: unused_result
    ref.read(conversationListProvider.notifier).refresh();
    router.push('/chat/$groupId');
  }

  void _accept(BuildContext context, WidgetRef ref, String groupId) async {
    final router = ref.read(routerProvider);
    Navigator.of(context).pop();
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.groupInviteAccept(groupId));
      // ignore: unused_result
      ref.read(conversationListProvider.notifier).refresh();
      router.push('/chat/$groupId');
    } catch (e) {
      debugPrint('[GroupInvite] Accept failed: $e');
    }
  }

  void _reject(BuildContext context, WidgetRef ref, String groupId) async {
    Navigator.of(context).pop();
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post(ApiEndpoints.groupInviteReject(groupId));
      // Drop the (auto-joined) group from the in-memory list immediately
      // so the rejecter doesn't see it lingering in their conversation
      // list. The server-side query already filters status='rejected' out.
      // ignore: unused_result
      ref.read(conversationListProvider.notifier).refresh();
    } catch (e) {
      debugPrint('[GroupInvite] Reject failed: $e');
    }
  }
}
