/// @file        enhanced_tx_list_tile.dart
/// @description Transaction history list tile based on Helius Enhanced
///              Transaction. type-based icon/label (TRANSFER, SWAP, NFT_SALE,
///              ...) + description subtitle. NFT trade rows (nftSale /
///              nftListing / nftCancelListing) show the owner's net SOL.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-11-12 (removed the SnowChat marketplace NFT name / price title; back to a StatelessWidget; NFT trade rows keep the net-SOL amount). Earlier 2026-04-26 (Phase X-2 marketplace name+price)
///
/// @functions
///  - EnhancedTxListTile: per-transaction tile widget based on EnhancedTransaction
library;

import 'package:flutter/material.dart';

import '../transaction/enhanced_transaction.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textTertiary = Color(0xFF5C5C5C);
  static const error = Color(0xFFFF4444);
  static const warning = Color(0xFFFFAA00);
  static const purple = Color(0xFFBB86FC);
  static const divider = Color(0xFF1E1E1E);
}

/// A single transaction row for the Enhanced History activity list.
class EnhancedTxListTile extends StatelessWidget {
  const EnhancedTxListTile({
    super.key,
    required this.tx,
    required this.ownerAddress,
    this.onTap,
  });

  final EnhancedTransaction tx;
  final String ownerAddress;
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
                  style: TextStyle(fontSize: 11, color: _statusColor()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon() {
    final (iconData, iconColor) = _iconConfig();
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

  (IconData, Color) _iconConfig() {
    final isSend = tx.isSend(ownerAddress);
    return switch (tx.type) {
      EnhancedTxType.transfer || EnhancedTxType.transferChecked => isSend
          ? (Icons.arrow_upward_rounded, _C.error)
          : (Icons.arrow_downward_rounded, _C.primary),
      EnhancedTxType.swap => (Icons.swap_horiz_rounded, _C.warning),
      EnhancedTxType.nftSale => (Icons.storefront_rounded, _C.purple),
      EnhancedTxType.nftListing => (Icons.sell_rounded, _C.warning),
      EnhancedTxType.nftCancelListing => (Icons.cancel_outlined, _C.textTertiary),
      EnhancedTxType.nftMint || EnhancedTxType.compressedNftMint =>
        (Icons.auto_awesome, _C.purple),
      EnhancedTxType.tokenMint => (Icons.generating_tokens, _C.primary),
      EnhancedTxType.burn || EnhancedTxType.burnChecked =>
        (Icons.local_fire_department, _C.error),
      _ => (Icons.receipt_long_rounded, _C.textTertiary),
    };
  }

  String _title() {
    final isSend = tx.isSend(ownerAddress);
    return switch (tx.type) {
      EnhancedTxType.transfer || EnhancedTxType.transferChecked =>
        isSend ? 'Sent' : 'Received',
      EnhancedTxType.swap => 'Swapped',
      // isSend is net-SOL based for NFT trades: net SOL out = buyer.
      EnhancedTxType.nftSale => isSend ? 'NFT Purchased' : 'NFT Sold',
      EnhancedTxType.nftListing => 'Listed NFT',
      EnhancedTxType.nftCancelListing => 'Cancelled Listing',
      EnhancedTxType.nftMint || EnhancedTxType.compressedNftMint => 'Minted NFT',
      EnhancedTxType.tokenMint => 'Token Mint',
      EnhancedTxType.burn || EnhancedTxType.burnChecked => 'Burned',
      _ => tx.type.displayLabel,
    };
  }

  String _subtitle() {
    // Prefer Helius natural-language description
    if (tx.description != null && tx.description!.isNotEmpty) {
      return tx.description!;
    }
    // fallback: source + time
    final time = _formatTime(tx.dateTime);
    if (tx.source != null && tx.source!.isNotEmpty && tx.source != 'SYSTEM_PROGRAM') {
      return '${tx.sourceLabel} - $time';
    }
    return time;
  }

  String _amount() {
    // NFT trades spread SOL over several legs (price, royalty, fees), so the
    // first native transfer alone gives a wrong sign / amount. Sum the
    // owner's net SOL change instead.
    if (tx.type == EnhancedTxType.nftSale ||
        tx.type == EnhancedTxType.nftListing ||
        tx.type == EnhancedTxType.nftCancelListing) {
      final net = tx.netSolForOwner(ownerAddress);
      if (net == BigInt.zero) return '';
      final prefix = net < BigInt.zero ? '-' : '+';
      final formatted = _formatSol(net.abs());
      return '$prefix$formatted SOL';
    }

    // Native transfer amount (SOL)
    final lamports = tx.primaryAmountLamports(ownerAddress);
    if (lamports != null && lamports > BigInt.zero) {
      final formatted = _formatSol(lamports);
      final prefix = tx.isSend(ownerAddress) ? '-' : '+';
      return '$prefix$formatted SOL';
    }

    // Token transfer amount
    if (tx.tokenTransfers.isNotEmpty) {
      final tt = tx.tokenTransfers.first;
      final prefix = tt.fromUserAccount == ownerAddress ? '-' : '+';
      final amount = tt.tokenAmount;
      final formatted = amount == amount.truncateToDouble()
          ? amount.toInt().toString()
          : amount.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return '$prefix$formatted';
    }

    return '';
  }

  Color _amountColor() {
    if (tx.type == EnhancedTxType.swap) return _C.warning;
    return tx.isSend(ownerAddress) ? _C.textPrimary : _C.primary;
  }

  String _statusLabel() {
    if (tx.transactionError != null) return 'Failed';
    return 'Confirmed';
  }

  Color _statusColor() {
    if (tx.transactionError != null) return _C.error;
    return _C.primary;
  }

  static String _formatSol(BigInt lamports) {
    final abs = lamports.abs();
    final sol = abs ~/ BigInt.from(1000000000);
    final frac = (abs % BigInt.from(1000000000)).toString().padLeft(9, '0');
    final trimmed = frac.replaceAll(RegExp(r'0+$'), '');
    if (trimmed.isEmpty) return '$sol';
    return '$sol.$trimmed';
  }

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }
}
