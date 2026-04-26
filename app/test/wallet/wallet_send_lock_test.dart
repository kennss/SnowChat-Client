/// @file        wallet_send_lock_test.dart
/// @description WalletSendLock 의 reference counting + balance 강제 + 멀티
///              wallet 격리 검증.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-25

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/wallet/core/wallet_send_lock.dart';

void main() {
  group('WalletSendLock — basic acquire/release', () {
    test('초기 상태: hasAnyActive=false, isLocked=false', () {
      final lock = WalletSendLock();
      expect(lock.hasAnyActive, isFalse);
      expect(lock.isLocked('any'), isFalse);
    });

    test('acquire 후 isLocked=true', () {
      final lock = WalletSendLock();
      lock.acquire('wal_a');
      expect(lock.isLocked('wal_a'), isTrue);
      expect(lock.hasAnyActive, isTrue);
    });

    test('acquire 후 release → unlock', () {
      final lock = WalletSendLock();
      lock.acquire('wal_a');
      lock.release('wal_a');
      expect(lock.isLocked('wal_a'), isFalse);
      expect(lock.hasAnyActive, isFalse);
    });
  });

  group('WalletSendLock — multi-wallet 격리', () {
    test('wallet A 의 lock 이 wallet B 에 영향 없음', () {
      final lock = WalletSendLock();
      lock.acquire('wal_a');
      expect(lock.isLocked('wal_a'), isTrue);
      expect(lock.isLocked('wal_b'), isFalse);
    });

    test('여러 wallet 동시 lock — activeWalletIds 정확', () {
      final lock = WalletSendLock();
      lock.acquire('wal_a');
      lock.acquire('wal_b');
      lock.acquire('wal_c');
      expect(lock.activeWalletIds.toSet(), {'wal_a', 'wal_b', 'wal_c'});
      expect(lock.hasAnyActive, isTrue);
    });

    test('일부 release 후 hasAnyActive=true 유지', () {
      final lock = WalletSendLock();
      lock.acquire('wal_a');
      lock.acquire('wal_b');
      lock.release('wal_a');
      expect(lock.isLocked('wal_a'), isFalse);
      expect(lock.isLocked('wal_b'), isTrue);
      expect(lock.hasAnyActive, isTrue);
    });
  });

  group('WalletSendLock — reference counting', () {
    test('같은 wallet 두 번 acquire — 두 번 release 필요', () {
      final lock = WalletSendLock();
      lock.acquire('wal_a');
      lock.acquire('wal_a');
      expect(lock.isLocked('wal_a'), isTrue);

      lock.release('wal_a');
      expect(lock.isLocked('wal_a'), isTrue); // 아직 1번 acquire 남음

      lock.release('wal_a');
      expect(lock.isLocked('wal_a'), isFalse);
    });

    test('release 가 acquire 보다 많으면 ArgumentError', () {
      final lock = WalletSendLock();
      lock.acquire('wal_a');
      lock.release('wal_a');
      expect(
        () => lock.release('wal_a'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('acquire 없는 wallet release → ArgumentError', () {
      final lock = WalletSendLock();
      expect(
        () => lock.release('wal_unseen'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
