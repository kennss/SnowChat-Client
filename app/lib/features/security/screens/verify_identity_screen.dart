/// @file        verify_identity_screen.dart
/// @description Safety Number verification screen for a 1:1 peer.
///
///              B-2 Safety Number v2 (2026-11-10): the 60-digit number is an
///              ACCOUNT fingerprint — computed over both users' ACCOUNT public
///              keys (the keys the SnowChat IDs are derived from) with
///              algorithm version 2. It answers "is the SnowChat ID I am
///              talking to really this person's account?" (friend-add snowId
///              substitution). Device-key changes of the same account do not
///              change it; those are proven by the account-signed identity
///              binding and only produce an informational notice.
///              The peer's account key comes from VerifiedIdentityStore (bound
///              or invite-pinned) or, for peers without a binding, from the
///              non-consuming identity directory — accepted only if it derives
///              the peer's snowId.
///
///              A legacy peer whose keys changed while marked verified is
///              blocked (§5.5); marking verified here adopts the pending keys,
///              clears the block and asks the server to redeliver held
///              messages.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-11-10 (B-2: Safety Number v2 over account keys; re-verify
///              flow unblocks a pending legacy key change)
///
/// @functions
///  - VerifyIdentityScreen: ConsumerStatefulWidget for the verify flow
///  - _bootstrap(): resolve both account keys and compute / load the v2 number
///  - _resolvePeerAccountKey(): store → identity directory (derive-checked)
///  - _toggleVerified(): mark verified (re-verify unblocks pending changes)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/crypto/identity_binding.dart';
import '../../../core/crypto/safety_number.dart';
import '../../../core/storage/daos/identity_verification_dao.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../widgets/safety_number_display.dart';
import '../widgets/safety_number_qr.dart';

class VerifyIdentityScreen extends ConsumerStatefulWidget {
  final String peerSnowchatId;
  final String peerDisplayName;

  const VerifyIdentityScreen({
    super.key,
    required this.peerSnowchatId,
    required this.peerDisplayName,
  });

  @override
  ConsumerState<VerifyIdentityScreen> createState() =>
      _VerifyIdentityScreenState();
}

class _VerifyIdentityScreenState extends ConsumerState<VerifyIdentityScreen> {
  String? _digits60;
  Object? _error;
  bool _busy = true;

  /// Legacy peer whose keys changed while verified — messaging is paused
  /// until the user re-verifies (B-2 §5.5).
  bool _pendingKeyChange = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<Uint8List?> _resolvePeerAccountKey() async {
    final store = ref.read(verifiedIdentityStoreProvider);
    final rec = await store.get(widget.peerSnowchatId);
    if (rec?.accountPublicKey != null) return rec!.accountPublicKey;
    final dir = await ref
        .read(signalSessionManagerProvider)
        .fetchIdentityDirectory(widget.peerSnowchatId);
    final key = dir.accountPublicKey;
    if (!IdentityBindingV1.accountKeyMatchesSnowId(
        key, widget.peerSnowchatId)) {
      return null;
    }
    await store.rememberAccountKey(widget.peerSnowchatId, key);
    return key;
  }

  Future<void> _bootstrap() async {
    try {
      final dao = ref.read(identityVerificationDaoProvider);
      final identityManager = ref.read(identityManagerProvider);
      final store = ref.read(verifiedIdentityStoreProvider);

      final rec = await store.get(widget.peerSnowchatId);
      _pendingKeyChange = rec?.hasPendingChange ?? false;

      final mySnow = await identityManager.getSnowChatId();
      final myAccount = await identityManager.getPublicKey();
      if (mySnow == null || mySnow.isEmpty || myAccount == null) {
        throw StateError('Local identity unavailable');
      }

      Uint8List? peerAccount;
      try {
        peerAccount = await _resolvePeerAccountKey();
      } catch (_) {
        peerAccount = null;
      }
      if (peerAccount == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = "Couldn't load ${widget.peerDisplayName}'s account key. "
                'Check your connection and try again.';
          });
        }
        return;
      }

      // Cache hit only for a v2 row computed over this exact account key.
      final existing = await dao.getCurrentByPeer(widget.peerSnowchatId);
      if (existing != null &&
          existing.safetyNumber.length == 60 &&
          existing.pinnedEd25519 == base64Encode(peerAccount)) {
        if (mounted) {
          setState(() {
            _digits60 = existing.safetyNumber;
            _busy = false;
          });
        }
        return;
      }

      final digits = SafetyNumber.compute(
        mySnowId: mySnow,
        myEd25519: myAccount,
        theirSnowId: widget.peerSnowchatId,
        theirEd25519: peerAccount,
        version: IdentityVerificationDao.currentVersion,
      );

      // Cache for subsequent opens. Does not flip wasPreviouslyVerified.
      await dao.upsertVerification(
        snowchatId: widget.peerSnowchatId,
        ed25519Key: peerAccount,
        safetyNumber: digits,
      );

      if (mounted) {
        setState(() {
          _digits60 = digits;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    }
  }

  Future<void> _toggleVerified(bool next, bool currentlyVerified) async {
    final dao = ref.read(identityVerificationDaoProvider);
    if (next == currentlyVerified && !(next && _pendingKeyChange)) return;
    if (next) {
      // Re-verification adopts a pending legacy key change and lifts the
      // block, then asks the server to redeliver messages we held back.
      final store = ref.read(verifiedIdentityStoreProvider);
      final adopted = await store.acceptPendingChange(widget.peerSnowchatId);
      ref
          .read(signalSessionManagerProvider)
          .clearIdentityRejection(widget.peerSnowchatId);
      await dao.markVerified(widget.peerSnowchatId);
      if (adopted) {
        if (mounted) setState(() => _pendingKeyChange = false);
        final queue = ref.read(messageQueueProvider);
        queue.releaseHeldForPeer(widget.peerSnowchatId);
        unawaited(queue.fetchPending());
      }
    } else {
      await dao.markUnverified(widget.peerSnowchatId);
    }
  }

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'What is a safety number?',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'The safety number is a fingerprint of both accounts. If you and '
          'your contact see the same number, the SnowChat ID you are talking '
          "to really is your contact's account.\n\n"
          "Each device's keys are signed by its account, so a reinstall does "
          "not change this number. Compare it only when both of you run "
          'the latest SnowChat version — older versions show a different '
          'number. Compare out-of-band (in person, video call).',
          style: TextStyle(color: SnowColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it',
                style: TextStyle(color: SnowColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verificationStream = ref.watch(_verificationProvider(
      widget.peerSnowchatId,
    ));

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Verify Safety Number'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'What is this?',
            onPressed: _showHelp,
          ),
        ],
      ),
      body: _busy
          ? const Center(
              child: CircularProgressIndicator(color: SnowColors.primary),
            )
          : _error != null
              ? _buildError(_error!)
              : _buildBody(verificationStream),
    );
  }

  Widget _buildError(Object err) {
    return Padding(
      padding: const EdgeInsets.all(SnowSizes.lg),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded,
                size: 56, color: SnowColors.textTertiary),
            const SizedBox(height: SnowSizes.md),
            Text(
              err.toString(),
              style: const TextStyle(
                color: SnowColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AsyncValue<dynamic> verificationStream) {
    final digits = _digits60!;
    final row = verificationStream.value;
    final verified = (row?.verified as bool?) ?? false;
    final wasPreviouslyVerified =
        (row?.wasPreviouslyVerified as bool?) ?? false;
    final lastChangedAt = row?.lastChangedAt as int?;

    final mismatchActive =
        lastChangedAt != null && (lastChangedAt > 0) && !verified;

    return ListView(
      padding: const EdgeInsets.all(SnowSizes.lg),
      children: [
        // --- Header (avatar + name + snow id) ---
        Center(
          child: Column(
            children: [
              SnowAvatar(
                snowId: widget.peerSnowchatId,
                size: 72,
                displayName: widget.peerDisplayName,
              ),
              const SizedBox(height: SnowSizes.sm),
              Text(
                widget.peerDisplayName,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.peerSnowchatId,
                style: const TextStyle(
                  color: SnowColors.textTertiary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SnowSizes.lg),

        // --- Pending legacy key change (blocked until re-verified) ---
        if (_pendingKeyChange) const _PendingChangeBanner(),
        if (_pendingKeyChange) const SizedBox(height: SnowSizes.md),

        // --- Mismatch banner (if applicable) ---
        if (mismatchActive)
          _ChangedBanner(wasPreviouslyVerified: wasPreviouslyVerified),
        if (mismatchActive) const SizedBox(height: SnowSizes.md),

        // --- Instruction text ---
        const Text(
          'If both of you see the same number, your conversation is '
          'secure. Compare it in person or over a video call.',
          style: TextStyle(
            color: SnowColors.textSecondary,
            fontSize: 14,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SnowSizes.lg),

        // --- 60-digit grid ---
        SafetyNumberDisplay(digits60: digits),
        const SizedBox(height: SnowSizes.lg),

        // --- Mark as verified toggle ---
        Container(
          decoration: BoxDecoration(
            color: SnowColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SnowColors.divider),
          ),
          child: SwitchListTile(
            value: verified && !_pendingKeyChange,
            title: const Text(
              'Mark as Verified',
              style: TextStyle(color: SnowColors.textPrimary),
            ),
            subtitle: Text(
              verified
                  ? "You confirmed this number matches your contact's screen."
                  : 'Toggle on after comparing the number with your contact.',
              style: const TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 12,
              ),
            ),
            activeThumbColor: SnowColors.primary,
            onChanged: (next) =>
                _toggleVerified(next, verified && !_pendingKeyChange),
          ),
        ),
        const SizedBox(height: SnowSizes.md),

        // --- Show QR ---
        OutlinedButton.icon(
          onPressed: () => showSafetyNumberQr(
            context,
            peerSnowId: widget.peerSnowchatId,
            peerDisplayName: widget.peerDisplayName,
            digits60: digits,
          ),
          icon: const Icon(Icons.qr_code_2_rounded,
              color: SnowColors.primary),
          label: const Text('Show QR code',
              style: TextStyle(color: SnowColors.primary)),
        ),
      ],
    );
  }
}

/// One-row provider for the IdentityVerifications row of [snowchatId].
/// Implemented inline (not a generated provider) to keep this screen
/// self-contained.
final _verificationProvider =
    StreamProvider.family<dynamic, String>((ref, snowchatId) {
  final dao = ref.watch(identityVerificationDaoProvider);
  return dao.watchByPeer(snowchatId);
});

class _ChangedBanner extends StatelessWidget {
  final bool wasPreviouslyVerified;

  const _ChangedBanner({required this.wasPreviouslyVerified});

  @override
  Widget build(BuildContext context) {
    final critical = wasPreviouslyVerified;
    final color = critical ? SnowColors.error : Colors.amber.shade800;
    final bg = (critical ? SnowColors.error : Colors.amber)
        .withValues(alpha: 0.12);
    final title = critical
        ? 'Safety number changed — re-verify'
        : 'Safety number changed';
    final body = critical
        ? 'You previously verified this contact. Their identity key '
            'changed, which can mean they reinstalled the app — or that '
            'someone is trying to impersonate them. Verify the new number '
            'before continuing.'
        : 'The safety number for this contact changed. This is normal if '
            'they reinstalled the app, but worth confirming before you '
            'share anything sensitive.';
    return Container(
      padding: const EdgeInsets.all(SnowSizes.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(critical ? Icons.warning_rounded : Icons.shield_rounded,
              color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: SnowColors.textPrimary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// B-2 §5.5: shown while a verified legacy contact's key change is pending.
class _PendingChangeBanner extends StatelessWidget {
  const _PendingChangeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SnowSizes.md),
      decoration: BoxDecoration(
        color: SnowColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SnowColors.error.withValues(alpha: 0.6)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.pause_circle_outline_rounded, color: SnowColors.error),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "This contact's security keys changed after you verified them. "
              'Messaging is paused. Compare the number below with your '
              'contact, then turn on "Mark as Verified" to continue.',
              style: TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
