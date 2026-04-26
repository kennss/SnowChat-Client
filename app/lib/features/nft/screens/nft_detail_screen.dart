/// @file        nft_detail_screen.dart
/// @description NFT detail screen (full image, description, attributes, token standard, send action).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - NFTDetailScreen: screen widget that shows NFT details

/// NFT detail screen showing full image, description, and attributes.
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:go_router/go_router.dart';

import '../../../shared/models/nft_models.dart';
import '../widgets/attribute_chip.dart';

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const surfaceVariant = Color(0xFF1A1A1A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
}

class NFTDetailScreen extends StatelessWidget {
  const NFTDetailScreen({super.key, required this.nft});

  final NFTAsset nft;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      body: CustomScrollView(
        slivers: [
          // Image + back button.
          SliverAppBar(
            backgroundColor: _C.background,
            expandedHeight: MediaQuery.of(context).size.width,
            pinned: true,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _C.background.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: _C.textPrimary, size: 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: CachedNetworkImage(
                imageUrl: nft.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: _C.surface,
                  child: const Center(
                    child: CircularProgressIndicator(color: _C.primary),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: _C.surface,
                  child: const Icon(Icons.broken_image, color: _C.textSecondary, size: 64),
                ),
              ),
            ),
          ),

          // Details.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Collection name.
                  if (nft.collectionName != null)
                    Text(
                      nft.collectionName!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _C.primary,
                      ),
                    ),
                  const SizedBox(height: 4),

                  // NFT name.
                  Text(
                    nft.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: _C.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description.
                  if (nft.description != null) ...[
                    Text(
                      nft.description!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _C.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Attributes.
                  if (nft.attributes.isNotEmpty) ...[
                    const Text(
                      'Attributes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _C.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: nft.attributes
                          .map((attr) => AttributeChip(attribute: attr))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Info section.
                  _infoSection(),
                  const SizedBox(height: 24),

                  // Actions — "Listed" badge if listed, otherwise Send/List buttons
                  if (nft.isListed)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _C.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _C.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.storefront_rounded, color: _C.primary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Listed on Marketplace'
                            '${nft.formattedListingPrice != null ? ' — ${nft.formattedListingPrice}' : ''}',
                            style: TextStyle(
                              color: _C.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => context.push('/nft/send', extra: nft),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _C.primary,
                              foregroundColor: const Color(0xFF000000),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Send',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.push('/marketplace/create'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _C.primary,
                              side: BorderSide(color: _C.primary.withValues(alpha: 0.3)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'List for Sale',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _infoRow('Mint', _shortenAddress(nft.mint)),
          if (nft.collectionMint != null)
            _infoRow('Collection', _shortenAddress(nft.collectionMint!)),
          _infoRow('Standard', _tokenStandardLabel(nft.tokenStandard)),
          if (nft.isCompressed) _infoRow('Type', 'Compressed (cNFT)'),
          if (nft.animationUrl != null)
            _infoRow('Media', 'Video/3D — view coming soon'),
          if (nft.externalUrl != null) _infoRow('Link', nft.externalUrl!),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _C.textTertiary, fontSize: 13)),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: _C.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _shortenAddress(String address) {
    if (address.length <= 12) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 6)}';
  }

  String _tokenStandardLabel(NftTokenStandard std) {
    return switch (std) {
      NftTokenStandard.nonFungible => 'Non-Fungible',
      NftTokenStandard.nonFungibleEdition => 'Edition',
      NftTokenStandard.programmableNonFungible => 'Programmable (pNFT)',
      NftTokenStandard.programmableNonFungibleEdition => 'Programmable Edition',
      NftTokenStandard.fungibleAsset => 'Semi-Fungible',
      NftTokenStandard.core => 'Core NFT',
      NftTokenStandard.unknown => 'Unknown',
    };
  }
}
