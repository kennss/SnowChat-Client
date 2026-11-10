/// @file        database_key_manager_test.dart
/// @description At-rest protection level 1 — DatabaseKeyManager: a key is
///              created exactly once when storage is provably readable, never
///              created (and nothing deleted) when secure storage is locked /
///              unreadable — including the iOS BFU false-"not found" case —
///              and racing writers converge on the persisted key.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-11
/// @lastUpdated 2026-11-11
///
/// @functions
///  - _FakeStorage: SecureStorageService fake with lock / failure injection
///  - main(): test cases
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';
import 'package:snowchat/core/storage/database_key_manager.dart';
import 'package:snowchat/core/storage/secure_storage.dart';

/// [locked] models an iOS keychain before first unlock as observed through
/// flutter_secure_storage: reads may answer `null` (false "not found") and
/// writes fail. [throwOnRead] models a hard platform error on read.
class _FakeStorage extends Fake implements SecureStorageService {
  final Map<String, String> data = {};
  bool locked = false;
  bool throwOnRead = false;
  int writes = 0;

  /// Runs right after a successful write of [DatabaseKeyManager.keyName]
  /// (simulates another writer racing in).
  void Function()? afterKeyWrite;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw StateError('errSecInteractionNotAllowed');
    if (locked) return null;
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (locked) throw StateError('errSecInteractionNotAllowed');
    writes++;
    data[key] = value;
    if (key == DatabaseKeyManager.keyName) afterKeyWrite?.call();
  }

  @override
  Future<void> delete(String key) async {
    if (locked) throw StateError('errSecInteractionNotAllowed');
    data.remove(key);
  }
}

void main() {
  setUp(DatabaseKeyManager.resetForTest);

  group('key absent on readable storage', () {
    test('creates a 32-byte hex key once and reuses it afterwards', () async {
      final storage = _FakeStorage();
      var beforeCreate = 0;
      final mgr = DatabaseKeyManager(storage);

      final r1 = await mgr.resolve(
          allowCreate: true, onBeforeCreate: () async => beforeCreate++);
      expect(r1.created, isTrue);
      expect(DatabaseKeyManager.isValidHexKey(r1.hexKey), isTrue);
      expect(storage.data[DatabaseKeyManager.keyName], r1.hexKey);
      expect(beforeCreate, 1);
      // The readability probe is cleaned up.
      expect(storage.data.containsKey(DatabaseKeyManager.probeKeyName), isFalse);

      final r2 = await mgr.resolve(
          allowCreate: true, onBeforeCreate: () async => beforeCreate++);
      expect(r2.created, isFalse);
      expect(r2.hexKey, r1.hexKey);
      expect(beforeCreate, 1);
    });

    test('concurrent resolves in one isolate produce a single key', () async {
      final storage = _FakeStorage();
      var beforeCreate = 0;
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          DatabaseKeyManager(storage).resolve(
              allowCreate: true, onBeforeCreate: () async => beforeCreate++),
      ]);
      expect(results.map((r) => r.hexKey).toSet(), hasLength(1));
      expect(beforeCreate, 1);
      // One readability probe + one key write — no second writer.
      expect(storage.writes, 2);
    });

    test('known-present key proves readability without a probe write',
        () async {
      final storage = _FakeStorage()
        ..data[VerifiedIdentityStore.unlockProbeKey] = 'snow0123';
      final r = await DatabaseKeyManager(storage)
          .resolve(allowCreate: true, onBeforeCreate: () async {});
      expect(r.created, isTrue);
      expect(storage.writes, 1); // only the key itself
    });

    test('a racing writer wins → its persisted key is adopted', () async {
      final other = 'ab' * 32;
      final storage = _FakeStorage();
      storage.afterKeyWrite = () {
        storage.afterKeyWrite = null;
        storage.data[DatabaseKeyManager.keyName] = other;
      };
      final r = await DatabaseKeyManager(storage)
          .resolve(allowCreate: true, onBeforeCreate: () async {});
      expect(r.hexKey, other);
      expect(r.created, isFalse);
    });

    test('non-owner isolate may not create: throws, nothing written/deleted',
        () async {
      final storage = _FakeStorage();
      var beforeCreate = 0;
      await expectLater(
        DatabaseKeyManager(storage).resolve(
            allowCreate: false, onBeforeCreate: () async => beforeCreate++),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );
      expect(beforeCreate, 0);
      expect(storage.data.containsKey(DatabaseKeyManager.keyName), isFalse);
    });
  });

  group('storage unreadable (BFU / keychain locked)', () {
    test('read throws → no create, no delete, retryable exception', () async {
      final storage = _FakeStorage()..throwOnRead = true;
      var beforeCreate = 0;
      await expectLater(
        DatabaseKeyManager(storage).resolve(
            allowCreate: true, onBeforeCreate: () async => beforeCreate++),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );
      expect(beforeCreate, 0);
      expect(storage.writes, 0);
    });

    test('false "not found" while locked is NOT taken as absent', () async {
      // The real key exists but the locked keychain answers null.
      final storage = _FakeStorage()
        ..data[DatabaseKeyManager.keyName] = 'cd' * 32
        ..locked = true;
      var beforeCreate = 0;
      await expectLater(
        DatabaseKeyManager(storage).resolve(
            allowCreate: true, onBeforeCreate: () async => beforeCreate++),
        throwsA(isA<DatabaseKeyUnavailableException>()),
      );
      expect(beforeCreate, 0, reason: 'database must not be deleted');
      expect(storage.data[DatabaseKeyManager.keyName], 'cd' * 32,
          reason: 'existing key must not be replaced');
    });

    test('after unlock the next resolve returns the existing key', () async {
      final storage = _FakeStorage()
        ..data[DatabaseKeyManager.keyName] = 'ef' * 32
        ..locked = true;
      final mgr = DatabaseKeyManager(storage);
      await expectLater(
          mgr.resolve(allowCreate: true, onBeforeCreate: () async {}),
          throwsA(isA<DatabaseKeyUnavailableException>()));
      storage.locked = false;
      final r =
          await mgr.resolve(allowCreate: true, onBeforeCreate: () async {});
      expect(r.hexKey, 'ef' * 32);
      expect(r.created, isFalse);
    });
  });

  group('stored key', () {
    test('existing valid key is returned without side effects', () async {
      final storage = _FakeStorage()..data[DatabaseKeyManager.keyName] = '01' * 32;
      var beforeCreate = 0;
      final r = await DatabaseKeyManager(storage).resolve(
          allowCreate: true, onBeforeCreate: () async => beforeCreate++);
      expect(r.hexKey, '01' * 32);
      expect(r.created, isFalse);
      expect(beforeCreate, 0);
      expect(storage.writes, 0);
    });

    test('malformed key → StateError, never replaced', () async {
      final storage = _FakeStorage()..data[DatabaseKeyManager.keyName] = 'xyz';
      await expectLater(
        DatabaseKeyManager(storage)
            .resolve(allowCreate: true, onBeforeCreate: () async {}),
        throwsA(isA<StateError>()),
      );
      expect(storage.data[DatabaseKeyManager.keyName], 'xyz');
    });

    test('deleteKey removes only the key', () async {
      final storage = _FakeStorage()
        ..data[DatabaseKeyManager.keyName] = '01' * 32
        ..data['other'] = 'x';
      await DatabaseKeyManager(storage).deleteKey();
      expect(storage.data.keys, ['other']);
    });
  });
}
