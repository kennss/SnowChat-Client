/// @file        action_buttons.dart
/// @description Circular action buttons for wallet home (Receive, Send, Swap,
///              Market).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - ActionButtons: widget showing the Receive/Send/Swap/Market circular button row

/// Phantom-style circular action buttons: Receive, Send, Swap.
library;

import 'package:flutter/material.dart';

abstract class _C {
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const textSecondary = Color(0xFF9E9E9E);
}

/// Row of circular action buttons (Receive / Send / Swap).
class ActionButtons extends StatelessWidget {
  const ActionButtons({
    super.key,
    this.onReceive,
    this.onSend,
    this.onSwap,
    this.onMarket,
  });

  final VoidCallback? onReceive;
  final VoidCallback? onSend;
  final VoidCallback? onSwap;
  final VoidCallback? onMarket;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.arrow_downward_rounded,
            label: 'Receive',
            onTap: onReceive,
          ),
          _ActionButton(
            icon: Icons.arrow_upward_rounded,
            label: 'Send',
            onTap: onSend,
          ),
          _ActionButton(
            icon: Icons.swap_horiz_rounded,
            label: 'Swap',
            onTap: onSwap,
          ),
          _ActionButton(
            icon: Icons.storefront_rounded,
            label: 'Market',
            onTap: onMarket,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _C.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: _C.primary.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(icon, color: _C.primary, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _C.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
