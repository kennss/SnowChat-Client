/// @file        add_friend_screen.dart
/// @description Full-screen "Add Friend" — SnowChat ID input/validation +
///              live server lookup + preview tile + Send Friend Request CTA.
///              Mirrors NewChatScreen pattern (Chats ✏️ flow) so the two
///              "search a SnowChat ID" touchpoints feel consistent. Replaces
///              the old AlertDialog (no preview, no live validation).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-28
/// @lastUpdated 2026-04-28
///
/// @functions
///  - AddFriendScreen: ConsumerStatefulWidget for adding a friend
///  - _lookupUser(): live server lookup as user types a valid SnowChat ID
///  - _sendRequest(): friend request action + post-action snackbar/navigation

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../providers/channel_provider.dart';

class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _isSearching = false;
  bool _isSending = false;
  Map<String, dynamic>? _foundUser;

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
      final response = await apiClient.get(ApiEndpoints.userLookup(snowId));
      if (!mounted) return;
      setState(() {
        _foundUser = Map<String, dynamic>.from(response.data as Map);
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'User not found';
        _isSearching = false;
      });
    }
  }

  Future<void> _sendRequest() async {
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
      setState(() => _error = 'You cannot add yourself');
      return;
    }
    if (_foundUser == null) {
      // Lookup may still be in flight or failed silently — explicit guard.
      setState(() => _error = 'User not found — verify the SnowChat ID');
      return;
    }

    setState(() => _isSending = true);
    final status = await ref.read(friendActionsProvider).addFriend(snowId);
    if (!mounted) return;
    setState(() => _isSending = false);

    String message;
    Color bg;
    switch (status) {
      case 'pending':
        message = 'Friend request sent!';
        bg = SnowColors.success;
      case 'already_friend':
        message = 'Already friends.';
        bg = SnowColors.success;
      case 'already_pending':
        message = 'Friend request already pending.';
        bg = Colors.amber;
      default:
        message = 'Failed to send friend request.';
        bg = SnowColors.error;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (status == 'pending' || status == 'already_friend') {
      ref.invalidate(personalChannelProvider);
      ref.invalidate(friendRequestsProvider);
      context.pop();
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
        title: const Text('Add Friend'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SnowSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              "Enter your friend's SnowChat ID. They'll receive a friend request you can chat once accepted.",
              style: TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: SnowSizes.lg),

            TextField(
              controller: _controller,
              autofocus: true,
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
                  Icons.person_search_rounded,
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

            // Live preview tile (NewChatScreen 패턴 동일).
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
                            _foundUser!['displayName'] as String? ?? 'Unknown',
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

            ElevatedButton(
              onPressed: (_isSending || _foundUser == null) ? null : _sendRequest,
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Friend Request'),
            ),
          ],
        ),
      ),
    );
  }
}
