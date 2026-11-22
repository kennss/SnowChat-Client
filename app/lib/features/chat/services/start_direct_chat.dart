/// @file        start_direct_chat.dart
/// @description Helper that opens (or resumes) a direct 1:1 chat with a
///              given SnowChat ID. The room is made on this device (its id
///              is the peer's snowId): an account of the friend list needs
///              no server call; any other is resolved once (POST
///              /users/resolve) to know it exists. Shared by the Friends
///              list tap and NewChatScreen.
///
///              The 2026-05-06 friend-list UX rework introduced a direct
///              tap → chat path (instead of routing through NewChatScreen
///              first), which is what motivated extracting this helper
///              from the original NewChatScreen._startChat().
///
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-06
/// @lastUpdated 2026-11-22 (an account a screen resolved already is not resolved again
///              ([resolved]); [replaceCurrent] opens the chat in place of the calling screen — New
///              Chat). Earlier 2026-11-22 (friend graph off the server: no find-or-create — the room
///              is made here; a peer outside the friend list is resolved once). Earlier 2026-11-21 (an account this user blocked: confirmUnblockIfBlocked first, instead of
///              the server's refusal shown as "Failed to start conversation"). Earlier 2026-11-20 (the room id is the recipient's snowId — the server's reply only says
///              whether a 1:1 may start, it never names the room)
///
/// @functions
///  - openDirectChatWith(): existing direct convo → /chat/{id}; otherwise make the room (resolve the
///    peer first when it is not in the friend list and the caller did not resolve it) then
///    /chat/{id} — on top of the caller, or in its place (replaceCurrent)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/contacts/contact_lookup.dart' show FoundAccount;
import '../../contacts/blocked_peer_prompt.dart';
import '../models/conversation.dart';
import '../providers/conversation_list_provider.dart';

/// Opens a 1:1 chat with the given SnowChat ID. If a direct conversation
/// already exists between the current user and the recipient, navigates
/// straight to it. Otherwise inserts the conversation into the local list
/// (so the chat screen can resolve its recipientSnowchatId immediately —
/// avoids the group-fallback bug the old code hit), then navigates. A
/// recipient outside the friend list is resolved first (it must exist).
///
/// [resolved]: the account as a lookup on the calling screen returned it
/// (not resolved again). [replaceCurrent]: the chat takes the place of the
/// calling screen instead of going on top of it.
///
/// On failure shows a SnackBar through the nearest ScaffoldMessenger and
/// returns without navigating. Caller does not need to handle errors.
Future<void> openDirectChatWith({
  required BuildContext context,
  required WidgetRef ref,
  required String recipientSnowchatId,
  String? recipientDisplayName,
  FoundAccount? resolved,
  bool replaceCurrent = false,
}) async {
  void open(String convId) {
    if (!context.mounted) return;
    if (replaceCurrent) {
      context.pushReplacement('/chat/$convId');
    } else {
      context.push('/chat/$convId');
    }
  }

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
    open(convId);
    return;
  }

  // A 1:1 starts with anyone (§5.7). An account of the friend list is known
  // here; any other is resolved once — it must exist, and its name is what
  // the server says until its certificate arrives.
  try {
    var title = recipientDisplayName;
    final inList = await ref.read(contactStoreProvider).entry(recipientSnowchatId);
    if (inList == null) {
      var account = resolved?.snowId == recipientSnowchatId ? resolved : null;
      if (account == null) {
        final r = await ref.read(contactLookupProvider).resolve(recipientSnowchatId);
        account = r.account;
        if (account == null) {
          throw StateError(r.notFound ? 'no such account' : 'lookup failed');
        }
      }
      title ??= account.displayName;
    } else {
      title ??= inList.nickname;
    }

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
        title: title,
        createdAt: DateTime.now(),
      ));
    }
    notifier.refresh();

    open(convId);
  } catch (e) {
    debugPrint('[openDirectChatWith] failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start conversation')),
      );
    }
  }
}
