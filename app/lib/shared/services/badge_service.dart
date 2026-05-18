/// @file        badge_service.dart
/// @description App icon badge wrapper. Wraps app_badge_plus so the rest of
///              the app sees a tiny intent-based API (setCount / clear).
///              iOS receives badge counts via APNs aps.badge automatically;
///              this service drives the FG / resume / read-receipt updates
///              that the OS-level path can't see.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-14
/// @lastUpdated 2026-05-14
///
/// @functions
///  - BadgeService.instance: singleton
///  - setCount(int): write badge — clamps to >=0, no-op when count unchanged
///  - clear(): setCount(0) sugar

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  int _last = -1;

  Future<void> setCount(int count) async {
    final clamped = count < 0 ? 0 : count;
    if (clamped == _last) return;
    _last = clamped;
    try {
      final supported = await AppBadgePlus.isSupported();
      if (!supported) {
        // Pixel / AOSP launcher path — notification dot already covers the
        // unread cue, no badge plugin call needed.
        return;
      }
      await AppBadgePlus.updateBadge(clamped);
    } catch (e) {
      debugPrint('[BadgeService] setCount($clamped) failed: $e');
    }
  }

  Future<void> clear() => setCount(0);
}
