/// @file        toast.dart
/// @description Toast notification widget. SnackBar-based toast messages for success, error, warning, info types
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - ToastType: toast type enum (success, error, warning, info)
///  - SnowToast: utility class for showing toast messages
///  - SnowToast.show(): show a toast message

import 'package:flutter/material.dart';
import '../constants/colors.dart';

enum ToastType { success, error, warning, info }

class SnowToast {
  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final color = switch (type) {
      ToastType.success => SnowColors.success,
      ToastType.error => SnowColors.error,
      ToastType.warning => SnowColors.warning,
      ToastType.info => SnowColors.primary,
    };

    final icon = switch (type) {
      ToastType.success => Icons.check_circle_rounded,
      ToastType.error => Icons.error_rounded,
      ToastType.warning => Icons.warning_rounded,
      ToastType.info => Icons.info_rounded,
    };

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: SnowColors.surface,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
