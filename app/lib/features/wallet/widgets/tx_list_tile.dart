/// @file        tx_list_tile.dart
/// @description Transaction-history list-tile widget (type-based icon,
///              amount, status).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - TxListTile: list-tile widget that displays per-transaction info

/// Transaction history list tile.
library;

import 'package:flutter/material.dart';

import '../../../shared/models/wallet_models.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textTertiary = Color(0xFF5C5C5C);
  static const error = Color(0xFFFF4444);
  static const warning = Color(0xFFFFAA00);
  static const divider = Color(0xFF1E1E1E);
}

/// A single transaction row for the activity / history list.
class TxListTile extends StatelessWidget {
  const TxListTile({
    super.key,
    required this.tx,
    this.onTap,
  });

  final TransactionInfo tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _C.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            _icon(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _C.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    style: const TextStyle(fontSize: 12, color: _C.textTertiary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _amount(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _amountColor(),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _statusLabel(),
                  style: TextStyle(
                    fontSize: 11,
                    color: _statusColor(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon() {
    IconData iconData;
    Color iconColor;
    switch (tx.type) {
      case TransactionType.receive:
        iconData = Icons.arrow_downward_rounded;
        iconColor = _C.primary;
        break;
      case TransactionType.send:
        iconData = Icons.arrow_upward_rounded;
        iconColor = _C.error;
        break;
      case TransactionType.swap:
        iconData = Icons.swap_horiz_rounded;
        iconColor = _C.warning;
        break;
      case TransactionType.nftSend:
        iconData = Icons.image_outlined;
        iconColor = _C.error;
        break;
      case TransactionType.nftReceive:
        iconData = Icons.image_outlined;
        iconColor = _C.primary;
        break;
      case TransactionType.unknown:
        iconData = Icons.help_outline;
        iconColor = _C.textTertiary;
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: iconColor, size: 20),
    );
  }

  String _title() {
    switch (tx.type) {
      case TransactionType.receive:
        return 'Received';
      case TransactionType.send:
        return 'Sent';
      case TransactionType.swap:
        return 'Swap';
      case TransactionType.nftSend:
        return 'NFT Sent';
      case TransactionType.nftReceive:
        return 'NFT Received';
      case TransactionType.unknown:
        return 'Transaction';
    }
  }

  String _subtitle() {
    final time = _formatTime(tx.timestamp);
    if (tx.nftName != null) return '${tx.nftName} - $time';
    if (tx.fromAddress != null && tx.type == TransactionType.receive) {
      return 'From ${TransactionInfo.shortenAddress(tx.fromAddress!)} - $time';
    }
    if (tx.toAddress != null && tx.type == TransactionType.send) {
      return 'To ${TransactionInfo.shortenAddress(tx.toAddress!)} - $time';
    }
    return time;
  }

  String _amount() {
    if (tx.amountLamports == null || tx.tokenSymbol == null) return '';
    final symbol = tx.tokenSymbol!;
    final lamports = tx.amountLamports!;
    // Simple display: convert to human-readable.
    final decimals = symbol == 'SOL' ? 9 : 6;
    final divisor = BigInt.from(10).pow(decimals);
    final whole = lamports ~/ divisor;
    final frac = (lamports % divisor).abs();
    var fracStr = frac.toString().padLeft(decimals, '0').replaceAll(RegExp(r'0+$'), '');
    final value = fracStr.isEmpty ? '$whole' : '$whole.$fracStr';

    final prefix = tx.type == TransactionType.receive || tx.type == TransactionType.nftReceive
        ? '+'
        : '-';
    return '$prefix$value $symbol';
  }

  Color _amountColor() {
    if (tx.type == TransactionType.receive || tx.type == TransactionType.nftReceive) {
      return _C.primary;
    }
    return _C.textPrimary;
  }

  String _statusLabel() {
    switch (tx.status) {
      case TransactionStatus.confirmed:
        return 'Confirmed';
      case TransactionStatus.pending:
        return 'Pending';
      case TransactionStatus.failed:
        return 'Failed';
    }
  }

  Color _statusColor() {
    switch (tx.status) {
      case TransactionStatus.confirmed:
        return _C.primary;
      case TransactionStatus.pending:
        return _C.warning;
      case TransactionStatus.failed:
        return _C.error;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }
}
