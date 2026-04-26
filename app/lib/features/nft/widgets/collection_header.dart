/// @file        collection_header.dart
/// @description Collection-group header widget for the NFT gallery (icon, name, NFT count).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - CollectionHeader: header widget showing collection icon, name, and NFT count

/// Collection group header for the NFT gallery.
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../shared/models/nft_models.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
}

/// A header row showing the collection icon, name, and NFT count.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.collection,
    this.onTap,
  });

  final NFTCollection collection;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Row(
          children: [
            // Collection icon.
            ClipOval(
              child: collection.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: collection.imageUrl!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 8),

            // Name.
            Expanded(
              child: Text(
                collection.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _C.textPrimary,
                ),
              ),
            ),

            // Count.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${collection.count}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _C.textSecondary,
                ),
              ),
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: _C.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: _C.surface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        collection.name.isNotEmpty ? collection.name[0] : '?',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _C.primary,
        ),
      ),
    );
  }
}
