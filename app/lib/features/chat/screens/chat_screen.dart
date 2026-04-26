/// @file        chat_screen.dart
/// @description Chat screen (1:1 + group) — message list, message input/send, typing indicator, expiring messages, read receipts, online status, reply/quote, message deletion, link preview, group AppBar mode (tap -> group info screen), system-message display, Send Asset (Wallet V2 Phase F, 1:1 only)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-20 Wallet V2 Phase F: + menu -> Send Asset option (1:1 only) -> TransferRequestScreen)
///
/// @functions
///  - ChatScreen: chat-screen ConsumerStatefulWidget
///  - _ttlDisplayLabel(): convert TTL value to an AppBar display label
///  - _showContextMenu(): message context menu (reply, copy, delete)
///  - _scrollToMessage(): scroll to the original message on reply-quote tap
///  - _confirmDeleteChat(): "Delete chat" confirmation dialog (local-only deletion)
///  - _confirmBlockContact(): "Block contact" confirmation dialog (server block + local deletion)
///  - _handleSendAsset(): Wallet V2 Phase F — enter 1:1 chat transfer screen (TransferRequestScreen)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/network/link_preview_service.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../channels/providers/channel_provider.dart';
import '../../call/screens/voip_policy_dialog.dart';
import '../../contacts/contact_provider.dart';
import '../../../shared/widgets/snowflake_background.dart';
import '../providers/chat_provider.dart';
import '../providers/conversation_list_provider.dart';
import '../providers/mark_read_helper.dart';
import '../widgets/disappearing_timer_selector.dart';
import '../widgets/identity_change_banner.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/message_input.dart';
import '../widgets/message_timer_badge.dart';
import '../widgets/reply_preview_bar.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/attachment_picker_sheet.dart';
import '../widgets/system_message_bubble.dart';
import '../models/message.dart';
import '../models/conversation.dart';
import '../../wallet/screens/transfer_request_screen.dart';
import '../../ai/providers/ai_provider.dart';
import '../../ai/providers/translation_provider.dart';
import '../../ai/service/conversation_summarizer.dart';
import '../../ai/service/supported_languages.dart';
import '../widgets/summary_sheet.dart';
import '../../group/providers/group_detail_provider.dart';
import '../../settings/settings_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  late final MarkReadHelper _markReadHelper;
  StreamSubscription<Map<String, dynamic>>? _groupDeletedSub;
  StreamSubscription<Map<String, dynamic>>? _channelOwnerChangedSub;

  /// P0-2: in-memory dismissal of the IdentityChangeBanner. Reset every
  /// time the user navigates back into the chat screen (StatefulWidget
  /// dispose).
  bool _identityBannerDismissed = false;

  String get _myId => ref.read(currentSnowIdProvider) ?? '';

  /// Shared link preview service instance for this chat screen.
  final _linkPreviewService = LinkPreviewService();

  @override
  void initState() {
    super.initState();

    // Phase 2: MarkReadHelper — drift DB SSoT for unread tracking
    _markReadHelper = MarkReadHelper(
      conversationId: widget.conversationId,
      messageDao: ref.read(messageDaoProvider),
      socketManager: ref.read(socketManagerProvider),
      expiringManager: ref.read(expiringMessageManagerProvider),
      myId: ref.read(currentSnowIdProvider) ?? '',
      onMarkedRead: (_) {
        // Reset in-memory unread count when drift marks messages as read
        if (mounted) {
          ref
              .read(conversationListProvider.notifier)
              .markAsRead(widget.conversationId);
        }
      },
    );
    _markReadHelper.activate();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushServiceProvider).setActiveConversation(widget.conversationId);
      // Mark all messages as read on chat entry
      _markReadHelper.markAllVisibleAsRead();
      // Phase 5.6: Refresh messages from server every time user enters the chat.
      // ChatNotifier persists across navigation (Riverpod), so _loadMessages
      // only runs at first entry. Without this, missed messages (sent while
      // user was in another app or chat) are never fetched.
      ref.read(chatProvider(widget.conversationId).notifier).refresh();
    });

    final sm = ref.read(socketManagerProvider);

    // Reload group detail when channel ownership changes (badge update)
    _channelOwnerChangedSub = sm.onChannelOwnerChanged.listen((data) {
      final convs = ref.read(conversationListProvider);
      final conv = convs.where((c) => c.id == widget.conversationId).firstOrNull;
      if (conv?.channelId != null) {
        final groupId = conv?.groupId ?? widget.conversationId;
        ref.read(groupDetailProvider(groupId).notifier).loadGroup();
      }
    });

    // Auto-pop when group is deleted by owner (room demolition)
    _groupDeletedSub = sm.onChatDeleted.listen((data) {
      final deletedId = (data['conversationId'] ?? data['groupChatId']) as String?;
      if (deletedId == null) return;
      final convs = ref.read(conversationListProvider);
      final conv = convs.where((c) => c.id == widget.conversationId).firstOrNull;
      if (deletedId == widget.conversationId ||
          deletedId == conv?.groupId) {
        if (mounted) {
          context.pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This group has been deleted')),
          );
        }
      }
    });
  }

  @override
  void deactivate() {
    ref.read(pushServiceProvider).setActiveConversation(null);
    // Ensure in-memory unread count is zeroed when leaving chat.
    // Must use addPostFrameCallback — Riverpod forbids provider mutation
    // during widget lifecycle (deactivate/dispose) AND during build phase.
    // addPostFrameCallback runs after the frame completes, so all builds
    // are done and state notification is safe.
    final notifier = ref.read(conversationListProvider.notifier);
    final convId = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifier.markAsRead(convId);
    });
    super.deactivate();
  }

  @override
  void dispose() {
    _groupDeletedSub?.cancel();
    _channelOwnerChangedSub?.cancel();
    _markReadHelper.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // reverse: true → position 0.0 is the bottom (newest messages)
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scroll to a specific message by ID (for reply quote tap).
  void _scrollToMessage(String messageId) {
    final chatState = ref.read(chatProvider(widget.conversationId));
    final index = chatState.messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || !_scrollController.hasClients) return;

    // reverse: true → older messages are at higher scroll offsets
    final reverseIndex = chatState.messages.length - 1 - index;
    final estimatedOffset = reverseIndex * 60.0;
    _scrollController.animateTo(
      estimatedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _showAttachmentSheet() {
    // Wallet V2 Phase F: Send Asset option is shown only in 1:1 rooms (V1 limit).
    final conversations = ref.read(conversationListProvider);
    final conversation = conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final isDirect1to1 = conversation?.type == ConversationType.direct;
    final peerSnowId = isDirect1to1
        ? (conversation?.otherParticipant(_myId) ?? '')
        : '';

    showModalBottomSheet(
      context: context,
      backgroundColor: SnowColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => AttachmentPickerSheet(
        onImagesSelected: (paths) async {
          final notifier =
              ref.read(chatProvider(widget.conversationId).notifier);
          if (paths.length == 1) {
            notifier.sendFileMessage(
              filePath: paths.first,
              fileName: paths.first.split('/').last,
              mimeType: 'image/jpeg',
            );
          } else {
            for (final path in paths) {
              await notifier.sendFileMessage(
                filePath: path,
                fileName: path.split('/').last,
                mimeType: 'image/jpeg',
              );
            }
          }
        },
        onFileSelected: (path, name, mimeType) {
          ref
              .read(chatProvider(widget.conversationId).notifier)
              .sendFileMessage(
                filePath: path,
                fileName: name,
                mimeType: mimeType ?? 'application/octet-stream',
              );
        },
        onAddFriend: () => _handleAddFriend(),
        onSendAsset: (isDirect1to1 && peerSnowId.isNotEmpty)
            ? () => _handleSendAsset(
                  peerSnowId: peerSnowId,
                  conversation: conversation,
                )
            : null,
      ),
    );
  }

  /// Wallet V2 Phase F — enter the 1:1 chat transfer screen.
  ///
  /// **Flow**:
  /// 1. Resolve peer displayName (contact cache -> conversation.displayName -> snow ID)
  /// 2. Push TransferRequestScreen (rootNavigator) — that screen calls
  ///    transferServiceProvider.sendRequest directly + SnackBar feedback.
  /// 3. This chat_screen just navigates — no result handling here.
  Future<void> _handleSendAsset({
    required String peerSnowId,
    required Conversation? conversation,
  }) async {
    // displayName resolution (same priority as chat header).
    final contacts = ref.read(contactProvider);
    final contact =
        contacts.where((c) => c.snowChatId == peerSnowId).firstOrNull;
    final displayName = (contact?.displayName?.isNotEmpty ?? false)
        ? contact!.displayName!
        : (conversation?.displayName(_myId) ??
            (peerSnowId.length > 12
                ? '${peerSnowId.substring(0, 8)}...${peerSnowId.substring(peerSnowId.length - 4)}'
                : peerSnowId));

    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => TransferRequestScreen(
          recipientSnowchatId: peerSnowId,
          recipientDisplayName: displayName,
        ),
      ),
    );
  }

  /// Phase 9.1: Add friend(s) from the current chat room.
  /// - 1:1: directly send friend request to the other participant.
  /// - Group: show member list → user picks → batch friend request.
  Future<void> _handleAddFriend() async {
    final conversations = ref.read(conversationListProvider);
    final conversation = conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final isDirect = conversation?.type == ConversationType.direct;

    if (isDirect) {
      // 1:1 chat: send friend request to the other participant
      final otherSnowId = conversation?.otherParticipant(_myId) ?? '';
      if (otherSnowId.isEmpty) return;
      final result =
          await ref.read(friendActionsProvider).addFriend(otherSnowId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result == 'pending'
              ? 'Friend request sent!'
              : result == 'already_friend'
                  ? 'Already friends!'
                  : 'Could not send friend request.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } else {
      // Group chat: show member picker
      await _showGroupFriendPicker();
    }
  }

  /// Show a multi-select dialog of group members for friend requests.
  Future<void> _showGroupFriendPicker() async {
    final groupId = ref.read(conversationListProvider)
        .where((c) => c.id == widget.conversationId)
        .firstOrNull
        ?.groupId ?? widget.conversationId;

    // Fetch group members from server
    final apiClient = ref.read(apiClientProvider);
    Map<String, dynamic> data;
    try {
      final res = await apiClient.get('/groups/$groupId');
      data = Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to load members.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final members = (data['members'] as List?)
            ?.map((m) => Map<String, dynamic>.from(m as Map))
            .where((m) => (m['snowchatId'] as String?) != _myId)
            .toList() ??
        [];

    if (members.isEmpty || !mounted) return;

    final selected = <String>{};

    await showModalBottomSheet(
      context: context,
      backgroundColor: SnowColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Add Friends',
                    style: TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ...members.map((m) {
                  final snowId = m['snowchatId'] as String;
                  final name = m['displayName'] as String? ?? snowId.substring(0, 12);
                  final isSelected = selected.contains(snowId);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (v) => setSheetState(() {
                      if (v == true) {
                        selected.add(snowId);
                      } else {
                        selected.remove(snowId);
                      }
                    }),
                    title: Text(name,
                        style: const TextStyle(color: SnowColors.textPrimary)),
                    subtitle: Text(snowId.substring(0, 16),
                        style: const TextStyle(
                            color: SnowColors.textTertiary, fontSize: 12)),
                    activeColor: SnowColors.primary,
                    checkColor: SnowColors.background,
                  );
                }),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(sheetContext),
                      child: Text('Add ${selected.length} Friend(s)'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Send friend requests
    if (selected.isNotEmpty && mounted) {
      var sentOk = 0;
      for (final snowId in selected) {
        final result =
            await ref.read(friendActionsProvider).addFriend(snowId);
        if (result == 'pending' || result == 'already_friend') sentOk++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$sentOk friend request(s) sent!'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _sendMessage(String text) {
    final notifier = ref.read(chatProvider(widget.conversationId).notifier);
    notifier.sendMessage(text);
    notifier.onUserStoppedTyping();
    // Update preview only (no unreadCount increment for own messages).
    // Pass recipientId so a new conversation entry is created for the sender.
    ref.read(conversationListProvider.notifier).updatePreview(
      widget.conversationId,
      text: text,
      senderId: _myId,
      messageTime: DateTime.now(),
      recipientId: notifier.recipientId,
    );
    _scrollToBottom();
  }

  /// Mark incoming messages as read when the chat is visible.
  /// Now delegated to MarkReadHelper which writes directly to drift DB.
  void _markAsRead() {
    _markReadHelper.markAllVisibleAsRead();
  }

  /// Show context menu on long press of a message.
  Future<void> _showContextMenu(Message message, bool isMine) async {
    final action = await showMessageContextMenu(
      context,
      message: message,
      isMine: isMine,
    );
    if (action == null || !mounted) return;

    final notifier = ref.read(chatProvider(widget.conversationId).notifier);

    switch (action) {
      case MessageAction.reply:
        notifier.setReplyTo(message);
        break;
      case MessageAction.copy:
        // Already copied in the context menu widget
        break;
      case MessageAction.deleteForMe:
        notifier.deleteMessageForMe(message.id);
        break;
      case MessageAction.deleteForEveryone:
        await notifier.deleteMessageForEveryone(message.id);
        break;
    }
  }

  /// Leave Group dialog.
  /// - Owner: warns about ownership transfer, single "Leave" button.
  /// - Non-owner: two choices — "Leave" or "Leave and delete my messages".
  void _confirmLeaveGroup({required bool isCreator}) {
    final description = isCreator
        ? 'Ownership will be transferred to the next oldest member. '
          'You will leave this group.'
        : 'You can leave the group, or leave and delete all your '
          'messages for everyone.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Leave group',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: Text(
          description,
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SnowColors.textSecondary),
            ),
          ),
          // Non-owner only: "Leave and delete my messages"
          if (!isCreator)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _executeLeaveAndDelete();
              },
              child: const Text(
                'Leave and delete',
                style: TextStyle(color: SnowColors.error),
              ),
            ),
          // Both owner and non-owner: simple "Leave"
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeLeave();
            },
            child: const Text(
              'Leave',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Execute simple leave (no message deletion).
  void _executeLeave() {
    Future.microtask(() async {
      if (!mounted) return;
      await ref
          .read(chatProvider(widget.conversationId).notifier)
          .leaveGroup();
      if (!mounted) return;
      ref
          .read(conversationListProvider.notifier)
          .removeConversation(widget.conversationId);
      if (mounted) context.pop();
    });
  }

  /// Execute leave + batch-delete own messages for everyone.
  void _executeLeaveAndDelete() {
    Future.microtask(() async {
      if (!mounted) return;
      await ref
          .read(chatProvider(widget.conversationId).notifier)
          .leaveAndDeleteMyMessages();
      if (!mounted) return;
      ref
          .read(conversationListProvider.notifier)
          .removeConversation(widget.conversationId);
      if (mounted) context.pop();
    });
  }

  /// Phase 11 + Vuln 3 (Stage 3): Clear Chat dialog.
  ///
  /// [localOnly] true → regular group member: skip server call, clean up local only.
  /// [localOnly] false → 1:1 or group admin/owner: existing server fan-out path.
  void _confirmClearChat({bool localOnly = false}) {
    final title = localOnly ? 'Clear locally only' : 'Clear chat';
    final body = localOnly
        ? 'Messages will be removed from your device only. '
            'Other members of this group will still see them.'
        : 'All messages will be removed from this chat. '
            'The chat itself will remain in your list.';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: Text(
          title,
          style: const TextStyle(color: SnowColors.textPrimary),
        ),
        content: Text(
          body,
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SnowColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Future.microtask(() async {
                if (!mounted) return;
                final notifier = ref
                    .read(chatProvider(widget.conversationId).notifier);
                if (localOnly) {
                  // Local-only path is silent on failure (drift only).
                  await notifier.clearChatLocally();
                  if (!mounted) return;
                  ref
                      .read(conversationListProvider.notifier)
                      .clearPreview(widget.conversationId);
                  return;
                }
                // P1-2: server-side clearChat now rethrows on failure (403,
                // 401, network). Surface a SnackBar and skip local wipe so
                // cross-device state stays consistent. The user can pick
                // "Clear locally only" from the same menu if they really
                // want to drop their local copy.
                try {
                  await notifier.clearChat();
                  if (!mounted) return;
                  ref
                      .read(conversationListProvider.notifier)
                      .clearPreview(widget.conversationId);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: SnowColors.error,
                      duration: const Duration(seconds: 4),
                      content: Text(
                        'Could not clear chat on the server (${_friendlyClearChatError(e)}). '
                        'Local messages were kept to stay in sync with your other devices. '
                        'Use "Clear locally only" if you really want to drop your local copy.',
                      ),
                    ),
                  );
                }
              });
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// P1-2: short human label for the SnackBar after a server clearChat error.
  /// Maps Dio 403 → "permission", 401 → "auth", anything else → "network".
  String _friendlyClearChatError(Object e) {
    final s = e.toString();
    if (s.contains('403')) return 'permission';
    if (s.contains('401')) return 'auth';
    if (s.contains('SocketException') || s.contains('TimeoutException')) {
      return 'offline';
    }
    return 'network';
  }

  /// Delete Chat — 1:1 only.
  /// Removes conversation + messages for both sides.
  void _confirmDeleteChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Delete chat',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'Messages and media in this chat will be removed. '
          'The other person will also lose this conversation.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SnowColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Future.microtask(() async {
                if (!mounted) return;
                // P2: for 1:1 also clean up TOFU pin + Safety Number verification row.
                final conv = ref
                    .read(conversationListProvider)
                    .where((c) => c.id == widget.conversationId)
                    .firstOrNull;
                final peer = (conv?.type == ConversationType.direct)
                    ? conv?.otherParticipant(_myId)
                    : null;
                await ref
                    .read(chatProvider(widget.conversationId).notifier)
                    .deleteChat();
                if (peer != null && peer.isNotEmpty) {
                  try {
                    await ref.read(identityPinStoreProvider).unpin(peer);
                    await ref
                        .read(identityVerificationDaoProvider)
                        .deleteByPeer(peer);
                  } catch (e) {
                    debugPrint('[ChatScreen] purge identity state failed: $e');
                  }
                }
                if (!mounted) return;
                ref
                    .read(conversationListProvider.notifier)
                    .removeConversation(widget.conversationId);
                if (mounted) context.pop();
              });
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete Group (room demolition) — owner only.
  /// Permanently destroys the group for all members.
  void _confirmDeleteGroup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Delete group',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'This will permanently delete the group, all messages, '
          'and remove all members. This cannot be undone.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SnowColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Future.microtask(() async {
                if (!mounted) return;
                await ref
                    .read(chatProvider(widget.conversationId).notifier)
                    .deleteGroup();
                if (!mounted) return;
                ref
                    .read(conversationListProvider.notifier)
                    .removeConversation(widget.conversationId);
                if (mounted) context.pop();
              });
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Block a 1:1 contact. Server stops delivering messages from the blocker
  /// to us. The peer is NOT notified that they have been blocked. The chat
  /// is also deleted locally so the user doesn't see the contact anymore.
  void _confirmBlockContact(String snowchatId) {
    if (snowchatId.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Block contact',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'Blocked contacts can no longer send you messages. They will not be '
          'notified that you blocked them. This chat will also be removed from '
          'this device.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SnowColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Future.microtask(() async {
                if (!mounted) return;
                // 1. Block on the server (idempotent)
                ref.read(contactProvider.notifier).blockContact(snowchatId);
                // 2. Local chat cleanup
                await ref
                    .read(chatProvider(widget.conversationId).notifier)
                    .deleteChat();
                if (!mounted) return;
                ref
                    .read(conversationListProvider.notifier)
                    .removeConversation(widget.conversationId);
                if (mounted) context.pop();
              });
            },
            child: const Text(
              'Block',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showTimerSelector() async {
    final notifier = ref.read(chatProvider(widget.conversationId).notifier);
    final currentTtl = ref.read(chatProvider(widget.conversationId)).disappearingTTL;
    final selected = await showDisappearingTimerSelector(
      context,
      currentTtl: currentTtl,
    );
    if (mounted) {
      notifier.setDisappearingTimer(selected);
    }
  }

  /// Resolve channel room title: default room → channel name, system → "System", else room name.
  String _resolveChannelRoomTitle(WidgetRef ref, String roomId) {
    final channels = ref.watch(myChannelsProvider).valueOrNull ?? [];
    for (final channel in channels) {
      for (final room in channel.rooms) {
        if (room.id == roomId) {
          if (room.isDefaultRoom) return channel.name ?? 'Channel';
          if (room.isSystemRoom) return 'System';
          return room.name;
        }
      }
    }
    return 'Chat';
  }

  static String? _ttlDisplayLabel(int? ttl) {
    if (ttl == null) return null;
    if (ttl <= 300) return '5m';
    if (ttl <= 1800) return '30m';
    return '1h';
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider(widget.conversationId));
    debugPrint('[ChatScreen:build] conversationId=${widget.conversationId} messages=${chatState.messages.length}');
    final conversations = ref.watch(conversationListProvider);
    final conversation = conversations
        .where((c) => c.id == widget.conversationId)
        .firstOrNull;

    final isChannelRoom = (conversation?.channelId != null) ||
        (conversation == null &&
            _resolveChannelRoomTitle(ref, widget.conversationId) != 'Chat');
    final isGroupChat =
        conversation?.type == ConversationType.group || isChannelRoom;

    // Resolve title: channel rooms use channel/room name, not encrypted group title.
    String title;
    if (isChannelRoom) {
      title = _resolveChannelRoomTitle(ref, widget.conversationId);
      if (title == 'Chat') title = conversation?.title ?? 'Group';
    } else if (conversation != null) {
      title = isGroupChat
          ? (conversation.title ?? 'Group')
          : (conversation.displayName(_myId) ?? 'Chat');
    } else {
      // New conversation not yet in list — resolve recipient name from provider
      final recipientId = ref.watch(chatProvider(widget.conversationId).notifier).recipientId;
      title = (recipientId != null && recipientId.isNotEmpty)
          ? '${recipientId.substring(0, recipientId.length.clamp(0, 10))}...'
          : 'Chat';
    }
    final otherSnowId = conversation?.otherParticipant(_myId) ?? '';
    final ttlLabel = _ttlDisplayLabel(chatState.disappearingTTL);

    // Presence (only for 1:1 chats)
    final presenceService = ref.watch(presenceServiceProvider);
    final isDirect =
        conversation?.type == ConversationType.direct;
    final isOnline =
        isDirect ? presenceService.isOnline(otherSnowId) : false;

    // Owner check: needed to show "Delete Group" menu item (owner only)
    final groupId = conversation?.groupId ?? widget.conversationId;
    final isCreator = isGroupChat
        ? ref.watch(groupDetailProvider(groupId)).members.any(
            (m) => m.snowchatId == _myId && m.userId == ref.watch(groupDetailProvider(groupId)).creatorId,
          )
        : false;
    // Vuln 3 (Stage 3): Clear Chat — admin/owner only on the server side.
    // Mirror that on the client so a regular member's button does the
    // local-only purge instead of hitting the now-403 endpoint.
    // Owner = creator (role==='OWNER'); Admin = isAdmin true. Server gate is
    // `isAdmin || role==='OWNER' || role==='ADMIN'`. Client GroupMember
    // exposes only isAdmin, so reuse the pre-computed isCreator (=OWNER) to
    // cover the case where an owner has isAdmin=false.
    final isGroupAdminOrOwner = isGroupChat
        ? (isCreator ||
            ref.watch(groupDetailProvider(groupId)).members.any(
                  (m) => m.snowchatId == _myId && m.isAdmin,
                ))
        : false;
    final lastSeenText =
        isDirect && !isOnline ? presenceService.formatLastSeen(otherSnowId) : null;

    // _markAsRead() is already called in initState via addPostFrameCallback
    // Do NOT call it here in build() — causes Riverpod state modification during build

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: isGroupChat
              ? () => context.push('/group-info/${conversation?.groupId ?? widget.conversationId}')
              : null,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              SnowAvatar(
                snowId: isGroupChat ? (conversation?.groupId ?? widget.conversationId) : otherSnowId,
                size: 34,
                displayName: title,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isGroupChat)
                      const Text(
                        'Group chat',
                        style: TextStyle(
                          fontSize: 12,
                          color: SnowColors.textTertiary,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    else if (chatState.isTyping)
                      Text(
                        chatState.typingUserName != null
                            ? '${chatState.typingUserName} is typing...'
                            : 'typing...',
                        style: const TextStyle(
                          fontSize: 12,
                          color: SnowColors.primary,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    else if (isOnline)
                      const Text(
                        'Online',
                        style: TextStyle(
                          fontSize: 12,
                          color: SnowColors.primary,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    else if (lastSeenText != null)
                      Text(
                        lastSeenText,
                        style: const TextStyle(
                          fontSize: 11,
                          color: SnowColors.textTertiary,
                          fontWeight: FontWeight.w400,
                        ),
                      )
                    else if (ttlLabel != null)
                      Text(
                        'Messages disappear after $ttlLabel',
                        style: const TextStyle(
                          fontSize: 11,
                          color: SnowColors.textTertiary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // AI summary icon (on-device, Zero-Knowledge)
          _buildSummaryIcon(chatState.messages),
          // Translation icon + native-character badge (i18n-safe, in place of a flag)
          _buildTranslateIcon(conversation),
          // Phase 8.2 VoIP: 1:1 voice call (group deferred to V3 — §19.4)
          if (!isGroupChat && otherSnowId.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.call_rounded,
                color: SnowColors.textSecondary,
                size: 22,
              ),
              tooltip: 'E2EE Voice Call',
              onPressed: () async {
                // Zero-Trace policy dialog on first call (§23.6)
                await VoipPolicyDialog.showIfNeeded(context);
                if (!context.mounted) return;
                final notifier = ref.read(callProvider.notifier);
                // Phase F: apply user-setting Always Relay. OR'd across both
                // sides — if either is true, both ends are forced through TURN.
                final alwaysRelay =
                    ref.read(settingsProvider).callAlwaysRelay;
                // Own displayName — attached to the call_invite payload so the
                // recipient UI / system toast shows it as the caller name.
                final myDisplayName =
                    ref.read(currentDisplayNameProvider);
                // Peer displayName resolution priority (Galaxy nickname-not-shown fix):
                //   1. contactProvider — server /users synced directory (most trusted)
                //   2. conversation.title (= title) — _resolveSenderDisplayName
                //      only updated in-memory and didn't persist to drift → regressed
                //      to null after restart. iPhone calls happened to have title
                //      populated so it was OK, but Android fell back to a truncated
                //      snow ID after restart/reload.
                //   3. truncated snow ID (title) — last-ditch fallback
                final contacts = ref.read(contactProvider);
                final recipient = contacts
                    .where((c) => c.snowChatId == otherSnowId)
                    .firstOrNull;
                final recipientName =
                    (recipient?.displayName?.isNotEmpty ?? false)
                        ? recipient!.displayName
                        : title;
                try {
                  // /call navigation is handled by app.dart's ref.listen<CallState>
                  // immediately on state=outgoing transition. Here we fire-and-
                  // forget without await — during startCall()'s WebRTC setup
                  // (~3-5s) the UI shows OutgoingCallScreen instantly. The
                  // previous await pattern caused a 5-6s UI lag because
                  // navigation only happened after setup completed.
                  unawaited(notifier.startCall(
                    recipientSnowchatId: otherSnowId,
                    alwaysRelay: alwaysRelay,
                    remoteDisplayName: recipientName,
                    senderDisplayName: myDisplayName,
                  ).catchError((Object e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to start call: $e')),
                      );
                    }
                  }));
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to start call: $e')),
                    );
                  }
                }
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            color: SnowColors.surface,
            onSelected: (value) {
              switch (value) {
                case 'group_info':
                  context.push(
                    '/group-info/${conversation?.groupId ?? widget.conversationId}',
                  );
                  break;
                case 'verify_identity':
                  // P0-2: Safety Number verification for the 1:1 peer.
                  if (otherSnowId.isNotEmpty) {
                    final encodedName = Uri.encodeQueryComponent(title);
                    context.push(
                        '/safety/$otherSnowId?name=$encodedName');
                  }
                  break;
                case 'block':
                  _confirmBlockContact(otherSnowId);
                  break;
                case 'clear':
                  // Vuln 3 (Stage 3): regular group members can only clear locally
                  _confirmClearChat(
                    localOnly: isGroupChat && !isGroupAdminOrOwner,
                  );
                  break;
                case 'leave':
                  _confirmLeaveGroup(isCreator: isCreator);
                  break;
                case 'delete_group':
                  _confirmDeleteGroup();
                  break;
                case 'delete':
                  _confirmDeleteChat();
                  break;
              }
            },
            itemBuilder: (_) {
              return <PopupMenuEntry<String>>[
              // Auto-translate toggle
              // Group info (group only)
              if (isGroupChat)
                const PopupMenuItem(
                  value: 'group_info',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: SnowColors.textSecondary, size: 20),
                      SizedBox(width: 12),
                      Text('Group info',
                          style: TextStyle(color: SnowColors.textPrimary)),
                    ],
                  ),
                ),
              // 1:1: Verify Safety Number (P0-2)
              if (isDirect && otherSnowId.isNotEmpty)
                const PopupMenuItem(
                  value: 'verify_identity',
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          color: SnowColors.textSecondary, size: 20),
                      SizedBox(width: 12),
                      Text('Verify safety number',
                          style: TextStyle(color: SnowColors.textPrimary)),
                    ],
                  ),
                ),
              // 1:1: Block contact
              if (isDirect && otherSnowId.isNotEmpty)
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block_rounded,
                          color: SnowColors.error, size: 20),
                      SizedBox(width: 12),
                      Text('Block contact',
                          style: TextStyle(color: SnowColors.error)),
                    ],
                  ),
                ),
              // Clear chat (all except channel rooms)
              // Vuln 3 (Stage 3):
              //   - 1:1: 'Clear chat' (server cooperation N/A on this path — local clear)
              //   - Group admin/owner: 'Clear chat for everyone' (server fan-out)
              //   - Group regular member: 'Clear locally only' (no server call)
              if (!isChannelRoom)
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      const Icon(Icons.cleaning_services_rounded,
                          color: SnowColors.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        isGroupChat
                            ? (isGroupAdminOrOwner
                                ? 'Clear chat for everyone'
                                : 'Clear locally only')
                            : 'Clear chat',
                        style: const TextStyle(color: SnowColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              // Leave group (group only, NOT channel rooms)
              if (isGroupChat && !isChannelRoom)
                const PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app_rounded,
                          color: SnowColors.error, size: 20),
                      SizedBox(width: 12),
                      Text('Leave group',
                          style: TextStyle(color: SnowColors.error)),
                    ],
                  ),
                ),
              // Delete group (owner only, NOT channel rooms)
              if (isGroupChat && !isChannelRoom && isCreator)
                const PopupMenuItem(
                  value: 'delete_group',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever_rounded,
                          color: SnowColors.error, size: 20),
                      SizedBox(width: 12),
                      Text('Delete group',
                          style: TextStyle(color: SnowColors.error)),
                    ],
                  ),
                ),
              // Delete chat (1:1 only, NOT channel rooms)
              if (isDirect)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: SnowColors.error, size: 20),
                      SizedBox(width: 12),
                      Text('Delete chat',
                          style: TextStyle(color: SnowColors.error)),
                    ],
                  ),
                ),
            ];},
          ),
        ],
      ),
      body: Stack(
        children: [
          // Snowflake pattern wallpaper
          const SnowflakeBackground(),
          Column(
        children: [
          // P0-2: Safety Number change banner (1:1 only).
          // Visible iff the IdentityVerifications row reports a recent
          // mismatch and the user hasn't dismissed it for this screen.
          if (isDirect && otherSnowId.isNotEmpty && !_identityBannerDismissed)
            Consumer(builder: (ctx, cref, _) {
              final dao = cref.watch(identityVerificationDaoProvider);
              return StreamBuilder<dynamic>(
                stream: dao.watchByPeer(otherSnowId),
                builder: (_, snap) {
                  final row = snap.data;
                  if (row == null) return const SizedBox.shrink();
                  final lastChangedAt = row.lastChangedAt as int?;
                  final verified = (row.verified as bool?) ?? false;
                  if (lastChangedAt == null ||
                      lastChangedAt <= 0 ||
                      verified) {
                    return const SizedBox.shrink();
                  }
                  final wasPrev =
                      (row.wasPreviouslyVerified as bool?) ?? false;
                  return IdentityChangeBanner(
                    peerDisplayName: title,
                    wasPreviouslyVerified: wasPrev,
                    onVerify: () {
                      final encodedName = Uri.encodeQueryComponent(title);
                      context.push(
                          '/safety/$otherSnowId?name=$encodedName');
                    },
                    onDismiss: () =>
                        setState(() => _identityBannerDismissed = true),
                  );
                },
              );
            }),
          // Messages list
          Expanded(
            child: chatState.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: SnowColors.primary,
                    ),
                  )
                : chatState.messages.isEmpty
                    ? _buildEmptyChat()
                    : ListView.builder(
                        reverse: true, // Chat standard: newest at bottom, auto-scroll
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: SnowSizes.md,
                          vertical: SnowSizes.sm,
                        ),
                        itemCount: chatState.messages.length +
                            (chatState.isTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          // reverse=true: index 0 = bottom (newest)
                          // Typing indicator at the very bottom (index 0)
                          if (chatState.isTyping && index == 0) {
                            return const Padding(
                              padding: EdgeInsets.only(left: 4, top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TypingIndicator(),
                              ),
                            );
                          }

                          // Adjust index for typing indicator offset
                          final msgIndex = chatState.isTyping ? index - 1 : index;
                          // Reverse: map to actual message (newest first → oldest last)
                          final actualIndex = chatState.messages.length - 1 - msgIndex;
                          if (actualIndex < 0 || actualIndex >= chatState.messages.length) {
                            return const SizedBox.shrink();
                          }

                          final message = chatState.messages[actualIndex];
                          final isMine = message.isMine(_myId);

                          // Check if we should show timestamp header
                          // In reversed list, compare with the NEXT message (visually above)
                          final showDate = actualIndex == 0 ||
                              _shouldShowDate(
                                chatState.messages[actualIndex - 1].timestamp,
                                message.timestamp,
                              );

                          // Group chat: show sender name above other people's messages
                          bool showSenderName = false;
                          if (isGroupChat && !isMine && message.type != MessageType.system) {
                            showSenderName = true;
                            // Hide if consecutive text from same sender
                            // (always show for file/image — visually distinct)
                            if (actualIndex > 0 &&
                                message.type == MessageType.text) {
                              final prevMsg = chatState.messages[actualIndex - 1];
                              if (prevMsg.senderSnowchatId == message.senderSnowchatId &&
                                  prevMsg.type != MessageType.system) {
                                showSenderName = false;
                              }
                            }
                          }

                          // Determine sender role for bubble color
                          final senderRole = _getSenderRole(
                            ref, widget.conversationId,
                            message.senderSnowchatId, isGroupChat, isMine,
                          );

                          return Column(
                            children: [
                              if (showDate) _buildDateHeader(message.timestamp),
                              if (message.type == MessageType.system)
                                SystemMessageBubble(message: message)
                              else
                                Column(
                                  crossAxisAlignment: isMine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (showSenderName)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 12, bottom: 2, top: 4),
                                        child: _SenderNameWithRole(
                                          senderSnowchatId: message.senderSnowchatId,
                                          displayName: message.senderDisplayName ?? _truncateSnowId(message.senderSnowchatId),
                                          color: _senderColor(message.senderSnowchatId),
                                          roomId: widget.conversationId,
                                        ),
                                      ),
                                    Builder(builder: (ctx) {
                                      // Read auto-translation data (memory only)
                                      final translations = ref.watch(
                                          translationCacheProvider(widget.conversationId));
                                      final entry = translations[message.id];
                                      return MessageBubble(
                                        message: message,
                                        isMine: isMine,
                                        senderRole: senderRole,
                                        onLongPress: () =>
                                            _showContextMenu(message, isMine),
                                        onTapReply: message.replyToId != null
                                            ? () => _scrollToMessage(
                                                message.replyToId!)
                                            : null,
                                        linkPreviewService:
                                            _linkPreviewService,
                                        translatedText: entry?.translatedText,
                                        isTranslating: entry?.isLoading ?? false,
                                      );
                                    }),
                                    if (message.expiresAt != null)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          left: isMine ? 0 : 12,
                                          right: isMine ? 12 : 0,
                                          bottom: 2,
                                        ),
                                        child: MessageTimerBadge(
                                          expiresAt: message.expiresAt!,
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
          ),

          // Reply preview bar (shown when replying to a message)
          if (chatState.replyToMessage != null)
            ReplyPreviewBar(
              replyTo: chatState.replyToMessage!,
              senderName: chatState.replyToMessage!.isMine(_myId)
                  ? 'You'
                  : _shortId(chatState.replyToMessage!.senderSnowchatId),
              onClose: () {
                ref
                    .read(chatProvider(widget.conversationId).notifier)
                    .clearReplyTo();
              },
            ),

          // Input bar
          MessageInput(
            onSend: _sendMessage,
            onAttachment: _showAttachmentSheet,
            onTimerTap: _showTimerSelector,
            disappearingTTL: chatState.disappearingTTL,
            onTypingChanged: () {
              ref
                  .read(chatProvider(widget.conversationId).notifier)
                  .onUserTyping();
            },
          ),
        ],
      ),
        ],
      ),
    );
  }

  /// Shorten a SnowChat ID for display.
  String _shortId(String snowId) {
    if (snowId.length > 10) {
      return '${snowId.substring(0, 10)}...';
    }
    return snowId;
  }

  /// AI summary icon. Dimmed when AI is not installed.
  /// Disabled with a tooltip for short conversations (< 3 meaningful messages).
  Widget _buildSummaryIcon(List<Message> messages) {
    final aiAsync = ref.watch(aiAvailableProvider);
    final aiReady = aiAsync.valueOrNull ?? false;
    final canSummarize = ConversationSummarizer.canSummarize(messages);
    final enabled = aiReady && canSummarize;
    const activeColor = Color(0xFF00D2FF);

    String tooltip;
    if (!aiReady) {
      tooltip = 'AI model not ready';
    } else if (!canSummarize) {
      tooltip = 'Conversation too short to summarize';
    } else {
      tooltip = 'Summarize conversation';
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: enabled
          ? () => showSummarySheet(
                context: context,
                conversationId: widget.conversationId,
                messages: messages,
              )
          : () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tooltip),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
      icon: Icon(
        Icons.auto_awesome,
        color: enabled ? activeColor : SnowColors.textTertiary,
        size: 22,
      ),
    );
  }

  /// Translation status icon — native-character badge (i18n-safe, in place of a flag).
  /// OFF: gray translate icon; ON: blue + bottom-right badge (한/A/あ/中/Fr/De...)
  Widget _buildTranslateIcon(Conversation? conversation) {
    final enabled = conversation?.autoTranslateEnabled ?? false;
    final targetLang = conversation?.autoTranslateTargetLang
        ?? ref.watch(settingsProvider).preferredLanguage;
    final badge = SupportedLanguages.badgeChar(targetLang);
    const activeColor = Color(0xFF00D2FF);

    return IconButton(
      tooltip: enabled ? 'Auto-translate to $targetLang' : 'Translation off',
      onPressed: () => _showTranslationSheet(conversation),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.translate,
            color: enabled ? activeColor : SnowColors.textSecondary,
            size: 22,
          ),
          if (enabled)
            Positioned(
              right: -6,
              bottom: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: SnowColors.background, width: 1),
                ),
                child: Text(
                  badge,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Translation settings BottomSheet — ON/OFF switch + target-language selection.
  void _showTranslationSheet(Conversation? conversation) {
    final convId = widget.conversationId;
    final dao = ref.read(conversationDaoProvider);
    final listNotifier = ref.read(conversationListProvider.notifier);
    final globalLang = ref.read(settingsProvider).preferredLanguage;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SnowColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final currentConv = ref.read(conversationListProvider).firstWhere(
                (c) => c.id == convId,
                orElse: () => conversation ?? Conversation(
                  id: convId,
                  participantIds: const [],
                  createdAt: DateTime.now(),
                ),
              );
          final enabled = currentConv.autoTranslateEnabled;
          final currentTarget = currentConv.autoTranslateTargetLang ?? globalLang;
          final languages = SupportedLanguages.forPlatform();

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Toggle row
                SwitchListTile.adaptive(
                  title: const Text(
                    'Auto-translate this chat',
                    style: TextStyle(
                      color: SnowColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Incoming messages translated on-device',
                    style: TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  value: enabled,
                  activeColor: const Color(0xFF00D2FF),
                  onChanged: (v) {
                    dao.setAutoTranslate(convId, enabled: v);
                    listNotifier.toggleAutoTranslate(convId, enabled: v);
                    setSheet(() {});
                  },
                ),
                const Divider(height: 1),
                // Target language list
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Translate to',
                      style: TextStyle(
                        color: enabled
                            ? SnowColors.textSecondary
                            : SnowColors.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: languages.map((lang) {
                      final isSelected = lang.name == currentTarget;
                      return ListTile(
                        enabled: enabled,
                        leading: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected && enabled
                                ? const Color(0xFF00D2FF)
                                : SnowColors.background,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            lang.badgeChar,
                            style: TextStyle(
                              color: isSelected && enabled
                                  ? Colors.white
                                  : SnowColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          lang.nativeLabel,
                          style: TextStyle(
                            color: enabled
                                ? SnowColors.textPrimary
                                : SnowColors.textTertiary,
                            fontSize: 15,
                          ),
                        ),
                        trailing: isSelected && enabled
                            ? const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF00D2FF),
                              )
                            : null,
                        onTap: enabled
                            ? () {
                                dao.setAutoTranslateTarget(convId, lang.name);
                                listNotifier.setAutoTranslateTarget(
                                    convId, lang.name);
                                setSheet(() {});
                              }
                            : null,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyChat() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_rounded,
            size: 48,
            color: SnowColors.textTertiary,
          ),
          SizedBox(height: SnowSizes.md),
          Text(
            'Messages are end-to-end encrypted',
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Get sender role from group detail (watched for reactivity).
  static SenderRole _getSenderRole(
    WidgetRef ref, String roomId, String senderSnowchatId,
    bool isGroupChat, bool isMine,
  ) {
    if (!isGroupChat || isMine) return SenderRole.none;
    final gd = ref.watch(groupDetailProvider(roomId));
    if (gd.creatorId.isEmpty || gd.members.isEmpty) return SenderRole.none;

    final isOwner = gd.members.any(
      (m) => m.snowchatId == senderSnowchatId && m.userId == gd.creatorId,
    );
    if (isOwner) return SenderRole.owner;

    final isAdmin = gd.members.any(
      (m) => m.snowchatId == senderSnowchatId && m.isAdmin,
    );
    if (isAdmin) return SenderRole.admin;

    return SenderRole.none;
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    String label;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      label = 'Today';
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      label = 'Yesterday';
    } else {
      label =
          '${date.month}/${date.day}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: SnowColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  bool _shouldShowDate(DateTime prev, DateTime current) {
    return prev.day != current.day ||
        prev.month != current.month ||
        prev.year != current.year;
  }

  /// Consistent color per sender based on snowchatId hash.
  static const _senderColors = [
    Color(0xFF25D366), // green
    Color(0xFF34B7F1), // blue
    Color(0xFFE91E63), // pink
    Color(0xFF9C27B0), // purple
    Color(0xFFFF9800), // orange
    Color(0xFF00BCD4), // cyan
    Color(0xFFFFEB3B), // yellow
    Color(0xFF4CAF50), // dark green
  ];

  Color _senderColor(String snowchatId) {
    final hash = snowchatId.hashCode.abs();
    return _senderColors[hash % _senderColors.length];
  }

  String _truncateSnowId(String snowId) {
    if (snowId.length > 12) {
      return '${snowId.substring(0, 8)}...${snowId.substring(snowId.length - 4)}';
    }
    return snowId;
  }
}

// ---------------------------------------------------------------------------
// Sender name with Owner/Admin role badge
// ---------------------------------------------------------------------------

class _SenderNameWithRole extends ConsumerWidget {
  const _SenderNameWithRole({
    required this.senderSnowchatId,
    required this.displayName,
    required this.color,
    required this.roomId,
  });

  final String senderSnowchatId;
  final String displayName;
  final Color color;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupState = ref.watch(groupDetailProvider(roomId));
    final detail = groupState;

    // Determine role
    String? roleLabel;
    Color? roleBgColor;
    IconData? roleIcon;

    if (detail.creatorId.isNotEmpty) {
      // Check if sender is creator (Owner)
      final isOwner = detail.members.any(
        (m) => m.snowchatId == senderSnowchatId &&
               m.userId == detail.creatorId,
      );
      if (isOwner) {
        roleLabel = 'Owner';
        roleBgColor = const Color(0xFFFFAB00);
        roleIcon = Icons.star_rounded;
      } else {
        // Check if sender is admin
        final isAdmin = detail.members.any(
          (m) => m.snowchatId == senderSnowchatId && m.isAdmin,
        );
        if (isAdmin) {
          roleLabel = 'Admin';
          roleBgColor = const Color(0xFF00F782);
          roleIcon = Icons.shield_rounded;
        }
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (roleLabel != null) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: roleBgColor!.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(roleIcon, size: 10, color: roleBgColor),
                const SizedBox(width: 2),
                Text(
                  roleLabel,
                  style: TextStyle(
                    color: roleBgColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
