/// @file        app_lock.dart
/// @description When the app locks again after the background. The cold start
///              always locks (the /pin-login route, isLockedProvider); this is
///              the other case: the app was in the background for at least the
///              user's auto-lock delay (default one minute) and comes back.
///              Pure state — AppLockGate (app/app_lock_gate.dart) feeds it the
///              lifecycle and shows the lock over the app while it is locked.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - AppLockController.wentToBackground(): remember when the app left
///  - AppLockController.cameBack(): lock when it was away long enough
///  - AppLockController.unlock(): the passcode (or biometrics) was right
///  - appLockProvider: the controller
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True while the app is locked after a return from the background.
class AppLockController extends StateNotifier<bool> {
  AppLockController({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        super(false);

  final DateTime Function() _now;
  DateTime? _leftAt;

  /// The app went to the background (not a mere "inactive" — a system sheet
  /// or the CallKit banner makes it inactive without leaving).
  void wentToBackground() {
    _leftAt ??= _now();
  }

  /// The app is in the foreground again. Locks when it was away for at least
  /// [delay] and the lock applies now ([canLock]: a passcode is set, the
  /// account is set up, the cold-start lock is not already showing).
  void cameBack({required Duration delay, required bool canLock}) {
    final left = _leftAt;
    _leftAt = null;
    if (left == null || !canLock || state) return;
    if (_now().difference(left) >= delay) state = true;
  }

  /// Unlocked by the passcode or biometrics.
  void unlock() {
    state = false;
  }
}

final appLockProvider = StateNotifierProvider<AppLockController, bool>(
  (ref) => AppLockController(),
);
