/// @file        token_manager_test.dart
/// @description Phase 11 — TokenManager unit tests. Verifies the mutex pattern
///              (100 concurrent ensureFresh → single refresh fire), retry
///              backoff, expiredHard event, JWT exp claim decode, and legacy
///              slot migration.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-03
/// @lastUpdated 2026-05-03
///
/// @functions
///  - _MemoryStorage: in-memory SecureStorageService stub for isolation
///  - _makeJwt(): build a synthetic JWT with the given exp seconds
///  - test groups: mutex, sequential, retry/backoff, expiredHard, hydrate

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/network/token_manager.dart';
import 'package:snowchat/core/storage/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub the iOS-only relaxed-keychain MethodChannel so SecureStorageService
  // construction inside _MemoryStorage doesn't blow up if a sub-call ever
  // routes through it (defense-in-depth — _MemoryStorage overrides all three
  // methods we use, so the channel should never actually fire).
  setUpAll(() {
    const channel = MethodChannel('snowchat/keychain_relaxed');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    // Register the main-isolate marker so ensureFresh's BG isolate guard
    // doesn't reject every test call. In production this happens in main.dart.
    TokenManager.registerMainIsolateOwner();
  });

  group('JWT exp claim decode', () {
    test('decodes valid exp claim', () {
      final exp = DateTime.now().toUtc().add(const Duration(hours: 1));
      final jwt = _makeJwt(expSec: exp.millisecondsSinceEpoch ~/ 1000);
      final decoded = TokenSnapshot.decodeExpAt(jwt);
      // Allow 1s rounding tolerance (we strip ms from the encoded exp).
      expect(decoded.difference(exp).abs().inSeconds, lessThanOrEqualTo(1));
    });

    test('throws on malformed JWT', () {
      expect(() => TokenSnapshot.decodeExpAt('not.a.jwt.really'),
          throwsA(isA<FormatException>()));
      expect(() => TokenSnapshot.decodeExpAt('only-one-part'),
          throwsA(isA<FormatException>()));
    });
  });

  group('TokenSnapshot toString', () {
    test('redacts the access token', () {
      final access =
          _makeJwt(expSec: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60);
      final s = TokenSnapshot.fromTokens(
        access: access,
        refresh: 'super-secret-refresh-token-XYZ',
        version: 1,
      );
      final str = s.toString();
      expect(str, contains('*REDACTED*'));
      expect(str, isNot(contains('super-secret-refresh')));
      // The full access token should NOT appear, but the prefix is allowed.
      expect(str, isNot(contains(access)));
    });
  });

  group('Mutex — 100 concurrent ensureFresh fires single refresh', () {
    test('Acceptance Criterion #1', () async {
      final storage = _MemoryStorage();
      var refreshCount = 0;
      final tm = TokenManager(
        storage: storage,
        refreshFn: (refresh) async {
          refreshCount++;
          // Yield to give all other concurrent callers time to enter the
          // mutex check before this one resolves.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          return _makeSnapshot(version: refreshCount + 1);
        },
      );
      // Seed an EXPIRED snapshot so ensureFresh always triggers a refresh.
      await tm.setFromLogin(_makeSnapshot(expInSeconds: -10, version: 1));

      final futures = List<Future<TokenSnapshot>>.generate(
        100,
        (_) => tm.ensureFresh(reason: 'test'),
      );
      final results = await Future.wait(futures);

      expect(refreshCount, 1, reason: 'mutex must coalesce 100 calls into 1');
      // All callers must receive the same snapshot.
      expect(results.toSet().length, 1);
      tm.dispose();
    });
  });

  group('Sequential ensureFresh — second call after first returns', () {
    test('still triggers second refresh after the first completes', () async {
      final storage = _MemoryStorage();
      var refreshCount = 0;
      final tm = TokenManager(
        storage: storage,
        // Each refresh returns a token that is also already expired so the
        // next ensureFresh sees a stale snapshot and fires again.
        refreshFn: (refresh) async {
          refreshCount++;
          return _makeSnapshot(expInSeconds: -10, version: refreshCount + 1);
        },
      );
      await tm.setFromLogin(_makeSnapshot(expInSeconds: -10, version: 1));

      await tm.ensureFresh(reason: 'first');
      await tm.ensureFresh(reason: 'second');

      expect(refreshCount, 2);
      tm.dispose();
    });
  });

  group('Retry / backoff', () {
    test('3× failure → expiredHard event + clear', () async {
      final storage = _MemoryStorage();
      final events = <TokenEvent>[];
      final tm = TokenManager(
        storage: storage,
        refreshFn: (_) async => throw Exception('network down'),
      );
      tm.events.listen(events.add);
      await tm.setFromLogin(_makeSnapshot(expInSeconds: -10, version: 1));
      // Drain the login event so the assertion below counts only refresh events.
      await Future<void>.delayed(Duration.zero);

      Object? caught;
      try {
        await tm.ensureFresh(reason: 'test');
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<Exception>(),
          reason: 'ensureFresh must rethrow after 3× exhausted');

      // Drain microtasks so the event listener fires.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final hardEvents =
          events.where((e) => e.type == TokenEventType.expiredHard).toList();
      expect(hardEvents.length, 1, reason: 'expiredHard must be emitted once');
      expect(tm.snapshot, isNull, reason: 'clear() must wipe the snapshot');
      tm.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('backoff timing — 1s, 2s, 4s before final failure', () async {
      final storage = _MemoryStorage();
      final attemptTimes = <DateTime>[];
      final tm = TokenManager(
        storage: storage,
        refreshFn: (_) async {
          attemptTimes.add(DateTime.now());
          throw Exception('boom');
        },
      );
      await tm.setFromLogin(_makeSnapshot(expInSeconds: -10, version: 1));

      try {
        await tm.ensureFresh(reason: 'backoff-test');
      } catch (_) {/* expected */}

      expect(attemptTimes.length, 3,
          reason: '3 attempts before declaring expiredHard');
      // Gap between attempt 1 and 2 should be ~1s; 2 and 3 ~2s. Allow
      // generous slack for CI jitter.
      final gap12 = attemptTimes[1].difference(attemptTimes[0]).inMilliseconds;
      final gap23 = attemptTimes[2].difference(attemptTimes[1]).inMilliseconds;
      expect(gap12, inInclusiveRange(900, 1500), reason: 'backoff #1 ≈ 1s');
      expect(gap23, inInclusiveRange(1900, 2500), reason: 'backoff #2 ≈ 2s');
      tm.dispose();
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('hydrate — v2 envelope', () {
    test('reads stored snapshot and emits hydrated', () async {
      final storage = _MemoryStorage();
      final pre = _makeSnapshot(version: 5);
      await storage.write('auth_tokens_v2', json.encode(pre.toJson()));

      final events = <TokenEvent>[];
      final tm = TokenManager(
        storage: storage,
        refreshFn: (_) async => throw StateError('should not be called'),
      );
      tm.events.listen(events.add);
      await tm.hydrateFromStorage();
      // Drain microtasks so the broadcast event is delivered.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tm.snapshot, isNotNull);
      expect(tm.snapshot!.version, 5);
      expect(events.where((e) => e.type == TokenEventType.hydrated).length, 1);
      tm.dispose();
    });

    test('migrates legacy slots → v2 envelope and deletes them', () async {
      final storage = _MemoryStorage();
      final accessJwt = _makeJwt(
          expSec: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600);
      const refreshTok = 'legacy-refresh-XYZ';
      await storage.write('auth_token', accessJwt);
      await storage.write('auth_refresh_token', refreshTok);

      final tm = TokenManager(
        storage: storage,
        refreshFn: (_) async => throw StateError('should not be called'),
      );
      await tm.hydrateFromStorage();

      expect(tm.snapshot, isNotNull);
      expect(tm.snapshot!.access, accessJwt);
      expect(tm.snapshot!.refresh, refreshTok);
      // v2 envelope should now be persisted.
      final stored = await storage.read('auth_tokens_v2');
      expect(stored, isNotNull);
      // Legacy slots must be wiped.
      expect(await storage.read('auth_token'), isNull);
      expect(await storage.read('auth_refresh_token'), isNull);
      tm.dispose();
    });

    test('no tokens at all → snapshot stays null', () async {
      final storage = _MemoryStorage();
      final tm = TokenManager(
        storage: storage,
        refreshFn: (_) async => throw StateError('should not be called'),
      );
      await tm.hydrateFromStorage();
      expect(tm.snapshot, isNull);
      tm.dispose();
    });
  });

  group('clear()', () {
    test('emits logout + wipes snapshot + storage', () async {
      final storage = _MemoryStorage();
      final tm = TokenManager(
        storage: storage,
        refreshFn: (_) async => throw StateError('should not be called'),
      );
      final events = <TokenEvent>[];
      tm.events.listen(events.add);
      await tm.setFromLogin(_makeSnapshot(version: 1));
      expect(tm.snapshot, isNotNull);

      await tm.clear();
      // Drain microtask queue.
      await Future<void>.delayed(Duration.zero);

      expect(tm.snapshot, isNull);
      expect(await storage.read('auth_tokens_v2'), isNull);
      expect(events.where((e) => e.type == TokenEventType.logout).length, 1);
      tm.dispose();
    });
  });

  group('ensureFresh — fresh snapshot returns sync without refresh', () {
    test('cached snapshot > 5min remaining → no refresh fire', () async {
      final storage = _MemoryStorage();
      var refreshCount = 0;
      final tm = TokenManager(
        storage: storage,
        refreshFn: (_) async {
          refreshCount++;
          return _makeSnapshot(version: 99);
        },
      );
      // 1h remaining — well past the 5min freshness threshold.
      await tm.setFromLogin(_makeSnapshot(expInSeconds: 3600, version: 1));

      final result = await tm.ensureFresh(reason: 'fresh-cache');
      expect(refreshCount, 0, reason: 'no refresh when cache > 5min fresh');
      expect(result.version, 1);
      tm.dispose();
    });
  });
}

/// Build a synthetic JWT — `header.payload.signature` with the given exp
/// (unix seconds). Other claims are minimal. The signature is opaque (we only
/// decode the payload locally, never verify).
String _makeJwt({required int expSec}) {
  String b64u(Map<String, dynamic> m) => base64Url
      .encode(utf8.encode(json.encode(m)))
      .replaceAll('=', '');
  final header = b64u({'alg': 'HS256', 'typ': 'JWT'});
  final payload = b64u({'sub': 'test-user', 'exp': expSec});
  return '$header.$payload.fake-sig';
}

/// Convenience constructor that builds a TokenSnapshot whose access JWT
/// expires `expInSeconds` seconds from now (negative → already expired).
TokenSnapshot _makeSnapshot({int expInSeconds = 3600, required int version}) {
  final exp = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + expInSeconds;
  final access = _makeJwt(expSec: exp);
  return TokenSnapshot.fromTokens(
    access: access,
    refresh: 'refresh-tok-v$version',
    version: version,
  );
}

/// In-memory SecureStorageService for tests. Overrides the three methods
/// TokenManager actually uses (read / write / delete) — the parent
/// constructor's FlutterSecureStorage instantiation is harmless because
/// none of its calls reach the platform channel here.
class _MemoryStorage extends SecureStorageService {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}
