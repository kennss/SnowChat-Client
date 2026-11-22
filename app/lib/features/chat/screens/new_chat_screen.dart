/// @file        new_chat_screen.dart
/// @description New-chat start screen — SnowChat ID input/validation, account resolve, existing-conversation check, new-conversation creation (on this device)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (the list under the id field is the friends on this device (tap → their
///              chat); a typed id of the friend list is not looked up on the server, any other is
///              resolved once; the chat opens through openDirectChatWith (an account this user
///              blocked asks to unblock first) in place of this screen; a rate-limited lookup is
///              told apart from "not found"). Earlier 2026-11-22 (friend graph off the server —
///              bindings only: the id is resolved with POST /users/resolve (ContactLookup); no
///              find-or-create — the room is made on this device). Earlier 2026-11-20 (the Group card shows only where groups can run (gv2GroupsAvailable);
///              _startChat: the room id is the recipient's snowId — the server's reply only says
///              whether a 1:1 may start, it never names the room). Earlier 2026-04-26 (header English translation; previous: 2026-04-14)
///
/// @functions
///  - NewChatScreen: ConsumerStatefulWidget for starting a new chat
///  - _lookupUser(): the typed SnowChat ID — a friend from this device, else POST /users/resolve
///  - _startChat(): open the chat with the typed id (openDirectChatWith, in place of this screen)
///  - _buildFriendItem(): a friend row (tap → its chat)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../core/contacts/contact_lookup.dart' show FoundAccount;
import '../../../core/crypto/key_derivation.dart';
import '../../../core/group_v2/gv2_trusted_keys.dart' show gv2GroupsAvailable;
import '../../contacts/contact_provider.dart';
import '../models/conversation.dart';
import '../providers/conversation_list_provider.dart';
import '../services/start_direct_chat.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _isSearching = false;

  /// The account the typed id names: its snowId and name (from the friend
  /// list, or from the server's answer — then [_resolved] holds it).
  ({String snowId, String? name})? _foundUser;
  FoundAccount? _resolved;
  bool _isGroupMode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The account [snowId] names: a friend of this device's list (no server
  /// call), else the server's answer (POST /users/resolve).
  Future<void> _lookupUser(String snowId) async {
    for (final c in ref.read(contactProvider)) {
      if (c.snowChatId == snowId) {
        setState(() {
          _error = null;
          _resolved = null;
          _foundUser = (snowId: snowId, name: c.displayName);
        });
        return;
      }
    }
    setState(() {
      _isSearching = true;
      _error = null;
      _foundUser = null;
      _resolved = null;
    });

    final result = await ref.read(contactLookupProvider).resolve(snowId);
    if (!mounted || _controller.text.trim() != snowId) return;
    final account = result.account;
    setState(() {
      _isSearching = false;
      if (account == null) {
        _error = result.notFound
            ? 'User not found'
            : result.rateLimited
                ? 'Too many lookups. Please try again in a bit.'
                : 'Could not look this ID up';
      } else {
        _resolved = account;
        _foundUser = (snowId: account.snowId, name: account.displayName);
      }
    });
  }

  Future<void> _startChat() async {
    final snowId = _controller.text.trim();
    final myId = ref.read(currentSnowIdProvider) ?? '';

    if (snowId.isEmpty) {
      setState(() => _error = 'Please enter a SnowChat ID');
      return;
    }

    if (!KeyDerivation.isValidSnowChatId(snowId)) {
      setState(
        () => _error = 'Invalid SnowChat ID format (snow + 32 hex chars)',
      );
      return;
    }

    if (snowId == myId) {
      setState(() => _error = 'You cannot chat with yourself');
      return;
    }

    // A chat with the account exists already: open it, nothing to look up.
    final exists = ref.read(conversationListProvider).any(
          (c) => c.type == ConversationType.direct && c.id == snowId,
        );
    if (exists) {
      await openDirectChatWith(
        context: context,
        ref: ref,
        recipientSnowchatId: snowId,
        replaceCurrent: true,
      );
      return;
    }

    // The typed id must be an account: looked up when that has not run for
    // it yet (a friend needs no server call).
    if (_foundUser?.snowId != snowId) await _lookupUser(snowId);
    if (!mounted) return;
    final found = _foundUser;
    if (found == null || found.snowId != snowId) return;
    // The room is made on this device (its id is the peer's snowId); the
    // chat takes this screen's place.
    await openDirectChatWith(
      context: context,
      ref: ref,
      recipientSnowchatId: snowId,
      recipientDisplayName: found.name,
      resolved: _resolved,
      replaceCurrent: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
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
            // Mode selector: two equal cards — only where groups can run
            // (this build pins the server keys); otherwise this screen
            // starts a 1:1 only.
            if (gv2GroupsAvailable) ...[
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
            ],

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
              style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
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
                  setState(() {
                    _foundUser = null;
                    _resolved = null;
                  });
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
                      snowId: _foundUser!.snowId,
                      size: 40,
                      displayName: _foundUser!.name ?? '',
                    ),
                    const SizedBox(width: SnowSizes.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _foundUser!.name ?? 'Unknown',
                            style: const TextStyle(
                              color: SnowColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _foundUser!.snowId,
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

            // Friends (this device's list)
            const Text(
              'Friends',
              style: TextStyle(
                color: SnowColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: SnowSizes.md),

            if (friends.isEmpty)
              const Text(
                'No friends yet — add one from the Friends tab, or enter a '
                'SnowChat ID above.',
                style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
              )
            else
              for (final c in friends) _buildFriendItem(c),
          ],
        ),
      ),
    );
  }

  /// A friend: the tap opens (or makes) its chat in place of this screen.
  Widget _buildFriendItem(Contact c) {
    final snowId = c.snowChatId;
    final name = (c.displayName?.isNotEmpty ?? false)
        ? c.displayName!
        : shortSnowId(snowId);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SnowAvatar(snowId: snowId, size: 40, displayName: name),
      title: Text(
        name,
        style: const TextStyle(color: SnowColors.textPrimary, fontSize: 15),
      ),
      subtitle: Text(
        '${snowId.substring(0, 10)}...${snowId.substring(snowId.length - 4)}',
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
      ),
      onTap: () => openDirectChatWith(
        context: context,
        ref: ref,
        recipientSnowchatId: snowId,
        recipientDisplayName: c.displayName,
        replaceCurrent: true,
      ),
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
                color: isSelected
                    ? SnowColors.primary
                    : SnowColors.textSecondary,
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
