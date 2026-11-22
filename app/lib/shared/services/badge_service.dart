/// @file        badge_service.dart
/// @description App icon badge wrapper. Wraps app_badge_plus so the rest of
///              the app sees a tiny intent-based API (setCount / clear).
///              iOS receives badge counts via APNs aps.badge automatically;
///              this service drives the FG / resume / read-receipt updates
///              that the OS-level path can't see.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-14
/// @lastUpdated 2026-11-22 (setCount(force:): the app is not the only writer of the badge — APNs aps.badge sets it too, and a pushed count the app never saw change (the message was read as it arrived, the chat open) stayed on the icon because the last written value matched; appBadgeUpdaterProvider forces a write on every resume)
///
/// @functions
///  - BadgeService.instance: singleton
///  - setCount(int, {force}): write badge — clamps to >=0; skips a value equal
///    to the last one this service wrote unless [force]
///  - clear(): setCount(0) sugar

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';

class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  int _last = -1;

  /// [force]: write even when [count] equals the last value written here.
  /// The OS badge is also set by push payloads (iOS aps.badge), so "equal to
  /// what this service wrote" does not mean "equal to what the icon shows".
  Future<void> setCount(int count, {bool force = false}) async {
    final clamped = count < 0 ? 0 : count;
    if (!force && clamped == _last) return;
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
