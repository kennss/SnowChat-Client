/// @file        snow_id_display.dart
/// @description SnowChat ID display widget. Monospace styling, truncated display, clipboard-copy support
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - SnowIdDisplay: SnowChat ID display StatelessWidget

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/colors.dart';

/// Displays a SnowChat ID with monospace styling and a copy button.
/// Format: "snow" + 32 hex chars = 36 chars total.
class SnowIdDisplay extends StatelessWidget {
  final String snowId;
  final bool compact;
  final bool showCopy;
  final double fontSize;

  const SnowIdDisplay({
    super.key,
    required this.snowId,
    this.compact = false,
    this.showCopy = true,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final display = compact ? _truncated() : snowId;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'snow',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: SnowColors.primary,
                  ),
                ),
                TextSpan(
                  text: display.substring(4),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: fontSize,
                    fontWeight: FontWeight.w400,
                    color: SnowColors.textSecondary,
                  ),
                ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showCopy) ...[
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            iconSize: fontSize + 4,
            color: SnowColors.primary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Copy ID',
            onPressed: () => _copyToClipboard(context),
          ),
        ],
      ],
    );
  }

  String _truncated() {
    if (snowId.length <= 12) return snowId;
    return '${snowId.substring(0, 10)}...${snowId.substring(snowId.length - 6)}';
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: snowId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('SnowChat ID copied!'),
        backgroundColor: SnowColors.primaryBg,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
