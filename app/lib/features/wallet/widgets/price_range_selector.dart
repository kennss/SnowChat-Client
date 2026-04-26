/// @file        price_range_selector.dart
/// @description Price-chart range selector — segmented d1/d7/d30/y1/all.
///              Phase 6.1.2 §3.1.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - PriceRangeSelector: range-toggle segmented control
library;

import 'package:flutter/material.dart';

import '../price/price_history_models.dart';

class PriceRangeSelector extends StatelessWidget {
  const PriceRangeSelector({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final PriceRange current;
  final ValueChanged<PriceRange> onChanged;

  static const _bg = Color(0xFF111111);
  static const _selected = Color(0xFF00F782);
  static const _text = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: PriceRange.values.map((r) {
        final isSelected = r == current;
        return GestureDetector(
          onTap: () => onChanged(r),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? _selected.withValues(alpha: 0.15) : _bg,
              borderRadius: BorderRadius.circular(8),
              border: isSelected
                  ? Border.all(color: _selected.withValues(alpha: 0.4))
                  : null,
            ),
            child: Text(
              r.label,
              style: TextStyle(
                color: isSelected ? _selected : _text,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
