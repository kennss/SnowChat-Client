/// @file        wallet_lifecycle_manager_test.dart
/// @description WalletLifecycleManager 의 idle grace timer + defer + resume
///              cancel 검증.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-25

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/wallet/core/wallet_lifecycle_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalletLifecycleManager — start/dispose', () {
    test('start 는 idempotent — 두 번 호출해도 observer 1개만', () {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
        idleGrace: const Duration(milliseconds: 50),
      );
      mgr.start();
      mgr.start();
      // observer 가 두 번 등록되면 didChange 가 두 번 트리거되어
      // onIdle 도 두 번 호출됨 → 1번이어야 정상.
      mgr.debugTriggerPaused();
      // 50ms grace + 약간 여유
      return Future.delayed(const Duration(milliseconds: 100), () {
        expect(called, 1);
        mgr.dispose();
      });
    });

    test('dispose 는 idempotent — start 안 한 상태에서 dispose 무해', () {
      final mgr = WalletLifecycleManager(
        onIdle: () {},
        shouldDefer: () => false,
      );
      // start 없이 dispose — throw 안 해야 함
      expect(() => mgr.dispose(), returnsNormally);
    });

    test('dispose 후 timer cancel — onIdle 호출 안 됨', () async {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
        idleGrace: const Duration(milliseconds: 50),
      );
      mgr.start();
      mgr.debugTriggerPaused();
      expect(mgr.hasActiveTimer, isTrue);
      mgr.dispose();
      expect(mgr.hasActiveTimer, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(called, 0);
    });
  });

  group('WalletLifecycleManager — paused → idle', () {
    test('paused → grace 만료 후 onIdle 호출', () async {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
        idleGrace: const Duration(milliseconds: 50),
      );
      mgr.start();
      mgr.debugTriggerPaused();
      expect(called, 0); // 아직 grace 안 끝남
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(called, 1);
      mgr.dispose();
    });

    test('inactive → grace 만료 후 onIdle 호출', () async {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
        idleGrace: const Duration(milliseconds: 50),
      );
      mgr.start();
      mgr.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(called, 1);
      mgr.dispose();
    });

    test('hidden → grace 만료 후 onIdle 호출', () async {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
        idleGrace: const Duration(milliseconds: 50),
      );
      mgr.start();
      mgr.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(called, 1);
      mgr.dispose();
    });
  });

  group('WalletLifecycleManager — resume cancel', () {
    test('paused → resumed (grace 내) → onIdle 호출 안 됨', () async {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
        idleGrace: const Duration(milliseconds: 100),
      );
      mgr.start();
      mgr.debugTriggerPaused();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      mgr.debugTriggerResumed();
      expect(mgr.hasActiveTimer, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(called, 0);
      mgr.dispose();
    });

    test('paused → paused 반복 → grace timer reset', () async {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
        idleGrace: const Duration(milliseconds: 100),
      );
      mgr.start();
      mgr.debugTriggerPaused();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      mgr.debugTriggerPaused(); // reset — 100ms 더 대기 필요
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(called, 0); // 아직 100ms 안 됨
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(called, 1);
      mgr.dispose();
    });
  });

  group('WalletLifecycleManager — defer (in-flight send)', () {
    test('shouldDefer=true → grace 만료 후에도 onIdle 보류', () async {
      var called = 0;
      var inFlight = true;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => inFlight,
        idleGrace: const Duration(milliseconds: 50),
      );
      mgr.start();
      mgr.debugTriggerPaused();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(called, 0); // defer 중

      // send 완료 — 1초 retry timer 가 잡아낼 것
      inFlight = false;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(called, 1);
      mgr.dispose();
    });

    test('grace 후 defer→ defer 풀리면 retry 가 잡음', () async {
      var called = 0;
      var inFlight = true;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => inFlight,
        idleGrace: const Duration(milliseconds: 30),
      );
      mgr.start();
      mgr.debugTriggerPaused();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(called, 0);

      inFlight = false;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(called, greaterThanOrEqualTo(1));
      mgr.dispose();
    });
  });

  group('WalletLifecycleManager — detached', () {
    test('detached + shouldDefer=false → 즉시 onIdle 호출', () {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => false,
      );
      mgr.start();
      mgr.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(called, 1);
      mgr.dispose();
    });

    test('detached + shouldDefer=true → onIdle 호출 안 됨 (앱 종료 직전 in-flight)', () {
      var called = 0;
      final mgr = WalletLifecycleManager(
        onIdle: () => called++,
        shouldDefer: () => true,
      );
      mgr.start();
      mgr.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(called, 0);
      mgr.dispose();
    });
  });
}
