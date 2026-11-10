/// @file        add_friend_screen.dart
/// @description Full-screen "Add Friend". PRIMARY path = by nickname (design B
///              first-contact): type a friend's nick → server exact-match lookup
///              returns a one-time OPAQUE invite token (never the target's id or
///              avatar) → confirm "@nick" (+ a "recently reassigned" warning when
///              the nick changed hands lately) → send. An "Add by SnowChat ID"
///              advanced path keeps the raw-id flow for power users. A nick is
///              something a person can actually say out loud, so two people who
///              know each other can connect without exchanging a 36-char id.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-28
/// @lastUpdated 2026-11-10 (B-2: invite links carry the inviter's account public key (?k=); verified against the id and pinned into VerifiedIdentityStore on send). Earlier 2026-08-05 (initialId: open straight to the SnowChat-ID confirm
///              when arriving from a snowchat://user/<id> QR/link first-contact;
///              nick-based primary path via opaque-token lookup/add unchanged)
///
/// @functions
///  - AddFriendScreen: nick-first add-friend, with an advanced SnowChat-ID mode.
///    initialId (from a scanned/tapped snowchat://user/<id> deeplink) opens the
///    id path pre-filled + auto-looked-up.
///  - _lookupNick(): debounced POST /users/lookup-by-nick (opaque token result)
///  - _sendByToken(): redeem the opaque invite token → friend request
///  - _lookupUser()/_sendById(): advanced SnowChat-ID lookup + request
///    (B-2: a link/QR account key is derive-checked on open and pinned into
///    VerifiedIdentityStore on send — first contact via link cannot be
///    downgraded to unbound keys)
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/crypto/identity_binding.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../providers/channel_provider.dart';

class AddFriendScreen extends ConsumerStatefulWidget {
  /// When non-null (arrived from a snowchat://user/<id> QR/link), the screen
  /// opens directly in SnowChat-ID mode, pre-filled and auto-looked-up.
  final String? initialId;

  /// B-2: the inviter's ACCOUNT public key (64 lowercase hex) carried by the
  /// link/QR (`?k=`). Must derive [initialId]; pinned on send.
  final String? initialAccountKeyHex;

  const AddFriendScreen({
    super.key,
    this.initialId,
    this.initialAccountKeyHex,
  });

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final _controller = TextEditingController();
  bool _idMode = false; // false = nick (primary), true = SnowChat ID (advanced)

  Timer? _debounce;
  bool _isSearching = false;
  bool _isSending = false;
  String? _error;

  // Nick-mode lookup state
  bool _nickChecked = false; // a lookup has completed for the current input
  bool _nickExists = false;
  String? _inviteToken;
  bool _recentlyReassigned = false;
  bool _rateLimited = false;

  // ID-mode lookup state
  Map<String, dynamic>? _foundUser;

  /// B-2: derive-checked account key from the invite link (null when the
  /// link carried none — older inviter app — or for manual entry).
  ({String snowId, Uint8List key})? _linkAccountKey;

  @override
  void initState() {
    super.initState();
    final id = widget.initialId?.trim();
    final keyHex = widget.initialAccountKeyHex?.trim();
    if (id != null && keyHex != null && keyHex.isNotEmpty) {
      final key = IdentityBindingV1.parseAccountKeyHex(keyHex);
      if (key == null ||
          !IdentityBindingV1.accountKeyMatchesSnowId(key, id)) {
        // A link whose key does not derive its id was tampered with.
        _error = 'This contact link is invalid or was modified.';
        return;
      }
      _linkAccountKey = (snowId: id, key: key);
    }
    if (id != null && KeyDerivation.isValidSnowChatId(id)) {
      // Arrived from a snowchat://user/<id> QR/link — open the id confirm
      // directly and resolve the preview so the user only has to hit Send.
      _idMode = true;
      _controller.text = id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lookupUser(id);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _resetLookup() {
    _debounce?.cancel();
    _nickChecked = false;
    _nickExists = false;
    _inviteToken = null;
    _recentlyReassigned = false;
    _rateLimited = false;
    _foundUser = null;
    _error = null;
  }

  void _switchMode(bool idMode) {
    setState(() {
      _idMode = idMode;
      _controller.clear();
      _resetLookup();
    });
  }

  void _onChanged(String value) {
    setState(_resetLookup);
    final text = value.trim();
    if (text.isEmpty) return;
    if (_idMode) {
      if (KeyDerivation.isValidSnowChatId(text)) _lookupUser(text);
      return;
    }
    // Nick: debounce, min 2 chars.
    if (text.length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 450), () => _lookupNick(text));
  }

  // --- Nick (primary) -------------------------------------------------------

  Future<void> _lookupNick(String nick) async {
    setState(() => _isSearching = true);
    final r = await ref.read(friendActionsProvider).lookupByNick(nick);
    if (!mounted || _controller.text.trim() != nick) return;
    setState(() {
      _isSearching = false;
      _nickChecked = true;
      _nickExists = r.exists;
      _inviteToken = r.inviteToken;
      _recentlyReassigned = r.recentlyReassigned;
      _rateLimited = r.rateLimited;
    });
  }

  Future<void> _sendByToken() async {
    final token = _inviteToken;
    if (token == null) return;
    setState(() => _isSending = true);
    final status = await ref.read(friendActionsProvider).addFriendByToken(token);
    if (!mounted) return;
    setState(() => _isSending = false);
    if (status == 'expired') {
      // Token TTL elapsed — re-run the lookup to mint a fresh one.
      setState(() => _resetLookup());
      _showResult('This invite expired — search the nickname again.', Colors.amber);
      final nick = _controller.text.trim();
      if (nick.length >= 2) _lookupNick(nick);
      return;
    }
    _handleRequestStatus(status);
  }

  // --- SnowChat ID (advanced) ----------------------------------------------

  Future<void> _lookupUser(String snowId) async {
    setState(() => _isSearching = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get(ApiEndpoints.userLookup(snowId));
      if (!mounted || _controller.text.trim() != snowId) return;
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

  Future<void> _sendById() async {
    final snowId = _controller.text.trim();
    final myId = ref.read(currentSnowIdProvider) ?? '';
    if (!KeyDerivation.isValidSnowChatId(snowId)) {
      setState(() => _error = 'Invalid SnowChat ID format (snow + 32 hex chars)');
      return;
    }
    if (snowId == myId) {
      setState(() => _error = 'You cannot add yourself');
      return;
    }
    if (_foundUser == null) {
      setState(() => _error = 'User not found — verify the SnowChat ID');
      return;
    }
    setState(() => _isSending = true);
    final linkKey = _linkAccountKey;
    if (linkKey != null && linkKey.snowId == snowId) {
      final pinned = await ref
          .read(verifiedIdentityStoreProvider)
          .pinFromInviteLink(snowId, linkKey.key);
      if (!pinned) {
        if (!mounted) return;
        setState(() {
          _isSending = false;
          _error = "This link's account key conflicts with the key on file "
              'for this contact.';
        });
        return;
      }
    }
    final status = await ref.read(friendActionsProvider).addFriend(snowId);
    if (!mounted) return;
    setState(() => _isSending = false);
    _handleRequestStatus(status);
  }

  // --- Shared result handling ----------------------------------------------

  void _handleRequestStatus(String status) {
    switch (status) {
      case 'pending':
        _showResult('Friend request sent!', SnowColors.success);
      case 'already_friend':
        _showResult('Already friends.', SnowColors.success);
      case 'already_pending':
        _showResult('Friend request already pending.', Colors.amber);
      default:
        _showResult('Failed to send friend request.', SnowColors.error);
    }
    if (status == 'pending' || status == 'already_friend') {
      ref.invalidate(personalChannelProvider);
      ref.invalidate(friendRequestsProvider);
      context.pop();
    }
  }

  void _showResult(String message, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
          children: _idMode ? _buildIdMode() : _buildNickMode(),
        ),
      ),
    );
  }

  // --- Nick UI --------------------------------------------------------------

  List<Widget> _buildNickMode() {
    final nick = _controller.text.trim();
    return [
      const Text(
        'Add by nickname',
        style: TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: SnowSizes.sm),
      const Text(
        "Enter your friend's nickname. They'll get a request — you can chat once they accept.",
        style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
      ),
      const SizedBox(height: SnowSizes.lg),
      TextField(
        controller: _controller,
        autofocus: true,
        onChanged: _onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: SnowColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'nickname',
          prefixIcon: const Icon(Icons.alternate_email_rounded,
              color: SnowColors.textTertiary),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
        ),
      ),
      if (_rateLimited) ...[
        const SizedBox(height: SnowSizes.md),
        _hint('Too many lookups. Please try again in a bit.', Colors.amber),
      ] else if (_nickChecked && _nickExists) ...[
        const SizedBox(height: SnowSizes.md),
        _foundTile(nick),
        if (_recentlyReassigned) ...[
          const SizedBox(height: SnowSizes.sm),
          _hint(
            'Heads up: this nickname was recently reassigned. Make sure this is the right person.',
            Colors.amber,
          ),
        ],
        const SizedBox(height: SnowSizes.lg),
        ElevatedButton(
          onPressed: _isSending ? null : _sendByToken,
          child: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Send Friend Request'),
        ),
      ] else if (_nickChecked && !_nickExists && nick.length >= 2) ...[
        const SizedBox(height: SnowSizes.md),
        _hint('No one is using that nickname.', SnowColors.textTertiary),
      ],
      const SizedBox(height: SnowSizes.xl),
      Center(
        child: TextButton(
          onPressed: () => _switchMode(true),
          child: const Text('Add by SnowChat ID instead'),
        ),
      ),
    ];
  }

  /// Confirm tile for a nick hit. No real avatar — the server returns none
  /// (avatars are E2EE and unreadable to a non-friend); this shows a nick-derived
  /// placeholder so the "preview" never implies verified identity.
  Widget _foundTile(String nick) {
    return Container(
      padding: const EdgeInsets.all(SnowSizes.md),
      decoration: BoxDecoration(
        color: SnowColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SnowColors.primary.withAlpha(77)),
      ),
      child: Row(
        children: [
          SnowAvatar(snowId: nick, size: 40, displayName: nick),
          const SizedBox(width: SnowSizes.md),
          Expanded(
            child: Text(
              '@$nick',
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: SnowColors.primary),
        ],
      ),
    );
  }

  Widget _hint(String text, Color color) {
    return Text(text, style: TextStyle(color: color, fontSize: 13));
  }

  // --- SnowChat ID UI (advanced) -------------------------------------------

  List<Widget> _buildIdMode() {
    return [
      const Text(
        'Add by SnowChat ID',
        style: TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: SnowSizes.sm),
      const Text(
        "Paste your friend's full SnowChat ID (snow + 32 hex chars).",
        style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
      ),
      const SizedBox(height: SnowSizes.lg),
      TextField(
        controller: _controller,
        // Don't steal focus (pop keyboard over the confirm) when we arrived
        // pre-filled from a snowchat://user/<id> deeplink.
        autofocus: widget.initialId == null,
        onChanged: _onChanged,
        style: const TextStyle(
            color: SnowColors.textPrimary, fontFamily: 'monospace', fontSize: 14),
        decoration: InputDecoration(
          hintText: 'snow...',
          errorText: _error,
          prefixIcon: const Icon(Icons.person_search_rounded,
              color: SnowColors.textTertiary),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : null,
        ),
      ),
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
                displayName: _foundUser!['displayName'] as String? ?? '',
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
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _foundUser!['snowchatId'] as String? ?? '',
                      style: const TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle_rounded, color: SnowColors.primary),
            ],
          ),
        ),
      ],
      const SizedBox(height: SnowSizes.lg),
      ElevatedButton(
        onPressed: (_isSending || _foundUser == null) ? null : _sendById,
        child: _isSending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Send Friend Request'),
      ),
      const SizedBox(height: SnowSizes.xl),
      Center(
        child: TextButton(
          onPressed: () => _switchMode(false),
          child: const Text('Add by nickname instead'),
        ),
      ),
    ];
  }
}
