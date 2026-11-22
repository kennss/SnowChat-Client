/// @file        add_friend_screen.dart
/// @description Full-screen "Add Friend". PRIMARY path = by nickname: type a friend's nick →
///              server exact-match lookup returns the account (snowId + account key, the key
///              checked to derive the id) → confirm "@nick" with the short snowId (+ a "recently
///              reassigned" warning, + a warning when the name is another account's in the list
///              or chats) → the request is added on this device and a sealed contact_added goes
///              out. An "Add by SnowChat ID" advanced path resolves a typed / scanned id.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-28
/// @lastUpdated 2026-11-22 (the name collision warning names both accounts' short snowIds; the found
///              account shows where it stands in the list (already a friend / asked already / asked
///              you — the button accepts); a blocked account asks to unblock first; a failed or
///              rate-limited lookup (nickname or id) is told apart from "not found"; the result
///              says "Request sent" or "You are now friends"). Earlier 2026-11-22 (friend graph off
///              the server — data bindings: the nickname lookup names
///              the account (ContactLookup.byNick; no invite token, no add-by-token), the id path
///              resolves with POST /users/resolve (ContactLookup.resolve), a request is
///              ContactNotifier.requestFound (added here, vouched for, contact_added through the
///              outbox); a link's account key must equal the resolved one). Earlier 2026-11-21 (a
///              request by nickname passes the nickname, so it is vouched for once accepted). Earlier 2026-11-10 (B-2: invite links carry the inviter's account public key (?k=); verified against the id and pinned into VerifiedIdentityStore on send). Earlier 2026-08-05 (initialId: open straight to the SnowChat-ID confirm
///              when arriving from a snowchat://user/<id> QR/link first-contact;
///              nick-based primary path via opaque-token lookup/add unchanged)
///
/// @functions
///  - AddFriendScreen: nick-first add-friend, with an advanced SnowChat-ID mode.
///    initialId (from a scanned/tapped snowchat://user/<id> deeplink) opens the
///    id path pre-filled + auto-looked-up.
///  - _lookupNick(): debounced nickname lookup (ContactLookup.byNick) + name collision check
///  - _sendFound(): the friend request to the account found by nickname
///  - _listStateOf(): where a found account stands in this user's list
///  - _lookupUser()/_sendById(): advanced SnowChat-ID resolve + request
///    (B-2: a link/QR account key is derive-checked on open and pinned into
///    VerifiedIdentityStore on send — first contact via link cannot be
///    downgraded to unbound keys)
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/contacts/contact_lookup.dart';
import '../../../core/contacts/contact_store.dart' show ContactLabel;
import '../../../core/crypto/identity_binding.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../contacts/blocked_peer_prompt.dart';
import '../../contacts/contact_provider.dart';

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
  FoundAccount? _nickAccount;
  bool _recentlyReassigned = false;
  bool _rateLimited = false;

  /// The lookup could not be made (no network, an answer that did not hold
  /// up) — not the same as "no such name".
  bool _lookupFailed = false;

  /// Another account this device knows under the same name (a warning).
  String? _nameTakenBy;

  /// Where the found account stands in this user's list (null: not in it).
  ContactLabel? _foundLabel;

  // ID-mode lookup state
  FoundAccount? _foundUser;

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
    _nickAccount = null;
    _recentlyReassigned = false;
    _rateLimited = false;
    _lookupFailed = false;
    _nameTakenBy = null;
    _foundLabel = null;
    _foundUser = null;
    _error = null;
  }

  /// The label of [snowId] in this user's list, or null when it is not in
  /// it (a request this user declined counts as not in it).
  ContactLabel? _listStateOf(String snowId) {
    for (final c in ref.read(contactProvider)) {
      if (c.snowChatId == snowId) return c.label;
    }
    return null;
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
    final r = await ref.read(contactLookupProvider).byNick(nick);
    final account = r.account;
    final taken = account == null
        ? null
        : await ref
            .read(contactProvider.notifier)
            .nameTakenBy(nick, account.snowId);
    if (!mounted || _controller.text.trim() != nick) return;
    setState(() {
      _isSearching = false;
      _nickChecked = true;
      _nickAccount = account;
      _recentlyReassigned = r.recentlyReassigned;
      _rateLimited = r.rateLimited;
      _lookupFailed = r.failed;
      _nameTakenBy = taken;
      _foundLabel = account == null ? null : _listStateOf(account.snowId);
    });
  }

  Future<void> _sendFound() async {
    final account = _nickAccount;
    if (account == null) return;
    await _send(account);
  }

  // --- SnowChat ID (advanced) ----------------------------------------------

  Future<void> _lookupUser(String snowId) async {
    setState(() => _isSearching = true);
    final r = await ref.read(contactLookupProvider).resolve(snowId);
    if (!mounted || _controller.text.trim() != snowId) return;
    setState(() {
      _isSearching = false;
      _foundUser = r.account;
      _foundLabel = r.account == null ? null : _listStateOf(snowId);
      if (r.account == null) {
        _error = r.notFound
            ? 'User not found'
            : r.rateLimited
                ? 'Too many lookups. Please try again in a bit.'
                : 'Could not look this ID up';
      }
    });
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
    final found = _foundUser;
    if (found == null) {
      setState(() => _error = 'User not found — verify the SnowChat ID');
      return;
    }
    setState(() => _isSending = true);
    final linkKey = _linkAccountKey;
    if (linkKey != null && linkKey.snowId == snowId) {
      // The link fixes the account key; the server's answer must agree.
      if (!constantTimeEquals(linkKey.key, found.accountPub)) {
        setState(() {
          _isSending = false;
          _error = "The server's key for this ID does not match the link.";
        });
        return;
      }
      final pinned = await ref
          .read(verifiedIdentityStoreProvider)
          .pinAccountKey(snowId, linkKey.key);
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
    await _send(found);
  }

  // --- Shared ---------------------------------------------------------------

  /// Add [account] to this user's list (a request — or the acceptance when
  /// it added this user); the notice goes out through the outbox.
  Future<void> _send(FoundAccount account) async {
    if (account.snowId == ref.read(currentSnowIdProvider)) {
      setState(() => _error = 'You cannot add yourself');
      return;
    }
    // An account this user blocked: offer to unblock first.
    if (!await confirmUnblockIfBlocked(
      context: context,
      ref: ref,
      snowId: account.snowId,
      displayName: account.displayName,
    )) {
      if (mounted) setState(() => _isSending = false);
      return;
    }
    if (!mounted) return;
    // Adding an account that asked already accepts its request.
    final accepting = _listStateOf(account.snowId) == ContactLabel.requestReceived;
    setState(() => _isSending = true);
    try {
      await ref.read(contactProvider.notifier).requestFound(account);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _showResult('Could not send the friend request.', SnowColors.error);
      return;
    }
    if (!mounted) return;
    setState(() => _isSending = false);
    _showResult(accepting ? 'You are now friends.' : 'Request sent.',
        SnowColors.success);
    context.pop();
  }

  /// The button under a found account: what it does there depends on
  /// where the account stands in this user's list.
  Widget _sendButton(VoidCallback onSend) {
    final label = _foundLabel;
    if (label == ContactLabel.friend) {
      return _hint('Already your friend.', SnowColors.textSecondary);
    }
    if (label == ContactLabel.requestSent) {
      return _hint('Request sent already — waiting for them to add you.',
          SnowColors.textSecondary);
    }
    return ElevatedButton(
      onPressed: _isSending ? null : onSend,
      child: _isSending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label == ContactLabel.requestReceived
              ? 'Accept Friend Request'
              : 'Send Friend Request'),
    );
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
        "Enter your friend's exact nickname. They'll get a friend request; you are friends once they add you too.",
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
      ] else if (_nickChecked && _lookupFailed) ...[
        const SizedBox(height: SnowSizes.md),
        _hint('Could not look this nickname up. Check your connection and try again.',
            Colors.amber),
      ] else if (_nickChecked && _nickAccount != null) ...[
        const SizedBox(height: SnowSizes.md),
        _foundTile(nick, _nickAccount!.snowId),
        if (_nameTakenBy != null) ...[
          const SizedBox(height: SnowSizes.sm),
          _hint(
            '@$nick is ${shortSnowId(_nickAccount!.snowId)}, but another '
            'account you know, ${shortSnowId(_nameTakenBy!)}, already goes by '
            'this name. Make sure this is the right person.',
            Colors.amber,
          ),
        ],
        if (_recentlyReassigned) ...[
          const SizedBox(height: SnowSizes.sm),
          _hint(
            'Heads up: this nickname was recently reassigned. Make sure this is the right person.',
            Colors.amber,
          ),
        ],
        const SizedBox(height: SnowSizes.lg),
        _sendButton(_sendFound),
      ] else if (_nickChecked && _nickAccount == null && nick.length >= 2) ...[
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

  /// Confirm tile for a nick hit, with the short snowId of the account the
  /// server named (only a link, a QR or the safety number fixes an identity).
  Widget _foundTile(String nick, String snowId) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@$nick',
                  style: const TextStyle(
                    color: SnowColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  shortSnowId(snowId),
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
                snowId: _foundUser!.snowId,
                size: 40,
                displayName: _foundUser!.displayName ?? '',
              ),
              const SizedBox(width: SnowSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _foundUser!.displayName ?? 'Unknown',
                      style: const TextStyle(
                          color: SnowColors.textPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _foundUser!.snowId,
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
      if (_foundUser != null)
        _sendButton(_sendById)
      else
        const ElevatedButton(
          onPressed: null,
          child: Text('Send Friend Request'),
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
