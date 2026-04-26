/// @file        system_message_bubble.dart
/// @description System-message bubble widget — renders group-event (member added/removed, name change, etc.) system notices
///              as centered gray text. Phase 10: includes decryption-failed placeholder rendering.
///              Wallet V2 Phase G: added transfer_completed permanent system message (Sent/Received +
///              7-char tx hash + Solana explorer link).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-20 Wallet V2 Phase G: _TransferCompletedBubble — Sent/Received + explorer link)
///
/// @functions
///  - SystemMessageBubble: StatelessWidget rendering WhatsApp-style system messages
///  - _buildDecryptionFailedBubble(): decryption-failed placeholder UI (lock icon + guidance copy)
///  - _buildIconBubble(): icon + label system message (safety_number_changed, etc.)
///  - _MissedCallBubble: missed call — 5-min countdown + red call_missed icon (StatefulWidget)
///  - _TransferCompletedBubble: transfer completed — direction (sent/received) + amount + token + 7-char tx hash (permanent, StatelessWidget)
///  - _formatTransferAmount(): metadata's amount (BigInt string) + token + decimals -> display string
///  - _resolveTokenLabel(): token type + mint -> "SOL" / "USDC" / "TOKEN" / "NFT" label
///  - _explorerUrlForNetwork(): metadata.network -> SolanaNetwork mapping -> explorerTxUrl

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/constants/colors.dart';
import '../../wallet/rpc/rpc_config.dart';
import '../../wallet/utils/amount_converter.dart';
import '../models/message.dart';

/// WhatsApp-style centered system message (no sender bubble).
/// Used for group events like member added/removed, name changes, etc.
/// Also renders decryption failure placeholders (Phase 10 P0-B).
class SystemMessageBubble extends StatelessWidget {
  final Message message;

  const SystemMessageBubble({super.key, required this.message});

  /// Returns the message metadata map, or an empty map if absent.
  Map<String, dynamic> _decodeMetadata() {
    final raw = message.metadata;
    if (raw == null) return const {};
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    // Phase 10 P0-B: decryption failure placeholder
    if (message.status == MessageStatus.decryptionFailed) {
      return _buildDecryptionFailedBubble(context);
    }

    // P0-2: eventType-aware system bubble (safety_number_changed → shield).
    final metadata = _decodeMetadata();
    final eventType = metadata['eventType'] as String?;
    if (eventType == 'safety_number_changed') {
      final wasPrev =
          (metadata['wasPreviouslyVerified'] as bool?) ?? false;
      return _buildIconBubble(
        context,
        icon: Icons.shield_outlined,
        accent: wasPrev ? SnowColors.error : Colors.amber.shade800,
      );
    }
    // V1.0.1: missed-call system message — dynamic countdown display.
    // Per call/CLAUDE.md §2.2 restrictive notification policy (forced 5-min TTL).
    // Phase I follow-up (2026-04-21): caller-side busy/offline result messages
    // also render the same bubble — reuses the 5-min TTL countdown.
    if (eventType == 'missed_voice_call' ||
        (eventType != null && eventType.startsWith('outgoing_voice_call_'))) {
      return _MissedCallBubble(message: message, metadata: metadata);
    }
    // Wallet V2 Phase G — permanent transfer-completed system message
    // (Sent/Received + 7-char tx hash + Solana explorer link). spec §6.4 / §5.9.
    if (eventType == 'transfer_completed') {
      return _TransferCompletedBubble(metadata: metadata);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SnowColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message.plaintext,
            style: const TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildIconBubble(
    BuildContext context, {
    required IconData icon,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.plaintext,
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders a decryption failure placeholder with a lock icon and (legacy doc).
  /// Below: missed call bubble with live countdown (Auto-deletes in mm:ss).
  /// informative text. Matches Signal's "Waiting for this message.
  /// This may take a moment." UX pattern.
  Widget _buildDecryptionFailedBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SnowColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: SnowColors.textTertiary.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: SnowColors.textTertiary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Waiting for this message. This may take a moment.',
                  style: TextStyle(
                    color: SnowColors.textTertiary.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// V1.0.1: missed-call bubble — forced 5-min TTL countdown (Auto-deletes in mm:ss).
/// 1-second setState driven off `metadata['insertedAtMs']`. call/CLAUDE.md §2.2.
class _MissedCallBubble extends StatefulWidget {
  final Message message;
  final Map<String, dynamic> metadata;

  const _MissedCallBubble({
    required this.message,
    required this.metadata,
  });

  @override
  State<_MissedCallBubble> createState() => _MissedCallBubbleState();
}

class _MissedCallBubbleState extends State<_MissedCallBubble> {
  static const _ttl = Duration(minutes: 5);
  Timer? _timer;
  late DateTime _insertedAt;

  @override
  void initState() {
    super.initState();
    final ms = widget.metadata['insertedAtMs'];
    _insertedAt = ms is int
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration get _remaining {
    final elapsed = DateTime.now().difference(_insertedAt);
    final remaining = _ttl - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatRemaining(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    const accent = SnowColors.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call_missed, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.message.plaintext,
                      style: const TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Auto-deletes in ${_formatRemaining(_remaining)}',
                style: TextStyle(
                  color: accent.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wallet V2 Phase G — permanent transfer-completed system message bubble.
///
/// metadata keys (transfer_service `_commitTransferSystemMessage`):
///   - requestId: UUID (for debug)
///   - txHash: Solana tx signature (Base58, ~88 chars)
///   - amount: BigInt string (lamports or SPL smallest unit)
///   - token: 'SOL' | 'SPL' | 'NFT' (TokenType.toJson)
///   - mint: SPL/NFT mint address (null/missing for SOL)
///   - decimals: int (SOL=9, USDC=6, NFT=0)
///   - direction: 'sent' | 'received' (sender side vs recipient side)
///   - network: 'devnet' | 'mainnet' (explorer cluster branch)
///
/// No TTL — kept permanently as transaction evidence (spec §6.4).
/// Direction branch favors metadata (the system message's senderSnowchatId is
/// stored as an empty string by MessageDao.insertLocalSystemMessage, so a self
/// comparison is impossible — the direction key is ground truth).
///
/// StatelessWidget — currently no ref usage. If token-registry watch becomes
/// necessary, promote to ConsumerWidget in Phase V1.x (V1 falls back to a
/// 'TOKEN' label).
class _TransferCompletedBubble extends StatelessWidget {
  final Map<String, dynamic> metadata;

  const _TransferCompletedBubble({required this.metadata});

  @override
  Widget build(BuildContext context) {
    const accent = SnowColors.primary;
    final direction = (metadata['direction'] as String?) ?? 'received';
    final isSent = direction == 'sent';
    final verb = isSent ? 'Sent' : 'Received';

    final amountDisplay = _formatTransferAmount(metadata);
    final tokenLabel = _resolveTokenLabel(metadata);
    final txHash = (metadata['txHash'] as String?) ?? '';
    final txHashShort =
        txHash.length >= 7 ? '${txHash.substring(0, 7)}...' : txHash;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$verb $amountDisplay $tokenLabel',
                      style: const TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle, size: 12, color: accent),
                ],
              ),
              if (txHash.isNotEmpty) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _openExplorer(context, txHash),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          txHashShort,
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontFamily: 'monospace',
                            decoration: TextDecoration.underline,
                            decorationColor: accent.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new,
                          size: 10,
                          color: accent.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExplorer(BuildContext context, String txHash) async {
    final url = _explorerUrlForNetwork(metadata, txHash);
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open explorer')),
      );
    }
  }
}

/// metadata.amount (BigInt string) + decimals → display string.
/// SOL converts lamports → SOL (1e9); others use smallestUnitToDisplay(decimals).
/// Returns '?' on bad values (fallback first, never block the UI).
String _formatTransferAmount(Map<String, dynamic> metadata) {
  try {
    final amountStr = metadata['amount'] as String?;
    if (amountStr == null || amountStr.isEmpty) return '?';
    final amount = BigInt.parse(amountStr);
    final token = (metadata['token'] as String?) ?? 'SOL';
    if (token.toUpperCase() == 'SOL') {
      return lamportsToSol(amount);
    }
    final decimals = (metadata['decimals'] as int?) ?? 0;
    return smallestUnitToDisplay(amount, decimals);
  } catch (_) {
    return '?';
  }
}

/// Token label — SOL as-is, NFT shows 'NFT', SPL shows 'TOKEN' (until V1.x deferred).
/// Only USDC mint is named explicitly — other SPL = 'TOKEN' (token symbol mapping deferred to V1.x).
String _resolveTokenLabel(Map<String, dynamic> metadata) {
  final token = (metadata['token'] as String?)?.toUpperCase() ?? 'SOL';
  if (token == 'SOL') return 'SOL';
  if (token == 'NFT') return 'NFT';
  // SPL — per-mint symbol mapping is deferred to V1.x.
  // The USDC devnet/mainnet mint hard-list needs a separate wire-up via the token registry provider.
  return 'TOKEN';
}

/// metadata.network ('devnet'|'mainnet') → SolanaNetwork → explorerTxUrl.
/// Missing or unknown values fall back to devnet (dev environment first).
String _explorerUrlForNetwork(
  Map<String, dynamic> metadata,
  String txHash,
) {
  final networkStr = (metadata['network'] as String?) ?? 'devnet';
  final network = networkStr == 'mainnet'
      ? SolanaNetwork.mainnet
      : SolanaNetwork.devnet;
  return network.explorerTxUrl(txHash);
}
