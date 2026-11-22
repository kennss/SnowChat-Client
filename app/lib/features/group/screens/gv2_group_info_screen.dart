/// @file        gv2_group_info_screen.dart
/// @description Group info for a group protocol v2 group: its name, its
///              members with their roles, the accounts invited and not yet
///              in, and what this account may do there — rename, invite,
///              take an invite back, make or unmake an admin, hand the
///              group over, remove a member, leave, end the group. Shows
///              the group as this device holds it; every change is an entry
///              in the group's change log (Gv2GroupActions).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (a leave or end that was made takes the chat from the list also when the screen closed meanwhile; P5.6: a member or invite whose ciphertext names no account can be removed / taken back; Add Members counts every place taken; the leave dialog is shared with the chat screen — askGv2Leave; P5.6: shown from the stored rows while groups are not running — says so, offers no change; a failed read is not "not on this device"). Earlier 2026-11-20 (the server keys this app trusts: a paused note, and a group created under other keys)
///
/// @functions
///  - Gv2GroupInfoScreen: the screen
///  - _run(): make a change, showing progress and why it failed
///  - _catchUp(): sync the group's change log (on opening, and on a pull)
///  - _rename() / _memberSheet() / _confirm(): the dialogs
///  - _leave(): leave (optionally taking back this account's messages),
///    then remove the chat from this device
///
/// Notes:
///  - Which controls show follows Gv2GroupView (the permission table of the
///    change log, design §5.3); the change is checked again when it is
///    built and by the server.
///  - A member whose account this device could not confirm is marked: it
///    receives nothing from this device and can be given no role.
///  - Leaving removes the chat from this device, as it does for a v1 group.
///    A group this account was removed from stays, read-only, until the
///    user removes its chat.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/group_v2/gv2_groups.dart';
import '../../../core/group_v2/gv2_payloads.dart' show gv2MaxTitleNameBytes;
import '../../../core/storage/tables/gv2_tables.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../providers/gv2_group_provider.dart';
import '../widgets/gv2_leave_dialog.dart';

class Gv2GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;

  const Gv2GroupInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<Gv2GroupInfoScreen> createState() => _Gv2GroupInfoScreenState();
}

class _Gv2GroupInfoScreenState extends ConsumerState<Gv2GroupInfoScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Catch up with the group's change log (what is shown here is this
    // device's copy; an invite that was declined, for one, is told to
    // nobody and shows only in the log), and look up the members' display
    // names, at most once a day per member.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_catchUp());
      ref.read(gv2RuntimeProvider)?.groups.refreshNames(widget.groupId);
    });
  }

  /// Ask for a sync of the group through its inbox lane (syncs of one group
  /// are spaced by the messaging layer). Never throws: the screen goes on
  /// showing what this device holds.
  Future<void> _catchUp() async {
    try {
      await ref.read(gv2RuntimeProvider)?.inbox.requestSync(widget.groupId);
    } catch (_) {
      // Shown as it is held.
    }
  }

  Gv2GroupActions? get _groups => ref.read(gv2RuntimeProvider)?.groups;

  void _say(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? SnowColors.error : SnowColors.surface,
      ),
    );
  }

  /// Make a change: one at a time, with a progress bar while the server is
  /// asked, and the reason when it could not be made. Returns whether it
  /// was made.
  Future<bool> _run(Future<void> Function(Gv2GroupActions groups) change) async {
    if (_busy) return false;
    final groups = _groups;
    if (groups == null) {
      _say('Groups are not running on this device yet. Try again once it can '
          'reach the server.', error: true);
      return false;
    }
    setState(() => _busy = true);
    try {
      await change(groups);
      return true;
    } catch (e) {
      _say(gv2FailureText(e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String text,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: Text(title, style: const TextStyle(color: SnowColors.textPrimary)),
        content: Text(
          text,
          style: const TextStyle(color: SnowColors.textSecondary),
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
            child: Text(action, style: const TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _rename(Gv2GroupView group) async {
    final controller = TextEditingController(text: group.title ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Group name',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: SnowColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Enter group name',
            hintStyle: TextStyle(color: SnowColors.textTertiary),
          ),
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
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text(
              'Save',
              style: TextStyle(color: SnowColors.primary),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == group.title) return;
    if (utf8.encode(name).length > gv2MaxTitleNameBytes) {
      _say('This name is too long.', error: true);
      return;
    }
    await _run((groups) => groups.setTitle(widget.groupId, name));
  }

  void _memberSheet(Gv2GroupView group, Gv2MemberView member) {
    final snowId = member.snowId;
    // Roles and ownership go only to an account (canSetRole / canMakeOwner
    // ask for one); a removal names the ciphertext.
    final setRole = snowId != null && group.canSetRole(member);
    final makeOwner = snowId != null && group.canMakeOwner(member);
    final remove = group.canRemove(member);
    if (!setRole && !makeOwner && !remove) return;

    Widget option(IconData icon, String label, VoidCallback onTap,
        {bool danger = false}) {
      final color = danger ? SnowColors.error : SnowColors.textPrimary;
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      );
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SnowColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(SnowSizes.md),
              child: Text(
                member.name,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (setRole && !member.isAdmin && member.confirmed)
              option(
                Icons.shield_outlined,
                'Make admin',
                () => _run(
                  (groups) => groups.setRole(widget.groupId, snowId!, admin: true),
                ),
              ),
            if (setRole && member.isAdmin)
              option(
                Icons.remove_moderator_outlined,
                'Remove as admin',
                () => _run(
                  (groups) =>
                      groups.setRole(widget.groupId, snowId!, admin: false),
                ),
              ),
            if (makeOwner)
              option(Icons.workspace_premium_outlined, 'Make owner', () async {
                final ok = await _confirm(
                  title: 'Hand over the group',
                  text: '${member.name} becomes the owner. You stay in the '
                      'group as an admin.',
                  action: 'Hand over',
                );
                if (ok) {
                  await _run(
                    (groups) => groups.transferOwner(widget.groupId, snowId!),
                  );
                }
              }),
            if (remove)
              option(
                Icons.person_remove_outlined,
                'Remove from group',
                () async {
                  final ok = await _confirm(
                    title: 'Remove ${member.name}',
                    text: 'They can no longer read new messages of this '
                        'group.',
                    action: 'Remove',
                  );
                  if (ok) {
                    await _run(
                      (groups) =>
                          groups.removeMember(widget.groupId, member.ciphertext),
                    );
                  }
                },
                danger: true,
              ),
            const SizedBox(height: SnowSizes.sm),
          ],
        ),
      ),
    );
  }

  /// Leave the group, then remove its chat from this device and go back to
  /// the list. Nothing is removed when the leave could not be made.
  Future<void> _leave({required bool deleteMyMessages}) => _takeOut(
    (chat) => deleteMyMessages
        ? chat.leaveAndDeleteMyMessages()
        : chat.leaveGroup(),
  );

  /// Make a change that takes this account out of the group (a leave, the
  /// end). When it was made the chat goes from the list — also when this
  /// screen was closed meanwhile — and the list is shown; when not, why.
  Future<void> _takeOut(Future<void> Function(ChatNotifier chat) change) async {
    if (_busy) return;
    setState(() => _busy = true);
    final chat = ref.read(chatProvider(widget.groupId).notifier);
    final list = ref.read(conversationListProvider.notifier);
    try {
      await change(chat);
    } catch (e) {
      _say(gv2FailureText(e), error: true);
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      list.removeConversation(widget.groupId);
    } catch (_) {
      // The list was taken down meanwhile (a reset): nothing to update.
    }
    if (mounted) context.go('/chat');
  }

  Future<void> _askLeave(Gv2GroupView group) async {
    final choice = await askGv2Leave(context, group);
    if (choice == null) return;
    await _leave(deleteMyMessages: choice == Gv2LeaveChoice.leaveAndDelete);
  }

  Future<void> _askEnd() async {
    final ok = await _confirm(
      title: 'End group',
      text: 'The group ends for everyone. Nobody can write in it again, and '
          'this cannot be undone.',
      action: 'End group',
    );
    if (!ok) return;
    await _takeOut((chat) => chat.deleteGroup());
  }

  static String _roleLabel(Gv2MemberView m) =>
      m.isOwner ? 'Owner' : (m.isAdmin ? 'Admin' : '');

  /// What this device knows of the member beyond its role; null when there
  /// is nothing to say.
  static (String, Color)? _memberNote(Gv2MemberView m) {
    if (m.reach == Gv2Reach.deleted) {
      return ('Deleted account', SnowColors.error);
    }
    if (m.snowId == null || (!m.confirmed && !m.unchecked)) {
      return ('Not verified', SnowColors.error);
    }
    if (m.unchecked) return ('Checking…', SnowColors.textTertiary);
    if (m.reach == Gv2Reach.unreachable) {
      return ('Not reachable', SnowColors.textTertiary);
    }
    return null;
  }

  static String? _standingNote(Gv2Standing standing) => switch (standing) {
    Gv2Standing.awaitingConfirm =>
      'Waiting for a member to confirm this device.',
    Gv2Standing.withheld => 'The server is holding back changes of this group.',
    Gv2Standing.serverKeysDiffer =>
      'The server is not using the keys this app trusts. Groups are paused.',
    Gv2Standing.updateRequired => 'Update SnowChat to go on using this group.',
    Gv2Standing.frozen =>
      'The server showed two different histories of this group. It is '
          'read-only; leaving removes it.',
    Gv2Standing.gone => 'You are no longer in this group.',
    Gv2Standing.notReady =>
      'Groups are not running on this device yet. They start once it can '
          'reach the server.',
    Gv2Standing.creating => 'This group is still being created.',
    Gv2Standing.invited => 'You are invited to this group.',
    Gv2Standing.usable => null,
  };

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 10)),
  );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: SnowSizes.md,
      vertical: SnowSizes.sm,
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: SnowColors.textTertiary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _action(IconData icon, String label, VoidCallback onTap) => ListTile(
    leading: Icon(icon, color: SnowColors.error),
    title: Text(label, style: const TextStyle(color: SnowColors.error)),
    onTap: _busy ? null : onTap,
  );

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gv2GroupViewProvider(widget.groupId));
    final group = view.valueOrNull;
    // No row is "not on this device" only where the groups can be read.
    final readable = !view.hasError && ref.watch(gv2GroupsOnDeviceProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Group Info'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: SnowColors.primary,
                ),
              )
            : null,
      ),
      body: view.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: SnowColors.primary),
            )
          : group == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(SnowSizes.lg),
                child: Text(
                  readable
                      ? 'This group is not on this device.'
                      : 'Groups are not running on this device yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: SnowColors.textTertiary),
                ),
              ),
            )
          : _body(group),
    );
  }

  Widget _body(Gv2GroupView group) {
    final name = (group.title == null || group.title!.isEmpty)
        ? 'Unnamed Group'
        : group.title!;
    // A group created under other server keys than this app trusts says so
    // (a rename records the current ones), when nothing weightier does.
    final note = _standingNote(group.standing) ??
        (group.titleKeysMatch == false
            ? 'This group was created under other server keys than this app '
                'trusts. Renaming it records the current ones.'
            : null);
    final gone = group.standing == Gv2Standing.gone;

    return RefreshIndicator(
      onRefresh: _catchUp,
      color: SnowColors.primary,
      child: _list(group, name: name, note: note, gone: gone),
    );
  }

  Widget _list(
    Gv2GroupView group, {
    required String name,
    required String? note,
    required bool gone,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: SnowSizes.xl),
        Center(
          child: SnowAvatar(snowId: widget.groupId, size: 80, displayName: name),
        ),
        const SizedBox(height: SnowSizes.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (group.canRename) ...[
              const SizedBox(width: SnowSizes.sm),
              GestureDetector(
                onTap: _busy ? null : () => _rename(group),
                child: const Icon(
                  Icons.edit_rounded,
                  size: SnowSizes.iconSm,
                  color: SnowColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SnowSizes.lg,
              SnowSizes.sm,
              SnowSizes.lg,
              0,
            ),
            child: Text(
              note,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: group.standing == Gv2Standing.frozen
                    ? SnowColors.error
                    : SnowColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(height: SnowSizes.xl),
        const Divider(color: SnowColors.divider, height: 1),

        if (!gone) ...[
          _sectionTitle('Members (${group.members.length})'),
          if (group.canInvite)
            ListTile(
              leading: Container(
                width: SnowSizes.avatarMd,
                height: SnowSizes.avatarMd,
                decoration: BoxDecoration(
                  color: SnowColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add_rounded,
                  color: SnowColors.primary,
                  size: SnowSizes.iconMd,
                ),
              ),
              title: const Text(
                'Add Members',
                style: TextStyle(
                  color: SnowColors.primary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: _busy
                  ? null
                  : () => context.push(
                      '/add-group-members/${widget.groupId}',
                      extra: (
                        existing: [
                          for (final m in group.members) ?m.snowId,
                          for (final i in group.invitees) ?i.snowId,
                        ],
                        // Every place, those that name no account included.
                        taken: group.placesTaken,
                      ),
                    ),
            ),
          for (final member in group.members)
            ListTile(
              leading: SnowAvatar(
                snowId: member.snowId ?? widget.groupId,
                size: SnowSizes.avatarMd,
                displayName: member.name,
              ),
              title: Text(
                member.isMe ? '${member.name} (you)' : member.name,
                style: TextStyle(
                  color: member.confirmed
                      ? SnowColors.textPrimary
                      : SnowColors.textTertiary,
                  fontSize: 15,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_memberNote(member) case (final text, final color))
                    _chip(text, color),
                  if (_roleLabel(member).isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      _roleLabel(member),
                      style: const TextStyle(
                        color: SnowColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: _busy ? null : () => _memberSheet(group, member),
            ),

          if (group.invitees.isNotEmpty) ...[
            const Divider(color: SnowColors.divider, height: 1),
            _sectionTitle('Invited (${group.invitees.length})'),
            for (final invitee in group.invitees)
              ListTile(
                leading: SnowAvatar(
                  snowId: invitee.snowId ?? widget.groupId,
                  size: SnowSizes.avatarMd,
                  displayName: invitee.name,
                ),
                title: Text(
                  invitee.name,
                  style: const TextStyle(
                    color: SnowColors.textTertiary,
                    fontSize: 15,
                  ),
                ),
                subtitle: const Text(
                  'Has not accepted yet',
                  style: TextStyle(color: SnowColors.textTertiary, fontSize: 12),
                ),
                trailing: group.canRevoke(invitee)
                    ? TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                (groups) => groups.revokePending(
                                  widget.groupId,
                                  invitee.ciphertext,
                                ),
                              ),
                        child: const Text(
                          'Take back',
                          style: TextStyle(color: SnowColors.error),
                        ),
                      )
                    : null,
              ),
          ],
          const Divider(color: SnowColors.divider, height: 1),
        ],

        if (group.canLeave)
          _action(
            Icons.exit_to_app_rounded,
            'Leave group',
            () => _askLeave(group),
          ),
        if (group.canEnd)
          _action(Icons.delete_forever_rounded, 'End group', _askEnd),
        if (gone)
          _action(Icons.delete_outline_rounded, 'Remove chat', () async {
            final ok = await _confirm(
              title: 'Remove chat',
              text: 'The messages and media of this group will be removed '
                  'from this device.',
              action: 'Remove',
            );
            if (!ok || !mounted) return;
            await ref.read(chatProvider(widget.groupId).notifier).deleteChat();
            if (!mounted) return;
            ref
                .read(conversationListProvider.notifier)
                .removeConversation(widget.groupId);
            context.go('/chat');
          }),
        const SizedBox(height: SnowSizes.xl),
      ],
    );
  }
}
