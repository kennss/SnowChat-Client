/// @file        create_group_screen.dart
/// @description Group-chat creation screen — pick accounts, enter a group name, create a group
///              protocol v2 group and invite them. Picks from this user's friends and the 1:1
///              peers they chose (design 2026-11-22-friend-graph-off-server §5.6), or — opened from
///              a community — from that community's roster. Either way the accounts this user
///              chose by an action of their own (VerifiedIdentityStore.isVouched) are listed as
///              known and "Select all" takes only them; the others are shown only after a
///              warning, because a roster and every name are the server's word and an invite
///              gives an account the group's key for good (AccountPickerList). Every account
///              shows its snowId.
///              Blocked accounts are not listed. A group holds up to gv2GroupSizeLimit accounts.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-11-22 (the picker's empty and error texts speak of friends — the candidates
///              are this device's friend list and chosen 1:1 peers, not a server contact list).
///              Earlier 2026-11-21 (X1: the blocked accounts left out of the roster are this device's list (BlockList), not a server call). Earlier 2026-11-21 (community roster mode; known = vouched for by the user, in both modes;
///              unknown accounts behind a warning; blocked accounts left out; the gv2GroupSizeLimit
///              cap — the list is AccountPickerList). Earlier 2026-11-20
///              (v1 groups removed: a new group is always a v2 group — no GMK, no server group
///              creation; one picked contact is enough). Earlier same day (group protocol v2: with
///              AppConfig.enableGroupsV2 a new group is a v2 group). Earlier 2026-11-10 (B-2 §5.7:
///              IdentityBindingInvalidException / IdentityKeyChangedException handled as terminal —
///              logged once, never retried). Earlier 2026-04-26 (header English translation;
///              previous: 2026-04-10 Phase 8.8: GMK-based group-name E2EE)
///
/// @functions
///  - CreateGroupScreen: group-chat creation ConsumerStatefulWidget ([communityId]: roster mode)
///  - _loadRoster(): fetch the community roster and the block list; mark each account known
///    or unknown
///  - _toggleMember(): pick / unpick one account (up to the group size limit)
///  - _selectAllKnown(): pick (or unpick) every known account
///  - _nameOf(): the name shown for a picked account
///  - _pickerList(): the roster or contact candidates in an AccountPickerList
///  - _showGroupNameDialog(): show group-name input dialog
///  - _createGroup(): create a v2 group, wait for the server to accept it, open its chat
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../core/group_v2/gv2_groups.dart';
import '../../../core/group_v2/gv2_payloads.dart' show gv2MaxTitleNameBytes;
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/database.dart' show Gv2GroupRow;
import '../../../core/storage/tables/gv2_tables.dart';
import '../../../app/providers.dart';
import '../../group/providers/gv2_group_provider.dart';
import '../../group/providers/pick_candidates.dart';
import '../../group/widgets/account_picker_list.dart';
import '../providers/conversation_list_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  /// Pick from this community's roster instead of the contacts.
  final String? communityId;

  /// The community's name, for the title (roster mode).
  final String? communityName;

  const CreateGroupScreen({super.key, this.communityId, this.communityName});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final PickSelection _picked = PickSelection(_maxPicks);
  bool _isCreating = false;

  /// Roster mode: the roster (null while it loads), the community's name as
  /// the server gave it, and whether loading failed.
  List<PickCandidate>? _roster;
  String? _communityName;
  bool _rosterFailed = false;

  /// How many accounts have to be picked. A group starts with its creator
  /// alone and grows by invites, so one is enough.
  static const int _minMembers = 1;

  /// How many accounts can be picked: the group holds the creator too.
  static const int _maxPicks = gv2GroupSizeLimit - 1;

  bool get _rosterMode => widget.communityId != null;

  @override
  void initState() {
    super.initState();
    if (_rosterMode) _loadRoster();
  }

  Future<void> _loadRoster() async {
    setState(() {
      _roster = null;
      _rosterFailed = false;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get<Object?>(
        ApiEndpoints.channelDetail(widget.communityId!),
      );
      // The accounts this user blocked are not offered (this device's list).
      final blockList = ref.read(blockListProvider);
      await blockList.load();
      final blocked = blockList.blocked;
      final store = ref.read(verifiedIdentityStoreProvider);
      final roster = await rosterCandidates(
        detail: res.data,
        mySnowId: ref.read(currentSnowIdProvider),
        blocked: blocked,
        isKnown: store.isVouched,
      );
      final detail = res.data;
      final name = detail is Map ? detail['name'] : null;
      if (mounted) {
        setState(() {
          _roster = roster;
          if (name is String && name.trim().isNotEmpty) _communityName = name;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _rosterFailed = true);
    }
  }

  void _toggleMember(String snowId) {
    final picked = _picked.toggle(snowId);
    setState(() {});
    if (!picked) _say(_fullText);
  }

  static final String _fullText = gv2FailureText(
    const Gv2GroupException(Gv2GroupFailure.full),
  );

  /// The candidates on screen (empty while they load).
  List<PickCandidate> get _candidates => _rosterMode
      ? (_roster ?? const <PickCandidate>[])
      : (ref.read(contactPickCandidatesProvider).value ??
          const <PickCandidate>[]);

  /// Pick every known account (as many as fit), or unpick them all when
  /// they are all picked already (or the group is full).
  void _selectAllKnown() {
    final cut = _picked.selectAllKnown(_candidates);
    setState(() {});
    if (cut) _say(_fullText);
  }

  void _showGroupNameDialog() {
    String groupName = '';
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: SnowColors.surface,
          title: const Text(
            'Group Name',
            style: TextStyle(color: SnowColors.textPrimary),
          ),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: SnowColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Enter group name',
              hintStyle: TextStyle(color: SnowColors.textTertiary),
            ),
            onChanged: (v) => groupName = v.trim(),
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
                final name = groupName;
                Navigator.of(ctx).pop();
                if (name.isNotEmpty) {
                  _createGroup(name);
                }
              },
              child: const Text(
                'Create',
                style: TextStyle(color: SnowColors.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  /// How long the screen waits for the server to accept a new v2 group
  /// before it leaves the rest to the outbox.
  static const Duration _createWait = Duration(seconds: 20);

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? SnowColors.error : SnowColors.surface,
      ),
    );
  }

  /// Group protocol v2: the group is made on this device and its members
  /// are invited (design §9.1) — each of them becomes a member when their
  /// app accepts. The server is told by the outbox: this waits for its
  /// answer for a while, then opens the chat. Without a connection the
  /// group is created later and shows up in the list then.
  Future<void> _createGroup(String groupName) async {
    if (_isCreating) return;
    final runtime = ref.read(gv2RuntimeProvider);
    if (runtime == null) {
      _say('Groups are not ready yet. Try again in a moment.', error: true);
      return;
    }
    if (utf8.encode(groupName).length > gv2MaxTitleNameBytes) {
      _say('This name is too long.', error: true);
      return;
    }
    setState(() => _isCreating = true);
    try {
      final groupId = await runtime.groups.create(
        title: groupName,
        invite: _picked.ids.toList(),
      );
      final store = ref.read(snowDatabaseProvider).gv2Store;
      Gv2GroupRow? row;
      var answered = true;
      try {
        row = await store
            .watchGroup(groupId)
            .firstWhere(
              (g) => g == null || g.membership != Gv2Membership.creating,
            )
            .timeout(_createWait);
      } on TimeoutException {
        answered = false;
      }
      if (!mounted) return;
      if (!answered) {
        _say(
          'No answer from the server yet. The group appears in your chats '
          'once it is created.',
        );
        context.pop();
        return;
      }
      if (row == null) {
        _say('The server did not accept the group.', error: true);
        return;
      }
      // The chat opens on the group's conversation row; the list learns of
      // it the same way it does for a group this account was invited to.
      await ref.read(conversationListProvider.notifier).syncGv2Group(groupId);
      if (mounted) context.pushReplacement('/chat/$groupId');
    } on Gv2GroupException catch (e) {
      _say(gv2FailureText(e), error: true);
    } catch (_) {
      _say('The group could not be created.', error: true);
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  /// The name shown for a picked account.
  String? _nameOf(String snowId) => _candidates
      .where((c) => c.snowId == snowId)
      .firstOrNull
      ?.name;

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SnowColors.textTertiary),
          ),
        ),
      );

  Widget _list(List<PickCandidate> candidates, String emptyText) =>
      AccountPickerList(
        candidates: candidates,
        selected: _picked.ids,
        onToggle: _toggleMember,
        onSelectAllKnown: _selectAllKnown,
        allKnownTaken: _picked.allKnownTaken(candidates),
        emptyText: emptyText,
      );

  /// The roster or the contacts, as an AccountPickerList.
  Widget _pickerList() {
    if (!_rosterMode) {
      return ref.watch(contactPickCandidatesProvider).when(
            data: (c) => _list(
                c,
                'No one to add yet. Add friends first, or write to someone '
                'in a 1:1 chat.'),
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, _) => _message("Couldn't load your friends."),
          );
    }
    if (_rosterFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Couldn't load the member list.",
              style: TextStyle(color: SnowColors.textTertiary),
            ),
            TextButton(
              onPressed: _loadRoster,
              child: const Text(
                'Try again',
                style: TextStyle(color: SnowColors.primary),
              ),
            ),
          ],
        ),
      );
    }
    final roster = _roster;
    if (roster == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return _list(roster, 'Nobody else is in this community yet.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _rosterMode && (_communityName ?? widget.communityName) != null
              ? 'New group · ${_communityName ?? widget.communityName}'
              : 'New Group',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected members chips
          if (_picked.ids.isNotEmpty)
            Container(
              height: 90,
              padding: const EdgeInsets.symmetric(
                horizontal: SnowSizes.md,
                vertical: SnowSizes.sm,
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _picked.ids.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: SnowSizes.sm),
                itemBuilder: (context, index) {
                  final snowId = _picked.ids.elementAt(index);
                  final name = _nameOf(snowId) ?? snowId;
                  return GestureDetector(
                    onTap: () => _toggleMember(snowId),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            SnowAvatar(
                              snowId: snowId,
                              size: SnowSizes.avatarMd,
                              displayName: name,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: SnowColors.error,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 12,
                                  color: SnowColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SnowSizes.xs),
                        SizedBox(
                          width: 60,
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: SnowColors.textSecondary,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

          if (_picked.ids.isNotEmpty)
            const Divider(color: SnowColors.divider, height: 1),

          // Member count hint
          Padding(
            padding: const EdgeInsets.all(SnowSizes.md),
            child: Text(
              '${_picked.ids.length} member${_picked.ids.length != 1 ? 's' : ''} selected'
              '${_picked.ids.length < _minMembers ? ' (minimum $_minMembers)' : ''}'
              '${_rosterMode ? ' · up to $_maxPicks' : ''}',
              style: const TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),

          Expanded(child: _pickerList()),
        ],
      ),
      floatingActionButton: _picked.ids.length >= _minMembers
          ? FloatingActionButton(
              onPressed: _isCreating ? null : _showGroupNameDialog,
              backgroundColor: SnowColors.primary,
              child: _isCreating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SnowColors.background,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_forward_rounded,
                      color: SnowColors.background,
                    ),
            )
          : null,
    );
  }
}
