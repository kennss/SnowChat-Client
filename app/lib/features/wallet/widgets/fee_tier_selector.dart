/// @file        fee_tier_selector.dart
/// @description Priority-fee toggle widget with 3 tiers: Slow / Normal / Fast.
///              Phantom parity (Phase 6.1 §2.1).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - FeeTierSelector: 3-tier ChoiceChip row
library;

import 'package:flutter/material.dart';

import '../transaction/compute_budget_helper.dart';

class FeeTierSelector extends StatelessWidget {
  const FeeTierSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PriorityLevel value;
  final ValueChanged<PriorityLevel> onChanged;

  static const _bg = Color(0xFF1A1A1A);
  static const _accent = Color(0xFF00F782);
  static const _text = Color(0xFFFFFFFF);
  static const _muted = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: PriorityLevel.values.map((level) {
          final selected = level == value;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(level),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? _accent.withOpacity(0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? _accent : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _iconFor(level),
                      size: 18,
                      color: selected ? _accent : _muted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _labelFor(level),
                      style: TextStyle(
                        color: selected ? _text : _muted,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _iconFor(PriorityLevel level) {
    switch (level) {
      case PriorityLevel.slow:
        return Icons.directions_walk;
      case PriorityLevel.normal:
        return Icons.directions_bike;
      case PriorityLevel.fast:
        return Icons.bolt;
    }
  }

  String _labelFor(PriorityLevel level) {
    switch (level) {
      case PriorityLevel.slow:
        return 'Slow';
      case PriorityLevel.normal:
        return 'Normal';
      case PriorityLevel.fast:
        return 'Fast';
    }
  }
}
