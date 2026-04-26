/// @file        new_chat_screen.dart
/// @description New-chat start screen — SnowChat ID input/validation, server user lookup, existing-conversation check, new-conversation creation
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-14)
///
/// @functions
///  - NewChatScreen: ConsumerStatefulWidget for starting a new chat
///  - _lookupUser(): user lookup on the server
///  - _startChat(): start a conversation or navigate to an existing one

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../core/network/api_endpoints.dart';
import '../../contacts/contact_provider.dart';
import '../models/conversation.dart';
import '../providers/conversation_list_provider.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _isSearching = false;
  Map<String, dynamic>? _foundUser;
  bool _isGroupMode = false;

  @override
  void initState() {
    super.initState();
    // Refresh contacts on screen open to pick up newly registered users
    Future.microtask(() => ref.read(contactProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Look up a user by SnowChat ID on the server.
  Future<void> _lookupUser(String snowId) async {
    setState(() {
      _isSearching = true;
      _error = null;
      _foundUser = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get(
        ApiEndpoints.userLookup(snowId),
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      setState(() {
        _foundUser = data;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _error = 'User not found';
        _isSearching = false;
      });
    }
  }

  Future<void> _startChat() async {
    final snowId = _controller.text.trim();
    final myId = ref.read(currentSnowIdProvider) ?? '';

    if (snowId.isEmpty) {
      setState(() => _error = 'Please enter a SnowChat ID');
      return;
    }

    if (!KeyDerivation.isValidSnowChatId(snowId)) {
      setState(() =>
          _error = 'Invalid SnowChat ID format (snow + 32 hex chars)');
      return;
    }

    if (snowId == myId) {
      setState(() => _error = 'You cannot chat with yourself');
      return;
    }

    // Check if conversation already exists
    final conversations = ref.read(conversationListProvider);
    final existing = conversations.where((c) =>
        c.type == ConversationType.direct &&
        c.participantIds.contains(snowId));

    if (existing.isNotEmpty) {
      context.pop();
      context.push('/chat/${existing.first.id}');
      return;
    }

    // Phase 3: Create conversation via server API (single ID)
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        ApiEndpoints.conversationFindOrCreate,
        data: {'recipientSnowchatId': snowId},
      );
      final convId = (response.data as Map)['id'] as String;

      // Add to conversation list BEFORE navigating so chatProvider
      // can resolve recipientSnowchatId immediately (avoids group fallback bug).
      final notifier = ref.read(conversationListProvider.notifier);
      final alreadyExists =
          ref.read(conversationListProvider).any((c) => c.id == convId);
      if (!alreadyExists) {
        notifier.addConversation(Conversation(
          id: convId,
          type: ConversationType.direct,
          participantIds: [myId, snowId],
          title: _foundUser?['displayName'] as String?,
          createdAt: DateTime.now(),
        ));
      }

      // Refresh full list in background (for server-accurate data)
      notifier.refresh();

      context.pop();
      context.push('/chat/$convId');
    } catch (e) {
      debugPrint('[NewChat] Failed to create conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start conversation')),
        );
      }
    }
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
        title: const Text('New Chat'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SnowSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode selector: two equal cards
            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    icon: Icons.person_rounded,
                    label: 'Message',
                    isSelected: !_isGroupMode,
                    onTap: () => setState(() => _isGroupMode = false),
                  ),
                ),
                const SizedBox(width: SnowSizes.md),
                Expanded(
                  child: _ModeCard(
                    icon: Icons.group_add_rounded,
                    label: 'Group',
                    isSelected: _isGroupMode,
                    onTap: () {
                      context.push('/create-group');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: SnowSizes.lg),
            const Divider(color: SnowColors.divider, height: 1),
            const SizedBox(height: SnowSizes.lg),

            const Text(
              'Enter SnowChat ID',
              style: TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SnowSizes.sm),
            const Text(
              'Enter the recipient\'s SnowChat ID to start a conversation.',
              style: TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: SnowSizes.lg),

            // ID Input
            TextField(
              controller: _controller,
              onChanged: (value) {
                setState(() => _error = null);
                final trimmed = value.trim();
                if (KeyDerivation.isValidSnowChatId(trimmed)) {
                  _lookupUser(trimmed);
                } else {
                  setState(() => _foundUser = null);
                }
              },
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'snow...',
                errorText: _error,
                prefixIcon: const Icon(
                  Icons.person_rounded,
                  color: SnowColors.textTertiary,
                ),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(
                        Icons.search_rounded,
                        color: SnowColors.textTertiary,
                      ),
              ),
            ),

            // Show found user info
            if (_foundUser != null) ...[
              const SizedBox(height: SnowSizes.md),
              Container(
                padding: const EdgeInsets.all(SnowSizes.md),
                decoration: BoxDecoration(
                  color: SnowColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SnowColors.primary.withAlpha(77)),
                ),
                child: Row(
                  children: [
                    SnowAvatar(
                      snowId: _foundUser!['snowchatId'] as String? ?? '',
                      size: 40,
                      displayName:
                          _foundUser!['displayName'] as String? ?? '',
                    ),
                    const SizedBox(width: SnowSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _foundUser!['displayName'] as String? ??
                                'Unknown',
                            style: const TextStyle(
                              color: SnowColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _foundUser!['snowchatId'] as String? ?? '',
                            style: const TextStyle(
                              color: SnowColors.textTertiary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      color: SnowColors.primary,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: SnowSizes.lg),

            // Start chat button
            ElevatedButton(
              onPressed: _startChat,
              child: const Text('Start Chat'),
            ),

            const SizedBox(height: SnowSizes.xl),

            // Contacts
            const Text(
              'Contacts',
              style: TextStyle(
                color: SnowColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: SnowSizes.md),

            ...ref.watch(contactProvider)
                .where((c) => !c.isBlocked)
                .map((c) => _buildContactItem(
                      c.displayName ?? c.snowChatId,
                      c.snowChatId,
                    )),
          ],
        ),
      ),
    );
  }

  /// Start chat directly from a contact tap.
  void _startChatWithContact(String snowId) {
    _controller.text = snowId;
    _startChat();
  }

  Widget _buildContactItem(String name, String snowId) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SnowAvatar(snowId: snowId, size: 40, displayName: name),
      title: Text(
        name,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        '${snowId.substring(0, 10)}...${snowId.substring(snowId.length - 4)}',
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
      onTap: () => _startChatWithContact(snowId),
    );
  }
}

/// Card widget for the Message/Group mode selector.
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isSelected
              ? SnowColors.primary.withAlpha(25)
              : SnowColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? SnowColors.primary : SnowColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? SnowColors.primary : SnowColors.textTertiary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color:
                    isSelected ? SnowColors.primary : SnowColors.textSecondary,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
