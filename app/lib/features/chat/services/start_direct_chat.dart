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
/// @lastUpdated 2026-05-06
///
/// @functions
///  - openDirectChatWith(): existing direct convo → /chat/{id}; otherwise POST conversations/find-or-create then /chat/{id}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_endpoints.dart';
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
  final myId = ref.read(currentSnowIdProvider) ?? '';

  // Existing direct conversation?
  final conversations = ref.read(conversationListProvider);
  final existing = conversations.where((c) =>
      c.type == ConversationType.direct &&
      c.participantIds.contains(recipientSnowchatId));
  if (existing.isNotEmpty) {
    if (context.mounted) {
      context.push('/chat/${existing.first.id}');
    }
    return;
  }

  // Otherwise create through the server.
  try {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.post(
      ApiEndpoints.conversationFindOrCreate,
      data: {'recipientSnowchatId': recipientSnowchatId},
    );
    final convId = (response.data as Map)['id'] as String;

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
