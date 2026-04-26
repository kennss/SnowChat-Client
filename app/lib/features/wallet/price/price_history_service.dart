/// @file        price_history_service.dart
/// @description Price time-series service — calls server proxy
///              (/api/v2/price/history) + in-memory cache + dedupe.
///              Phase 6.1.2 §3.3: fetch dedupe + cancelOthers.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - PriceHistoryService.fetch(mint, range): fetch time series (cache hit or server call)
///  - PriceHistoryService.cancelOthers(mint, keepRange): cancel prior fetches when range switches
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import 'coin_id_resolver.dart';
import 'price_history_models.dart';

/// Composite (mint, range) key.
class _Key {
  const _Key(this.mint, this.range);
  final String mint;
  final PriceRange range;

  @override
  bool operator ==(Object other) =>
      other is _Key && other.mint == mint && other.range == range;

  @override
  int get hashCode => Object.hash(mint, range);
}

class PriceHistoryService {
  PriceHistoryService({
    required this.coinIdResolver,
    required this.apiClient,
  });

  final CoinIdResolver coinIdResolver;
  final ApiClient apiClient;

  final _cache = <_Key, PriceHistory>{};
  final _pending = <_Key, Future<PriceHistory?>>{};

  /// Fetch the time-series. Cache hit → return immediately; miss → server call.
  Future<PriceHistory?> fetch({
    required String mint,
    required PriceRange range,
  }) async {
    final key = _Key(mint, range);

    // Cache hit (within TTL)
    final cached = _cache[key];
    if (cached != null && !cached.isExpired(range.ttl)) return cached;

    // Dedupe in-flight identical fetches
    final pending = _pending[key];
    if (pending != null) return pending;

    // New fetch
    final future = _doFetch(key);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  Future<PriceHistory?> _doFetch(_Key key) async {
    // mint → coin_id
    final coinId = await coinIdResolver.resolve(key.mint);
    if (coinId == null) {
      debugPrint('[PriceHistory] No coin_id for ${key.mint}');
      return null;
    }

    try {
      final response = await apiClient.get(
        '/price/history',
        queryParameters: {
          'coin_id': coinId,
          'range': key.range.apiValue,
        },
      );

      if (response.statusCode != 200 || response.data == null) return null;

      final data = response.data as Map<String, dynamic>;
      final rawPoints = data['points'] as List? ?? [];
      final points = rawPoints.map<PricePoint>((p) {
        final m = p as Map<String, dynamic>;
        return PricePoint(
          DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt() * 1000),
          (m['p'] as num).toDouble(),
        );
      }).toList();

      final history = PriceHistory(
        coinId: coinId,
        range: key.range,
        points: points,
        changePercent: (data['change_percent'] as num?)?.toDouble() ?? 0,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          ((data['fetched_at'] as num?) ?? 0).toInt() * 1000,
        ),
        isStale: data['_stale'] == true,
      );

      _cache[key] = history;
      debugPrint('[PriceHistory] ${key.mint}/${key.range.name}: ${points.length} points');
      return history;
    } on DioException catch (e) {
      debugPrint('[PriceHistory] fetch failed: $e');
      // stale cache fallback
      return _cache[key];
    }
  }

  /// On range switch, prior in-flight fetches complete naturally but their
  /// results are ignored.
  /// (Handled via simple pending removal rather than http.Client.close.)
  void cancelOthers(String mint, PriceRange keepRange) {
    _pending.removeWhere((key, _) =>
        key.mint == mint && key.range != keepRange);
  }
}
