/// @file        price_history_provider.dart
/// @description Price time-series Riverpod Provider —
///              FutureProvider.family(mint, range). Phase 6.1.2 §3.4.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - priceHistoryServiceProvider: PriceHistoryService instance
///  - coinIdResolverProvider: CoinIdResolver instance
///  - priceHistoryProvider: FutureProvider.family(mint, range) → PriceHistory?
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show apiClientProvider;
import '../price/coin_id_resolver.dart';
import '../price/price_history_models.dart';
import '../price/price_history_service.dart';

final coinIdResolverProvider = Provider<CoinIdResolver>((ref) {
  return CoinIdResolver(apiClient: ref.read(apiClientProvider));
});

final priceHistoryServiceProvider = Provider<PriceHistoryService>((ref) {
  return PriceHistoryService(
    coinIdResolver: ref.read(coinIdResolverProvider),
    apiClient: ref.read(apiClientProvider),
  );
});

/// Fetch the price time-series by (mint, range) pair.
final priceHistoryProvider = FutureProvider.autoDispose
    .family<PriceHistory?, ({String mint, PriceRange range})>((ref, key) async {
  return ref.read(priceHistoryServiceProvider).fetch(
        mint: key.mint,
        range: key.range,
      );
});
