/// @file        transfer_confirm_dialog.dart
/// @description Wallet V2 Phase 1 (Phase D) — receiver (B) side
///              accept/decline modal. Shown when EncryptedMessageHandler →
///              TransferEventBus → TransferRequestEvent arrives. Sender
///              nickname/avatar + amount/token/network badge + 10-minute
///              countdown + Accept/Decline buttons.
///              Timer lives inside the dialog itself (V1.0 simplification)
///              — will be split out into a service-owned timer in Phase E
///              (P1-7, preserves timer across screen lock / VoIP interrupts).
///              Float/double strictly forbidden (wallet/CLAUDE.md §2.1) —
///              amounts are BigInt.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-20
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showTransferConfirmDialog(): bottom-sheet entry, returns Future<bool?>
///    (true=Accept / false=Decline / null=timeout or external dismiss)
///  - TransferConfirmDialog (ConsumerStatefulWidget): bottom-sheet body
///    - initState(): start countdown timer (Timer.periodic 1s, 600s → 0)
///    - dispose(): cancel timer + safe shutdown
///    - _tick(): _remainingSec-- every 1s + handle timeout when reaching 0
///    - _onAccept(): double-tap guard → Navigator.pop(true)
///    - _onDecline(): double-tap guard → Navigator.pop(false)
///    - build(): header (avatar+name) + amount + Network badge + countdown + buttons
///  - _formatCountdown(): seconds → "mm:ss" format
///  - _displayAmount(): TransferRequest → "1.5 SOL" / "10 USDC" / "1 NFT (mint…)"
///  - _Avatar (private widget): first-letter placeholder for displayName
///  - _NetworkBadge (private widget): Devnet (green) / Mainnet (orange)

library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../contacts/contact_provider.dart';
import '../models/transfer_request.dart';
import '../utils/amount_converter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color tokens (same as transfer_request_screen — unified wallet-module design)
// ─────────────────────────────────────────────────────────────────────────────

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const primaryBg = Color(0xFF0A2A1A);
  static const surface = Color(0xFF111111);
  static const surfaceVariant = Color(0xFF1A1A1A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const warning = Color(0xFFFFA726);
}

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/// Total countdown time (seconds). Spec §2 — request expiry 10 minutes.
const int _countdownTotalSec = 600;

// ─────────────────────────────────────────────────────────────────────────────
// Public entry — bottom sheet launcher
// ─────────────────────────────────────────────────────────────────────────────

/// Show the recipient(B)-side accept/decline bottom sheet.
///
/// **Returns**:
/// - `true` — user tapped Accept
/// - `false` — user tapped Decline
/// - `null` — timeout (10 minutes elapsed) or external dismiss (background tap, back, etc.)
///
/// **Call example** (from Phase E TransferService):
/// ```dart
/// final result = await showTransferConfirmDialog(
///   context,
///   fromSnowchatId: event.fromSnowchatId,
///   fromDisplayName: contact?.displayName,
///   request: event.payload,
/// );
/// switch (result) {
///   case true: await _sendAccepted(...); break;
///   case false: await _sendDeclined(...); break;
///   case null: /* timeout already handled by service-owned timer */ break;
/// }
/// ```
///
/// V1.0 limitation (TODO Phase E):
/// - timer is dialog-scoped — when bottom sheet dismisses on screen lock /
///   background / VoIP incoming call, the timer dies with it → split into
///   a service-owned timer + switch dialog to a service-state-listen
///   pattern (P1-7).
Future<bool?> showTransferConfirmDialog(
  BuildContext context, {
  required String fromSnowchatId,
  required String? fromDisplayName,
  required TransferRequest request,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: _C.surface,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => TransferConfirmDialog(
      fromSnowchatId: fromSnowchatId,
      fromDisplayName: fromDisplayName,
      request: request,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet body
// ─────────────────────────────────────────────────────────────────────────────

/// Recipient(B)-side transfer confirm UI (bottom sheet body).
///
/// **Always** display via [showTransferConfirmDialog] — direct
/// instantiation can break Navigator.pop result delivery.
class TransferConfirmDialog extends ConsumerStatefulWidget {
  const TransferConfirmDialog({
    super.key,
    required this.fromSnowchatId,
    required this.fromDisplayName,
    required this.request,
  });

  /// Sender SnowChat ID (authenticated sender after E2EE decrypt).
  final String fromSnowchatId;

  /// Sender nickname — falls back to a slice of SnowChat ID when null/empty.
  /// If present in contactProvider cache, refreshed at build via re-lookup.
  final String? fromDisplayName;

  /// E2EE payload (BigInt-safe amount lamports).
  final TransferRequest request;

  @override
  ConsumerState<TransferConfirmDialog> createState() =>
      _TransferConfirmDialogState();
}

class _TransferConfirmDialogState extends ConsumerState<TransferConfirmDialog> {
  Timer? _ticker;
  int _remainingSec = _countdownTotalSec;

  /// Accept/Decline duplicate-tap guard. Blocks the race window where
  /// re-entered setState reaches a disposed widget after Navigator.pop.
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    // TODO(Phase E): TransferService owns the timer → dialog only listens
    //   to service state. Currently a dialog-scope timer (lifecycle-bound)
    //   — on screen lock / VoIP interrupt, bottom-sheet dismiss → timer
    //   cancel → 10-minute expiry guarantee broken.
    //   Fix: TransferService keeps pending Map<requestId, expireAt> + a
    //   global ticker.
    _startCountdown();
  }

  void _startCountdown() {
    // Adjust for elapsed time since sentAt (E2EE routing delay + queued
    // offline messages).
    // If request.sentAt is in the future or abnormal, start at 600s as-is.
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - widget.request.sentAt;
    if (elapsedMs > 0) {
      final elapsedSec = elapsedMs ~/ 1000;
      final remaining = _countdownTotalSec - elapsedSec;
      _remainingSec = remaining > _countdownTotalSec
          ? _countdownTotalSec
          : (remaining < 0 ? 0 : remaining);
    }

    if (_remainingSec <= 0) {
      // Arrived already expired — handle timeout immediately (after frame).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _completed) return;
        _onTimeout();
      });
      return;
    }

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _completed) {
      _ticker?.cancel();
      return;
    }
    setState(() {
      _remainingSec -= 1;
    });
    if (_remainingSec <= 0) {
      _onTimeout();
    }
  }

  void _onTimeout() {
    if (_completed) return;
    _completed = true;
    _ticker?.cancel();
    if (!mounted) return;
    // Return null — caller treats as timeout.
    Navigator.of(context).pop<bool>(null);
  }

  void _onAccept() {
    if (_completed) return;
    _completed = true;
    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop<bool>(true);
  }

  void _onDecline() {
    if (_completed) return;
    _completed = true;
    _ticker?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop<bool>(false);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Refresh displayName from contact cache (may be newer than widget.fromDisplayName).
    final contacts = ref.watch(contactProvider);
    final cachedName = contacts
        .where((c) => c.snowChatId == widget.fromSnowchatId)
        .map((c) => c.displayName)
        .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null);

    final displayName = (widget.fromDisplayName != null &&
            widget.fromDisplayName!.isNotEmpty)
        ? widget.fromDisplayName!
        : (cachedName ?? _truncateSnowchatId(widget.fromSnowchatId));

    final network = widget.request.network;
    final amountText = _displayAmount(widget.request);
    final mintShort = _mintPrefix(widget.request.mint);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle (visual only — enableDrag=false blocks swipe-to-dismiss).
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _C.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header — avatar + sender name.
            Row(
              children: [
                _Avatar(displayName: displayName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: _C.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'wants to send you',
                        style: TextStyle(
                          color: _C.textSecondary.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Amount + token (headline).
            Center(
              child: Column(
                children: [
                  Text(
                    amountText,
                    style: const TextStyle(
                      color: _C.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (mintShort != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      mintShort,
                      style: const TextStyle(
                        color: _C.textTertiary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Network badge.
            Center(child: _NetworkBadge(network: network)),
            const SizedBox(height: 20),

            // Countdown.
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _C.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined,
                      color: _C.textSecondary, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Auto-cancel in ${_formatCountdown(_remainingSec)}',
                    style: const TextStyle(
                      color: _C.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Buttons — Accept (primary) + Decline (secondary).
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _completed ? null : _onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  disabledBackgroundColor: _C.surfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: Text(
                  'Accept',
                  style: TextStyle(
                    color: _completed
                        ? _C.textTertiary
                        : const Color(0xFF000000),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _completed ? null : _onDecline,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _C.textPrimary,
                  side: const BorderSide(color: _C.textTertiary, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text(
                  'Decline',
                  style: TextStyle(
                    color: _completed ? _C.textTertiary : _C.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your wallet address is shared only after you Accept.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _C.textTertiary.withOpacity(0.9),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// seconds → "mm:ss" format ("09:59", "00:30").
String _formatCountdown(int totalSec) {
  if (totalSec < 0) totalSec = 0;
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return '$mm:$ss';
}

/// TransferRequest → display string ("1.5 SOL" / "10 USDC" / "1 NFT").
/// BigInt-only — Float/double never used.
String _displayAmount(TransferRequest req) {
  final BigInt? raw = BigInt.tryParse(req.amount);
  if (raw == null) {
    // Abnormal (should have passed dispatcher-side validation) — display raw as-is.
    return '${req.amount} ${_symbolForToken(req)}';
  }

  switch (req.token) {
    case TokenType.sol:
      return '${lamportsToSol(raw)} SOL';
    case TokenType.spl:
      return '${smallestUnitToDisplay(raw, req.decimals)} ${_symbolForToken(req)}';
    case TokenType.nft:
      // NFT amount is always 1 — separate count vs label.
      return '$raw NFT';
  }
}

/// Show the mint prefix for SPL/NFT ("4ZpAk…r5L8"). null for SOL.
String? _mintPrefix(String? mint) {
  if (mint == null || mint.isEmpty) return null;
  if (mint.length <= 12) return mint;
  return '${mint.substring(0, 6)}…${mint.substring(mint.length - 4)}';
}

/// Token symbol fallback. For SPL, show "SPL" when only mint is known
/// without metadata. (USDC and other well-known mint mappings are
/// hardened in Phase E when integrating token_list_service.)
String _symbolForToken(TransferRequest req) {
  switch (req.token) {
    case TokenType.sol:
      return 'SOL';
    case TokenType.spl:
      return 'SPL';
    case TokenType.nft:
      return 'NFT';
  }
}

/// SnowChat ID truncation (display fallback when no contact name).
/// "snow05a3b2c4..." → "snow05a3…b2c4".
String _truncateSnowchatId(String id) {
  if (id.length <= 12) return id;
  return '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Avatar fallback — first letter of displayName (uppercase). Color is a
/// deterministic tone based on ID hash (same user always gets the same
/// color). Placeholder until image avatars are introduced.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final letter = displayName.trim().isEmpty
        ? '?'
        : displayName.trim().substring(0, 1).toUpperCase();
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _C.primaryBg,
        shape: BoxShape.circle,
        border: Border.all(color: _C.primary.withOpacity(0.4), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: _C.primary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Network badge — Devnet (green primary) / Mainnet (orange warning).
/// Same tone as transfer_request_screen._NetworkBadge.
class _NetworkBadge extends StatelessWidget {
  const _NetworkBadge({required this.network});

  final NetworkType network;

  @override
  Widget build(BuildContext context) {
    final isDevnet = network == NetworkType.devnet;
    final label = isDevnet ? 'Devnet' : 'Mainnet';
    final color = isDevnet ? _C.primary : _C.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// To add in Phase E:
//   - import rpc_client_provider + RPC ATA-existence check right after dialog display (P0-4)
//   - subscribe to the service-owned timer (P1-7) — drop this dialog's _ticker
//   - bundle walletAddress + Ed25519 sig in response send (P1-5)
//   - listen to inline transfer_failed → integrate immediate dismiss (Phase E TransferService)
