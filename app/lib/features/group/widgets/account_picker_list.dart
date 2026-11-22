/// @file        account_picker_list.dart
/// @description The list of a group picker (new group, from the contacts or
///              a community roster; add members): the accounts this user
///              knows (PickCandidate.known — chosen by an action of their
///              own), with "Select all" where the screen offers it, then the
///              others under "Not verified", listed only after a warning
///              that an invite gives an account the group's key for good.
///              Every account shows its snowId (the name is the server's
///              word). The lists: this user's friends and chosen 1:1 peers
///              (design 2026-11-22-friend-graph-off-server §5.6), or a
///              community roster.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (the warning no longer says every list is kept by the server — the
///              friend list is this device's; a roster and every name still are the server's word)
///
/// @functions
///  - AccountPickerList: the sections, the rows and the warning
///  - accountShortId(): a snowId as the pickers show it
///  - accountPickerWarningTitle: the warning's title (for tests)
library;

import 'package:flutter/material.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../providers/pick_candidates.dart';

/// A snowId as the pickers show it.
String accountShortId(String snowId) =>
    '${snowId.substring(0, 10)}...${snowId.substring(snowId.length - 4)}';

const String accountPickerWarningTitle = 'Accounts you have not verified';

class AccountPickerList extends StatefulWidget {
  final List<PickCandidate> candidates;
  final Set<String> selected;
  final void Function(String snowId) onToggle;

  /// "Select all" on the known section (null: none); [allKnownTaken] turns
  /// it into "Clear".
  final VoidCallback? onSelectAllKnown;
  final bool allKnownTaken;

  /// Shown when there is no account at all.
  final String emptyText;

  const AccountPickerList({
    super.key,
    required this.candidates,
    required this.selected,
    required this.onToggle,
    required this.emptyText,
    this.onSelectAllKnown,
    this.allKnownTaken = false,
  });

  @override
  State<AccountPickerList> createState() => _AccountPickerListState();
}

class _AccountPickerListState extends State<AccountPickerList> {
  /// The user chose to see the accounts they have not verified.
  bool _unknownShown = false;

  Future<void> _showUnknown() async {
    final show = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          accountPickerWarningTitle,
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'You have not chosen these accounts yourself on this device — no '
          'friend request, no message from you, no safety number checked. A '
          "community's member list and every name come from the server. An "
          "invite gives an account this group's key for good: it keeps the "
          'key even if it never joins or you remove it later. Invite only '
          'people you know.',
          style: TextStyle(color: SnowColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SnowColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Show them',
              style: TextStyle(color: SnowColors.primary),
            ),
          ),
        ],
      ),
    );
    if (show == true && mounted) setState(() => _unknownShown = true);
  }

  Widget _accountTile(PickCandidate c) {
    final isSelected = widget.selected.contains(c.snowId);
    return ListTile(
      leading: SnowAvatar(
        snowId: c.snowId,
        size: SnowSizes.avatarMd,
        displayName: c.name,
      ),
      title: Text(
        c.name ?? c.snowId,
        style: const TextStyle(color: SnowColors.textPrimary, fontSize: 15),
      ),
      subtitle: Text(
        accountShortId(c.snowId),
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
      trailing: Checkbox(
        value: isSelected,
        onChanged: (_) => widget.onToggle(c.snowId),
        activeColor: SnowColors.primary,
        checkColor: SnowColors.background,
        side: const BorderSide(color: SnowColors.textTertiary),
      ),
      onTap: () => widget.onToggle(c.snowId),
    );
  }

  Widget _header(String text, {bool selectAll = false}) {
    final onSelectAll = widget.onSelectAllKnown;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SnowSizes.md,
        SnowSizes.md,
        SnowSizes.sm,
        SnowSizes.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: SnowColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (selectAll && onSelectAll != null)
            TextButton(
              onPressed: onSelectAll,
              child: Text(
                widget.allKnownTaken ? 'Clear' : 'Select all',
                style: const TextStyle(color: SnowColors.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _showUnknownRow(int count) => ListTile(
        leading: const Icon(
          Icons.visibility_outlined,
          color: SnowColors.textTertiary,
        ),
        title: Text(
          "Show $count account${count == 1 ? '' : 's'} you haven't verified",
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        subtitle: const Text(
          "You haven't added them as a friend, written to them or checked "
          'their safety number on this device.',
          style: TextStyle(color: SnowColors.textTertiary, fontSize: 12),
        ),
        onTap: _showUnknown,
      );

  @override
  Widget build(BuildContext context) {
    final candidates = widget.candidates;
    if (candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Text(
            widget.emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SnowColors.textTertiary),
          ),
        ),
      );
    }
    final known = [for (final c in candidates) if (c.known) c];
    final unknown = [for (final c in candidates) if (!c.known) c];
    final rows = <Widget Function()>[
      if (known.isNotEmpty) ...[
        () => _header('People you know (${known.length})', selectAll: true),
        for (final c in known) () => _accountTile(c),
      ],
      if (unknown.isNotEmpty) ...[
        () => _header('Not verified (${unknown.length})'),
        if (_unknownShown)
          for (final c in unknown) () => _accountTile(c)
        else
          () => _showUnknownRow(unknown.length),
      ],
    ];
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](),
    );
  }
}
