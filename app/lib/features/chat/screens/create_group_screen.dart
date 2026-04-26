/// @file        create_group_screen.dart
/// @description Group-chat creation screen — pick members from contacts, enter group name, GMK encryption then server creation
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-10 Phase 8.8: GMK-based group-name E2EE)
///
/// @functions
///  - CreateGroupScreen: group-chat creation ConsumerStatefulWidget
///  - _showGroupNameDialog(): show group-name input dialog
///  - _createGroup(): generate GMK -> encrypt name -> per-member GMK E2EE -> atomic POST

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../core/crypto/group_metadata_crypto.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../app/providers.dart';
import '../../contacts/contact_provider.dart';
import '../models/conversation.dart';
import '../providers/conversation_list_provider.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final Set<String> _selectedIds = {};
  bool _isCreating = false;

  void _toggleMember(String snowChatId) {
    setState(() {
      if (_selectedIds.contains(snowChatId)) {
        _selectedIds.remove(snowChatId);
      } else {
        _selectedIds.add(snowChatId);
      }
    });
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

  Future<void> _createGroup(String groupName) async {
    if (_isCreating) return;
    setState(() => _isCreating = true);

    debugPrint('[CreateGroup] Creating group "$groupName" with members: $_selectedIds');

    try {
      // Phase 8.8: Generate GMK and encrypt group name
      final gmk = GroupMetadataCrypto.generateGMK();
      final encryptedName = GroupMetadataCrypto.encryptGroupName(gmk, groupName);
      debugPrint('[CreateGroup] GMK generated, name encrypted');

      final sessionManager = ref.read(signalSessionManagerProvider);
      final mySnowId = ref.read(currentSnowIdProvider) ?? '';

      // Step 1: Create group on server (encryptedName only, no plaintext)
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        ApiEndpoints.groups,
        data: {
          'memberSnowchatIds': _selectedIds.toList(),
          'encryptedName': encryptedName,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);
      final groupId = (data['groupId'] ?? data['id']) as String;
      debugPrint('[CreateGroup] Group created: $groupId');

      // Step 2: Store GMK locally
      await GroupMetadataCrypto.storeGMK(groupId, gmk, 0);

      // Step 3: Distribute signed GMK to each member via 1:1 E2EE
      final signingKeySeed = sessionManager.signal.signingKeySeed;
      final signature = signingKeySeed != null
          ? GroupMetadataCrypto.signGMK(
              signingKeySeed: signingKeySeed,
              groupId: groupId,
              gmk: gmk,
              epoch: 0,
            )
          : null;

      for (final memberId in _selectedIds) {
        if (memberId == mySnowId) continue;
        try {
          await sessionManager.ensureSession(memberId);
          final deviceId = await sessionManager.getDeviceIdForRecipient(memberId);
          final gmkPayload = jsonEncode({
            'type': 'group_metadata_key',
            'groupId': groupId,
            'gmk': base64Encode(gmk),
            'epoch': 0,
            if (signature != null) 'signature': base64Encode(signature),
            'coordinatorSnowId': mySnowId,
          });
          final encrypted = await sessionManager.encrypt(
            memberId, deviceId, Uint8List.fromList(utf8.encode(gmkPayload)),
          );
          ref.read(socketManagerProvider).sendPrivateMessage({
            'recipientId': memberId,
            'encryptedContent': {
              'ciphertext': base64Encode(encrypted['ciphertext'] as Uint8List),
            },
            'messageType': encrypted['messageType'],
            'type': 'group_metadata_key',
          });
          debugPrint('[CreateGroup] GMK sent to $memberId');
        } catch (e) {
          debugPrint('[CreateGroup] GMK send to $memberId failed: $e');
        }
      }

      final conversation = Conversation(
        id: groupId,
        type: ConversationType.group,
        groupId: groupId,
        title: groupName,
        participantIds: _selectedIds.toList(),
        createdAt: DateTime.now(),
      );

      Future.microtask(() {
        ref.read(conversationListProvider.notifier).addConversation(conversation);
        if (mounted) {
          context.pushReplacement('/chat/$groupId');
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: $e'),
            backgroundColor: SnowColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactProvider).where((c) => !c.isBlocked).toList();

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('New Group'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected members chips
          if (_selectedIds.isNotEmpty)
            Container(
              height: 90,
              padding: const EdgeInsets.symmetric(
                horizontal: SnowSizes.md,
                vertical: SnowSizes.sm,
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedIds.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: SnowSizes.sm),
                itemBuilder: (context, index) {
                  final snowId = _selectedIds.elementAt(index);
                  final contact = contacts
                      .where((c) => c.snowChatId == snowId)
                      .firstOrNull;
                  final name = contact?.displayName ?? snowId;
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

          if (_selectedIds.isNotEmpty)
            const Divider(color: SnowColors.divider, height: 1),

          // Member count hint
          Padding(
            padding: const EdgeInsets.all(SnowSizes.md),
            child: Text(
              '${_selectedIds.length} member${_selectedIds.length != 1 ? 's' : ''} selected'
              '${_selectedIds.length < 2 ? ' (minimum 2)' : ''}',
              style: const TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),

          // Contact list
          Expanded(
            child: contacts.isEmpty
                ? const Center(
                    child: Text(
                      'No contacts available',
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
      floatingActionButton: _selectedIds.length >= 2
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
