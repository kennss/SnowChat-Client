/// @file        coin_id_resolver.dart
/// @description mint → CoinGecko coin_id mapping. Static hot map first, lazy
///              fetch via server proxy on miss.
///              Phase 6.1.2 §2.4: no secure_storage, lazy fetch, 7-day TTL.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - CoinIdResolver.resolve(mint): mint → coin_id (null = chart unsupported)
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';

/// Static hot map — major Solana tokens. Zero server calls.
const _hotMap = <String, String>{
  'SOL': 'solana',
  'So11111111111111111111111111111111111111112': 'solana',
  'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v': 'usd-coin',
  'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB': 'tether',
  'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263': 'bonk',
  'JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN': 'jupiter-exchange-solana',
};

class CoinIdResolver {
  CoinIdResolver({required this.apiClient});

  final ApiClient apiClient;

  /// Cache of the full mapping fetched from the server.
  Map<String, String>? _serverMap;
  DateTime? _serverMapFetchedAt;
  static const _serverMapTtl = Duration(days: 7);

  /// mint → coin_id. null means chart unsupported.
  Future<String?> resolve(String mint) async {
    // 1st: static hot map
    final hot = _hotMap[mint];
    if (hot != null) return hot;

    // 2nd: server cache
    if (_serverMap != null &&
        _serverMapFetchedAt != null &&
        DateTime.now().difference(_serverMapFetchedAt!) < _serverMapTtl) {
      return _serverMap![mint];
    }

    // 3rd: lazy fetch from server
    await _fetchServerMap();
    return _serverMap?[mint];
  }

  Future<void> _fetchServerMap() async {
    try {
      final response = await apiClient.get('/price/coin-map');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final map = data['map'] as Map<String, dynamic>? ?? {};
        _serverMap = map.map((k, v) => MapEntry(k, v as String));
        _serverMapFetchedAt = DateTime.now();
        debugPrint('[CoinIdResolver] loaded ${_serverMap!.length} mappings');
      }
    } on DioException catch (e) {
      debugPrint('[CoinIdResolver] fetch failed: $e');
    }
  }
}
