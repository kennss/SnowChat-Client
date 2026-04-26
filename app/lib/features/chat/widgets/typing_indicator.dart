/// @file        typing_indicator.dart
/// @description Typing-indicator widget — animated three dots shown while the peer is typing
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-29)
///
/// @functions
///  - TypingIndicator: StatefulWidget rendering the typing animation

import 'package:flutter/material.dart';
import '../../../shared/constants/colors.dart';

/// Animated three-dot typing indicator (Session style).
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SnowColors.bubbleIn,
        borderRadius: BorderRadius.circular(18),
      ),
      child: _DotsAnimator(
        controller: _controller,
        bounce: _bounce,
      ),
    );
  }

  double _bounce(double t) {
    if (t < 0) t += 1.0;
    if (t < 0.5) return 4 * t * t * (3 - 4 * t);
    return 0.0;
  }
}

class _DotsAnimator extends AnimatedWidget {
  final double Function(double) bounce;

  const _DotsAnimator({
    required AnimationController controller,
    required this.bounce,
  }) : super(listenable: controller);

  AnimationController get _controller => listenable as AnimationController;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        final delay = index * 0.2;
        final t = (_controller.value - delay) % 1.0;
        final scale = 0.5 + 0.5 * bounce(t);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: SnowColors.textTertiary
                    .withValues(alpha: 0.4 + 0.6 * bounce(t)),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
