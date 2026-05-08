/// @file        token_manager.dart
/// @description Phase 11 SSoT — JWT 토큰의 단일 책임 컴포넌트. 모든 access/refresh
///              경로 (HTTP, Socket.IO, FCM, push token sync) 가 본 클래스의
///              `ensureFresh()` 를 거친다. Mutex (`_inflight ??= …`) 로 100x
///              concurrent caller 가 와도 단일 refresh 만 수행. JWT exp claim 을
///              디코드해 access 만료 5분 전이면 능동 refresh. proactive Timer 는
///              FG 최적화 (background 진입 시 죽음 — 의존하지 않음 / `WidgetsBinding`
///              resumed 콜백에서 5분 임박 즉시 ensureFresh).
///
///              IsolateNameServer 가드: main isolate 만 'main_token_owner' 포트
///              등록. BG isolate (FCM bg handler 등) 가 `ensureFresh` 호출 시
///              `StateError` throw — push payload 는 metadata 만 사용해야 함.
///
///              Storage: secure_storage 의 단일 key `auth_tokens_v2` 에 access +
///              refresh + accessExpAt + version 을 JSON 한 묶음으로 저장
///              (atomic). 첫 hydrate 시 legacy slot (`auth_token`,
///              `auth_refresh_token`) 이 있으면 읽어서 bundled JSON 으로 재저장
///              + legacy slot 삭제 (one-time migration).
///
///              Events: hydrated / login / refreshed / expiredHard / logout
///              broadcast 로 노출. UI 는 expiredHard 시 SnackBar + onboarding
///              navigate. pushTokenAutoSync 는 login || hydrated 만 listen.
///
///              Security: TokenSnapshot.toString() 은 `*REDACTED*` — debugPrint
///              에 access/refresh full 이 흘러나가지 않도록 강제.
///
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-03
/// @lastUpdated 2026-05-07 (transient-aware failure classification —
///              RefreshTransientFailure (network/5xx) does NOT count toward
///              the 3-strike expiredHard cap; only the 60s wall-clock cap
///              trips it. RefreshHardReject (4xx / malformed body) counts
///              as before. Pre-this-fix every DioException was equal weight
///              so a 7s network blip wrongly bounced users to /welcome —
///              pajooman003 Galaxy hit at UTC 10:55 with no server-side
///              refresh request reaching the server, recovered manually
///              via swipe-restart cold-start re-auth 5 minutes later.)
///
/// @functions
///  - TokenSnapshot: in-memory immutable JWT pair + exp + version
///  - TokenEvent: hydrated / login / refreshed / expiredHard / logout broadcast
///  - TokenManager.ensureFresh(): mutex-safe refresh entry — 모든 caller 의 단일 진입
///  - TokenManager.hydrateFromStorage(): cold boot 시 legacy → v2 마이그레이션 포함
///  - TokenManager.setFromLogin(): authenticate() 결과를 SSoT 에 주입
///  - TokenManager.clear(): logout / expiredHard 후 wipe + cancel timer
///  - TokenManager.isMainIsolateOwner(): IsolateNameServer 가드 (BG isolate 차단)
///  - TokenManager._decodeExpAt(): JWT payload 의 exp claim → DateTime
///  - TokenManager._scheduleProactive(): exp - now - 0.2 × ttl 시점 Timer

library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate' show ReceivePort;
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';

import '../storage/secure_storage.dart';

/// Storage layout v2: single key, JSON envelope.
const String _kStorageKey = 'auth_tokens_v2';

/// Legacy slots — read for migration, then deleted.
const String _kLegacyAccessKey = 'auth_token';
const String _kLegacyRefreshKey = 'auth_refresh_token';

/// IsolateNameServer port name. main isolate registers in main.dart;
/// BG isolate looks up — null result = refuse refresh.
const String _kMainOwnerPort = 'main_token_owner';

/// 5-minute "near expiry" window — `ensureFresh` returns the cached snapshot
/// only if `accessExpAt - now > 5min`. Below this, force a refresh.
const Duration _kFreshThreshold = Duration(minutes: 5);

/// Proactive timer fires at `accessExpAt - now - 0.2 × ttl`. For 1h TTL the
/// scheduling delta is `60 - 12 = 48` minutes after issuance.
const double _kProactiveAdvanceRatio = 0.2;

/// Backoff base — 1s, 2s, 4s on attempts 1, 2, 3.
const Duration _kBackoffUnit = Duration(seconds: 1);

/// Max HARD-reject attempts before declaring the refresh dead and emitting
/// expiredHard. "Hard reject" = the server explicitly refused the refresh
/// (e.g. 401 family revoked, 400 malformed). Transient failures (network
/// timeout, 5xx, no-response DioException) do NOT count toward this cap —
/// they only trip the wall-clock cap below.
const int _kMaxAttempts = 3;

/// Wall-clock cap on TRANSIENT failures (network unreachable / 5xx). If the
/// cumulative time spent retrying transient errors exceeds this, the refresh
/// gives up and emits expiredHard. Past this threshold the device is most
/// likely offline for an extended period; the caller (HTTP request / socket
/// connect) abandoning is healthier than infinite background retry.
///
/// 2026-05-07 — added so a brief network blip on Galaxy/iPhone wakeup does
/// not bounce the user all the way to onboarding. Pre-this fix any 3
/// consecutive DioException (no-response) within ~7s (1+2+4 backoff) emitted
/// expiredHard regardless of cause; pajooman003 hit this exact path at UTC
/// 10:55, recovered manually 5 minutes later via swipe-restart cold-start.
const Duration _kTransientWallCap = Duration(seconds: 60);

/// Immutable snapshot of the current JWT pair. `toString()` redacts the raw
/// access/refresh material so accidental debugPrint does not leak. Construct
/// only via the named factories so the JWT exp claim decode is uniform.
@immutable
class TokenSnapshot {
  /// JWT access token (Bearer header value).
  final String access;

  /// JWT refresh token — long-lived (30d).
  final String refresh;

  /// Expiry instant decoded from access JWT `exp` claim.
  final DateTime accessExpAt;

  /// Monotonic counter — bumped on every successful login / refresh. Useful
  /// for downstream listeners to detect "the same access string was rotated"
  /// (rare but possible if server returns the same token within the same
  /// second).
  final int version;

  const TokenSnapshot({
    required this.access,
    required this.refresh,
    required this.accessExpAt,
    required this.version,
  });

  /// Decode JWT exp claim from raw access token. JWT format: `header.payload.signature`,
  /// base64url-decoded payload contains `exp` (unix seconds).
  static DateTime decodeExpAt(String accessToken) {
    final parts = accessToken.split('.');
    if (parts.length != 3) {
      throw const FormatException('Invalid JWT — expected 3 parts');
    }
    final payloadStr = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final payload = json.decode(payloadStr) as Map<String, dynamic>;
    final expSec = payload['exp'];
    if (expSec is! int) {
      throw const FormatException('JWT missing/invalid `exp` claim');
    }
    return DateTime.fromMillisecondsSinceEpoch(expSec * 1000, isUtc: true);
  }

  /// Construct from a freshly-issued JWT pair (login or refresh response).
  /// `version` should be the previous snapshot's version + 1, or 1 for first.
  factory TokenSnapshot.fromTokens({
    required String access,
    required String refresh,
    required int version,
  }) {
    return TokenSnapshot(
      access: access,
      refresh: refresh,
      accessExpAt: decodeExpAt(access),
      version: version,
    );
  }

  /// JSON envelope written to secure storage under `auth_tokens_v2`.
  Map<String, dynamic> toJson() => {
        'access': access,
        'refresh': refresh,
        'accessExpAt': accessExpAt.millisecondsSinceEpoch,
        'version': version,
      };

  factory TokenSnapshot.fromJson(Map<String, dynamic> j) {
    final accessStr = j['access'] as String;
    final refreshStr = j['refresh'] as String;
    final expMs = j['accessExpAt'] as int?;
    final ver = j['version'] as int? ?? 1;
    return TokenSnapshot(
      access: accessStr,
      refresh: refreshStr,
      // Prefer the server-decoded exp; fall back to re-decoding the JWT if
      // the stored field is missing (very old format).
      accessExpAt: expMs != null
          ? DateTime.fromMillisecondsSinceEpoch(expMs, isUtc: true)
          : decodeExpAt(accessStr),
      version: ver,
    );
  }

  /// Brief, non-leaky representation. The access prefix is shown only as the
  /// first 8 chars so logs can correlate refresh events without exposing the
  /// full bearer string.
  String get accessPrefix =>
      access.length > 8 ? access.substring(0, 8) : access;

  @override
  String toString() =>
      'TokenSnapshot(*REDACTED*, prefix=$accessPrefix, exp=$accessExpAt, v=$version)';

  @override
  bool operator ==(Object other) =>
      other is TokenSnapshot &&
      other.access == access &&
      other.refresh == refresh &&
      other.version == version;

  @override
  int get hashCode => Object.hash(access, refresh, version);
}

/// TokenEvent broadcast type. Listeners filter via `event.type ==`.
enum TokenEventType {
  /// hydrateFromStorage() loaded a stored snapshot (cold boot path).
  hydrated,

  /// setFromLogin() injected a fresh authenticate() result (onboarding).
  login,

  /// _doRefresh() succeeded — snapshot rotated.
  refreshed,

  /// 3x refresh exhausted — caller MUST re-authenticate. Snapshot cleared.
  expiredHard,

  /// clear() invoked (explicit logout).
  logout,
}

/// Single broadcast envelope. `snapshot` is null for `expiredHard` and
/// `logout`. `reason` is a free-form debug hint ("pre-flight" / "socket-connect"
/// / "proactive" / "resume" / "refresh failed 3x").
class TokenEvent {
  final TokenEventType type;
  final String? reason;
  final TokenSnapshot? snapshot;

  const TokenEvent._(this.type, {this.reason, this.snapshot});

  factory TokenEvent.hydrated(TokenSnapshot s) =>
      TokenEvent._(TokenEventType.hydrated, snapshot: s);

  factory TokenEvent.login(TokenSnapshot s) =>
      TokenEvent._(TokenEventType.login, snapshot: s);

  factory TokenEvent.refreshed({required String reason, TokenSnapshot? snapshot}) =>
      TokenEvent._(TokenEventType.refreshed, reason: reason, snapshot: snapshot);

  factory TokenEvent.expiredHard({required String reason}) =>
      TokenEvent._(TokenEventType.expiredHard, reason: reason);

  factory TokenEvent.logout() => const TokenEvent._(TokenEventType.logout);

  @override
  String toString() =>
      'TokenEvent(${type.name}, reason=$reason, snapshot=$snapshot)';
}

/// Refresh signature — caller supplies the actual HTTP refresh implementation.
/// The function receives the current refresh token and must return the next
/// snapshot (with rotated access + refresh). The function MUST throw on
/// failure; the manager handles backoff + retry.
///
/// 2026-05-07 — failures must be classified as either [RefreshTransientFailure]
/// (network-side / server outage — retry without counting toward exhaustion)
/// or [RefreshHardReject] (server explicitly refused — count toward the
/// 3-strike expiredHard cap). Anything else thrown is treated as a hard
/// reject (defensive default). The actual classifier lives in the closure
/// at `app/lib/app/providers.dart:tokenManagerProvider` so this layer stays
/// HTTP-library-agnostic.
typedef RefreshFn = Future<TokenSnapshot> Function(String refresh);

/// Network-side or transient server failure during a refresh attempt. The
/// manager will retry these without counting toward `_kMaxAttempts`, capping
/// only on cumulative wall-clock time (`_kTransientWallCap`).
///
/// Use for: DioException with no response (connectionError, *Timeout, cancel),
/// 5xx server responses, plain SocketException, etc.
class RefreshTransientFailure implements Exception {
  final Object cause;
  final StackTrace? causeStack;
  const RefreshTransientFailure(this.cause, [this.causeStack]);
  @override
  String toString() => 'RefreshTransientFailure(cause=${cause.runtimeType})';
}

/// Server-side explicit rejection of the refresh — the token is presumed
/// invalid (rotated by another device, family revoked, malformed, etc.).
/// Counts toward `_kMaxAttempts` and triggers expiredHard on exhaustion.
class RefreshHardReject implements Exception {
  final Object cause;
  final StackTrace? causeStack;
  final int? statusCode;
  const RefreshHardReject(this.cause, {this.statusCode, this.causeStack});
  @override
  String toString() =>
      'RefreshHardReject(status=$statusCode, cause=${cause.runtimeType})';
}

/// SSoT for JWT lifecycle. Constructed once at app start (Riverpod KeepAlive).
/// All HTTP/Socket/Push paths route through `ensureFresh()`.
class TokenManager {
  final SecureStorageService _storage;
  final RefreshFn _refreshFn;

  TokenSnapshot? _current;

  /// Mutex — `ensureFresh` does `_inflight ??= _doRefresh(...)` so 100
  /// concurrent callers end up awaiting the same Future. CRITICAL: there
  /// MUST be no `await` between the `_current` check and the `_inflight ??=`
  /// assignment, otherwise two callers can race past the cache check and
  /// each fire `_doRefresh`. Hence `ensureFresh` is intentionally
  /// non-async — it returns Future synchronously.
  Future<TokenSnapshot>? _inflight;

  /// Proactive timer — only meaningful in FG. Cancelled on background
  /// (Timer naturally fires later if process survives). Re-armed on every
  /// successful refresh.
  Timer? _proactiveTimer;

  final StreamController<TokenEvent> _events =
      StreamController<TokenEvent>.broadcast();

  bool _disposed = false;

  TokenManager({
    required SecureStorageService storage,
    required RefreshFn refreshFn,
  })  : _storage = storage,
        _refreshFn = refreshFn;

  // ── Sync getters ─────────────────────────────────────────────────────

  /// Current in-memory snapshot. Null = unauthenticated.
  TokenSnapshot? get snapshot => _current;

  /// True iff an access token is loaded AND not yet past its decoded expiry.
  /// Use this for cheap pre-checks; `ensureFresh()` is the real entry.
  bool get hasValidToken {
    final s = _current;
    if (s == null) return false;
    return s.accessExpAt.isAfter(DateTime.now().toUtc());
  }

  /// Broadcast stream — listeners survive multiple subscribers.
  Stream<TokenEvent> get events => _events.stream;

  // ── Mutex-safe refresh entry ─────────────────────────────────────────

  /// Returns a snapshot that is GUARANTEED fresh for at least
  /// [_kFreshThreshold] (5 min). If the cached snapshot already satisfies that,
  /// returns it synchronously (Future.value). Otherwise enters the mutex.
  ///
  /// CRITICAL: this method MUST stay non-async. Inserting `await` between the
  /// cache check and the `_inflight ??=` assignment opens a race window.
  Future<TokenSnapshot> ensureFresh({required String reason}) {
    final s = _current;
    if (s != null &&
        s.accessExpAt.difference(DateTime.now().toUtc()) > _kFreshThreshold) {
      return Future.value(s);
    }
    if (s == null) {
      // Nothing to refresh — caller must invoke setFromLogin() first.
      return Future.error(
        StateError('ensureFresh($reason) called with no snapshot — login required'),
      );
    }
    // BG isolate guard. If main isolate didn't register the port name,
    // we are running in an FCM bg handler / equivalent — refuse so we
    // don't double-refresh and clobber main isolate's state.
    if (!isMainIsolateOwnerSync()) {
      return Future.error(
        StateError('ensureFresh($reason) refused — not main isolate owner'),
      );
    }
    // ⚠ NO AWAIT before the assign — race-free.
    return _inflight ??= _doRefresh(reason);
  }

  /// Internal refresh loop. 3 attempts with 1s, 2s, 4s backoff. On final
  /// failure: emits `expiredHard`, clears state, rethrows so the caller
  /// (HTTP request / socket connect) sees the error.
  ///
  /// 2026-05-07 — failure classification is two-track:
  /// * [RefreshHardReject] (4xx, malformed response, etc.) — increments the
  ///   hard-attempt counter; expiredHard fires after `_kMaxAttempts` strikes.
  /// * [RefreshTransientFailure] (network unreachable, 5xx, request cancel)
  ///   — does NOT increment the hard counter; only the wall-clock cap
  ///   (`_kTransientWallCap`) trips expiredHard. This stops a brief network
  ///   blip from bouncing the user to /welcome (pajooman003 incident
  ///   2026-05-07 UTC 10:55 — Galaxy hit expiredHard with no server-side
  ///   refresh request reaching the server, manual recovery only via
  ///   swipe-restart cold-start 5 minutes later).
  ///
  /// Anything else thrown by `_refreshFn` is treated as a hard reject
  /// (defensive — unknown errors shouldn't keep the user offline forever).
  Future<TokenSnapshot> _doRefresh(String reason) async {
    int hardAttempts = 0;
    DateTime? transientStartedAt;
    try {
      while (true) {
        try {
          final cur = _current;
          if (cur == null) {
            throw StateError('refresh: snapshot disappeared mid-flight');
          }
          final next = await _refreshFn(cur.refresh);
          _current = next;
          await _saveAtomic();
          _scheduleProactive();
          if (!_disposed) {
            _events.add(TokenEvent.refreshed(reason: reason, snapshot: next));
          }
          if (kDebugMode) {
            debugPrint(
                '[TokenManager] refreshed reason=$reason prefix=${next.accessPrefix} v=${next.version}');
          }
          return next;
        } catch (e, st) {
          final isTransient = e is RefreshTransientFailure;
          if (isTransient) {
            transientStartedAt ??= DateTime.now();
            final elapsed = DateTime.now().difference(transientStartedAt);
            if (kDebugMode) {
              debugPrint(
                  '[TokenManager] refresh transient: ${e.runtimeType} '
                  'elapsed=${elapsed.inSeconds}s/${_kTransientWallCap.inSeconds}s');
            }
            if (elapsed >= _kTransientWallCap) {
              if (!_disposed) {
                _events.add(TokenEvent.expiredHard(
                  reason:
                      'refresh transient > ${_kTransientWallCap.inSeconds}s',
                ));
              }
              await _clearInternal(emitLogout: false);
              Error.throwWithStackTrace(e, st);
            }
            // Fixed 2s backoff for transient — keep the retry quiet but
            // responsive. Network blips usually clear within seconds.
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          // Hard reject — server explicitly refused, or unknown error.
          hardAttempts++;
          if (kDebugMode) {
            debugPrint(
                '[TokenManager] refresh hard attempt $hardAttempts/$_kMaxAttempts: ${e.runtimeType}');
          }
          if (hardAttempts >= _kMaxAttempts) {
            if (!_disposed) {
              _events.add(TokenEvent.expiredHard(
                reason: 'refresh hard-rejected ${_kMaxAttempts}x',
              ));
            }
            await _clearInternal(emitLogout: false);
            Error.throwWithStackTrace(e, st);
          }
          // Exponential backoff for hard rejects: 1s, 2s, 4s.
          final waitMs =
              _kBackoffUnit.inMilliseconds * (1 << (hardAttempts - 1));
          await Future<void>.delayed(Duration(milliseconds: waitMs));
        }
      }
    } finally {
      _inflight = null;
    }
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  /// Cold-boot loader. Reads `auth_tokens_v2` first; if absent, reads legacy
  /// (`auth_token` + `auth_refresh_token`) and re-saves as bundled JSON +
  /// deletes legacy slots (one-time migration). Emits `hydrated` on success.
  Future<void> hydrateFromStorage() async {
    if (_current != null) return; // idempotent

    // Try v2 envelope.
    final raw = await _storage.read(_kStorageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = json.decode(raw) as Map<String, dynamic>;
        final s = TokenSnapshot.fromJson(j);
        _current = s;
        _scheduleProactive();
        if (!_disposed) _events.add(TokenEvent.hydrated(s));
        if (kDebugMode) {
          debugPrint(
              '[TokenManager] hydrated v2 prefix=${s.accessPrefix} v=${s.version}');
        }
        return;
      } catch (e) {
        debugPrint('[TokenManager] v2 parse failed — falling through to legacy: $e');
        // Fall through to legacy migration.
      }
    }

    // Legacy migration. Read both old slots; if either present, attempt to
    // build a snapshot and persist as v2 + delete legacy slots.
    final legacyAccess = await _storage.read(_kLegacyAccessKey);
    final legacyRefresh = await _storage.read(_kLegacyRefreshKey);
    if (legacyAccess == null ||
        legacyAccess.isEmpty ||
        legacyRefresh == null ||
        legacyRefresh.isEmpty) {
      // No tokens at all — fresh install or post-logout. Stay null.
      return;
    }
    try {
      final s = TokenSnapshot.fromTokens(
        access: legacyAccess,
        refresh: legacyRefresh,
        version: 1,
      );
      _current = s;
      await _saveAtomic();
      // Best-effort delete of legacy slots so they don't shadow next boot.
      try {
        await _storage.delete(_kLegacyAccessKey);
      } catch (_) {/* non-fatal */}
      try {
        await _storage.delete(_kLegacyRefreshKey);
      } catch (_) {/* non-fatal */}
      _scheduleProactive();
      if (!_disposed) _events.add(TokenEvent.hydrated(s));
      if (kDebugMode) {
        debugPrint(
            '[TokenManager] hydrated via legacy migration prefix=${s.accessPrefix}');
      }
    } catch (e) {
      debugPrint('[TokenManager] legacy migration failed (will not crash): $e');
      // Leave _current null — caller will redirect to onboarding.
    }
  }

  /// Inject a freshly-issued snapshot from `AuthService.authenticate()`.
  /// Bumps version (or sets to 1 if first). Persists + emits `login`.
  Future<void> setFromLogin(TokenSnapshot s) async {
    final prev = _current;
    final next = TokenSnapshot(
      access: s.access,
      refresh: s.refresh,
      accessExpAt: s.accessExpAt,
      version: prev != null ? prev.version + 1 : (s.version > 0 ? s.version : 1),
    );
    _current = next;
    await _saveAtomic();
    _scheduleProactive();
    if (!_disposed) _events.add(TokenEvent.login(next));
  }

  /// Explicit logout / wipe. Emits `logout` so listeners can navigate.
  Future<void> clear() async {
    await _clearInternal(emitLogout: true);
  }

  Future<void> _clearInternal({required bool emitLogout}) async {
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
    _current = null;
    try {
      await _storage.delete(_kStorageKey);
    } catch (_) {/* non-fatal */}
    // Also wipe legacy slots in case migration didn't.
    try {
      await _storage.delete(_kLegacyAccessKey);
    } catch (_) {/* non-fatal */}
    try {
      await _storage.delete(_kLegacyRefreshKey);
    } catch (_) {/* non-fatal */}
    if (emitLogout && !_disposed) _events.add(TokenEvent.logout());
  }

  /// Cleanup — call on Riverpod dispose. Rare in production (KeepAlive) but
  /// matters for tests + hot-restart.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _proactiveTimer?.cancel();
    _proactiveTimer = null;
    _inflight = null;
    _events.close();
  }

  // ── Internal helpers ─────────────────────────────────────────────────

  Future<void> _saveAtomic() async {
    final s = _current;
    if (s == null) return;
    final body = json.encode(s.toJson());
    // SecureStorage's underlying flutter_secure_storage write is itself a
    // single platform-channel call — atomic at the storage layer. Single
    // key = atomic at the application layer too. No write-then-write pair.
    await _storage.write(_kStorageKey, body);
  }

  /// Schedule a proactive refresh at `accessExpAt - now - 0.2 × ttl`. For a
  /// 1h JWT, that's ~48 minutes after issuance. Never schedules a negative
  /// delay (if already past the threshold, fires next event-loop tick — but
  /// the cache check in ensureFresh handles the actual decision).
  void _scheduleProactive() {
    _proactiveTimer?.cancel();
    final s = _current;
    if (s == null) return;
    final now = DateTime.now().toUtc();
    final ttl = s.accessExpAt.difference(now);
    if (ttl.isNegative || ttl.inSeconds <= 0) {
      // Already expired — let the next ensureFresh handle it.
      return;
    }
    final advanceMs = (ttl.inMilliseconds * _kProactiveAdvanceRatio).round();
    final fireDelay = ttl - Duration(milliseconds: advanceMs);
    if (fireDelay.isNegative) return;
    _proactiveTimer = Timer(fireDelay, () async {
      // Fire-and-forget. The expiredHard event was already emitted by
      // _doRefresh on exhaustion; the listener (app.dart +267) handles
      // user-visible recovery. We swallow the error here because this
      // future has no caller waiting on it — rethrowing only produces
      // an unhandled async exception. 2026-05-07 — pre-fix the
      // .catchError did `return _current ?? (throw e)` which became
      // unhandled when _doRefresh had just cleared _current as part of
      // exhaustion (Galaxy logcat 22:14:49.425).
      try {
        await ensureFresh(reason: 'proactive');
      } catch (e) {
        debugPrint('[TokenManager] proactive refresh failed: $e');
      }
    });
  }

  // ── BG isolate guard ─────────────────────────────────────────────────

  /// Sync version — checks IsolateNameServer registration. main isolate
  /// registers in main.dart. BG isolates (FCM bg handler, audio service, …)
  /// do NOT register, so this returns false there → ensureFresh refuses.
  static bool isMainIsolateOwnerSync() {
    try {
      final port = IsolateNameServer.lookupPortByName(_kMainOwnerPort);
      return port != null;
    } catch (_) {
      // In flutter_test the IsolateNameServer is available but lookup may
      // throw on some platforms. Default to true so unit tests can run.
      return true;
    }
  }

  /// Async wrapper — kept for spec compatibility. Returns the same as the
  /// sync version.
  static Future<bool> isMainIsolateOwner() async => isMainIsolateOwnerSync();

  /// Register the main-isolate marker port. Call ONCE from main.dart before
  /// running the app. Idempotent — safe to call after hot-restart.
  static void registerMainIsolateOwner() {
    try {
      final existing = IsolateNameServer.lookupPortByName(_kMainOwnerPort);
      if (existing != null) {
        // Hot-restart path — old port is dead but lookup still returns it.
        // Remove and re-register so the new isolate is recognised.
        IsolateNameServer.removePortNameMapping(_kMainOwnerPort);
      }
      final port = ReceivePort();
      final ok = IsolateNameServer.registerPortWithName(
        port.sendPort,
        _kMainOwnerPort,
      );
      if (!ok) {
        debugPrint('[TokenManager] registerMainIsolateOwner — register returned false');
      }
    } catch (e) {
      debugPrint('[TokenManager] registerMainIsolateOwner failed: $e');
    }
  }
}
