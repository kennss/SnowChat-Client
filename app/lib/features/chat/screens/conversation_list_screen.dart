/// @file        conversation_list_screen.dart
/// @description Conversation-list screen — group protocol v2 invites, Group Chats (v2 groups) and Direct Messages (1:1)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-20 (v1 groups removed: no community section — communities have no rooms and live in the Community tab — no v1 invite dialog or rejection toast; the Group Chats section lists every group). Earlier same day (group protocol v2: the invites into v2 groups that wait for an answer are listed above the chats — Gv2InviteTile). Earlier 2026-08-07 (one-shot launch prompt for the Android 14+ USE_FULL_SCREEN_INTENT permission via CallPermissionHelper.maybePromptOnLaunch — without the grant a locked-screen incoming call is downgraded from the full-screen call UI to a heads-up notification the user must tap; guarded by a static once-flag so tab re-mounts don't re-run it). Earlier 2026-08-05 (single-room communities flatten: a community whose only visible room is the default room now taps straight into that room's chat — no expand arrow, no room sublist — hiding the alien community→rooms nesting; admins with a System room / future multi-room keep the accordion. "Channel"→"Community" strings). Earlier 2026-04-26 (header + inline English translation; 2026-04-08 independent group section)
///
/// @functions
///  - ConversationListScreen: v2 group invites + Group Chats + Direct Messages sections
///  - _buildGroupSection(): the v2 groups
///  - _buildDmSection(): show 1:1 DMs as an independent section
///  - _buildGv2InviteSection(): the v2 group invites waiting for an answer

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/deeplink_handler.dart';
import '../../../app/providers.dart';
import '../../../core/call/call_permission_helper.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../group/providers/gv2_group_provider.dart';
import '../../group/widgets/gv2_invite_tile.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainPendingDeeplink();
      _maybePromptCallPermission();
    });

    // Auto background-download AI model (on WiFi) + auto-init when model is installed
    _initAI();
  }

  // One-shot per app process — prompt for the Android 14+ full-screen-intent
  // permission so locked-screen incoming calls show full-screen instead of a
  // heads-up notification. Guarded so tab switches (which re-mount this screen)
  // don't re-run it; the helper no-ops when already granted or dismissed.
  static bool _callPermissionChecked = false;
  Future<void> _maybePromptCallPermission() async {
    if (_callPermissionChecked) return;
    _callPermissionChecked = true;
    if (!mounted) return;
    await CallPermissionHelper.maybePromptOnLaunch(
      context,
      ref.read(secureStorageProvider),
    );
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

  /// Phase 1 deeplink: if app launched FROM a SnowChat deeplink
  /// (snowchat://invite/<code> or snowchat://user/<id>) while not yet onboarded
  /// (or pre-router race), DeeplinkHandler queued the resolved internal path.
  /// Drain on /chat mount — this is the first stable post-onboarding screen.
  void _drainPendingDeeplink() {
    final path = DeeplinkHandler.instance.consumePending();
    if (path != null && mounted) {
      context.push(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationListProvider);
    final gv2Invites = ref.watch(gv2InvitesProvider);

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
      body: conversations.isEmpty && gv2Invites.isEmpty
          ? _buildEmptyState(context)
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(conversationListProvider.notifier).refresh(),
              color: SnowColors.primary,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: SnowSizes.sm),
                children: [
                  // ── SnowChat AI ── (pinned at top)
                  const AiChatTile(),
                  const Divider(color: SnowColors.divider, height: 1),

                  // ── Group invites ── (group protocol v2: waiting for an
                  // answer)
                  ..._buildGv2InviteSection(gv2Invites),

                  // ── Group Chats ── section
                  ..._buildGroupSection(conversations),

                  // ── Direct Messages ── section
                  ..._buildDmSection(conversations),
                ],
              ),
            ),
    );
  }

  /// The invites into group protocol v2 groups that wait for this account's
  /// answer. Accepting opens the group's chat.
  List<Widget> _buildGv2InviteSection(List<Gv2InviteView> invites) {
    if (invites.isEmpty) return [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SnowSizes.md, vertical: 10),
        child: Row(
          children: [
            Container(width: 24, height: 1, color: SnowColors.divider),
            const SizedBox(width: 8),
            const Text(
              'Group Invites',
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
      for (final invite in invites)
        Gv2InviteTile(
          key: ValueKey('gv2-invite-${invite.groupId}'),
          invite: invite,
          onAccepted: (groupId) async {
            await ref
                .read(conversationListProvider.notifier)
                .syncGv2Group(groupId);
            if (mounted) context.push('/chat/$groupId');
          },
        ),
    ];
  }

  /// Render the "Group Chats" section: the group protocol v2 groups.
  List<Widget> _buildGroupSection(List<Conversation> conversations) {
    final groups = conversations
        .where((c) => c.type == ConversationType.group)
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
