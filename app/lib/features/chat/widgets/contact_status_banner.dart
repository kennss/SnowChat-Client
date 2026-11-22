/// @file        contact_status_banner.dart
/// @description The slim bar at the top of a 1:1 chat that says where the peer stands in this
///              user's friend list (design 2026-11-22-friend-graph-off-server §5.7, §5.1): not in
///              the list ("Not in your friends" — Add / Block), a request this user sent ("Request
///              sent"), a request the peer sent ("Wants to be your friend" — Accept / Decline), an
///              account the server refused again and again as not existing ("Account
///              unavailable"), an account this user blocked (Unblock). A friend shows no bar. The
///              list is this device's (ContactStore); nothing here asks the server.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - ContactBannerState: what the bar shows
///  - contactBannerStateOf(): the state of a peer from its row and the block list
///  - ContactStatusBanner: the bar (watches the friend list and the block list)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show blockedAccountsProvider;
import '../../../core/contacts/contact_store.dart';
import '../../../shared/constants/colors.dart';
import '../../contacts/contact_provider.dart';

/// What the bar of a 1:1 chat shows.
enum ContactBannerState {
  /// A friend: no bar.
  none,

  /// Not in this user's list (no row, or a request this user declined).
  notInList,

  /// This user's request waits for the peer.
  requestSent,

  /// The peer's request waits for this user.
  requestReceived,

  /// Sends to the peer were refused again and again as not existing.
  unavailable,

  /// This user blocked the peer.
  blocked,
}

/// The state of a peer whose row is [entry] (null: none) and that this
/// user did or did not block ([blocked]).
ContactBannerState contactBannerStateOf({
  required ContactEntry? entry,
  required bool blocked,
}) {
  if (blocked) return ContactBannerState.blocked;
  if (entry != null && entry.isUnavailable) return ContactBannerState.unavailable;
  if (entry == null || !entry.isVisible) return ContactBannerState.notInList;
  switch (entry.label) {
    case ContactLabel.friend:
      return ContactBannerState.none;
    case ContactLabel.requestSent:
      return ContactBannerState.requestSent;
    case ContactLabel.requestReceived:
      return ContactBannerState.requestReceived;
    case null:
      return ContactBannerState.notInList;
  }
}

class ContactStatusBanner extends ConsumerStatefulWidget {
  /// The 1:1 peer.
  final String peerSnowId;

  /// The name to keep with the row when this user adds the peer (the chat's
  /// name — a name certificate replaces it); null when none is known.
  final String? peerName;

  /// "Block" — the chat screen's own block flow (confirmation, the chat
  /// removed).
  final VoidCallback onBlock;

  const ContactStatusBanner({
    super.key,
    required this.peerSnowId,
    required this.peerName,
    required this.onBlock,
  });

  @override
  ConsumerState<ContactStatusBanner> createState() =>
      _ContactStatusBannerState();
}

class _ContactStatusBannerState extends ConsumerState<ContactStatusBanner> {
  /// An action is running (its buttons are off until it ends).
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(ContactNotifier contacts) action, {
    required String failure,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(ref.read(contactProvider.notifier));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(contactEntriesProvider);
    final blockedList = ref.watch(blockedAccountsProvider);
    // Nothing until both are read (no flash of "Not in your friends").
    if (!entries.hasValue || !blockedList.hasValue) {
      return const SizedBox.shrink();
    }
    final peer = widget.peerSnowId;
    final entry = entries.value!.where((e) => e.snowId == peer).firstOrNull;
    final state = contactBannerStateOf(
      entry: entry,
      blocked: blockedList.value!.contains(peer),
    );
    switch (state) {
      case ContactBannerState.none:
        return const SizedBox.shrink();
      case ContactBannerState.notInList:
        return _bar(
          icon: Icons.person_outline_rounded,
          text: 'Not in your friends',
          actions: [
            _action('Add', () => _run(
                  (c) => c.request(peer, displayName: widget.peerName),
                  failure: 'Could not send the friend request.',
                )),
            _action('Block', widget.onBlock, color: SnowColors.error),
          ],
        );
      case ContactBannerState.requestSent:
        return _bar(
          icon: Icons.schedule_rounded,
          text: 'Request sent',
          actions: const [],
        );
      case ContactBannerState.requestReceived:
        return _bar(
          icon: Icons.person_add_alt_1_rounded,
          text: 'Wants to be your friend',
          actions: [
            _action('Accept', () => _run(
                  (c) => c.accept(peer),
                  failure: 'Could not accept the request.',
                )),
            _action('Decline', () => _run(
                  (c) => c.decline(peer),
                  failure: 'Could not decline the request.',
                ), color: SnowColors.textSecondary),
          ],
        );
      case ContactBannerState.unavailable:
        return _bar(
          icon: Icons.person_off_outlined,
          text: 'Account unavailable — messages are not delivered',
          actions: const [],
          color: SnowColors.warning,
        );
      case ContactBannerState.blocked:
        return _bar(
          icon: Icons.block_rounded,
          text: 'You blocked this account',
          actions: [
            _action('Unblock', () => _run(
                  (c) => c.unblockContact(peer),
                  failure: 'Could not unblock.',
                )),
          ],
          color: SnowColors.error,
        );
    }
  }

  Widget _action(String label, VoidCallback onPressed, {Color? color}) =>
      TextButton(
        onPressed: _busy ? null : onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color ?? SnowColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _bar({
    required IconData icon,
    required String text,
    required List<Widget> actions,
    Color color = SnowColors.textSecondary,
  }) {
    return Material(
      color: SnowColors.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: color, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}
