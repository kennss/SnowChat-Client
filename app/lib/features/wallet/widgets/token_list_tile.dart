/// @file        token_list_tile.dart
/// @description Token list-item widget (icon, name, balance, USD value).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - TokenListTile: list-tile widget that displays token info in a card form

/// Phantom-style token list tile showing icon, name, balance, and USD value.
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../shared/models/wallet_models.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const divider = Color(0xFF1E1E1E);
}

/// A card-style token list item.
class TokenListTile extends StatelessWidget {
  const TokenListTile({
    super.key,
    required this.token,
    this.onTap,
  });

  final TokenInfo token;
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
            // Token icon.
            _TokenIcon(logoUrl: token.logoUrl, symbol: token.symbol),
            const SizedBox(width: 12),

            // Name + symbol.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    token.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _C.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    token.symbol,
                    style: const TextStyle(
                      fontSize: 13,
                      color: _C.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // Balance + USD value.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${token.shortBalance} ${token.symbol}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _C.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  token.usdValueCents > BigInt.zero
                      ? token.formattedUsd
                      : '--',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _C.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenIcon extends StatelessWidget {
  const _TokenIcon({required this.logoUrl, required this.symbol});

  final String? logoUrl;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: logoUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, __) => _placeholder(),
          errorWidget: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: _C.surface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        symbol.isNotEmpty ? symbol[0] : '?',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: _C.primary,
        ),
      ),
    );
  }
}
