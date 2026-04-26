/// @file        token_detail_screen.dart
/// @description Per-token detail screen (real balance data, price chart
///              placeholder, send/receive actions).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - TokenDetailScreen: screen widget that displays per-token details

/// Token detail screen showing balance, price chart placeholder, and actions.
library;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/wallet_models.dart';
import '../widgets/price_chart_panel.dart';

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
}

class TokenDetailScreen extends StatelessWidget {
  const TokenDetailScreen({super.key, required this.token});

  final TokenInfo token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          token.name,
          style: const TextStyle(color: _C.textPrimary, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // Token icon.
              _buildIcon(),
              const SizedBox(height: 16),

              // Balance.
              Text(
                '${token.shortBalance} ${token.symbol}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: _C.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                token.usdValueCents > BigInt.zero ? token.formattedUsd : '--',
                style: const TextStyle(fontSize: 16, color: _C.textSecondary),
              ),
              const SizedBox(height: 32),

              // Price chart (Phase 6.1.2).
              PriceChartPanel(mint: token.mint),
              const SizedBox(height: 24),

              // Info rows.
              _infoRow('Symbol', token.symbol),
              _infoRow('Decimals', '${token.decimals}'),
              _infoRow('Mint', _shortenMint(token.mint)),
              if (token.changePercent24h != 0)
                _infoRow(
                  '24h Change',
                  '${token.changePercent24h >= 0 ? '+' : ''}${(token.changePercent24h / 100).toStringAsFixed(2)}%',
                ),
              const SizedBox(height: 32),

              // Action buttons.
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.push('/wallet/send', extra: token),
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
                      onPressed: () => context.push('/wallet/receive'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.primary,
                        side: BorderSide(color: _C.primary.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Receive',
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
    );
  }

  Widget _buildIcon() {
    if (token.logoUrl != null && token.logoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: token.logoUrl!,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          placeholder: (_, __) => _iconPlaceholder(),
          errorWidget: (_, __, ___) => _iconPlaceholder(),
        ),
      );
    }
    return _iconPlaceholder();
  }

  Widget _iconPlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: _C.surface,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        token.symbol.isNotEmpty ? token.symbol[0] : '?',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: _C.primary,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _C.textTertiary, fontSize: 14)),
          Text(value, style: const TextStyle(color: _C.textPrimary, fontSize: 14)),
        ],
      ),
    );
  }

  String _shortenMint(String mint) {
    if (mint.length <= 12) return mint;
    return '${mint.substring(0, 6)}...${mint.substring(mint.length - 6)}';
  }
}
