/// @file        wallet_selector_chip.dart
/// @description Multi-Wallet active-wallet entry — small chip placed in the
///              wallet_home_screen header. Label + dropdown arrow. Tap
///              opens the [WalletSelectorSheet] bottom sheet.
///              Multi-Wallet-Design-FINAL.md §4.1.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - WalletSelectorChip: active-wallet label + dropdown chip

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants/colors.dart';
import '../providers/wallet_list_provider.dart';
import 'wallet_selector_sheet.dart';

class WalletSelectorChip extends ConsumerWidget {
  const WalletSelectorChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(activeWalletEntryProvider);
    if (entry == null) {
      // bootstrap incomplete / no index — hide the entry point
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () => showWalletSelectorSheet(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: SnowColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SnowColors.surfaceLight, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 14,
              color: SnowColors.textSecondary,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                entry.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: SnowColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
