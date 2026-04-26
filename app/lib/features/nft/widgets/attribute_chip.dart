/// @file        attribute_chip.dart
/// @description Widget that displays an NFT attribute (trait) as a chip.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - AttributeChip: widget showing an NFT attribute name and value as a compact chip

/// Attribute / trait chip for NFT detail screen.
library;

import 'package:flutter/material.dart';

import '../../../shared/models/nft_models.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const primaryBg = Color(0xFF0A2A1A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textTertiary = Color(0xFF5C5C5C);
}

/// Displays a single NFT attribute as a compact chip.
class AttributeChip extends StatelessWidget {
  const AttributeChip({
    super.key,
    required this.attribute,
  });

  final NFTAttribute attribute;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _C.primaryBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _C.primary.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            attribute.traitType.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _C.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            attribute.value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _C.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
