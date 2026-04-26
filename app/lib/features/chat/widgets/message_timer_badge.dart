/// @file        message_timer_badge.dart
/// @description Expiring-message countdown badge — shows the time remaining on a message and turns red when under 1 minute
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - MessageTimerBadge: StatefulWidget that periodically refreshes and shows the remaining time
///  - _formatRemaining(): convert Duration to a human-readable string

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../shared/constants/colors.dart';

class MessageTimerBadge extends StatefulWidget {
  final DateTime expiresAt;

  const MessageTimerBadge({super.key, required this.expiresAt});

  @override
  State<MessageTimerBadge> createState() => _MessageTimerBadgeState();
}

class _MessageTimerBadgeState extends State<MessageTimerBadge> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final diff = widget.expiresAt.difference(now);
    if (!mounted) return;
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == Duration.zero) {
      return const SizedBox.shrink();
    }

    final isUrgent = _remaining.inSeconds < 60;
    final color = isUrgent ? SnowColors.error : SnowColors.textTertiary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timer_outlined,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          _formatRemaining(_remaining),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: isUrgent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  static String _formatRemaining(Duration d) {
    if (d.inHours > 0) {
      final mins = d.inMinutes.remainder(60);
      return '${d.inHours}h ${mins}m';
    }
    if (d.inMinutes > 0) {
      final secs = d.inSeconds.remainder(60);
      return '${d.inMinutes}:${secs.toString().padLeft(2, '0')}';
    }
    return '${d.inSeconds}s';
  }
}
