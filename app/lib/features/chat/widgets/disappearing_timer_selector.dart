/// @file        disappearing_timer_selector.dart
/// @description Expiring-message TTL picker bottom sheet — 1 min, 5 min, 30 min, 1 hour, don't-delete options
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-20)
///
/// @functions
///  - DisappearingTimerSelector: bottom-sheet widget showing the 4 TTL options as radio buttons
///  - showDisappearingTimerSelector(): function that displays the bottom sheet and returns the selected TTL (in seconds)

import 'package:flutter/material.dart';
import '../../../shared/constants/colors.dart';

/// TTL option with display label and value in seconds (null = off).
class _TtlOption {
  final String label;
  final int? seconds;

  const _TtlOption(this.label, this.seconds);
}

const _ttlOptions = [
  _TtlOption('1 minute', 60),
  _TtlOption('5 minutes', 300),
  _TtlOption('30 minutes', 1800),
  _TtlOption('1 hour', 3600),
  _TtlOption("Don't delete", null),
];

/// Shows the disappearing timer selector bottom sheet.
///
/// Returns the selected TTL in seconds, or `null` for "Don't delete".
/// Returns the current value unchanged if the user dismisses without selecting.
Future<int?> showDisappearingTimerSelector(
  BuildContext context, {
  int? currentTtl,
}) async {
  return showModalBottomSheet<int?>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => DisappearingTimerSelector(currentTtl: currentTtl),
  );
}

class DisappearingTimerSelector extends StatelessWidget {
  final int? currentTtl;

  const DisappearingTimerSelector({super.key, this.currentTtl});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SnowColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Handle bar
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SnowColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            // Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: SnowColors.primary,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Disappearing Messages',
                    style: TextStyle(
                      color: SnowColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Messages will be deleted after the selected time.',
                style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Options
            ..._ttlOptions.map((option) {
              final isSelected = option.seconds == currentTtl;
              return _buildOption(context, option, isSelected);
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    _TtlOption option,
    bool isSelected,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(option.seconds),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isSelected ? SnowColors.primary : SnowColors.textTertiary,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: SnowColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            // Label
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  color: isSelected
                      ? SnowColors.primary
                      : SnowColors.textPrimary,
                  fontSize: 16,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                color: SnowColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
