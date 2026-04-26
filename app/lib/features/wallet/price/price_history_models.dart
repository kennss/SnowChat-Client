/// @file        price_history_models.dart
/// @description Price time-series models — PriceRange, PricePoint,
///              PriceHistory. Phase 6.1.2: maps the CoinGecko market_chart
///              server-proxy response.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - PriceRange: range enum (d1/d7/d30/y1/all)
///  - PricePoint: timestamp + USD price
///  - PriceHistory: series + change ratio + cache metadata
library;

/// Price-chart range. Maps to CoinGecko market_chart days.
enum PriceRange {
  d1('24H', 1, Duration(seconds: 60)),
  d7('7D', 7, Duration(seconds: 300)),
  d30('30D', 30, Duration(seconds: 300)),
  y1('1Y', 365, Duration(hours: 1));

  const PriceRange(this.label, this.days, this.ttl);

  /// UI display label.
  final String label;

  /// CoinGecko `days` parameter (-1 = 'max').
  final int days;

  /// Client-memory cache TTL.
  final Duration ttl;

  /// Server API `range` parameter.
  String get apiValue => name; // d1, d7, d30, y1, all
}

/// Single time-series point — display-only double (no BigInt arithmetic).
class PricePoint {
  const PricePoint(this.time, this.priceUsd);

  /// UTC time.
  final DateTime time;

  /// USD price (display-only double).
  final double priceUsd;
}

/// Time-series price data.
class PriceHistory {
  const PriceHistory({
    required this.coinId,
    required this.range,
    required this.points,
    required this.changePercent,
    required this.fetchedAt,
    this.isStale = false,
  });

  final String coinId;
  final PriceRange range;
  final List<PricePoint> points;

  /// (last - first) / first * 100. Display-only double.
  final double changePercent;

  /// Server fetch time (Unix seconds).
  final DateTime fetchedAt;

  /// Whether this is a Redis stale fallback.
  final bool isStale;

  /// Whether the cache has expired.
  bool isExpired(Duration ttl) =>
      DateTime.now().difference(fetchedAt) > ttl;
}
