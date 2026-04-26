/// @file        hidden_wallets_screen.dart
/// @description Multi-Wallet Phase A-3 (2026-04-26) — hidden derived
///              sub-wallet list + unhide entry point. The only path for the
///              user to make a wallet visible again after the Hide action
///              in selector_sheet.
///              Imported wallets are permanently deleted (not hidden), so
///              they are out of scope for this screen.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-26
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - HiddenWalletsScreen: hidden-wallet list + unhide button

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/toast.dart';
import '../../wallet/models/wallet_account_model.dart';
import '../../wallet/providers/wallet_list_provider.dart';
import '../../wallet/wallet_provider.dart';

class HiddenWalletsScreen extends ConsumerWidget {
  const HiddenWalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexAsync = ref.watch(walletIndexProvider);
    final hidden = indexAsync.valueOrNull?.derivedEntries
            .where((e) => e.hidden)
            .toList() ??
        const <WalletEntry>[];

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        backgroundColor: SnowColors.background,
        elevation: 0,
        title: const Text(
          'Hidden Accounts',
          style: TextStyle(
            color: SnowColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Derived sub-wallets you hid from the wallet selector. '
                'They remain on chain — unhide to make them visible '
                'again. Imported wallets cannot be hidden (they are '
                'removed permanently).',
                style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: SnowSizes.lg),
              Expanded(
                child: hidden.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        itemCount: hidden.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: SnowSizes.sm),
                        itemBuilder: (_, i) => _HiddenRow(entry: hidden[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.visibility_off_rounded,
            size: 56,
            color: SnowColors.textTertiary,
          ),
          SizedBox(height: SnowSizes.md),
          Text(
            'No hidden accounts',
            style: TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Derived sub-wallets you hide will appear here.',
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _HiddenRow extends ConsumerWidget {
  const _HiddenRow({required this.entry});

  final WalletEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortAddr = entry.address.length > 12
        ? '${entry.address.substring(0, 6)}…${entry.address.substring(entry.address.length - 4)}'
        : entry.address;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SnowColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: SnowColors.primaryDim.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              size: 18,
              color: SnowColors.primaryDim,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(
                    color: SnowColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  shortAddr,
                  style: const TextStyle(
                    color: SnowColors.textTertiary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _unhide(context, ref),
            icon: const Icon(
              Icons.visibility_rounded,
              size: 16,
              color: SnowColors.primary,
            ),
            label: const Text(
              'Unhide',
              style: TextStyle(color: SnowColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _unhide(BuildContext context, WidgetRef ref) async {
    final idx = entry.derivationAccountIndex;
    if (idx == null) {
      // case blocked by assert — safety net
      SnowToast.show(
        context,
        message: 'Internal error: missing derivation index',
        type: ToastType.error,
      );
      return;
    }
    try {
      await ref.read(walletProvider.notifier).unhideWallet(idx);
      if (context.mounted) {
        SnowToast.show(
          context,
          message: '${entry.label} restored',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        SnowToast.show(
          context,
          message: 'Failed to unhide: $e',
          type: ToastType.error,
        );
      }
    }
  }
}
