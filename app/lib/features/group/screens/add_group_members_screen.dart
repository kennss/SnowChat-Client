/// @file        add_group_members_screen.dart
/// @description Add-group-members screen — select contacts excluding existing members and invite them.
///              The contacts this user chose by an action of their own (vouched) are listed as
///              known; the others only after a warning (AccountPickerList) — the contact list is
///              the server's word and an invite gives an account the group's key for good. At
///              most as many as the group has room for (gv2GroupSizeLimit).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-11-21 (P5.6: the room left counts every place taken — placesTaken; invites go up to 64 in one change — inviteMany; earlier the same day: known / not verified contacts and the warning). Earlier 2026-11-20 (v1 groups removed: the selected contacts are always invited — an INVITE in
///              the group's change log each; no server add; says so when groups are not ready).
///              Earlier same day (group protocol v2: invites for a v2 group).
///              Earlier 2026-04-26 (header English translation)
///
/// @functions
///  - AddGroupMembersScreen: add-group-members ConsumerStatefulWidget
///  - _toggleMember(): toggle member select/deselect (up to the room left)
///  - _selectAllKnown(): pick (or unpick) every known contact
///  - _invite(): invite the selected contacts into the group
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../app/providers.dart';
import '../../../core/group_v2/gv2_groups.dart';
import '../../../core/group_v2/gv2_codec.dart' show gv2MaxChangeActions;
import '../providers/gv2_group_provider.dart';
import '../providers/pick_candidates.dart';
import '../widgets/account_picker_list.dart';

class AddGroupMembersScreen extends ConsumerStatefulWidget {
  final String groupId;
  final List<String> existingMemberSnowchatIds;

  /// The places taken in the group (members and open invites — those whose
  /// ciphertext names no account included, which the list above lacks).
  final int placesTaken;

  const AddGroupMembersScreen({
    super.key,
    required this.groupId,
    required this.existingMemberSnowchatIds,
    required this.placesTaken,
  });

  @override
  ConsumerState<AddGroupMembersScreen> createState() =>
      _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState
    extends ConsumerState<AddGroupMembersScreen> {
  /// As many as the group has room for (the server's log decides in the
  /// end: an invite past the limit is refused as `full`).
  late final PickSelection _picked = PickSelection(
    (gv2GroupSizeLimit - widget.placesTaken).clamp(0, gv2GroupSizeLimit),
  );
  bool _isAdding = false;

  /// The contacts that are not in the group (empty while they load).
  List<PickCandidate> _candidates(List<PickCandidate> all) => [
        for (final c in all)
          if (!widget.existingMemberSnowchatIds.contains(c.snowId)) c,
      ];

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: SnowColors.error),
    );
  }

  void _toggleMember(String snowId) {
    final picked = _picked.toggle(snowId);
    setState(() {});
    if (!picked) {
      _say(gv2FailureText(const Gv2GroupException(Gv2GroupFailure.full)));
    }
  }

  void _selectAllKnown(List<PickCandidate> candidates) {
    final cut = _picked.selectAllKnown(candidates);
    setState(() {});
    if (cut) {
      _say(gv2FailureText(const Gv2GroupException(Gv2GroupFailure.full)));
    }
  }

  /// Each selected contact is invited (design §9.2) and becomes a member
  /// when their app accepts. One invite at a time — each is an entry in the
  /// change log. Stops at the first that cannot be made and says how many
  /// were.
  Future<void> _invite() async {
    if (_isAdding || _picked.ids.isEmpty) return;
    final groups = ref.read(gv2RuntimeProvider)?.groups;
    if (groups == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Groups are not ready yet. Try again in a moment.'),
          backgroundColor: SnowColors.error,
        ),
      );
      return;
    }
    setState(() => _isAdding = true);
    var invited = 0;
    Object? failure;
    // As few changes as possible: up to gv2MaxChangeActions invites each
    // (one per account met the server's change budget early).
    final picked = _picked.ids.toList();
    for (var at = 0; at < picked.length; at += gv2MaxChangeActions) {
      final batch = picked.sublist(at, min(at + gv2MaxChangeActions, picked.length));
      try {
        invited += await groups.inviteMany(widget.groupId, batch);
      } catch (e) {
        failure = e;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _isAdding = false);
    final messenger = ScaffoldMessenger.of(context);
    if (failure != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            invited == 0
                ? gv2FailureText(failure)
                : '$invited invited. ${gv2FailureText(failure)}',
          ),
          backgroundColor: SnowColors.error,
        ),
      );
      if (invited == 0) return;
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$invited ${invited == 1 ? 'person' : 'people'} invited',
          ),
          backgroundColor: SnowColors.primary,
        ),
      );
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(contactPickCandidatesProvider);
    final count = _picked.ids.length;

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Add Members'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected count hint
          Padding(
            padding: const EdgeInsets.all(SnowSizes.md),
            child: Text(
              count == 0
                  ? 'Select members to add'
                  : '$count member${count != 1 ? 's' : ''} selected',
              style: const TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),

          // Contact list (without the members)
          Expanded(
            child: candidates.when(
              data: (all) {
                final list = _candidates(all);
                return AccountPickerList(
                  candidates: list,
                  selected: _picked.ids,
                  onToggle: _toggleMember,
                  onSelectAllKnown: () => _selectAllKnown(list),
                  allKnownTaken: _picked.allKnownTaken(list),
                  emptyText: 'No contacts available to add',
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, _) => const Center(
                child: Text(
                  "Couldn't load your contacts.",
                  style: TextStyle(color: SnowColors.textTertiary),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: count > 0
          ? FloatingActionButton(
              onPressed: _isAdding ? null : _invite,
              backgroundColor: SnowColors.primary,
              child: _isAdding
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SnowColors.background,
                      ),
                    )
                  : const Icon(
                      Icons.person_add_rounded,
                      color: SnowColors.background,
                    ),
            )
          : null,
    );
  }
}
