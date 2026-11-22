/// @file        start_direct_chat.dart
/// @description Helper that opens (or resumes) a direct 1:1 chat with a
///              given SnowChat ID. Encapsulates the find-or-create
///              conversation flow so multiple entry points — Friends list
///              tap, NewChatScreen, contacts screen — share the same
///              behaviour without duplicating the API call + cache update.
///
///              The 2026-05-06 friend-list UX rework introduced a direct
///              tap → chat path (instead of routing through NewChatScreen
///              first), which is what motivated extracting this helper
///              from the original NewChatScreen._startChat().
///
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-06
/// @lastUpdated 2026-11-21 (an account this user blocked: confirmUnblockIfBlocked first, instead of
///              the server's refusal shown as "Failed to start conversation"). Earlier 2026-11-20 (the room id is the recipient's snowId — the server's reply only says
///              whether a 1:1 may start, it never names the room)
///
/// @functions
///  - openDirectChatWith(): existing direct convo → /chat/{id}; otherwise POST conversations/find-or-create then /chat/{id}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_endpoints.dart';
import '../../contacts/blocked_peer_prompt.dart';
import '../models/conversation.dart';
import '../providers/conversation_list_provider.dart';

/// Opens a 1:1 chat with the given SnowChat ID. If a direct conversation
/// already exists between the current user and the recipient, navigates
/// straight to it. Otherwise calls /conversations/find-or-create on the
/// server, optimistically inserts the conversation into the local list
/// (so the chat screen can resolve its recipientSnowchatId immediately —
/// avoids the group-fallback bug the old code hit), then navigates.
///
/// On failure shows a SnackBar through the nearest ScaffoldMessenger and
/// returns without navigating. Caller does not need to handle errors.
Future<void> openDirectChatWith({
  required BuildContext context,
  required WidgetRef ref,
  required String recipientSnowchatId,
  String? recipientDisplayName,
}) async {
  // An account this user blocked: offer to unblock first (the server would
  // refuse the 1:1 anyway, with nothing but "Failed to start conversation").
  if (!await confirmUnblockIfBlocked(
    context: context,
    ref: ref,
    snowId: recipientSnowchatId,
    displayName: recipientDisplayName,
  )) {
    return;
  }
  if (!context.mounted) return;

  final myId = ref.read(currentSnowIdProvider) ?? '';

  // A 1:1 room's id is the peer's snowId.
  final convId = recipientSnowchatId;

  // Existing direct conversation?
  final conversations = ref.read(conversationListProvider);
  if (conversations
      .any((c) => c.type == ConversationType.direct && c.id == convId)) {
    if (context.mounted) {
      context.push('/chat/$convId');
    }
    return;
  }

  // Otherwise ask the server whether a 1:1 may start (a friend or a
  // community co-member; refused otherwise). Its reply never names the room.
  try {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.post(
      ApiEndpoints.conversationFindOrCreate,
      data: {'recipientSnowchatId': recipientSnowchatId},
    );

    // Optimistic insert — chatProvider needs the conversation present in
    // the list to resolve recipientSnowchatId (otherwise it group-falls
    // back, observed as a bug pre-2026-04). Refresh in the background so
    // the eventual server-canonical row replaces this stub.
    final notifier = ref.read(conversationListProvider.notifier);
    final alreadyExists =
        ref.read(conversationListProvider).any((c) => c.id == convId);
    if (!alreadyExists) {
      notifier.addConversation(Conversation(
        id: convId,
        type: ConversationType.direct,
        participantIds: [myId, recipientSnowchatId],
        title: recipientDisplayName,
        createdAt: DateTime.now(),
      ));
    }
    notifier.refresh();

    if (context.mounted) {
      context.push('/chat/$convId');
    }
  } catch (e) {
    debugPrint('[openDirectChatWith] failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start conversation')),
      );
    }
  }
}
