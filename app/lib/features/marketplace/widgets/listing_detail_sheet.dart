/// @file        listing_detail_sheet.dart
/// @description NFT listing detail bottom sheet — NFT image/name/collection, price, seller,
///              fee info, [Buy Now] slide-to-confirm or [Cancel Listing] button.
///              BigInt only (price). Display conversion via lamportsToSol() only.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-11
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showListingDetailSheet: utility function that shows the bottom sheet
///  - _ListingDetailContent: bottom sheet inner content widget

/// Listing detail bottom sheet — view NFT details, buy or cancel.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';

import '../../wallet/tensor/community_registration.dart';
import '../../wallet/tensor/fee_split_preview.dart';
import '../../wallet/tensor/tensor_providers.dart';
import '../../wallet/utils/amount_converter.dart';
import '../../wallet/utils/transfer_error_formatter.dart';
import '../marketplace_models.dart';
import '../providers/marketplace_provider.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const primaryBg = Color(0xFF0A2A1A);
  static const surface = Color(0xFF111111);
  static const surfaceLight = Color(0xFF1A1A1A);
  static const surfaceVariant = Color(0xFF242424);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const error = Color(0xFFFF4444);
  static const warning = Color(0xFFFF9800);
}

/// Show the listing detail bottom sheet.
void showListingDetailSheet({
  required BuildContext context,
  required MarketplaceListing listing,
  required bool isOwner,
  required WidgetRef ref,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ListingDetailContent(
      listing: listing,
      isOwner: isOwner,
      ref: ref,
    ),
  );
}

class _ListingDetailContent extends StatefulWidget {
  const _ListingDetailContent({
    required this.listing,
    required this.isOwner,
    required this.ref,
  });

  final MarketplaceListing listing;
  final bool isOwner;
  final WidgetRef ref;

  @override
  State<_ListingDetailContent> createState() => _ListingDetailContentState();
}

class _ListingDetailContentState extends State<_ListingDetailContent> {
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      decoration: const BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _C.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // NFT Image.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: listing.nftImageUrl != null &&
                          listing.nftImageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: listing.nftImageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: _C.surfaceVariant,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: _C.primary, strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: _C.surfaceVariant,
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined,
                                  color: _C.textSecondary, size: 48),
                            ),
                          ),
                        )
                      : Container(
                          color: _C.surfaceVariant,
                          child: const Center(
                            child: Icon(Icons.image_outlined,
                                color: _C.textTertiary, size: 48),
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // NFT name + collection + status.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Collection row with verified badge.
                  if (listing.collectionName != null &&
                      listing.collectionName!.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.verified,
                            size: 16, color: _C.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            listing.collectionName!,
                            style: const TextStyle(
                                color: _C.textSecondary, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],

                  // NFT Name.
                  Text(
                    listing.nftName ?? 'Unnamed NFT',
                    style: const TextStyle(
                      color: _C.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Mint address (copyable).
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(
                          ClipboardData(text: listing.nftMintAddress));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Mint address copied'),
                          backgroundColor: _C.surfaceLight,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          listing.shortMintAddress,
                          style: const TextStyle(
                              color: _C.textTertiary, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy,
                            size: 12, color: _C.textTertiary),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Price section.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _C.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    // Price with SOL icon.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Price',
                          style: TextStyle(
                              color: _C.textSecondary, fontSize: 14),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Solana gradient icon.
                            Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF9945FF),
                                    Color(0xFF14F195),
                                  ],
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'S',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFFFFFFF),
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              listing.formattedPrice,
                              style: const TextStyle(
                                color: _C.primary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Seller',
                      value: listing.shortSellerAddress,
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Marketplace fee (${listing.feeBps ~/ 100}%)',
                      value: listing.formattedFee,
                    ),
                    if (listing.royaltyBps > 0) ...[
                      const SizedBox(height: 12),
                      _DetailRow(
                        label: 'Creator royalty (${(listing.royaltyBps / 100).toStringAsFixed(listing.royaltyBps % 100 == 0 ? 0 : 1)}%)',
                        value: _formatLamports(
                          listing.priceLamports *
                              BigInt.from(listing.royaltyBps) ~/
                              BigInt.from(10000),
                        ),
                      ),
                    ],
                    // Phase 2: if the listing's collection is community-
                    // registered, surface the 50% leader share so the buyer
                    // knows where their fee flows. Fetched live from the
                    // CommunityRegistration PDA.
                    _CommunitySplitRow(listing: listing),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Info section (listing date, status, etc.).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _C.surfaceLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Status',
                      value: listing.status,
                      valueColor: listing.status == 'ACTIVE'
                          ? _C.primary
                          : listing.status == 'SOLD'
                              ? const Color(0xFF00C853)
                              : _C.warning,
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Listed',
                      value:
                          '${DateFormat('MMM d, yyyy').format(listing.listedAt)} (${listing.timeAgo})',
                    ),
                  ],
                ),
              ),
            ),

            // Error display.
            if (_error != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _C.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: _C.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: _C.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: widget.isOwner
                  ? _CancelListingButton(
                      isLoading: _isLoading,
                      onCancel: _handleCancel,
                    )
                  : _BuySlideToConfirm(
                      isLoading: _isLoading,
                      onConfirm: _handleBuy,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleBuy() async {
    // Biometric auth gate.
    final localAuth = LocalAuthentication();
    final canAuth = await localAuth.canCheckBiometrics ||
        await localAuth.isDeviceSupported();
    if (canAuth) {
      try {
        final didAuth = await localAuth.authenticate(
          localizedReason: 'Authenticate to purchase NFT',
          options: const AuthenticationOptions(biometricOnly: false),
        );
        if (!didAuth) return;
      } catch (e) {
        debugPrint('[Marketplace] Biometric auth error: $e');
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final notifier =
          widget.ref.read(marketplaceNotifierProvider.notifier);
      // Tensor PDA buy_legacy — single transaction. If the collection is
      // community-registered, 50/50 community split applies automatically
      // (decided inside buyListing).
      final success = await notifier.buyListing(
        listing: widget.listing,
      );

      if (mounted) {
        if (success) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Purchased ${widget.listing.nftName ?? 'NFT'} successfully!'),
              backgroundColor: _C.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
        } else {
          final state = widget.ref.read(marketplaceNotifierProvider);
          setState(() {
            _isLoading = false;
            _error = TransferErrorFormatter.format(
              state.error ?? 'Purchase failed',
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = TransferErrorFormatter.format(e.toString());
        });
      }
    }
  }

  Future<void> _handleCancel() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final notifier =
          widget.ref.read(marketplaceNotifierProvider.notifier);
      final success = await notifier.cancelListing(widget.listing);

      if (mounted) {
        if (success) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Listing cancelled'),
              backgroundColor: _C.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          );
        } else {
          final state = widget.ref.read(marketplaceNotifierProvider);
          setState(() {
            _isLoading = false;
            _error = TransferErrorFormatter.format(
              state.error ?? 'Cancel failed',
            );
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = TransferErrorFormatter.format(e.toString());
        });
      }
    }
  }
}

/// Format BigInt lamports to SOL display string.
String _formatLamports(BigInt lamports) {
  final sol = lamports ~/ BigInt.from(1000000000);
  final frac = (lamports % BigInt.from(1000000000)).abs();
  var fracStr = frac.toString().padLeft(9, '0');
  fracStr = fracStr.replaceAll(RegExp(r'0+$'), '');
  if (fracStr.isEmpty) return '$sol SOL';
  return '$sol.$fracStr SOL';
}

// ---------------------------------------------------------------------------
// Detail row
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor = _C.textPrimary,
    this.valueFontSize = 14,
    this.valueFontWeight = FontWeight.w500,
  });

  final String label;
  final String value;
  final Color valueColor;
  final double valueFontSize;
  final FontWeight valueFontWeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: _C.textSecondary, fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: valueFontSize,
            fontWeight: valueFontWeight,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Buy slide-to-confirm
// ---------------------------------------------------------------------------

class _BuySlideToConfirm extends StatefulWidget {
  const _BuySlideToConfirm({
    required this.onConfirm,
    this.isLoading = false,
  });

  final VoidCallback onConfirm;
  final bool isLoading;

  @override
  State<_BuySlideToConfirm> createState() => _BuySlideToConfirmState();
}

class _BuySlideToConfirmState extends State<_BuySlideToConfirm> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _C.primaryBg,
        borderRadius: BorderRadius.circular(28),
      ),
      child: widget.isLoading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: _C.primary, strokeWidth: 2.5),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxSlide = constraints.maxWidth - 56;
                return Stack(
                  children: [
                    Center(
                      child: Text(
                        'Slide to buy',
                        style: TextStyle(
                          color: _C.primary.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Positioned(
                      left: _progress * maxSlide,
                      top: 4,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) {
                          setState(() {
                            _progress += d.delta.dx / maxSlide;
                            _progress = _progress.clamp(0.0, 1.0);
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          if (_progress > 0.85) widget.onConfirm();
                          setState(() => _progress = 0);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: _C.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF000000),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cancel listing button
// ---------------------------------------------------------------------------

class _CancelListingButton extends StatelessWidget {
  const _CancelListingButton({
    required this.isLoading,
    required this.onCancel,
  });

  final bool isLoading;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: isLoading ? null : onCancel,
        style: OutlinedButton.styleFrom(
          foregroundColor: _C.warning,
          side: BorderSide(color: _C.warning.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: _C.warning, strokeWidth: 2),
              )
            : const Text(
                'Cancel Listing',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// Leader share preview — rendered when the listing's collection is
/// registered for Community Fee Share. Shows the exact lamports that will
/// flow to the community leader (from the buyer's taker fee) so the trade
/// is transparent. Hidden when no registration, or when the computed
/// share falls under the on-chain dust threshold.
class _CommunitySplitRow extends ConsumerWidget {
  const _CommunitySplitRow({required this.listing});

  final MarketplaceListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(communityFeaturesEnabledProvider);
    if (!enabled) return const SizedBox.shrink();
    final collectionMint = listing.collectionMint;
    if (collectionMint == null || collectionMint.isEmpty) {
      return const SizedBox.shrink();
    }

    final asyncReg =
        ref.watch(communityRegistrationFetchProvider(collectionMint));
    return asyncReg.when(
      data: (reg) {
        if (reg == null || !reg.isActive) return const SizedBox.shrink();
        return _buildPreview(reg);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildPreview(CommunityRegistration reg) {
    final split = computeExpectedSplit(
      listingPrice: listing.priceLamports,
      hasCommunity: true,
    );
    if (split.leaderShare <= BigInt.zero) {
      // dust redirected — don't mislead buyer.
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _C.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.groups_outlined, color: _C.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Community leader share (50% of protocol fee)',
                    style: TextStyle(color: _C.primary, fontSize: 12),
                  ),
                  Text(
                    '${lamportsToSol(split.leaderShare)} SOL → '
                    '${reg.leaderWallet.toBase58().substring(0, 4)}…'
                    '${reg.leaderWallet.toBase58().substring(reg.leaderWallet.toBase58().length - 4)}',
                    style: const TextStyle(
                      color: _C.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
