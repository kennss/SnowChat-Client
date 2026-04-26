/// @file        send_preview_sheet.dart
/// @description Pre-send user confirmation preview sheet. Shows base fee +
///              priority fee + total deducted amount. Uses FeeEstimator
///              result (BigInt only). Phase 6.1 §2.3, §2.4.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showSendPreviewSheet(): bottom-sheet entry helper
///  - SendPreviewSheet: widget
library;

import 'package:flutter/material.dart';

import '../transaction/compute_budget_helper.dart';
import '../transaction/fee_estimator.dart';
import '../utils/amount_converter.dart' as amt;
import 'fee_tier_selector.dart';

/// Preview result — closes with [confirmed=true] when the user taps "Confirm".
class SendPreviewResult {
  const SendPreviewResult({
    required this.confirmed,
    required this.level,
  });
  final bool confirmed;
  final PriorityLevel level;
}

typedef PreviewLoader = Future<FeeEstimate> Function(PriorityLevel level);

Future<SendPreviewResult?> showSendPreviewSheet({
  required BuildContext context,
  required String recipient,
  required BigInt amountLamports,
  required String tokenSymbol,
  required int tokenDecimals,
  required PriorityLevel initialLevel,
  required PreviewLoader loadEstimate,
}) {
  return showModalBottomSheet<SendPreviewResult>(
    context: context,
    backgroundColor: const Color(0xFF111111),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SendPreviewSheet(
      recipient: recipient,
      amountLamports: amountLamports,
      tokenSymbol: tokenSymbol,
      tokenDecimals: tokenDecimals,
      initialLevel: initialLevel,
      loadEstimate: loadEstimate,
    ),
  );
}

class SendPreviewSheet extends StatefulWidget {
  const SendPreviewSheet({
    super.key,
    required this.recipient,
    required this.amountLamports,
    required this.tokenSymbol,
    required this.tokenDecimals,
    required this.initialLevel,
    required this.loadEstimate,
  });

  final String recipient;
  final BigInt amountLamports;
  final String tokenSymbol;
  final int tokenDecimals;
  final PriorityLevel initialLevel;
  final PreviewLoader loadEstimate;

  @override
  State<SendPreviewSheet> createState() => _SendPreviewSheetState();
}

class _SendPreviewSheetState extends State<SendPreviewSheet> {
  static const _accent = Color(0xFF00F782);
  static const _accentBg = Color(0xFF0A2A1A);
  static const _text = Color(0xFFFFFFFF);
  static const _muted = Color(0xFF9E9E9E);
  static const _divider = Color(0xFF1F1F1F);

  late PriorityLevel _level;
  Future<FeeEstimate>? _future;

  @override
  void initState() {
    super.initState();
    _level = widget.initialLevel;
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.loadEstimate(_level);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grabber(),
            const SizedBox(height: 16),
            const Text(
              'Review transaction',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _kvRow('To', _shortAddress(widget.recipient)),
            const SizedBox(height: 8),
            _kvRow(
              'Amount',
              '${_formatAmount(widget.amountLamports, widget.tokenDecimals)} ${widget.tokenSymbol}',
            ),
            const SizedBox(height: 16),
            const Divider(color: _divider, height: 1),
            const SizedBox(height: 16),
            const Text(
              'Network speed',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            FeeTierSelector(
              value: _level,
              onChanged: (l) {
                _level = l;
                _reload();
              },
            ),
            const SizedBox(height: 16),
            _feeBlock(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _muted),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      SendPreviewResult(confirmed: false, level: _level),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: _muted),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      SendPreviewResult(confirmed: true, level: _level),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: _muted.withOpacity(0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _kvRow(String key, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key, style: const TextStyle(color: _muted, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: _text, fontSize: 13),
            ),
          ),
        ],
      );

  Widget _feeBlock() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accentBg.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FutureBuilder<FeeEstimate>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 56,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: _accent,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }
          if (snap.hasError || !snap.hasData) {
            return Text(
              'Failed to estimate fee. Defaulting to network minimum.',
              style: TextStyle(color: _muted.withOpacity(0.9), fontSize: 12),
            );
          }
          final est = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kvRow('Base fee', '${_formatSol(est.baseLamports)} SOL'),
              const SizedBox(height: 6),
              _kvRow('Priority fee', '${_formatSol(est.priorityLamports)} SOL'),
              const SizedBox(height: 6),
              _kvRow(
                'Total fee',
                '${_formatSol(est.totalLamports)} SOL',
              ),
              if (est.priorityLamports >=
                  ComputeBudgetHelper.maxPriorityFeeLamports) ...[
                const SizedBox(height: 8),
                Text(
                  'Priority fee is at the safety cap (0.001 SOL).',
                  style: TextStyle(
                    color: Colors.amber.shade400,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _shortAddress(String addr) {
    if (addr.length <= 12) return addr;
    return '${addr.substring(0, 6)}…${addr.substring(addr.length - 6)}';
  }

  static String _formatSol(BigInt lamports) {
    return amt.lamportsToSol(lamports);
  }

  static String _formatAmount(BigInt amount, int decimals) {
    if (decimals == 9) {
      return amt.lamportsToSol(amount);
    }
    return amt.smallestUnitToDisplay(amount, decimals);
  }
}
