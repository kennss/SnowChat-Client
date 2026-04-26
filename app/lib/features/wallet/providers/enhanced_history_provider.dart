/// @file        enhanced_history_provider.dart
/// @description Helius Enhanced Transaction History Provider.
///              Goes through the server proxy `/wallet/enhanced-history` to
///              fetch Helius-classified results, with automatic fallback to
///              the existing transactionHistoryProvider when Helius is not
///              configured.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - enhancedHistoryProvider: Enhanced Transaction history FutureProvider
///  - enhancedHistoryAvailableProvider: StateProvider for Helius availability
///  - enhancedTxDetailProvider: per-signature FutureProvider.family
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../transaction/enhanced_transaction.dart';
import '../wallet_provider.dart';

/// Whether Helius Enhanced History is available.
/// On the first call, 503(HELIUS_NOT_CONFIGURED) flips this to false → UI falls back.
final enhancedHistoryAvailableProvider = StateProvider<bool>((ref) => true);

/// Helius Enhanced Transaction History.
///
/// - Calls server `/wallet/enhanced-history?address=...&limit=30`
/// - Server Redis cache 30s
/// - When Helius is not configured (503), sets `enhancedHistoryAvailableProvider`
///   to false → wallet_home_screen falls back to the existing transactionHistoryProvider.
final enhancedHistoryProvider =
    FutureProvider.autoDispose<List<EnhancedTransaction>>((ref) async {
  final pubKey = ref.watch(walletProvider.select((s) => s.publicKey));
  if (pubKey == null || pubKey.isEmpty) return [];

  final apiClient = ref.read(apiClientProvider);

  try {
    final resp = await apiClient.get(
      '/wallet/enhanced-history',
      queryParameters: {'address': pubKey, 'limit': 30},
    );

    final data = resp.data;
    if (data is List) {
      return data
          .map((e) =>
              EnhancedTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  } on DioException catch (e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 503) {
      // Helius API key not configured → switch to fallback mode
      ref.read(enhancedHistoryAvailableProvider.notifier).state = false;
      debugPrint('[EnhancedHistory] Helius not configured — falling back');
      return [];
    }
    debugPrint('[EnhancedHistory] API error ($statusCode): $e');
    rethrow;
  } catch (e) {
    debugPrint('[EnhancedHistory] Unexpected error: $e');
    rethrow;
  }
});

/// Look up a single Enhanced Transaction (search cached history by signature).
/// Returns null if not in history (no server re-fetch right now — cache-hit only).
final enhancedTxDetailProvider = FutureProvider.autoDispose
    .family<EnhancedTransaction?, String>((ref, signature) async {
  // Search the already-loaded history
  final history = ref.watch(enhancedHistoryProvider);
  return history.when(
    data: (list) {
      try {
        return list.firstWhere((tx) => tx.signature == signature);
      } catch (_) {
        return null;
      }
    },
    loading: () => null,
    error: (_, _) => null,
  );
});
