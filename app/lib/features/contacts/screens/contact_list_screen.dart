/// @file        contact_list_screen.dart
/// @description Contact list screen — show active/blocked contacts, contact-options bottom sheet (message, block, delete).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///  - Converted to ConsumerStatefulWidget — auto refresh on tab entry
///
/// @functions
///  - ContactListScreen: ConsumerStatefulWidget that displays the contact list

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../shared/widgets/snow_id_display.dart';
import '../../../app/providers.dart';
import '../contact_provider.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../../../core/network/api_endpoints.dart';

class ContactListScreen extends ConsumerStatefulWidget {
  const ContactListScreen({super.key});

  @override
  ConsumerState<ContactListScreen> createState() => _ContactListScreenState();
}

class _ContactListScreenState extends ConsumerState<ContactListScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh contacts on tab entry for latest displayNames
    Future.microtask(() => ref.read(contactProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactProvider);
    final activeContacts = contacts.where((c) => !c.isBlocked).toList();
    final blockedContacts = contacts.where((c) => c.isBlocked).toList();

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded, color: SnowColors.primary),
            onPressed: () => context.push('/my-qr'),
          ),
          IconButton(
            icon:
                const Icon(Icons.person_add_rounded, color: SnowColors.primary),
            onPressed: () => context.push('/add-contact'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(contactProvider.notifier).refresh(),
        color: SnowColors.primary,
        backgroundColor: SnowColors.surface,
        child: contacts.isEmpty
          ? _buildEmptyState(context)
          : ListView(
              children: [
                // Active contacts
                if (activeContacts.isNotEmpty) ...[
                  _buildSectionHeader('Contacts (${activeContacts.length})'),
                  ...activeContacts.map((c) => _buildContactTile(context, ref, c)),
                ],

                // Blocked
                if (blockedContacts.isNotEmpty) ...[
                  const SizedBox(height: SnowSizes.md),
                  _buildSectionHeader('Blocked (${blockedContacts.length})'),
                  ...blockedContacts
                      .map((c) => _buildContactTile(context, ref, c)),
                ],
              ],
            ),
      ), // RefreshIndicator
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildContactTile(
      BuildContext context, WidgetRef ref, Contact contact) {
    final presenceService = ref.watch(presenceServiceProvider);
    final isOnline = presenceService.isOnline(contact.snowChatId);

    return ListTile(
      leading: Stack(
        children: [
          SnowAvatar(
            snowId: contact.snowChatId,
            size: 44,
            displayName: contact.displayName,
          ),
          if (isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: SnowColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SnowColors.background,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        contact.displayName ?? 'Unknown',
        style: TextStyle(
          color: contact.isBlocked
              ? SnowColors.textTertiary
              : SnowColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          decoration:
              contact.isBlocked ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: SnowIdDisplay(
        snowId: contact.snowChatId,
        compact: true,
        showCopy: false,
        fontSize: 11,
      ),
      trailing: contact.isTrusted
          ? const Icon(
              Icons.verified_rounded,
              color: SnowColors.primary,
              size: 18,
            )
          : null,
      onTap: () {
        _showContactOptions(context, ref, contact);
      },
    );
  }

  void _showContactOptions(
      BuildContext context, WidgetRef ref, Contact contact) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SnowColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
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
              SnowAvatar(
                snowId: contact.snowChatId,
                size: 56,
                displayName: contact.displayName,
              ),
              const SizedBox(height: 12),
              Text(
                contact.displayName ?? 'Unknown',
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SnowIdDisplay(
                snowId: contact.snowChatId,
                compact: true,
                fontSize: 12,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading:
                    const Icon(Icons.chat_rounded, color: SnowColors.primary),
                title: const Text('Send Message',
                    style: TextStyle(color: SnowColors.textPrimary)),
                onTap: () async {
                  Navigator.pop(context);
                  // Find or create conversation via server API (Phase 3: single ID)
                  try {
                    // Check local drift DB first
                    final convDao = ref.read(conversationDaoProvider);
                    final existing = await convDao.findDirectByParticipant(contact.snowChatId);
                    if (existing != null) {
                      context.push('/chat/${existing.id}');
                      return;
                    }
                    // Not found locally → call server
                    final apiClient = ref.read(apiClientProvider);
                    final response = await apiClient.post(
                      ApiEndpoints.conversationFindOrCreate,
                      data: {'recipientSnowchatId': contact.snowChatId},
                    );
                    final convId = (response.data as Map)['id'] as String;
                    // Refresh conversation list so the new conversation appears
                    ref.read(conversationListProvider.notifier).refresh();
                    context.push('/chat/$convId');
                  } catch (e) {
                    debugPrint('[Contact] Failed to create conversation: $e');
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  contact.isBlocked
                      ? Icons.check_circle_rounded
                      : Icons.block_rounded,
                  color: contact.isBlocked
                      ? SnowColors.primary
                      : SnowColors.error,
                ),
                title: Text(
                  contact.isBlocked ? 'Unblock' : 'Block',
                  style: TextStyle(
                    color: contact.isBlocked
                        ? SnowColors.textPrimary
                        : SnowColors.error,
                  ),
                ),
                onTap: () {
                  if (contact.isBlocked) {
                    ref
                        .read(contactProvider.notifier)
                        .unblockContact(contact.snowChatId);
                  } else {
                    ref
                        .read(contactProvider.notifier)
                        .blockContact(contact.snowChatId);
                  }
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_rounded, color: SnowColors.error),
                title: const Text('Remove Contact',
                    style: TextStyle(color: SnowColors.error)),
                onTap: () {
                  ref
                      .read(contactProvider.notifier)
                      .removeContact(contact.snowChatId);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.people_outline_rounded,
            size: 64,
            color: SnowColors.textTertiary,
          ),
          const SizedBox(height: SnowSizes.md),
          const Text(
            'No contacts yet',
            style: TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: SnowSizes.lg),
          ElevatedButton.icon(
            onPressed: () => context.push('/add-contact'),
            icon: const Icon(Icons.person_add_rounded, size: 20),
            label: const Text('Add Contact'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 44),
            ),
          ),
        ],
      ),
    );
  }
}
