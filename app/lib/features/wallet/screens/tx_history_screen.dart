/// @file        tx_history_screen.dart
/// @description Full transaction history screen (real RPC data, shimmer
///              loading, error retry).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - TxHistoryScreen: screen widget showing real transaction history as a list

/// Full transaction history screen with real RPC data.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../wallet_provider.dart';
import '../widgets/tx_list_tile.dart';
import 'wallet_home_screen.dart' show ShimmerBlock;

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
}

class TxHistoryScreen extends ConsumerWidget {
  const TxHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txHistory = ref.watch(transactionHistoryProvider);

    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Transaction History',
          style: TextStyle(color: _C.textPrimary, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: txHistory.when(
        loading: () => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: 6,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ShimmerBlock(width: 36, height: 36),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBlock(width: 120, height: 14),
                      SizedBox(height: 6),
                      ShimmerBlock(width: 80, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $e', style: const TextStyle(color: _C.textSecondary)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => ref.invalidate(transactionHistoryProvider),
                child: const Text('Retry', style: TextStyle(color: _C.primary)),
              ),
            ],
          ),
        ),
        data: (transactions) {
          if (transactions.isEmpty) {
            return const Center(
              child: Text(
                'No transactions yet',
                style: TextStyle(color: _C.textSecondary, fontSize: 16),
              ),
            );
          }
          return ListView.builder(
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final tx = transactions[index];
              return TxListTile(
                tx: tx,
                onTap: () {
                  final network = ref.read(solanaNetworkProvider);
                  final url = getSolanaExplorerUrl(tx.signature, network);
                  // TODO: Open URL with url_launcher.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Explorer: $url'),
                      backgroundColor: const Color(0xFF111111),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
