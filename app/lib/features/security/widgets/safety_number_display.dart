/// @file        safety_number_display.dart
/// @description Renders a 60-digit Safety Number as a 6×2 monospace grid
///              ("12345 67890" per row). Long-press copies the digits-only
///              form (no spaces) to the clipboard so the user can paste
///              into a side-channel for comparison. Designed to be visually
///              distinct from regular chat text — large mono font, fixed
///              column layout — so the user notices a single mismatched
///              digit at a glance.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-18
///
/// @functions
///  - SafetyNumberDisplay: 60-digit grid widget with copy-on-long-press
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/crypto/safety_number.dart';
import '../../../shared/constants/colors.dart';

class SafetyNumberDisplay extends StatelessWidget {
  /// Exactly 60 decimal digits (no spaces).
  final String digits60;

  /// If true, renders a slimmer compact version (e.g. for embedded preview
  /// in a sheet). Default false → full Verify screen layout.
  final bool compact;

  const SafetyNumberDisplay({
    super.key,
    required this.digits60,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    assert(digits60.length == 60,
        'SafetyNumberDisplay requires 60 digits, got ${digits60.length}');
    final formatted = SafetyNumber.formatForDisplay(digits60);

    return GestureDetector(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: digits60));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Safety number copied'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 20,
          vertical: compact ? 12 : 20,
        ),
        decoration: BoxDecoration(
          color: SnowColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: SnowColors.divider,
            width: 1,
          ),
        ),
        child: SelectableText(
          formatted,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: compact ? 16 : 22,
            color: SnowColors.textPrimary,
            letterSpacing: 1.5,
            height: 1.6,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
