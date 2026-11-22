/// @file        app_lock_test.dart
/// @description AppLockController: the app locks again only when it was in
///              the background for at least the auto-lock delay, only when the
///              lock applies (passcode set, account set up, no cold-start lock
///              showing), and unlocks on the passcode; an "inactive" spell
///              (system sheet, CallKit banner) that never reached the
///              background does not count.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/security/app_lock.dart';
import 'package:snowchat/features/settings/settings_provider.dart';

void main() {
  var now = DateTime.utc(2026, 11, 22, 12);
  AppLockController controller() => AppLockController(now: () => now);
  const minute = Duration(minutes: 1);

  test('the default delay is one minute', () {
    expect(kDefaultAutoLockSeconds, 60);
    expect(kAutoLockChoices, [0, 60, 300, 900, 3600]);
  });

  test('locks after the delay in the background, not before', () {
    final lock = controller();
    lock.wentToBackground();
    now = now.add(const Duration(seconds: 59));
    lock.cameBack(delay: minute, canLock: true);
    expect(lock.state, isFalse);

    lock.wentToBackground();
    now = now.add(const Duration(seconds: 60));
    lock.cameBack(delay: minute, canLock: true);
    expect(lock.state, isTrue);

    lock.unlock();
    expect(lock.state, isFalse);
  });

  test('"immediately" locks on any return from the background', () {
    final lock = controller();
    lock.wentToBackground();
    lock.cameBack(delay: Duration.zero, canLock: true);
    expect(lock.state, isTrue);
  });

  test('no lock without a background spell', () {
    final lock = controller();
    now = now.add(const Duration(hours: 2));
    lock.cameBack(delay: Duration.zero, canLock: true);
    expect(lock.state, isFalse);
  });

  test('no lock when it does not apply (no passcode / cold lock showing)', () {
    final lock = controller();
    lock.wentToBackground();
    now = now.add(const Duration(minutes: 10));
    lock.cameBack(delay: minute, canLock: false);
    expect(lock.state, isFalse);
  });

  test('the time counts from the first background event', () {
    final lock = controller();
    lock.wentToBackground(); // paused
    now = now.add(const Duration(seconds: 40));
    lock.wentToBackground(); // hidden, later — must not restart the clock
    now = now.add(const Duration(seconds: 30));
    lock.cameBack(delay: minute, canLock: true);
    expect(lock.state, isTrue);
  });
}
