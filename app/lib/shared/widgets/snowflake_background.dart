/// @file        snowflake_background.dart
/// @description Chat background snowflake pattern — background with SnowChat logo snowflakes subtly scattered
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-15
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SnowflakeBackground: snowflake-pattern background widget
///  - _SnowflakePainter: CustomPainter that draws snowflake icons with random position/size/rotation

import 'dart:math';
import 'package:flutter/material.dart';

/// Widget that renders a subtle snowflake pattern as the chat screen background.
/// Uses the SnowChat brand color (#00F782) at very low opacity.
class SnowflakeBackground extends StatelessWidget {
  const SnowflakeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _SnowflakePainter(),
      ),
    );
  }
}

class _SnowflakePainter extends CustomPainter {
  /// Fixed-seed random — keeps the same pattern across builds (no flicker).
  final _random = Random(42);

  @override
  void paint(Canvas canvas, Size size) {
    // Lay out without overlap — fewer flakes, larger size
    final count = (size.width * size.height / 12000).clamp(15, 35).toInt();

    for (int i = 0; i < count; i++) {
      final x = _random.nextDouble() * size.width;
      final y = _random.nextDouble() * size.height;
      // Size: 14px ~ 45px
      final snowSize = 14.0 + _random.nextDouble() * 31.0;
      final rotation = _random.nextDouble() * pi;
      final opacity = snowSize < 22 ? 0.18 : (snowSize < 34 ? 0.14 : 0.10);
      final paint = Paint()
        ..color = Color(0xFF00F782).withOpacity(opacity)
        ..strokeWidth = snowSize < 22 ? 1.3 : 1.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      _drawSnowflake(canvas, paint, snowSize);
      canvas.restore();
    }
  }

  /// SnowChat-logo-style snowflake — 6 arms + branches.
  void _drawSnowflake(Canvas canvas, Paint paint, double size) {
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3;

      // Main arm
      final endX = cos(angle) * size;
      final endY = sin(angle) * size;
      canvas.drawLine(Offset.zero, Offset(endX, endY), paint);

      // Small side branches (only when the flake is large enough)
      if (size > 8) {
        final branchLen = size * 0.35;
        final midX = cos(angle) * size * 0.55;
        final midY = sin(angle) * size * 0.55;

        for (final dir in [-1, 1]) {
          final branchAngle = angle + dir * pi / 4;
          canvas.drawLine(
            Offset(midX, midY),
            Offset(
              midX + cos(branchAngle) * branchLen,
              midY + sin(branchAngle) * branchLen,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
