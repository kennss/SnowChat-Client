/// @file        price_service.dart
/// @description Token price service — Jupiter Price API (primary) + CoinGecko (fallback)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-03
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - PriceService: token price class
///  - getTokenPrices(): fetch USD prices for multiple tokens
///  - getSolPrice(): fetch SOL USD price
///  - priceServiceProvider: Riverpod Provider
///  - solPriceProvider: SOL price FutureProvider

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show apiClientProvider;
import 'package:http/http.dart' as http;

/// SOL native mint address (used by Jupiter Price API).
const _solMint = 'So11111111111111111111111111111111';

/// Token price service using Jupiter Price API v2.
/// Devnet fallback: read Mainnet price from the CoinGecko server proxy.
///
/// Prices are double (display only) — NEVER used for amount arithmetic.
/// All amount calculations use BigInt lamports exclusively.
class PriceService {
  PriceService({http.Client? httpClient, this.apiClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Server API client — for the CoinGecko price fallback on Devnet.
  final dynamic apiClient;

  /// Cache: mint address → USD price. Expires after [_cacheTtl].
  final Map<String, _CachedPrice> _cache = {};
  static const _cacheTtl = Duration(seconds: 30);

  /// Get USD prices for multiple token mints.
  ///
  /// Returns a map of mint address → USD price (double, display only).
  /// Uses Jupiter Price API v2 as primary, falls back to cached values.
  Future<Map<String, double>> getTokenPrices(List<String> mintAddresses) async {
    if (mintAddresses.isEmpty) return {};

    // Check cache first
    final now = DateTime.now();
    final uncached = <String>[];
    final result = <String, double>{};

    for (final mint in mintAddresses) {
      final cached = _cache[mint];
      if (cached != null && now.difference(cached.fetchedAt) < _cacheTtl) {
        result[mint] = cached.priceUsd;
      } else {
        uncached.add(mint);
      }
    }

    if (uncached.isEmpty) return result;

    // Fetch from Jupiter
    try {
      final ids = uncached.join(',');
      final response = await _http
          .get(Uri.parse('https://api.jup.ag/price/v2?ids=$ids'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>? ?? {};

        for (final mint in uncached) {
          final entry = data[mint] as Map<String, dynamic>?;
          final price = double.tryParse(
                  entry?['price']?.toString() ?? '') ??
              0.0;
          result[mint] = price;
          _cache[mint] = _CachedPrice(price, now);
        }
      }
    } catch (e) {
      debugPrint('[PriceService] Jupiter fetch failed: $e');
      // Return cached or zero for uncached
      for (final mint in uncached) {
        result[mint] = _cache[mint]?.priceUsd ?? 0.0;
      }
    }

    // Devnet fallback: when Jupiter returns 0 for SOL, read Mainnet price from CoinGecko server proxy
    final solPrice = result[_solMint] ?? 0.0;
    if (solPrice == 0.0 && apiClient != null) {
      try {
        final cgPrice = await _fetchCoinGeckoPrice('solana');
        if (cgPrice > 0) {
          result[_solMint] = cgPrice;
          _cache[_solMint] = _CachedPrice(cgPrice, DateTime.now());
          debugPrint('[PriceService] CoinGecko fallback SOL: \$$cgPrice');
        }
      } catch (e) {
        debugPrint('[PriceService] CoinGecko fallback failed: $e');
      }
    }

    return result;
  }

  /// Fetch the last price point from the CoinGecko server proxy (Devnet fallback).
  Future<double> _fetchCoinGeckoPrice(String coinId) async {
    if (apiClient == null) return 0.0;
    try {
      final response = await apiClient.get(
        '/price/history',
        queryParameters: {'coin_id': coinId, 'range': 'd1'},
      );
      if (response.statusCode == 200 && response.data != null) {
        final points = response.data['points'] as List? ?? [];
        if (points.isNotEmpty) {
          final last = points.last as Map<String, dynamic>;
          return (last['p'] as num?)?.toDouble() ?? 0.0;
        }
      }
    } catch (_) {}
    return 0.0;
  }

  /// Get SOL price in USD.
  Future<double> getSolPrice() async {
    final prices = await getTokenPrices([_solMint]);
    return prices[_solMint] ?? 0.0;
  }

  /// Clear price cache.
  void clearCache() => _cache.clear();
}

class _CachedPrice {
  final double priceUsd;
  final DateTime fetchedAt;
  _CachedPrice(this.priceUsd, this.fetchedAt);
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// PriceService singleton provider.
final priceServiceProvider = Provider<PriceService>((ref) {
  // Inject apiClient — for the CoinGecko price fallback on Devnet
  dynamic apiClient;
  try {
    apiClient = ref.read(apiClientProvider);
  } catch (_) {}
  return PriceService(apiClient: apiClient);
});

/// Current SOL price in USD (auto-refreshes every 30s when watched).
final solPriceProvider = FutureProvider<double>((ref) async {
  final service = ref.read(priceServiceProvider);
  return service.getSolPrice();
});
