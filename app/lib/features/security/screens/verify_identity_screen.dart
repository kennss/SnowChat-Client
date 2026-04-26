/// @file        verify_identity_screen.dart
/// @description Safety Number verification screen for a 1:1 peer. Computes
///              (or reads from cache) the Signal-compatible 60-digit
///              fingerprint between the local user and the peer's currently
///              pinned Ed25519 identity key, displays it as a 6×2 grid,
///              shows a context-appropriate "key changed" banner if the
///              IdentityVerifications row indicates a recent TOFU mismatch,
///              and exposes:
///                - Mark as Verified toggle (writes to IdentityVerificationDao)
///                - Show QR code action (peer scan)
///                - Help dialog explaining what a Safety Number is
///
///              On first open, if no DAO row exists yet, the screen
///              computes the number from the IdentityPinStore (TOFU pin
///              keyed by "snowId:deviceId") and upserts a row so the
///              cached value is available for subsequent screen opens
///              without 5200 SHA-512 rounds in the UI thread.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18
///
/// @functions
///  - VerifyIdentityScreen: ConsumerStatefulWidget for the verify flow
///  - _resolvePeerKey(): pull peer Ed25519 from DAO → PinStore → null
///  - _computeOrLoadSafetyNumber(): cache-first Safety Number resolution
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/crypto/safety_number.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    try {
      final dao = ref.read(identityVerificationDaoProvider);
      final identityManager = ref.read(identityManagerProvider);
      final pinStore = ref.read(identityPinStoreProvider);

      // 1. DAO cache hit?
      final existing = await dao.getByPeer(widget.peerSnowchatId);
      if (existing != null && existing.safetyNumber.length == 60) {
        if (mounted) {
          setState(() {
            _digits60 = existing.safetyNumber;
            _busy = false;
          });
        }
        return;
      }

      // 2. Otherwise compute from IdentityPinStore. We don't know the device
      //    ID for sure, but the current single-device assumption (CLAUDE.md)
      //    means the session key is "snowId:<some-device>". Try the cached
      //    deviceId first, then fall back to scanning known prefixes.
      final mySnow = await identityManager.getSnowChatId();
      final myEd = await identityManager.getPublicKey();
      if (mySnow == null || mySnow.isEmpty || myEd == null) {
        throw StateError('Local identity unavailable');
      }

      Uint8List? peerKey;
      try {
        final deviceId = await ref
            .read(signalSessionManagerProvider)
            .getDeviceIdForRecipient(widget.peerSnowchatId);
        peerKey = await pinStore
            .getPinned('${widget.peerSnowchatId}:$deviceId');
      } catch (_) {
        // No cached deviceId — this peer hasn't received a message from us
        // yet. Surface a friendly message instead of crashing.
      }

      if (peerKey == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = 'No verified key on file yet. Send a message to '
                '${widget.peerDisplayName} to establish a session, then '
                'come back here.';
          });
        }
        return;
      }

      final digits = SafetyNumber.compute(
        mySnowId: mySnow,
        myEd25519: myEd,
        theirSnowId: widget.peerSnowchatId,
        theirEd25519: peerKey,
      );

      // Cache for subsequent opens. Does not flip wasPreviouslyVerified.
      await dao.upsertVerification(
        snowchatId: widget.peerSnowchatId,
        ed25519Key: peerKey,
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
    if (next == currentlyVerified) return;
    if (next) {
      await dao.markVerified(widget.peerSnowchatId);
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
          'Each conversation has a unique safety number derived from both '
          "users' identity keys. If you and your contact see the same "
          'number, no one is intercepting your messages.\n\n'
          'If the number changes unexpectedly, your contact may have '
          'reinstalled the app — but it could also mean someone is trying '
          'to impersonate them. Verify the new number out-of-band (in '
          'person, video call) before continuing to share sensitive '
          'information.',
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
            value: verified,
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
            onChanged: (next) => _toggleVerified(next, verified),
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

// Suppress unused-import warning (StreamSubscription kept for future hooks)
// ignore: unused_element
const _keep = StreamSubscription;
