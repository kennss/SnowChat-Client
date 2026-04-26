/// @file        balance_card.dart
/// @description Large balance card widget showing total balance + 24-hour
///              change ratio (real data, shimmer loading).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - BalanceCard: ConsumerWidget showing USD balance + 24h change (uses real provider data)

/// Phantom-style large balance card with USD value and 24h change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wallet_provider.dart';
import '../screens/wallet_home_screen.dart' show ShimmerBlock;

/// SnowColors reference (defined by Agent 3; inlined as fallback).
abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const error = Color(0xFFFF4444);
}

/// Large centered balance display, Phantom-style.
class BalanceCard extends ConsumerWidget {
  const BalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletState = ref.watch(walletProvider);
    final balance = walletState.balance;
    final isLoading = walletState.isLoading && balance == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      color: _C.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total USD value -- large, bold. Show shimmer while loading.
          if (isLoading)
            const ShimmerBlock(width: 180, height: 42)
          else
            Text(
              balance?.formattedUsd ?? '\$0.00',
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w700,
                color: _C.textPrimary,
                letterSpacing: -1,
              ),
            ),
          const SizedBox(height: 6),

          // 24h change.
          if (isLoading)
            const ShimmerBlock(width: 80, height: 16)
          else if (balance != null)
            Text(
              balance.formattedChange,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: balance.isPositiveChange ? _C.primary : _C.error,
              ),
            )
          else
            const Text(
              '--',
              style: TextStyle(fontSize: 15, color: _C.textSecondary),
            ),
        ],
      ),
    );
  }
}
