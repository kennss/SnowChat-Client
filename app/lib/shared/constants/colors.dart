/// @file        colors.dart
/// @description SnowChat app-wide color constants. Background, accent, text, message bubble, per-feature colors
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - SnowColors: app-wide color constants class

import 'package:flutter/material.dart';

abstract class SnowColors {
  // Backgrounds
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF111111);
  static const surfaceVariant = Color(0xFF1A1A1A);
  static const surfaceLight = Color(0xFF242424);

  // Accent (Session green)
  static const primary = Color(0xFF00F782);
  static const primaryDim = Color(0xFF00C853);
  static const primaryBg = Color(0xFF0A2A1A);

  // Text
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);

  // Message bubbles
  static const bubbleOut = Color(0xFF00F782);
  static const bubbleOutText = Color(0xFF000000);
  static const bubbleIn = Color(0xFF1A1A1A);
  static const bubbleInText = Color(0xFFFFFFFF);

  // Functional
  static const error = Color(0xFFFF4444);
  static const warning = Color(0xFFFFAA00);
  static const success = Color(0xFF00F782);
  static const divider = Color(0xFF1E1E1E);
}
