/// @file        nft_card.dart
/// @description NFT grid card widget (IPFS image fallback, name, price display).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - NFTCard: card widget that shows the NFT image and name in a 2-column grid

/// NFT card for grid display (image + name).
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../shared/models/nft_models.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const surfaceLight = Color(0xFF242424);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
}

/// A card displaying an NFT image and name, for use in a 2-column grid.
class NFTCard extends StatelessWidget {
  const NFTCard({
    super.key,
    required this.nft,
    this.onTap,
    this.showPrice = false,
  });

  final NFTAsset nft;
  final VoidCallback? onTap;
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image.
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: nft.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: _C.surfaceLight,
                    child: const Center(
                      child: Icon(Icons.image_outlined, color: _C.primary, size: 32),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: _C.surfaceLight,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, color: _C.textSecondary, size: 32),
                    ),
                  ),
                ),
              ),
            ),

            // Name + optional price.
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nft.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showPrice && nft.formattedListingPrice != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      nft.formattedListingPrice!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _C.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else if (nft.collectionName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      nft.collectionName!,
                      style: const TextStyle(fontSize: 11, color: _C.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
