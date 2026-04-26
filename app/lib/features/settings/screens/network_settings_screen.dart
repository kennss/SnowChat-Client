/// @file        network_settings_screen.dart
/// @description Solana network settings screen — Devnet/Mainnet-Beta toggle, network warning banner, status badge.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - NetworkSettingsScreen: Solana network-selection screen (ConsumerWidget)
///  - _NetworkBadge: widget that shows the current network status as a colored badge

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../wallet/wallet_provider.dart';

class NetworkSettingsScreen extends ConsumerWidget {
  const NetworkSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(solanaNetworkProvider);
    final isDevnet = network == SolanaNetwork.devnet;

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        backgroundColor: SnowColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SnowColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Network',
          style: TextStyle(
            color: SnowColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(SnowSizes.lg),
        children: [
          // Current network badge.
          Center(child: NetworkBadge(network: network)),
          const SizedBox(height: SnowSizes.xl),

          // Mainnet warning banner.
          if (!isDevnet)
            Container(
              padding: const EdgeInsets.all(SnowSizes.md),
              margin: const EdgeInsets.only(bottom: SnowSizes.lg),
              decoration: BoxDecoration(
                color: SnowColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SnowColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: SnowColors.warning,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Real funds at risk. Transactions on Mainnet-Beta use real SOL and cannot be reversed.',
                      style: TextStyle(
                        color: SnowColors.warning,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Network selection.
          _buildSectionHeader('SELECT NETWORK'),
          const SizedBox(height: SnowSizes.sm),

          _NetworkRadioTile(
            title: 'Devnet',
            subtitle: 'Test network with free airdrop SOL',
            color: SnowColors.success,
            isSelected: isDevnet,
            onTap: () => _switchNetwork(ref, SolanaNetwork.devnet),
          ),
          const SizedBox(height: SnowSizes.sm),
          _NetworkRadioTile(
            title: 'Mainnet-Beta',
            subtitle: 'Production network with real assets',
            color: SnowColors.warning,
            isSelected: !isDevnet,
            onTap: () => _showMainnetConfirm(context, ref),
          ),

          const SizedBox(height: SnowSizes.xl),

          // Info section.
          _buildSectionHeader('INFO'),
          const SizedBox(height: SnowSizes.sm),
          Container(
            padding: const EdgeInsets.all(SnowSizes.md),
            decoration: BoxDecoration(
              color: SnowColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Switching networks will refresh your wallet balance and reset cached data. '
                  'Your wallet address remains the same across networks.',
                  style: TextStyle(
                    color: SnowColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _switchNetwork(WidgetRef ref, SolanaNetwork network) {
    ref.read(solanaNetworkProvider.notifier).state = network;
    // Refresh wallet data for the new network.
    ref.read(walletProvider.notifier).refreshBalance();
  }

  void _showMainnetConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Switch to Mainnet-Beta?',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'You are about to switch to the production Solana network. '
          'All transactions will use real SOL and are irreversible.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _switchNetwork(ref, SolanaNetwork.mainnet);
            },
            child: const Text(
              'Switch',
              style: TextStyle(color: SnowColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _NetworkRadioTile extends StatelessWidget {
  const _NetworkRadioTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(SnowSizes.md),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : SnowColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.4)
                : SnowColors.divider,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : SnowColors.textTertiary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? color : SnowColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 12,
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

/// Reusable network badge widget.
class NetworkBadge extends StatelessWidget {
  const NetworkBadge({super.key, required this.network, this.compact = false});

  final SolanaNetwork network;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDevnet = network == SolanaNetwork.devnet;
    final color = isDevnet ? SnowColors.success : SnowColors.warning;
    final label = isDevnet ? 'Devnet' : 'Mainnet';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 14,
        vertical: compact ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 6 : 8,
            height: compact ? 6 : 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          SizedBox(width: compact ? 5 : 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: compact ? 11 : 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
