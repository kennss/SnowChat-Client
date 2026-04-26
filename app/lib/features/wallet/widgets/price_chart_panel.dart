/// @file        price_chart_panel.dart
/// @description Price chart panel — fl_chart LineChart + range toggle +
///              change-ratio header. Phase 6.1.2 §3.5. Phantom style (grid
///              off, filled area, crosshair).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - PriceChartPanel: price-chart widget embedded in the token detail screen
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../price/price_history_models.dart';
import '../providers/price_history_provider.dart';
import 'price_range_selector.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const error = Color(0xFFFF4444);
  static const surface = Color(0xFF111111);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
}

class PriceChartPanel extends ConsumerStatefulWidget {
  const PriceChartPanel({super.key, required this.mint});
  final String mint;

  @override
  ConsumerState<PriceChartPanel> createState() => _PriceChartPanelState();
}

class _PriceChartPanelState extends ConsumerState<PriceChartPanel> {
  PriceRange _range = PriceRange.d1;

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(
      priceHistoryProvider((mint: widget.mint, range: _range)),
    );

    return Column(
      children: [
        // Header: change ratio
        asyncData.when(
          data: (h) => _ChangeHeader(history: h),
          loading: () => const SizedBox(height: 24),
          error: (_, __) => const SizedBox(height: 24),
        ),
        const SizedBox(height: 8),

        // Chart
        SizedBox(
          height: 200,
          child: asyncData.when(
            loading: () => Container(
              decoration: BoxDecoration(
                color: _C.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: _C.primary,
                  strokeWidth: 2,
                ),
              ),
            ),
            error: (_, __) => const _Unavailable(),
            data: (h) {
              if (h == null || h.points.length < 2) return const _Unavailable();
              return _Chart(history: h);
            },
          ),
        ),
        const SizedBox(height: 12),

        // Range selector
        PriceRangeSelector(
          current: _range,
          onChanged: (r) {
            ref.read(priceHistoryServiceProvider).cancelOthers(widget.mint, r);
            setState(() => _range = r);
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Change-ratio header
// ---------------------------------------------------------------------------

class _ChangeHeader extends StatelessWidget {
  const _ChangeHeader({required this.history});
  final PriceHistory? history;

  @override
  Widget build(BuildContext context) {
    if (history == null || history!.points.isEmpty) {
      return const SizedBox(height: 24);
    }
    final pct = history!.changePercent;
    final isPositive = pct >= 0;
    final color = isPositive ? _C.primary : _C.error;
    final sign = isPositive ? '+' : '';
    final lastPrice = history!.points.last.priceUsd;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '\$${lastPrice.toStringAsFixed(lastPrice < 1 ? 6 : 2)}',
          style: const TextStyle(
            color: _C.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$sign${pct.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (history!.isStale) ...[
          const SizedBox(width: 6),
          const Tooltip(
            message: 'Stale data — update pending',
            child: Icon(Icons.access_time, size: 14, color: _C.textSecondary),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// fl_chart LineChart
// ---------------------------------------------------------------------------

class _Chart extends StatelessWidget {
  const _Chart({required this.history});
  final PriceHistory history;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (final p in history.points)
        FlSpot(
          p.time.millisecondsSinceEpoch.toDouble(),
          p.priceUsd,
        ),
    ];

    final isPositive = history.changePercent >= 0;
    final lineColor = isPositive ? _C.primary : _C.error;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.2,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    lineColor.withValues(alpha: 0.25),
                    lineColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => [
                for (final s in touchedSpots)
                  LineTooltipItem(
                    '\$${s.y.toStringAsFixed(s.y < 1 ? 6 : 2)}',
                    const TextStyle(
                      color: _C.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            getTouchedSpotIndicator: (barData, indexes) => indexes
                .map(
                  (i) => TouchedSpotIndicatorData(
                    FlLine(
                      color: lineColor.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                    FlDotData(show: false),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unsupported indicator
// ---------------------------------------------------------------------------

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          'Price chart not available',
          style: TextStyle(color: _C.textSecondary, fontSize: 13),
        ),
      ),
    );
  }
}
