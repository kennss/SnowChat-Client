/// @file        tx_detail_screen.dart
/// @description Transaction detail screen — Helius Enhanced Transaction
///              first, legacy fallback. signature / status / amount / from /
///              to / fee / blockTime / type badge / description +
///              nativeTransfers/tokenTransfers details + "Send Again" /
///              "Copy" / "Explorer" actions. Phase 6.1.3 — Phantom UX parity
///              + Helius Enhanced.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-09
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TxDetailScreen: shows transaction details + action buttons (auto Enhanced/Legacy switch)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../nft/nft_provider.dart' show nftAssetByMintProvider;
import '../providers/enhanced_history_provider.dart';
import '../providers/tx_detail_provider.dart';
import '../rpc/rpc_client_provider.dart' show solanaNetworkProvider;
import '../rpc/rpc_config.dart' show SolanaNetwork;
import '../tensor/tensor_providers.dart'
    show snowchatVaultAddressProvider, listStateAddressProvider;
import '../transaction/enhanced_transaction.dart';
import '../transaction/transaction_parser.dart';
import '../wallet_provider.dart';

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const error = Color(0xFFFF4444);
}

class TxDetailScreen extends ConsumerWidget {
  const TxDetailScreen({super.key, required this.signature});

  final String signature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(solanaNetworkProvider);
    final enhancedAvailable = ref.watch(enhancedHistoryAvailableProvider);

    // Enhanced mode: prefer Helius data when available
    if (enhancedAvailable) {
      final enhancedAsync = ref.watch(enhancedTxDetailProvider(signature));
      final enhancedTx = enhancedAsync.valueOrNull;
      if (enhancedTx != null) {
        final ownerAddress = ref.watch(walletProvider.select((s) => s.publicKey)) ?? '';
        return _buildScaffold(
          context: context,
          body: _EnhancedDetailBody(
            tx: enhancedTx,
            ownerAddress: ownerAddress,
            network: network,
          ),
        );
      }
    }

    // Legacy fallback
    final txAsync = ref.watch(txDetailProvider(signature));
    return _buildScaffold(
      context: context,
      body: txAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _C.primary),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: _C.textSecondary)),
        ),
        data: (tx) {
          if (tx == null) {
            return const Center(
              child: Text(
                'Transaction not found',
                style: TextStyle(color: _C.textSecondary, fontSize: 16),
              ),
            );
          }
          return _LegacyDetailBody(tx: tx, signature: signature, network: network);
        },
      ),
    );
  }

  Widget _buildScaffold({required BuildContext context, required Widget body}) {
    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        elevation: 0,
        title: const Text(
          'Transaction Details',
          style: TextStyle(color: _C.textPrimary, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      // SafeArea(top: false) — AppBar 가 status bar 처리, 우리는 system
      // gesture nav bar 인셋만 필요. S23 같은 작은 디스플레이에서 Explorer
      // 버튼이 nav bar 와 충돌해 잘려보이고 탭 어려운 문제 (2026-04-27 사용자
      // 리포트). 다른 wallet 화면들도 동일 패턴 적용 가치 있음.
      body: SafeArea(top: false, child: body),
    );
  }
}

// ---------------------------------------------------------------------------
// Enhanced Detail Body (Helius)
// ---------------------------------------------------------------------------

class _EnhancedDetailBody extends ConsumerWidget {
  const _EnhancedDetailBody({
    required this.tx,
    required this.ownerAddress,
    required this.network,
  });

  final EnhancedTransaction tx;
  final String ownerAddress;
  final SolanaNetwork network;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSend = tx.isSend(ownerAddress);
    final cp = tx.counterparty(ownerAddress);
    // Phase X-3 cleanup: marketplace 의 counterparty (PDA / vault) 는
    // 의미가 없으니 NFT mint 로 대체.
    final isMarketplace = tx.type == EnhancedTxType.nftSale ||
        tx.type == EnhancedTxType.nftListing ||
        tx.type == EnhancedTxType.nftCancelListing;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          _EnhancedStatusBadge(tx: tx, ownerAddress: ownerAddress),
          const SizedBox(height: 20),

          // Description (Helius natural-language description)
          // Marketplace 는 Helius 의 description 이 부정확 (PDA 주소 표시
          // 등) — 우리 fund-flow note 가 더 정확하니 marketplace 면 skip.
          if (!isMarketplace &&
              tx.description != null &&
              tx.description!.isNotEmpty) ...[
            Text(
              tx.description!,
              style: const TextStyle(color: _C.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
          ],

          // Primary amount
          if (tx.nativeTransfers.isNotEmpty || tx.tokenTransfers.isNotEmpty) ...[
            Text(
              _primaryAmountText(isSend),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _C.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
          ],

          // Counterparty — marketplace 면 NFT mint, 아니면 일반 주소.
          if (isMarketplace && tx.marketplaceNftMint != null) ...[
            Text(
              'NFT: ${_shorten(tx.marketplaceNftMint!)}',
              style: const TextStyle(color: _C.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
          ] else if (!isMarketplace && cp != null) ...[
            Text(
              '${isSend ? 'To' : 'From'} ${_shorten(cp)}',
              style: const TextStyle(color: _C.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
          ],

          // Details card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _DetailRow(
                  label: 'Signature',
                  value: _shorten(tx.signature),
                  onCopy: () => _copy(context, tx.signature, 'Signature'),
                ),
                _DetailRow(label: 'Type', value: tx.type.displayLabel),
                if (tx.source != null && tx.source!.isNotEmpty)
                  _DetailRow(label: 'Source', value: tx.sourceLabel),
                _DetailRow(label: 'Fee', value: '${_formatSol(tx.fee)} SOL'),
                _DetailRow(
                  label: 'Fee Payer',
                  value: _shorten(tx.feePayer),
                  onCopy: () => _copy(context, tx.feePayer, 'Fee Payer'),
                ),
                _DetailRow(
                  label: 'Time',
                  value: DateFormat('MMM d, y  h:mm a').format(tx.dateTime),
                ),
                // Marketplace 는 counterparty (PDA) 의미 없음 — skip.
                if (!isMarketplace && cp != null)
                  _DetailRow(
                    label: isSend ? 'Recipient' : 'Sender',
                    value: _shorten(cp),
                    onCopy: () => _copy(context, cp, 'Address'),
                  ),
              ],
            ),
          ),

          // Phase X-3: marketplace fund flow note (helps explain why
          // "net" differs from the listing price — PDA rent refund,
          // marketplace fee, royalty, network fee all combine).
          if (tx.type == EnhancedTxType.nftSale ||
              tx.type == EnhancedTxType.nftListing ||
              tx.type == EnhancedTxType.nftCancelListing) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _C.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _C.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: _C.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Why does the net differ from the price?',
                        style: TextStyle(
                          color: _C.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _marketplaceFlowExplain(),
                    style: const TextStyle(
                      color: _C.textSecondary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Native transfers (Phase X-3 entity-aware label for marketplace).
          if (tx.nativeTransfers.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'SOL Transfers',
              style: TextStyle(color: _C.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _SolTransfersList(
              tx: tx,
              ownerAddress: ownerAddress,
              isMarketplace: isMarketplace,
            ),
          ],

          // Token transfers
          if (tx.tokenTransfers.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Token Transfers',
              style: TextStyle(color: _C.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: tx.tokenTransfers.map((tt) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_shorten(tt.fromUserAccount)} -> ${_shorten(tt.toUserAccount)}',
                                style: const TextStyle(color: _C.textSecondary, fontSize: 12),
                              ),
                            ),
                            Text(
                              '${tt.tokenAmount}',
                              style: const TextStyle(color: _C.textPrimary, fontSize: 12),
                            ),
                          ],
                        ),
                        Text(
                          'Mint: ${_shorten(tt.mint)}',
                          style: const TextStyle(color: _C.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              if (isSend && (tx.type == EnhancedTxType.transfer || tx.type == EnhancedTxType.transferChecked))
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(
                      '/wallet/send',
                      extra: cp != null ? {'address': cp} : null,
                    ),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Send Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primary,
                      foregroundColor: _C.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (isSend && (tx.type == EnhancedTxType.transfer || tx.type == EnhancedTxType.transferChecked))
                const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = network.explorerTxUrl(tx.signature);
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Explorer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _C.primary,
                    side: BorderSide(color: _C.primary.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _primaryAmountText(bool isSend) {
    // Phase X-3: marketplace 는 owner net SOL change 사용 (첫 transfer
    // 만 보면 잘못된 amount).
    if (tx.type == EnhancedTxType.nftSale ||
        tx.type == EnhancedTxType.nftListing ||
        tx.type == EnhancedTxType.nftCancelListing) {
      final net = tx.netSolForOwner(ownerAddress);
      if (net != BigInt.zero) {
        final prefix = net < BigInt.zero ? 'Sent' : 'Received';
        return '$prefix ${_formatAmount(net.abs())} SOL net';
      }
    }
    // Native transfers
    for (final nt in tx.nativeTransfers) {
      if (nt.fromUserAccount == ownerAddress || nt.toUserAccount == ownerAddress) {
        final prefix = isSend ? 'Sent' : 'Received';
        return '$prefix ${_formatAmount(nt.amount)} SOL';
      }
    }
    // Token transfers
    for (final tt in tx.tokenTransfers) {
      if (tt.fromUserAccount == ownerAddress || tt.toUserAccount == ownerAddress) {
        final prefix = isSend ? 'Sent' : 'Received';
        return '$prefix ${tt.tokenAmount}';
      }
    }
    return tx.type.displayLabel;
  }

  /// Phase X-3 — explain marketplace tx fund movements so users don't
  /// wonder "why did I receive 1.002 SOL when the listing was 1 SOL?".
  /// Uses observed net to phrase context-aware text (sell vs buy vs
  /// list vs cancel).
  String _marketplaceFlowExplain() {
    final net = tx.netSolForOwner(ownerAddress);
    switch (tx.type) {
      case EnhancedTxType.nftListing:
        return 'Listing reserves rent for the on-chain PDA + ATA + pays '
            'a network fee. The PDA rent (~0.002 SOL) is returned '
            'automatically when the NFT sells or you cancel.';
      case EnhancedTxType.nftCancelListing:
        return 'Cancelling closes the PDA and refunds its rent (~0.002 '
            'SOL) back to you, minus the small network fee paid to '
            'broadcast this transaction.';
      case EnhancedTxType.nftSale:
        if (net > BigInt.zero) {
          // Seller view
          return 'Sale total = NFT price (received from buyer) + the PDA '
              'rent you originally deposited at listing time '
              '(~0.002 SOL is returned now that the PDA closes). '
              'Marketplace fee + creator royalty are paid by the buyer, '
              'not deducted from you.';
        }
        // Buyer view
        return 'Purchase total = NFT price (to seller) + creator royalty '
            '+ marketplace fee (to SnowChat) + network fee. The exact '
            'breakdown is visible in "SOL Transfers" below.';
      default:
        return '';
    }
  }

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _C.surface,
        content: Text('$label copied', style: const TextStyle(color: _C.textPrimary)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static String _shorten(String s) {
    if (s.length <= 12) return s;
    return '${s.substring(0, 6)}...${s.substring(s.length - 6)}';
  }

  static String _formatAmount(BigInt lamports) {
    final abs = lamports.abs();
    final sol = abs ~/ BigInt.from(1000000000);
    final frac = (abs % BigInt.from(1000000000)).toString().padLeft(9, '0');
    final trimmed = frac.replaceAll(RegExp(r'0+$'), '');
    if (trimmed.isEmpty) return '$sol';
    return '$sol.$trimmed';
  }

  static String _formatSol(BigInt lamports) {
    final sol = lamports ~/ BigInt.from(1000000000);
    final frac = (lamports % BigInt.from(1000000000)).abs().toString().padLeft(9, '0');
    return '$sol.${frac.substring(0, 6)}';
  }
}

/// Phase X-3 entity-aware SOL transfer list. For marketplace tx, each
/// row gets a meaning label (Marketplace fee / PDA rent / Royalty /
/// Sale price / You / Other). Non-marketplace tx falls back to the
/// raw "from -> to" view.
class _SolTransfersList extends ConsumerWidget {
  const _SolTransfersList({
    required this.tx,
    required this.ownerAddress,
    required this.isMarketplace,
  });

  final EnhancedTransaction tx;
  final String ownerAddress;
  final bool isMarketplace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? vault;
    String? listState;
    Set<String> creators = const {};

    if (isMarketplace) {
      vault = ref.watch(snowchatVaultAddressProvider).valueOrNull;
      final mint = tx.marketplaceNftMint;
      if (mint != null) {
        listState = ref.watch(listStateAddressProvider(mint)).valueOrNull;
        final asset = ref.watch(nftAssetByMintProvider(mint)).valueOrNull;
        if (asset != null && asset.creatorAddresses.isNotEmpty) {
          creators = asset.creatorAddresses.toSet();
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: tx.nativeTransfers.map((nt) {
          final label = isMarketplace
              ? _classify(nt, vault, listState, creators)
              : null;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_EnhancedDetailBody._shorten(nt.fromUserAccount)} '
                        '-> ${_EnhancedDetailBody._shorten(nt.toUserAccount)}',
                        style: const TextStyle(
                          color: _C.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      '${_EnhancedDetailBody._formatSol(nt.amount)} SOL',
                      style: const TextStyle(
                        color: _C.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (label != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: const TextStyle(
                      color: _C.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _classify(
    NativeTransfer nt,
    String? vault,
    String? listState,
    Set<String> creators,
  ) {
    if (vault != null && nt.toUserAccount == vault) {
      return 'Marketplace fee';
    }
    if (listState != null) {
      if (nt.fromUserAccount == listState) return 'PDA rent refund';
      if (nt.toUserAccount == listState) return 'PDA rent deposit';
    }
    if (creators.contains(nt.toUserAccount)) return 'Royalty';
    if (creators.contains(nt.fromUserAccount)) return 'Royalty (refund)';
    if (nt.toUserAccount == ownerAddress) return 'You receive';
    if (nt.fromUserAccount == ownerAddress) return 'You pay';
    return 'Other';
  }
}

/// Enhanced type + status badge.
class _EnhancedStatusBadge extends StatelessWidget {
  const _EnhancedStatusBadge({required this.tx, required this.ownerAddress});
  final EnhancedTransaction tx;
  final String ownerAddress;

  @override
  Widget build(BuildContext context) {
    final isSend = tx.isSend(ownerAddress);
    final (label, color, icon) = switch (tx.type) {
      EnhancedTxType.transfer || EnhancedTxType.transferChecked =>
        isSend ? ('Sent', _C.primary, Icons.arrow_upward) : ('Received', _C.primary, Icons.arrow_downward),
      EnhancedTxType.swap => ('Swap', const Color(0xFFFFAA00), Icons.swap_horiz),
      // Phase X-3: isSend = owner sent net SOL = buyer (NFT Purchased).
      // !isSend = owner received net SOL = seller (NFT Sold).
      EnhancedTxType.nftSale =>
        isSend ? ('NFT Purchased', const Color(0xFFBB86FC), Icons.storefront) : ('NFT Sold', const Color(0xFFBB86FC), Icons.storefront),
      EnhancedTxType.nftListing => ('NFT Listed', const Color(0xFFFFAA00), Icons.sell),
      EnhancedTxType.nftCancelListing => ('Listing Cancelled', _C.textTertiary, Icons.cancel_outlined),
      EnhancedTxType.nftMint || EnhancedTxType.compressedNftMint =>
        ('NFT Minted', const Color(0xFFBB86FC), Icons.auto_awesome),
      EnhancedTxType.tokenMint => ('Token Mint', _C.primary, Icons.generating_tokens),
      EnhancedTxType.burn || EnhancedTxType.burnChecked =>
        ('Burned', _C.error, Icons.local_fire_department),
      _ => (tx.type.displayLabel, _C.textTertiary, Icons.receipt_long),
    };

    final statusText = tx.transactionError != null ? 'Failed' : 'Confirmed';
    final statusColor = tx.transactionError != null ? _C.error : _C.primary;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (tx.source != null && tx.source!.isNotEmpty && tx.source != 'SYSTEM_PROGRAM')
                Text(
                  'via ${tx.sourceLabel}',
                  style: const TextStyle(color: _C.textTertiary, fontSize: 12),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            statusText,
            style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Legacy Detail Body (fallback)
// ---------------------------------------------------------------------------

class _LegacyDetailBody extends StatelessWidget {
  const _LegacyDetailBody({
    required this.tx,
    required this.signature,
    required this.network,
  });

  final ParsedTxResult tx;
  final String signature;
  final SolanaNetwork network;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(type: tx.type),
          const SizedBox(height: 20),

          if (tx.amountLamports != null) ...[
            Text(
              '${_typePrefix(tx.type)} ${_formatAmount(tx.amountLamports!)} ${tx.tokenMint == null ? 'SOL' : 'tokens'}',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: _C.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
          ],

          if (tx.counterparty != null) ...[
            Text(
              '${tx.type == ParsedTxType.solSend || tx.type == ParsedTxType.splSend ? 'To' : 'From'} ${_shorten(tx.counterparty!)}',
              style: const TextStyle(color: _C.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
          ],

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _DetailRow(
                  label: 'Signature',
                  value: _shorten(tx.signature),
                  onCopy: () => _copy(context, tx.signature, 'Signature'),
                ),
                if (tx.feeLamports != null)
                  _DetailRow(label: 'Fee', value: '${_formatSol(tx.feeLamports!)} SOL'),
                if (tx.blockTime != null)
                  _DetailRow(
                    label: 'Time',
                    value: DateFormat('MMM d, y  h:mm a').format(tx.dateTime!),
                  ),
                if (tx.slot != null)
                  _DetailRow(label: 'Slot', value: NumberFormat('#,###').format(tx.slot)),
                if (tx.tokenMint != null)
                  _DetailRow(
                    label: 'Token Mint',
                    value: _shorten(tx.tokenMint!),
                    onCopy: () => _copy(context, tx.tokenMint!, 'Mint'),
                  ),
                if (tx.counterparty != null)
                  _DetailRow(
                    label: tx.type == ParsedTxType.solSend || tx.type == ParsedTxType.splSend
                        ? 'Recipient'
                        : 'Sender',
                    value: _shorten(tx.counterparty!),
                    onCopy: () => _copy(context, tx.counterparty!, 'Address'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              if (tx.type == ParsedTxType.solSend || tx.type == ParsedTxType.splSend)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(
                      '/wallet/send',
                      extra: tx.counterparty != null ? {'address': tx.counterparty} : null,
                    ),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Send Again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _C.primary,
                      foregroundColor: _C.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (tx.type == ParsedTxType.solSend || tx.type == ParsedTxType.splSend)
                const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = network.explorerTxUrl(signature);
                    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Explorer'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _C.primary,
                    side: BorderSide(color: _C.primary.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _C.surface,
        content: Text('$label copied', style: const TextStyle(color: _C.textPrimary)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static String _shorten(String s) {
    if (s.length <= 12) return s;
    return '${s.substring(0, 6)}...${s.substring(s.length - 6)}';
  }

  static String _typePrefix(ParsedTxType type) {
    return switch (type) {
      ParsedTxType.solSend || ParsedTxType.splSend => 'Sent',
      ParsedTxType.solReceive || ParsedTxType.splReceive => 'Received',
      ParsedTxType.unknown => '',
    };
  }

  static String _formatAmount(BigInt lamports) {
    final abs = lamports.abs();
    final sol = abs ~/ BigInt.from(1000000000);
    final frac = (abs % BigInt.from(1000000000)).toString().padLeft(9, '0');
    final trimmed = frac.replaceAll(RegExp(r'0+$'), '');
    if (trimmed.isEmpty) return '$sol';
    return '$sol.$trimmed';
  }

  static String _formatSol(BigInt lamports) {
    final sol = lamports ~/ BigInt.from(1000000000);
    final frac = (lamports % BigInt.from(1000000000)).abs().toString().padLeft(9, '0');
    return '$sol.${frac.substring(0, 6)}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.type});
  final ParsedTxType type;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (type) {
      ParsedTxType.solSend || ParsedTxType.splSend => ('Sent', _C.primary, Icons.arrow_upward),
      ParsedTxType.solReceive || ParsedTxType.splReceive => ('Received', _C.primary, Icons.arrow_downward),
      ParsedTxType.unknown => ('Unknown', _C.textTertiary, Icons.help_outline),
    };
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _C.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Confirmed',
            style: TextStyle(color: _C.primary, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.onCopy});
  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _C.textTertiary, fontSize: 13)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: const TextStyle(color: _C.textPrimary, fontSize: 13)),
              if (onCopy != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onCopy,
                  child: const Icon(Icons.copy, size: 14, color: _C.textTertiary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
