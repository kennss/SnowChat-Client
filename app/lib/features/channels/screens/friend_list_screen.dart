/// @file        friend_list_screen.dart
/// @description The Friends tab — the friend list on this device (ContactStore; design
///              2026-11-22-friend-graph-off-server §5.1): requests received (Accept = add them too,
///              Decline = hidden here and nothing sent, Block), friends (tap → the 1:1 chat; the
///              sheet: Send message, Voice call, Remove — the messages are kept), requests sent
///              ("Requested": Resend, Cancel). Every row shows the short snowId under the name (the
///              name is the server's word). An account the server refused again and again as not
///              existing reads "Account unavailable". No presence anywhere (§5.8).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-09
/// @lastUpdated 2026-11-22 (the friend sheet offers "Resend friend request" — a friend that does not
///              show this user as one (it reinstalled without a backup, or never got the acceptance)
///              answers it; Block at the 5,000-account cap says so). Earlier 2026-11-22 (friend graph off the server — the tab reshaped to the label table of §5.1:
///              sections Requests received / Friends / Requests sent, each row with its short
///              snowId; Block on a received request; "Requested" with Resend / Cancel on a sent
///              one; the friend sheet's Remove says the messages are kept; "Account unavailable";
///              a voice call shows the first-call policy dialog like the chat; no presence and no
///              "Blocked" mark (blocking removes the row). Earlier 2026-11-22 (data bindings: the rows
///              come from contactProvider). Earlier 2026-11-21 (Voice Call to a blocked account asks to
///              unblock first — confirmUnblockIfBlocked). Earlier 2026-05-06 (friend tile tap opens (or
///              resumes) the 1:1 chat; long-press opens the options sheet; the find-or-create flow
///              moved to start_direct_chat.dart). Earlier 2026-04-28 (Add Friend opens the full-screen
///              AddFriendScreen.)
///
/// @functions
///  - FriendListScreen: the Friends tab
///  - _section(): a section header with its count
///  - _receivedTile(): a received request — Accept / Decline / Block
///  - _friendTile(): a friend — tap opens the chat, long-press or the more button opens the sheet
///  - _sentTile(): a sent request — "Requested", Resend / Cancel
///  - _showFriendOptions(): the friend sheet (Send message / Voice call / Resend friend request /
///    Remove)
///  - _placeVoiceCall(): a call from the sheet — the first-call policy dialog, the peer's name from
///    this device, CallNotifier.startCall (app.dart pushes /call)
///  - _confirmRemove() / _confirmBlock(): the confirmation dialogs
///  - friendListName(): the name a row shows (its name, else the short snowId)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart' show callProvider, shortSnowId;
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../call/screens/voip_policy_dialog.dart';
import '../../chat/services/start_direct_chat.dart';
import '../../../core/blocking/block_list.dart' show BlockLimitReached;
import '../../contacts/blocked_peer_prompt.dart';
import '../../contacts/contact_provider.dart';
import '../../settings/settings_provider.dart';

/// The name a row of the list shows: its name, else the short snowId.
String friendListName(Contact c) =>
    (c.displayName != null && c.displayName!.trim().isNotEmpty)
        ? c.displayName!
        : shortSnowId(c.snowChatId);

class FriendListScreen extends ConsumerStatefulWidget {
  const FriendListScreen({super.key});

  @override
  ConsumerState<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends ConsumerState<FriendListScreen> {
  /// Accounts with an action running (their buttons are off until it ends).
  final Set<String> _busy = {};

  ContactNotifier get _contacts => ref.read(contactProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final received = ref.watch(receivedRequestsProvider);
    final sent = ref.watch(sentRequestsProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          // My QR / scan hub — in-person first contact (show mine ↔ scan theirs).
          IconButton(
            icon: const Icon(Icons.qr_code_rounded, color: SnowColors.primary),
            tooltip: 'My code / scan',
            onPressed: () => context.push('/my-qr'),
          ),
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: SnowColors.primary),
            tooltip: 'Add friend',
            onPressed: () => context.push('/add-friend'),
          ),
        ],
      ),
      body: (friends.isEmpty && received.isEmpty && sent.isEmpty)
          ? _emptyState()
          : ListView(
              padding: const EdgeInsets.only(bottom: SnowSizes.lg),
              children: [
                if (received.isNotEmpty) ...[
                  _section('Requests received', received.length,
                      color: SnowColors.warning),
                  for (final c in received) _receivedTile(c),
                ],
                _section('Friends', friends.length),
                if (friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: SnowSizes.md, vertical: SnowSizes.sm),
                    child: Text(
                      'No friends yet. When someone accepts your request, '
                      'or you accept theirs, they show here.',
                      style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
                    ),
                  )
                else
                  for (final c in friends) _friendTile(c),
                if (sent.isNotEmpty) ...[
                  _section('Requests sent', sent.length),
                  for (final c in sent) _sentTile(c),
                ],
              ],
            ),
    );
  }

  // --- Sections and rows ----------------------------------------------------

  Widget _section(String title, int count, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SnowSizes.md, SnowSizes.md, SnowSizes.md, SnowSizes.xs),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          color: color ?? SnowColors.textTertiary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// The name and, under it, the short snowId ("Account unavailable" when
  /// the server refused sends to it again and again).
  Widget _nameBlock(Contact c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          friendListName(c),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: SnowColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          shortSnowId(c.snowChatId),
          style: const TextStyle(
            color: SnowColors.textTertiary,
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
        if (c.isUnavailable) ...[
          const SizedBox(height: 2),
          const Text(
            'Account unavailable',
            style: TextStyle(color: SnowColors.warning, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _smallButton(
    String label,
    VoidCallback? onPressed, {
    required Key key,
    Color color = SnowColors.primary,
    bool filled = false,
  }) {
    return TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: filled ? color.withAlpha(25) : null,
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  /// A received request: Accept (= add them too), Decline (hidden here,
  /// nothing sent), Block.
  Widget _receivedTile(Contact c) {
    final id = c.snowChatId;
    final busy = _busy.contains(id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SnowSizes.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SnowAvatar(snowId: id, size: 40, displayName: friendListName(c)),
              const SizedBox(width: 12),
              Expanded(child: _nameBlock(c)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            runSpacing: 6,
            children: [
              _smallButton('Accept', busy ? null : () => _accept(c),
                  key: ValueKey('accept:$id'), filled: true),
              _smallButton('Decline', busy ? null : () => _decline(c),
                  key: ValueKey('decline:$id'),
                  color: SnowColors.textSecondary,
                  filled: true),
              _smallButton('Block', busy ? null : () => _confirmBlock(c),
                  key: ValueKey('block:$id'), color: SnowColors.error),
            ],
          ),
        ],
      ),
    );
  }

  /// A friend: the row opens the chat; long-press or "more" opens the sheet.
  Widget _friendTile(Contact c) {
    final id = c.snowChatId;
    return InkWell(
      key: ValueKey('friend:$id'),
      onTap: () => openDirectChatWith(
        context: context,
        ref: ref,
        recipientSnowchatId: id,
        recipientDisplayName: c.displayName,
      ),
      onLongPress: () => _showFriendOptions(c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SnowSizes.md, 8, SnowSizes.xs, 8),
        child: Row(
          children: [
            SnowAvatar(snowId: id, size: 44, displayName: friendListName(c)),
            const SizedBox(width: 12),
            Expanded(child: _nameBlock(c)),
            IconButton(
              key: ValueKey('more:$id'),
              icon: const Icon(Icons.more_horiz_rounded,
                  color: SnowColors.textTertiary, size: 22),
              tooltip: 'More',
              onPressed: () => _showFriendOptions(c),
            ),
          ],
        ),
      ),
    );
  }

  /// A request this user sent (unanswered — or declined: the two look the
  /// same by design): "Requested", Resend, Cancel.
  Widget _sentTile(Contact c) {
    final id = c.snowChatId;
    final busy = _busy.contains(id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SnowSizes.md, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SnowAvatar(snowId: id, size: 40, displayName: friendListName(c)),
              const SizedBox(width: 12),
              Expanded(child: _nameBlock(c)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SnowColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Requested',
                  style: TextStyle(color: SnowColors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            children: [
              _smallButton('Resend', busy ? null : () => _resend(c),
                  key: ValueKey('resend:$id')),
              _smallButton('Cancel', busy ? null : () => _cancel(c),
                  key: ValueKey('cancel:$id'), color: SnowColors.error),
            ],
          ),
        ],
      ),
    );
  }

  // --- Actions --------------------------------------------------------------

  /// Run [action] for [c] once at a time; [done] on success, [failure] on
  /// an error.
  Future<void> _run(
    Contact c,
    Future<void> Function() action, {
    String? done,
    required String failure,
    String? Function(Object error)? failureOf,
  }) async {
    final id = c.snowChatId;
    if (!_busy.add(id)) return;
    setState(() {});
    Object? error;
    try {
      await action();
    } catch (e) {
      error = e;
    } finally {
      _busy.remove(id);
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    final ok = error == null;
    final text = ok ? done : (failureOf?.call(error) ?? failure);
    if (text == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: ok ? null : SnowColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _accept(Contact c) => _run(
        c,
        () => _contacts.accept(c.snowChatId),
        done: 'You and ${friendListName(c)} are friends now.',
        failure: 'Could not accept the request.',
      );

  /// Hidden here; nothing is sent to the requester.
  Future<void> _decline(Contact c) => _run(
        c,
        () => _contacts.decline(c.snowChatId),
        failure: 'Could not decline the request.',
      );

  Future<void> _resend(Contact c) => _run(
        c,
        () => _contacts.resend(c.snowChatId),
        done: 'Request sent again.',
        failure: 'Could not send the request.',
      );

  Future<void> _cancel(Contact c) => _run(
        c,
        () => _contacts.remove(c.snowChatId),
        done: 'Request cancelled.',
        failure: 'Could not cancel the request.',
      );

  Future<void> _confirmBlock(Contact c) async {
    final name = friendListName(c);
    final block = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: Text('Block $name?',
            style: const TextStyle(color: SnowColors.textPrimary)),
        content: const Text(
          'They can no longer message or call you, and their request goes '
          'away. They are not told.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: SnowColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block', style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    if (block != true || !mounted) return;
    await _run(
      c,
      () => _contacts.blockContact(c.snowChatId),
      done: '$name is blocked.',
      failure: 'Could not block.',
      failureOf: (e) => e is BlockLimitReached ? blockLimitText : null,
    );
  }

  Future<void> _confirmRemove(Contact c) async {
    final name = friendListName(c);
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Remove friend',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Text(
          'Remove $name from your friends? Your messages are kept.',
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: SnowColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Remove', style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    await _run(
      c,
      () => _contacts.remove(c.snowChatId),
      done: 'Removed from your friends.',
      failure: 'Could not remove.',
    );
  }

  void _showFriendOptions(Contact c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SnowColors.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SnowSizes.md),
              child: Row(
                children: [
                  SnowAvatar(
                    snowId: c.snowChatId,
                    size: 40,
                    displayName: friendListName(c),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _nameBlock(c)),
                ],
              ),
            ),
            const Divider(color: SnowColors.divider, height: 24),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded,
                  color: SnowColors.primary),
              title: const Text('Send message',
                  style: TextStyle(color: SnowColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                openDirectChatWith(
                  context: context,
                  ref: ref,
                  recipientSnowchatId: c.snowChatId,
                  recipientDisplayName: c.displayName,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_rounded, color: SnowColors.primary),
              title: const Text('Voice call',
                  style: TextStyle(color: SnowColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_placeVoiceCall(c));
              },
            ),
            ListTile(
              key: ValueKey('resend-friend:${c.snowChatId}'),
              leading: const Icon(Icons.sync_rounded, color: SnowColors.primary),
              title: const Text('Resend friend request',
                  style: TextStyle(color: SnowColors.textPrimary)),
              subtitle: const Text(
                'If they do not see you as a friend',
                style: TextStyle(color: SnowColors.textTertiary, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_run(
                  c,
                  () => _contacts.resend(c.snowChatId),
                  done: 'Sent again.',
                  failure: 'Could not send it.',
                ));
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_rounded,
                  color: SnowColors.error),
              title: const Text('Remove friend',
                  style: TextStyle(color: SnowColors.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_confirmRemove(c));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// A voice call from the sheet: the same start as the chat's call button
  /// (first-call policy dialog, alwaysRelay, the peer's name from this
  /// device). app.dart pushes /call when the call goes outgoing.
  Future<void> _placeVoiceCall(Contact c) async {
    // An account this user blocked: offer to unblock first.
    if (!await confirmUnblockIfBlocked(
      context: context,
      ref: ref,
      snowId: c.snowChatId,
      displayName: c.displayName,
    )) {
      return;
    }
    if (!mounted) return;
    await VoipPolicyDialog.showIfNeeded(context);
    if (!mounted) return;
    final notifier = ref.read(callProvider.notifier);
    final alwaysRelay = ref.read(settingsProvider).callAlwaysRelay;
    unawaited(notifier
        .startCall(
      recipientSnowchatId: c.snowChatId,
      alwaysRelay: alwaysRelay,
      remoteDisplayName: friendListName(c),
    )
        .catchError((Object e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start call: $e')),
      );
    }));
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SnowSizes.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              'Add a friend by nickname, SnowChat ID or QR code.\n'
              'Your friend list stays on this phone — the server keeps '
              'only a sealed backup it cannot read.',
              textAlign: TextAlign.center,
              style: TextStyle(color: SnowColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: SnowSizes.lg),
            ElevatedButton.icon(
              onPressed: () => context.push('/add-friend'),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: const Text('Add friend'),
            ),
          ],
        ),
      ),
    );
  }
}
