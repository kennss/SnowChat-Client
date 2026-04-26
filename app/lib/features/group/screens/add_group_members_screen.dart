/// @file        add_group_members_screen.dart
/// @description Add-group-members screen — select contacts excluding existing members.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - AddGroupMembersScreen: add-group-members ConsumerStatefulWidget
///  - _toggleMember(): toggle member select/deselect
///  - _addMembers(): add selected members via server API call

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../app/providers.dart';
import '../../contacts/contact_provider.dart';

class AddGroupMembersScreen extends ConsumerStatefulWidget {
  final String groupId;
  final List<String> existingMemberSnowchatIds;

  const AddGroupMembersScreen({
    super.key,
    required this.groupId,
    required this.existingMemberSnowchatIds,
  });

  @override
  ConsumerState<AddGroupMembersScreen> createState() =>
      _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState
    extends ConsumerState<AddGroupMembersScreen> {
  final Set<String> _selectedIds = {};
  bool _isAdding = false;

  void _toggleMember(String snowChatId) {
    setState(() {
      if (_selectedIds.contains(snowChatId)) {
        _selectedIds.remove(snowChatId);
      } else {
        _selectedIds.add(snowChatId);
      }
    });
  }

  Future<void> _addMembers() async {
    if (_isAdding || _selectedIds.isEmpty) return;
    setState(() => _isAdding = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.post(
        ApiEndpoints.groupMembers(widget.groupId),
        data: {
          'snowchatIds': _selectedIds.toList(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedIds.length} member${_selectedIds.length > 1 ? 's' : ''} added',
            ),
            backgroundColor: SnowColors.primary,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add members: $e'),
            backgroundColor: SnowColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref
        .watch(contactProvider)
        .where((c) =>
            !c.isBlocked &&
            !widget.existingMemberSnowchatIds.contains(c.snowChatId))
        .toList();

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
              _selectedIds.isEmpty
                  ? 'Select members to add'
                  : '${_selectedIds.length} member${_selectedIds.length != 1 ? 's' : ''} selected',
              style: const TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),

          // Contact list (filtered)
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Text(
                      'No contacts available to add',
                      style: TextStyle(color: SnowColors.textTertiary),
                    ),
                  )
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      final isSelected =
                          _selectedIds.contains(contact.snowChatId);
                      return ListTile(
                        leading: SnowAvatar(
                          snowId: contact.snowChatId,
                          size: SnowSizes.avatarMd,
                          displayName: contact.displayName,
                        ),
                        title: Text(
                          contact.displayName ?? contact.snowChatId,
                          style: const TextStyle(
                            color: SnowColors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          '${contact.snowChatId.substring(0, 10)}...${contact.snowChatId.substring(contact.snowChatId.length - 4)}',
                          style: const TextStyle(
                            color: SnowColors.textTertiary,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          onChanged: (_) =>
                              _toggleMember(contact.snowChatId),
                          activeColor: SnowColors.primary,
                          checkColor: SnowColors.background,
                          side: const BorderSide(
                            color: SnowColors.textTertiary,
                          ),
                        ),
                        onTap: () => _toggleMember(contact.snowChatId),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedIds.isNotEmpty
          ? FloatingActionButton(
              onPressed: _isAdding ? null : _addMembers,
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
