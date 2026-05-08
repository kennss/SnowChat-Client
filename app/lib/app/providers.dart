/// @file        providers.dart
/// @description Global Riverpod providers. DI for auth, crypto, network, storage, Solana network services.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-03 (Phase 11 — TokenManager 도입. authTokenProvider →
///              tokenSnapshotProvider 로 derived. tokenManagerProvider KeepAlive
///              SSoT. AuthService 의 onTokenRefresh callback 폐기. socket /
///              push token sync 도 events stream 으로 listen)
/// @note SolanaNetwork enum is defined in solana_config.dart and re-exported here
///
/// @functions
///  - isOnboardedProvider: onboarding completion state provider
///  - isLockedProvider: app PIN lock state provider
///  - secureStorageProvider: SecureStorageService provider
///  - signalProtocolServiceProvider: SignalProtocolService provider
///  - identityManagerProvider: IdentityManager provider
///  - currentSnowIdProvider: current user SnowChat ID state provider
///  - apiClientProvider: ApiClient provider
///  - authServiceProvider: AuthService provider
///  - tokenManagerProvider: SSoT for JWT lifecycle (Phase 11, KeepAlive)
///  - tokenSnapshotProvider: derived sync StateProvider exposing current TokenSnapshot
///  - authTokenProvider: legacy compat — projects tokenSnapshot.access (read-only)
///  - socketManagerProvider: SocketManager provider
///  - snowDatabaseProvider: SnowDatabase provider
///  - messageDaoProvider: MessageDao provider (drift DB SSoT)
///  - conversationDaoProvider: ConversationDao provider (drift DB SSoT)
///  - sessionStoreProvider: SessionStore provider
///  - signalSessionManagerProvider: SignalSessionManager provider
///  - groupSessionManagerProvider: GroupSessionManager provider
///  - fileServiceProvider: FileService provider
///  - encryptedMessageHandlerProvider: EncryptedMessageHandler provider
///  - notificationServiceProvider: NotificationService provider
///  - pushServiceProvider: PushService provider
///  - pushTokenAutoSyncProvider: auto-registers the FCM token whenever authToken transitions to non-null (fresh signup / restore / login / restart)
///  - presenceServiceProvider: PresenceService provider
///  - linkPreviewServiceProvider: LinkPreviewService provider
///  - solanaNetworkProvider: Solana network (Devnet/Mainnet) state provider
///  - solanaConfigProvider: SolanaConfig provider for the current network
///  - transferEventBusProvider: Wallet V2 — chat transfer event broadcast bus (Phase B)

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/call/call_service.dart';
import '../core/call/call_signaling.dart';
import '../core/call/callkit_manager.dart';
import '../core/call/turn_credential_manager.dart';
import '../core/crypto/encrypted_message_handler.dart';
import '../core/crypto/identity_change_handler.dart';
import '../features/call/providers/call_provider.dart';

// Phase 8.2: re-export CallState/CallStatus/CallNotifier so screens don't need
// to import call_provider.dart directly.
export '../features/call/providers/call_provider.dart' show CallState, CallStatus, CallNotifier;
import '../core/crypto/sealed_sender.dart';
import '../core/crypto/sender_certificate_manager.dart';
import '../features/chat/providers/expiring_message_manager.dart';
import '../core/crypto/group_session_manager.dart';
import '../core/messaging/global_message_router.dart';
import '../core/messaging/message_queue.dart';
import '../core/call/voip_push_service.dart';
import '../core/network/voip_native_bridge.dart';
import '../core/notifications/notification_service.dart';
import '../core/notifications/push_service.dart';
import '../core/crypto/identity_manager.dart';
import '../core/crypto/identity_pin_store.dart';
import '../core/crypto/session_store.dart';
import '../core/crypto/signal_protocol_service.dart';
import '../core/crypto/signal_session_manager.dart';
import '../core/network/api_client.dart';
import '../core/network/api_endpoints.dart';
import '../core/network/file_service.dart';
import '../core/network/link_preview_service.dart';
import '../core/network/presence_service.dart';
import '../core/network/socket_manager.dart';
import '../core/network/auth_service.dart';
import '../core/network/token_manager.dart';
import '../core/storage/database.dart';
import '../core/storage/daos/message_dao.dart';
import '../core/storage/daos/conversation_dao.dart';
import '../core/storage/daos/attachment_dao.dart';
import '../core/storage/daos/ai_message_dao.dart';
import '../core/storage/daos/identity_verification_dao.dart';
import '../core/storage/secure_storage.dart';
import '../features/settings/settings_provider.dart';
import '../features/wallet/services/transfer_event_bus.dart';
import '../features/wallet/services/transfer_service.dart';

// --- Solana network ---
// Re-export SolanaNetwork — canonical definition in rpc_config.dart.
export '../features/wallet/rpc/rpc_config.dart' show SolanaNetwork;

import '../features/wallet/rpc/rpc_config.dart' show SolanaNetwork;

final solanaNetworkProvider = StateProvider<SolanaNetwork>((ref) {
  return SolanaNetwork.devnet;
});

// --- Onboarding state ---
final isOnboardedProvider = StateProvider<bool>((ref) => false);

// --- App lock state ---
/// True when the app is locked and requires PIN entry to continue.
/// Set to true on app start if a PIN exists; set to false after successful verification.
final isLockedProvider = StateProvider<bool>((ref) => false);

/// Phase 8.7 round 5: true when this device has an identity but no PIN
/// stored in secure storage. The router redirects such devices to the
/// PIN-setup screen instead of /chat — without this guard, restoring an
/// existing identity (where the restore flow already skips setup-profile)
/// landed straight in the main app with no PIN, and every subsequent
/// process restart bypassed the lock screen.
final requiresPinSetupProvider = StateProvider<bool>((ref) => false);

// --- App startup initialization ---
/// Checks secure storage for existing identity, authenticates with server,
/// and ONLY THEN hydrates app state (isOnboarded, isLocked).
/// Must complete before the router is created.
///
/// Flow:
///   1. hasIdentity? → false → /welcome (fresh install)
///   2. authenticate() → 404 → /welcome (server DB reset)
///   3. authenticate() → 403 → /welcome (multi-device block)
///   4. authenticate() → network error → offline mode (show chat, can't send)
///   5. authenticate() → success → set isOnboarded/isLocked → initialize E2EE
final appStartupProvider = FutureProvider<bool>((ref) async {
  final identityManager = ref.read(identityManagerProvider);
  final secureStorage = ref.read(secureStorageProvider);

  // Step 0: iOS Keychain fresh-install detection (Phase 8.7 TODO #8).
  //
  // Apple's Keychain preserves items across app uninstall for every
  // accessibility class — deliberate Apple behavior that breaks our
  // "uninstall = wipe all sensitive data" assumption. Android's
  // EncryptedSharedPreferences does NOT preserve, so this is a no-op there.
  //
  // Technique: the application documents directory IS wiped on uninstall
  // on both platforms. We drop a plain-text install marker there. If the
  // marker file is missing on startup but Keychain has stale entries from
  // a previous install, we know this is a fresh install and must clear
  // the Keychain before the flow below reads any stored identity / PIN.
  //
  // Without this, a malicious holder of a lost iPhone could:
  //   (1) uninstall the app to bypass PIN,
  //   (2) reinstall — Keychain still has identity + PIN,
  //   (3) brute-force the PIN (6-digit, 30s lockout after 5 attempts),
  //   (4) walk into the full chat history + mnemonic + wallet.
  // With this, step (2) restarts the user in a true fresh-install state.
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final markerFile = File(p.join(docsDir.path, 'install_marker'));
    if (!await markerFile.exists()) {
      // Marker missing ⇒ app documents dir was wiped ⇒ fresh install.
      // Before we let appStartup observe stale identity, purge secure
      // storage. On Android this is a no-op (secure storage is already
      // empty after uninstall). On iOS this is the actual cleanup.
      try {
        await secureStorage.deleteAll();
        debugPrint('[AppStartup] Fresh install detected — '
            'secure storage purged (iOS Keychain cleanup)');
      } catch (e) {
        debugPrint('[AppStartup] deleteAll during fresh-install '
            'cleanup failed (non-fatal): $e');
      }
      // Write the marker so subsequent launches are recognised as normal
      // restarts, not fresh installs.
      try {
        await markerFile.writeAsString(
          DateTime.now().toUtc().toIso8601String(),
          flush: true,
        );
      } catch (e) {
        debugPrint('[AppStartup] install_marker write failed '
            '(non-fatal): $e');
      }
    }
  } catch (e) {
    // path_provider itself failing is rare; proceed without cleanup rather
    // than blocking onboarding. Real fresh-install still behaves correctly
    // because identity / PIN are absent on Android, and iOS will just
    // retry on next launch.
    debugPrint('[AppStartup] install marker check failed '
        '(non-fatal): $e');
  }

  // Phase 11 (2026-05-04 fresh-install fix): wire authTokenSyncProvider
  // BEFORE the no-identity early return. Previously the wire happened only
  // on the existing-identity branch (line moved here), so a fresh install
  // returned with the bridge inert → tokenManager.setFromLogin() during
  // onboarding updated tokenSnapshotProvider but the bridge never propagated
  // to authTokenProvider → sealedSenderAutoInitProvider's
  // `ref.watch(authTokenProvider)` stayed null → SealedSenderService never
  // activated → callSignalingProvider null → callServiceProvider null →
  // callProvider became `_IdleCallNotifier` → `_UnavailableCallService`
  // throws on startCall: "VoIP not initialized — SealedSender service
  // unavailable". Messaging worked because the legacy non-sealed E2EE path
  // does not require sealedSenderService. App restart "fixed" it because the
  // identity now exists and the original line-212 wire fires. User-reported
  // 2026-05-04 (fresh iPhone 13 install + Kennt onboarding + 통화 실패).
  ref.read(authTokenSyncProvider);

  // Step 1: Check local identity exists
  final hasId = await identityManager.hasIdentity();
  if (!hasId) {
    debugPrint('[AppStartup] No identity found — fresh install');
    return false;
  }

  final snowId = await identityManager.getSnowChatId();
  debugPrint('[AppStartup] Identity found: $snowId');

  // Step 1.5 (Phase 11): hydrate TokenManager from storage. Restores a
  // previously-saved snapshot (v2 envelope or legacy slot migration) so the
  // ensureFresh path can pick up where we left off without forcing a full
  // re-authenticate.
  final tokenManager = ref.read(tokenManagerProvider);
  await tokenManager.hydrateFromStorage();

  // Step 2: Authenticate with server (BEFORE setting any app state)
  // Skip if a token already exists (hydrated or previously set by onboarding).
  final existingSnap = tokenManager.snapshot;
  if (existingSnap != null) {
    debugPrint('[AppStartup] Auth snapshot present — skipping authenticate '
        '(prefix=${existingSnap.accessPrefix})');
  } else {
    try {
      final authService = ref.read(authServiceProvider);
      final snap = await authService.authenticate();
      await tokenManager.setFromLogin(snap);
      debugPrint('[AppStartup] Auth restored');
    } catch (e) {
      debugPrint('[AppStartup] Auth restore failed: $e');
      final statusCode = e is DioException ? e.response?.statusCode : null;

      if (statusCode == 404 || statusCode == 403) {
        // 404: Server DB reset — user doesn't exist → re-onboard
        // 403: Multi-device block — can't proceed → re-onboard
        debugPrint('[AppStartup] Server rejected ($statusCode) — resetting to onboarding');
        return false;
      }

      // Network error or other: proceed in offline mode
      // User can view old messages but can't send until reconnected
      debugPrint('[AppStartup] Proceeding in offline mode');
    }
  }

  // Step 3: Auth succeeded (or offline fallback) → NOW set app state
  final hasPin = await secureStorage.hasPin();
  ref.read(currentSnowIdProvider.notifier).state = snowId;
  // displayName initialization — attached as sender on VoIP call_invite payload.
  ref.read(currentDisplayNameProvider.notifier).state =
      await secureStorage.getDisplayName();
  ref.read(isOnboardedProvider.notifier).state = true;
  ref.read(isLockedProvider.notifier).state = hasPin;
  // Phase 8.7 round 5: if the identity exists but no PIN was set on this
  // device (restore flow could skip setup-profile when the user already
  // exists on the server), the router will redirect to /setup-profile so
  // the user MUST establish a PIN before reaching the main app.
  ref.read(requiresPinSetupProvider.notifier).state = !hasPin;

  // Step 4: Initialize E2EE (ensures identity key is on server)
  // Phase 11 fix: tokenManager.snapshot 직접 체크. authTokenProvider 는
  // tokenManagerProvider.events broadcast Stream 의 microtask-deferred
  // sync glue 라 hydrate 직후 sync read 시점에 아직 null 가능 → 이 분기
  // 통째 skip → sealedSenderAutoInit 안 fire → SealedSender unavailable
  // → VoIP 시도 시 _UnavailableCallService throw "Bad state: VoIP not
  // initialized — SealedSender service unavailable" 회귀.
  if (tokenManager.snapshot != null) {
    try {
      await ref.read(signalSessionManagerProvider).initialize();
      debugPrint('[AppStartup] E2EE initialized');
    } catch (e) {
      debugPrint('[AppStartup] E2EE init failed (non-fatal): $e');
    }

    // Step 4.5 — FCM token registration is handled by pushTokenAutoSyncProvider,
    // which watches authTokenProvider and re-registers whenever the token transitions
    // to non-null. Reading it here is the existing-session fallthrough so the same
    // path triggers on cold-boot with a restored session (mirrors sealedSender below).
    ref.read(pushTokenAutoSyncProvider);

    // Step 5 — SealedSender is handled by a separate auto-init provider
    // (sealedSenderAutoInitProvider) that watches authTokenProvider changes. Calling
    // it once here as fallthrough triggers it immediately on the existing-session
    // startup path too.
    ref.read(sealedSenderAutoInitProvider);

    // Step 6 — Wallet V2 Phase E2: in-flight transfer recovery.
    // For sender rows that never sent transfer_completed (status='sent' &&
    // signature non-null) due to app kill / network drop, query the RPC result
    // after the fact → emit transfer_completed retroactively (P0-1 persistence fix).
    // fire-and-forget — failures retry on the next startup (rows aged 1h+ are
    // auto-cleaned via timeout).
    Future<void>(() async {
      try {
        await ref.read(transferServiceProvider).recoverPending();
      } catch (e) {
        debugPrint('[AppStartup] transfer recoverPending failed (non-fatal): $e');
      }
    });
  }

  return true;
});

// --- Secure storage ---
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

// --- Identity Pin Store (Vuln 2 Stage A: TOFU pin for remote Ed25519 keys) ---
final identityPinStoreProvider = Provider<IdentityPinStore>((ref) {
  return IdentityPinStore(ref.read(secureStorageProvider));
});

// --- Signal Protocol Service (Pure Dart) ---
final signalProtocolServiceProvider = Provider<SignalProtocolService>((ref) {
  return SignalProtocolService(
    identityPinStore: ref.read(identityPinStoreProvider),
  );
});

// --- Identity ---
final identityManagerProvider = Provider<IdentityManager>((ref) {
  final manager = IdentityManager(ref.read(secureStorageProvider));
  manager.setSignalService(ref.read(signalProtocolServiceProvider));
  return manager;
});

// --- Current user SnowChat ID ---
final currentSnowIdProvider = StateProvider<String?>((ref) => null);

/// Current user displayName (nickname). Loaded by appStartupProvider from
/// secureStorage. Also updated via setDisplayName during onboarding.
/// Use site: sender identifier on VoIP call_invite payload (for receiver UI).
final currentDisplayNameProvider = StateProvider<String?>((ref) => null);

// --- Currently active (open) conversation ID ---
// Used to suppress unread badge while user is viewing the chat.
final activeConversationProvider = StateProvider<String?>((ref) => null);

// --- API client ---
final apiClientProvider = Provider<ApiClient>((ref) {
  // Phase 11: ApiClient now reads tokenManager via callback so it can pre-flight
  // ensureFresh() before every request and handle 401 retry without circular
  // provider creation.
  final client = ApiClient();
  client.tokenProvider = () => ref.read(tokenManagerProvider);
  return client;
});

// --- Auth ---
//
// Phase 11: AuthService no longer owns refresh logic. authenticate() returns a
// TokenSnapshot which the caller hands to TokenManager.setFromLogin(). All
// refresh / 401 / socket reconnect routes through TokenManager.ensureFresh().
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    apiClient: ref.read(apiClientProvider),
    identityManager: ref.read(identityManagerProvider),
    secureStorage: ref.read(secureStorageProvider),
  );
});

// --- TokenManager (Phase 11 SSoT, KeepAlive) ---
//
// Single source of truth for JWT lifecycle. Created once at app start; survives
// authToken null transitions (logout → re-login uses the same instance). The
// underlying refresh implementation hits POST /auth/refresh via Dio directly
// (separate Dio so we don't recurse through the interceptor).
//
// KeepAlive is critical: if a transient watcher disposes us mid-flight, the
// `_inflight` mutex disappears and a follow-up call would race a fresh refresh.
final tokenManagerProvider = Provider<TokenManager>((ref) {
  // Use a separate Dio instance for /auth/refresh so we never re-enter the
  // ApiClient interceptor (which itself would call ensureFresh and deadlock).
  final refreshDio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.getBaseUrl(),
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
  ));

  // Late binding lets the closure read `mgr.snapshot` without having to look
  // the provider up via `ref.read(tokenManagerProvider)` (which would form a
  // self-reference cycle and break Riverpod's type inference).
  late final TokenManager mgr;
  mgr = TokenManager(
    storage: ref.read(secureStorageProvider),
    refreshFn: (refresh) async {
      // 2026-05-07 — failure classification lives here so token_manager.dart
      // stays HTTP-library-agnostic. Transient (network unreachable / 5xx /
      // request cancel) → RefreshTransientFailure (manager retries without
      // counting toward exhaustion, only wall-clock cap trips expiredHard).
      // Server-explicit reject (4xx) → RefreshHardReject (counts toward
      // _kMaxAttempts). Anything else falls through as RefreshHardReject by
      // default (defensive). Pre-this-fix every DioException was treated
      // identically and 3× network blip in 7s wrongly bounced users to
      // /welcome — pajooman003 incident 2026-05-07 UTC 10:55.
      Response<dynamic> res;
      try {
        res = await refreshDio.post(
          ApiEndpoints.authRefresh,
          data: {'refreshToken': refresh},
        );
      } on DioException catch (e, st) {
        final code = e.response?.statusCode;
        if (e.response == null) {
          // No HTTP response landed at all — pure network-side failure.
          throw RefreshTransientFailure(e, st);
        }
        if (code != null && code >= 500 && code < 600) {
          // 5xx — server reachable but in trouble; retry as transient.
          throw RefreshTransientFailure(e, st);
        }
        // 4xx (or any other status) — server explicitly refused. Hard reject.
        throw RefreshHardReject(e, statusCode: code, causeStack: st);
      }
      try {
        final data = Map<String, dynamic>.from(res.data as Map);
        final access = data['token'] as String;
        final newRefresh = data['refreshToken'] as String;
        final prev = mgr.snapshot;
        return TokenSnapshot.fromTokens(
          access: access,
          refresh: newRefresh,
          version: (prev?.version ?? 0) + 1,
        );
      } catch (e, st) {
        // 200 OK 가 왔는데 body 가 예상한 모양이 아닌 케이스 — 서버 contract
        // 위반이니 hard reject 로 분류 (transient retry 의미 없음).
        throw RefreshHardReject(e,
            statusCode: res.statusCode, causeStack: st);
      }
    },
  );

  // Bridge events → tokenSnapshotProvider so widgets/legacy code that watch
  // authTokenProvider stay in sync.
  final sub = mgr.events.listen((event) {
    final next = mgr.snapshot;
    final notifier = ref.read(tokenSnapshotProvider.notifier);
    if (notifier.state?.version != next?.version ||
        notifier.state?.access != next?.access) {
      notifier.state = next;
    }
  });

  ref.onDispose(() {
    sub.cancel();
    mgr.dispose();
  });
  return mgr;
});

// --- Token snapshot (sync, derived) ---
//
// Phase 11: replaces the raw `authTokenProvider` with a typed snapshot.
// Sync read — widgets that just need "am I logged in?" check `state != null`.
// NOT autoDispose; lifetime matches tokenManagerProvider.
final tokenSnapshotProvider = StateProvider<TokenSnapshot?>((ref) => null);

// --- Auth token (legacy compat alias) ---
//
// Phase 11: kept as a writable StateProvider<String?> so legacy watchers
// (sealedSenderAutoInitProvider, pushTokenAutoSyncProvider, socketManager
// listener, conversation_list_provider, contact_provider) keep functioning
// without a sweeping rename. The init function seeds from tokenSnapshotProvider
// and the bridge listener (set up in authTokenSyncProvider below) keeps the
// two in sync going forward.
//
// Direct writes (`ref.read(authTokenProvider.notifier).state = token`) still
// work — they propagate "downstream" but do NOT update the SSoT TokenManager
// state. New code MUST call `tokenManager.setFromLogin(snapshot)` instead so
// the bridge listener pushes the snapshot through this provider too.
final authTokenProvider = StateProvider<String?>(
  (ref) => ref.read(tokenSnapshotProvider)?.access,
);

/// Authorization header for raw network calls that bypass the Dio interceptor
/// (Image.network on `/api/v2/files/:fileId` for channel/user avatars, etc.).
///
/// Phase 11 cut over moved Authorization injection from a Dio default header
/// to a per-request interceptor (`ApiClient.onRequest`). The previous pattern
/// `ref.read(apiClientProvider).dio.options.headers['Authorization']` now
/// reads null → Image.network sends no auth header → server `/files/:fileId`
/// returns 401 → `errorBuilder` fallback fires → user sees the initials
/// placeholder instead of the uploaded avatar (manifests as "save 가 안 됨"
/// because the upload + PUT both succeed but the next render cannot fetch
/// the file). Watching `tokenSnapshotProvider` here makes consumers rebuild
/// automatically on token rotation, so a refresh in flight does not leave a
/// stale header behind.
final authHeaderProvider = Provider<String?>((ref) {
  final snap = ref.watch(tokenSnapshotProvider);
  return snap != null ? 'Bearer ${snap.access}' : null;
});

// One-shot sync glue — listens to tokenSnapshotProvider and rewrites
// authTokenProvider on every change. Keep alive (KeepAlive) for the app
// lifetime so listeners never see stale values. Wired via app.dart's
// `ref.read(authTokenSyncProvider)`.
final authTokenSyncProvider = Provider<void>((ref) {
  ref.listen<TokenSnapshot?>(tokenSnapshotProvider, (prev, next) {
    final prevAccess = ref.read(authTokenProvider);
    final nextAccess = next?.access;
    if (prevAccess != nextAccess) {
      ref.read(authTokenProvider.notifier).state = nextAccess;
    }
  }, fireImmediately: true);
});

// --- Socket ---
//
// Phase 11: token state is owned by TokenManager. SocketManager exposes a
// `tokenProvider` callback so connect() can synchronously read the current
// access string. Refresh is delegated entirely to TokenManager — the socket's
// onConnectError JWT branch calls `tokenManager.ensureFresh()` and reconnects.
// expiredHard event drives logout via the events stream listener below.
final socketManagerProvider = Provider<SocketManager>((ref) {
  final tokenManager = ref.read(tokenManagerProvider);
  final initialSnap = ref.read(tokenSnapshotProvider);
  final manager = SocketManager(
    tokenProvider: () => tokenManager.snapshot?.access,
    ensureFreshToken: () async {
      try {
        final s = await tokenManager.ensureFresh(reason: 'socket-connect');
        return s.access;
      } catch (e) {
        debugPrint('[Socket] ensureFreshToken failed: $e');
        return null;
      }
    },
  );

  // Auto-connect if we already have a snapshot at creation (cold-boot path
  // when hydrateFromStorage ran first).
  if (initialSnap != null) {
    manager.connect();
  }

  // Listen for snapshot transitions (login / logout) to drive connect/disconnect.
  ref.listen<TokenSnapshot?>(tokenSnapshotProvider, (previous, next) {
    if (next != null && previous?.access != next.access) {
      if (!manager.isConnected) {
        manager.connect();
      }
    } else if (next == null) {
      manager.disconnect();
    }
  });

  // expiredHard from TokenManager → run logout-side effects + clear.
  final eventSub = tokenManager.events.listen((event) async {
    if (event.type == TokenEventType.expiredHard) {
      try {
        final authService = ref.read(authServiceProvider);
        await authService.logout();
      } catch (_) {/* best-effort */}
      // tokenManager.clear() already ran inside _doRefresh on expiredHard.
      manager.disconnect();
    }
  });

  ref.onDispose(() {
    eventSub.cancel();
    manager.dispose();
  });

  return manager;
});

// --- Local Database (Drift) ---
// File-based persistent database. Messages survive app restarts.
LazyDatabase _openDb() {
  return LazyDatabase(() async {
    final sw = Stopwatch()..start();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'snowchat.db'));
    final exists = await file.exists();
    debugPrint('[Perf] 💾 drift open start (exists=$exists)');
    final db = NativeDatabase.createInBackground(file);
    debugPrint('[Perf] 💾 drift LazyDatabase resolved: ${sw.elapsedMilliseconds}ms '
        '(onCreate/onUpgrade will run on first query)');
    return db;
  });
}

final snowDatabaseProvider = Provider<SnowDatabase>((ref) {
  final db = SnowDatabase(_openDb());
  ref.onDispose(() => db.close());
  return db;
});

// --- DAOs (drift DB SSoT access) ---
// Phase 1 Step 2a: DAO providers for direct drift DB access.
// These replace MessageStore as the primary data access layer.
final messageDaoProvider = Provider<MessageDao>((ref) {
  return ref.read(snowDatabaseProvider).messageDao;
});

final conversationDaoProvider = Provider<ConversationDao>((ref) {
  return ref.read(snowDatabaseProvider).conversationDao;
});

final attachmentDaoProvider = Provider<AttachmentDao>((ref) {
  return ref.read(snowDatabaseProvider).attachmentDao;
});

// --- Identity Verification DAO (P0-2: Safety Number 60-digit verification) ---
final identityVerificationDaoProvider = Provider<IdentityVerificationDao>((ref) {
  return ref.read(snowDatabaseProvider).identityVerificationDao;
});

// --- Identity Change Handler (P0-2 Stage B: TOFU mismatch pipeline) ---
//
// Centralized handler for IdentityKeyChangedException raised by
// SignalProtocolService when the TOFU pin store sees a new Ed25519 key
// for an existing peer. Recomputes Safety Number, latches the mismatch in
// IdentityVerificationDao, inserts a system message, and broadcasts an
// event for the chat banner.
final identityChangeHandlerProvider = Provider<IdentityChangeHandler>((ref) {
  final handler = IdentityChangeHandler(
    dao: ref.read(identityVerificationDaoProvider),
    messageDao: ref.read(messageDaoProvider),
    identityManager: ref.read(identityManagerProvider),
  );
  ref.onDispose(handler.dispose);
  return handler;
});

// --- AI Message DAO ---
final aiMessageDaoProvider = Provider<AiMessageDao>((ref) {
  return ref.read(snowDatabaseProvider).aiMessageDao;
});

// --- Expiring Message Manager (Signal pattern) ---
final expiringMessageManagerProvider =
    Provider<ExpiringMessageManager>((ref) {
  return ExpiringMessageManager(
    messageDao: ref.read(messageDaoProvider),
    attachmentDao: ref.read(attachmentDaoProvider),
  );
});

// --- Session Store (E2EE session persistence) ---
final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SessionStore(
    database: ref.read(snowDatabaseProvider),
    secureStorage: ref.read(secureStorageProvider),
  );
});

// --- Signal Session Manager ---
final signalSessionManagerProvider = Provider<SignalSessionManager>((ref) {
  return SignalSessionManager(
    signalService: ref.read(signalProtocolServiceProvider),
    apiClient: ref.read(apiClientProvider),
    secureStorage: ref.read(secureStorageProvider),
    identityManager: ref.read(identityManagerProvider),
    sessionStore: ref.read(sessionStoreProvider),
    socketManager: ref.read(socketManagerProvider),
    // Wallet V2 Phase F: TOFU pin store wired so getPeerEd25519PublicKey
    // takes the cache-hit path (TransferService walletAddressSig verification).
    identityPinStore: ref.read(identityPinStoreProvider),
  );
});

// --- Group Session Manager ---
//
// **Phase 6.9**: This provider is intentionally STATELESS w.r.t. myId. The
// caller (chat_provider) MUST pass the current SnowChat ID into every
// outbound operation. SenderKeyManager is resolved on-demand via
// `_sessionManager.signal.senderKeyManager` so that
// clearAllSessions()/loadSessionStore() reassignments are observed.
final groupSessionManagerProvider = Provider<GroupSessionManager>((ref) {
  return GroupSessionManager(
    sessionManager: ref.read(signalSessionManagerProvider),
    socketManager: ref.read(socketManagerProvider),
  );
});

// --- File Service ---
final fileServiceProvider = Provider<FileService>((ref) {
  return FileService(apiClient: ref.read(apiClientProvider));
});

// --- Phase 10.1: Sealed Sender Service ---
// Null until sealedSenderAutoInitProvider populates it (after auth completes).
// EncryptedMessageHandler / CallSignaling fall back to non-sealed / null while null.
final sealedSenderServiceProvider = StateProvider<SealedSenderService?>((ref) {
  return null;
});

// Auto-initializes SealedSender in reaction to authToken changes. Fresh install
// (Galaxy case): on app startup authToken=null → skip; once onboarding completes
// and authToken is created → this FutureProvider rebuilds → server fetches verify
// key → fills sealedSenderServiceProvider state → callSignalingProvider /
// callServiceProvider / callProvider auto-rebuild, swapping _IdleCallNotifier
// for the real CallNotifier. No app restart needed.
//
// Must be watched somewhere to stay alive — both appStartupProvider and app.dart
// ref.read/watch it.
final sealedSenderAutoInitProvider = FutureProvider<void>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) {
    // Reset on logout
    ref.read(sealedSenderServiceProvider.notifier).state = null;
    return;
  }
  if (ref.read(sealedSenderServiceProvider) != null) return; // already active
  try {
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.get('/auth/server-key');
    final verifyKeyB64 = response.data['verifyKey'] as String;
    final verifyKey = base64Decode(verifyKeyB64);
    ref.read(sealedSenderServiceProvider.notifier).state =
        SealedSenderService(serverVerifyKey: verifyKey);
    debugPrint('[SealedSender] activated (authToken trigger)');
  } catch (e) {
    debugPrint('[SealedSender] init failed (non-fatal): $e');
  }
});

// --- Phase 10.1: Sender Certificate Manager ---
final senderCertificateManagerProvider = Provider<SenderCertificateManager?>((ref) {
  try {
    final apiClient = ref.read(apiClientProvider);
    return SenderCertificateManager(apiClient: apiClient);
  } catch (_) {
    return null;
  }
});

// --- Wallet V2 Phase B: Transfer Event Bus ---
//
// Broadcast bus for chat transfer events (1:1 SOL/SPL/NFT). EncryptedMessageHandler's
// transfer_* dispatcher emits; wallet-module listeners (TransferService /
// TransferConfirmDialog etc.) subscribe via ref.watch(transferEventBusProvider).events.
// Single instance (app lifetime). dispose via ref.onDispose.
final transferEventBusProvider = Provider<TransferEventBus>((ref) {
  final bus = TransferEventBus();
  ref.onDispose(() => bus.dispose());
  return bus;
});

// --- Encrypted Message Handler ---
final encryptedMessageHandlerProvider =
    Provider<EncryptedMessageHandler>((ref) {
  final handler = EncryptedMessageHandler(
    sessionManager: ref.read(signalSessionManagerProvider),
    socketManager: ref.read(socketManagerProvider),
    groupSessionManager: ref.read(groupSessionManagerProvider),
    fileService: ref.read(fileServiceProvider),
    sealedSenderService: ref.read(sealedSenderServiceProvider),
    senderCertificateManager: ref.read(senderCertificateManagerProvider),
    transferEventBus: ref.read(transferEventBusProvider),
  );
  // P0-2 Stage B: wire identity change handler so send-path TOFU mismatch
  // routes into the Safety Number pipeline instead of looping forever.
  handler.identityChangeHandler = ref.read(identityChangeHandlerProvider);
  return handler;
});

// --- Phase 6: Message Queue (single source of truth for incoming messages) ---
final messageQueueProvider = Provider<MessageQueue>((ref) {
  final queue = MessageQueue(
    sessionManager: ref.read(signalSessionManagerProvider),
    e2eeHandler: ref.read(encryptedMessageHandlerProvider),
    messageDao: ref.read(messageDaoProvider),
    conversationDao: ref.read(conversationDaoProvider),
    attachmentDao: ref.read(attachmentDaoProvider),
    fileService: ref.read(fileServiceProvider),
    expiringManager: ref.read(expiringMessageManagerProvider),
    database: ref.read(snowDatabaseProvider),
    apiClient: ref.read(apiClientProvider),
    socketManager: ref.read(socketManagerProvider),
    myIdResolver: () => ref.read(currentSnowIdProvider) ?? '',
    // 2026-05-04 — Phase 8.2 Signal-style VoIP signaling persistence.
    // Server enqueues mid-call sealed envelopes with metadata.voip=true.
    // Route them to CallSignaling.injectEnvelope on offline-recovery fetch.
    // ref.read inside the lambda so we resolve callSignalingProvider lazily
    // (it depends on SignalSessionManager + SealedSenderService which may
    // not be ready at messageQueueProvider construction).
    injectVoipEnvelope: (envelopeBase64) async {
      final signaling = ref.read(callSignalingProvider);
      if (signaling == null) return;
      await signaling.injectEnvelope(envelopeBase64);
    },
  );
  // P0-2 Stage B: route receive-path TOFU mismatch into Safety Number pipeline.
  queue.identityChangeHandler = ref.read(identityChangeHandlerProvider);
  // Phase 8.8: onGmkReceived callback is wired by ConversationListNotifier
  // to avoid circular import (providers.dart cannot import conversation_list_provider.dart).
  return queue;
});

// --- Phase 6: Global Message Router (socket → queue) ---
final globalMessageRouterProvider = Provider<GlobalMessageRouter>((ref) {
  final router = GlobalMessageRouter(
    socketManager: ref.read(socketManagerProvider),
    queue: ref.read(messageQueueProvider),
    e2eeHandler: ref.read(encryptedMessageHandlerProvider),
    sessionManager: ref.read(signalSessionManagerProvider),
    messageDao: ref.read(messageDaoProvider),
    attachmentDao: ref.read(attachmentDaoProvider),
    myIdResolver: () => ref.read(currentSnowIdProvider) ?? '',
    ref: ref,
  );
  ref.onDispose(router.stop);
  return router;
});

// --- Notification Service ---
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  // Initialize async — callers should await initialize() before showing notifications
  service.initialize();
  return service;
});

// --- VoIP Push Service (iOS PushKit, Phase E-2) ---
final voipPushServiceProvider = Provider<VoipPushService>((ref) {
  debugPrint('[VoipPush] provider closure executed');
  final svc = VoipPushService(
    apiClient: ref.read(apiClientProvider),
    secureStorage: ref.read(secureStorageProvider),
  );
  unawaited(svc.start());
  ref.onDispose(svc.dispose);
  return svc;
});

// --- VoIP Native Bridge (iOS PushKit + CallKit accept handoff, Phase E-2 v3.1) ---
//
// Provider (NOT auto-dispose — N-Min-4): hot restart re-reads should reuse
// the same instance. The class internally guards against double attach
// (`_started` flag), but auto-dispose would let the Stream get re-subscribed
// twice between rebuilds, leading to duplicate envelope drains.
final voipNativeBridgeProvider = Provider<VoipNativeBridge>((ref) {
  final bridge = VoipNativeBridge();
  bridge.start();
  ref.onDispose(bridge.dispose);
  return bridge;
});

// Auto-pushes the resolved API base URL to native CallAcceptCoordinator
// whenever it becomes available. Until baseUrl arrives on native, accepts
// queue. We watch authTokenProvider as a proxy for "Riverpod has fully
// hydrated" — by the time auth is set, ApiEndpoints.getBaseUrl() is stable.
final voipNativeBaseUrlPushProvider = FutureProvider<void>((ref) async {
  if (!Platform.isIOS) return;
  final token = ref.watch(authTokenProvider);
  if (token == null) return;
  final bridge = ref.read(voipNativeBridgeProvider);
  await bridge.setBaseUrl(ApiEndpoints.getBaseUrl());
  // Wire native drain → CallNotifier.acceptPendingVoipCallWithEnvelopes.
  // Subscription is single-listener (cancelled on provider dispose) — no
  // duplicate hand-off across rebuilds.
  final sub = bridge.events.listen((event) {
    final notifier = ref.read(callProvider.notifier);
    final relay = ref.read(settingsProvider).callAlwaysRelay;
    notifier.acceptPendingVoipCallWithEnvelopes(
      nonce: event.nonce,
      envelopes: event.envelopes,
      localAlwaysRelay: relay,
      source: 'native',
    );
  });
  ref.onDispose(sub.cancel);
});

// --- Push Service ---
final pushServiceProvider = Provider<PushService>((ref) {
  final pushService = PushService(
    socketManager: ref.read(socketManagerProvider),
    notificationService: ref.read(notificationServiceProvider),
    apiClient: ref.read(apiClientProvider),
    secureStorage: ref.read(secureStorageProvider),
  );
  // Set current user ID for own-message filtering
  pushService.mySnowId = ref.read(currentSnowIdProvider);
  ref.listen<String?>(currentSnowIdProvider, (_, next) {
    pushService.mySnowId = next;
  });
  // Start listening to socket events for notifications
  pushService.initialize();
  ref.onDispose(() => pushService.dispose());
  return pushService;
});

// Auto-syncs FCM push token whenever the user authenticates (login) or a
// stored snapshot is hydrated on cold boot.
//
// Phase 11: previously this watched `authTokenProvider` and re-fired on every
// transition (including refresh, which caused the 4-6× register storm logged
// 2026-05-03). Now it listens to TokenManager.events and dedups so login OR
// hydrated triggers a single registration pass; refreshed events are ignored
// (the FCM token didn't change just because the JWT rotated).
//
// Fresh-signup gap fix (2026-04-28) is preserved: hydrate happens before
// onboarding completes, so login fires after onboarding -> registration runs
// on the SAME app launch as the signup, not waiting for the next cold boot.
final pushTokenAutoSyncProvider = Provider<void>((ref) {
  final tokenManager = ref.read(tokenManagerProvider);
  bool registered = false;
  Future<void> trigger(String reason) async {
    if (registered) return;
    registered = true;
    try {
      await ref.read(pushServiceProvider).retryTokenRegistration();
      debugPrint('[PushTokenAutoSync] registration via $reason succeeded');
    } catch (e) {
      registered = false; // allow retry on next event
      debugPrint('[PushTokenAutoSync] registration ($reason) failed (non-fatal): $e');
    }
  }

  // If a snapshot is already loaded by the time this provider mounts (cold
  // boot path), trigger immediately.
  if (tokenManager.snapshot != null) {
    unawaited(trigger('initial'));
  }

  final sub = tokenManager.events.listen((event) {
    if (event.type == TokenEventType.login ||
        event.type == TokenEventType.hydrated) {
      unawaited(trigger(event.type.name));
    } else if (event.type == TokenEventType.logout ||
        event.type == TokenEventType.expiredHard) {
      registered = false; // re-arm for next login
    }
  });
  ref.onDispose(sub.cancel);
});

// --- Presence Service ---
final presenceServiceProvider =
    ChangeNotifierProvider<PresenceService>((ref) {
  final socketManager = ref.read(socketManagerProvider);
  return PresenceService(socketManager);
});

// --- Link Preview Service ---
final linkPreviewServiceProvider = Provider<LinkPreviewService>((ref) {
  return LinkPreviewService();
});

// --- Friend Request Badge ---
/// Global counter for pending friend requests. Updated by
/// ConversationListNotifier when friend_request_received socket event
/// arrives. Router reads this to show a badge on the Friends tab.
final pendingFriendBadgeProvider = StateProvider<int>((ref) => 0);

// =====================================================================
// Phase 8.2 VoIP — voice calls (WebRTC P2P + Sealed Sender signaling)
// =====================================================================

/// Cloudflare Realtime TURN credentials cache (§14.5).
final turnCredentialManagerProvider = Provider<TurnCredentialManager>((ref) {
  return TurnCredentialManager(apiClient: ref.read(apiClientProvider));
});

/// VoIP signaling Sealed Sender wrapper (§24.2).
/// Null until SealedSenderService / SenderCertificateManager are initialized.
///
/// **Important**: on provider rebuild the previous instance must be disposed.
/// Otherwise socket listeners accumulate and a single incoming signal gets
/// processed N times (prior diagnosis: RouterListen FIRE 6× / TURN credentials
/// 6× calls → 429 rate limit).
final callSignalingProvider = Provider<CallSignaling?>((ref) {
  final sealed = ref.watch(sealedSenderServiceProvider);
  // watch (not read) — even if certMgr initializes later than sealed, this
  // ensures callSignaling rebuilds so the listener gets registered.
  final certMgr = ref.watch(senderCertificateManagerProvider);
  if (sealed == null || certMgr == null) return null;
  final signaling = CallSignaling(
    sessionManager: ref.read(signalSessionManagerProvider),
    sealedSenderService: sealed,
    senderCertificateManager: certMgr,
    socketManager: ref.read(socketManagerProvider),
    // 2026-05-04 fix: self-sender envelope leak 가드. CallSignaling 의
    // _onIncoming 이 own envelope 를 받으면 abort. providers 가
    // currentSnowIdProvider 를 closure 로 wire — sync read 라 BG isolate
    // 안전.
    mySnowchatIdResolver: () => ref.read(currentSnowIdProvider),
  );
  ref.onDispose(signaling.dispose);
  return signaling;
});

/// WebRTC PeerConnection manager (§3.3).
/// Null until CallSignaling is ready — UI stays in the disabled state.
final callServiceProvider = Provider<CallService?>((ref) {
  final signaling = ref.watch(callSignalingProvider);
  if (signaling == null) return null;
  final service = CallService(
    signaling: signaling,
    turnManager: ref.read(turnCredentialManagerProvider),
    // v204 (2026-05-03): inject CallKitManager so outbound startCall on iOS
    // can drive CXStartCallAction → didActivate (Apple-recommended pattern).
    // Pre-v204 outbound bypassed CallKit, leaving AURemoteIO without
    // PhoneCall priority → silent two-way audio failure.
    callKit: ref.read(callKitManagerProvider),
  );
  // v2.5 (2026-05-03): wire CallService → VoipNativeBridge audio session
  // events. The previous design had CallService register its own
  // setMethodCallHandler on `snowchat/voip_native`, colliding with the
  // bridge's handler — whichever provider initialized last won, silently
  // dropping the other side's MethodCalls. The bridge now owns the channel
  // exclusively and exposes audio session events as broadcast streams.
  // No-op on Android.
  if (Platform.isIOS) {
    final bridge = ref.read(voipNativeBridgeProvider);
    service.wireNativeBridge(
      audioSessionActivated: bridge.audioSessionActivated,
      audioSessionDeactivated: bridge.audioSessionDeactivated,
      systemReset: bridge.systemReset,
    );
  }
  ref.onDispose(service.dispose);
  return service;
});

/// Phase E-1: CallKit / ConnectionService Self-Managed system UI manager.
/// Single instance (app lifetime). dispose registered via ref.onDispose.
final callKitManagerProvider = Provider<CallKitManager>((ref) {
  final mgr = CallKitManager();
  ref.onDispose(mgr.dispose);
  return mgr;
});

/// CallNotifier — call state subscribed by the UI (§2).
/// family forbidden: concurrent-call policy allows only a single instance.
final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  final service = ref.watch(callServiceProvider);
  if (service == null) {
    // Until CallService is ready, replace with an idle-state dummy notifier.
    // Phase I (§25): _IdleCallNotifier still needs callKitManager injected so
    // it can receive FCM Voice Push Accept events and stash the nonce.
    // Later, once SealedSender initializes → this provider rebuilds → the real
    // CallNotifier resumes the pending nonce in its constructor.
    return _IdleCallNotifier(ref);
  }
  return CallNotifier(
    callService: service,
    callKitManager: ref.read(callKitManagerProvider),
    ref: ref, // V1.0.1: dao access for inserting missed-call system messages
  );
});

/// Fallback — used when SealedSender is not yet initialized.
///
/// Phase I (§25): inject callKitManager so Accept events can still be received.
/// However, pass `ref` as null to super so `_onCallKitEvent` branches into the
/// "ref==null path" and only stashes the nonce (decrypt/acceptCall are resumed
/// by the real CallNotifier later).
class _IdleCallNotifier extends CallNotifier {
  _IdleCallNotifier(Ref ref)
      : super(
          callService: _UnavailableCallService(),
          callKitManager: ref.read(callKitManagerProvider),
        );
}

/// Placeholder CallService — operations throw, but event streams are no-op.
///
/// CallNotifier's constructor immediately listen()s on `events`/`sasEvents`,
/// so both getters must return a valid (silent) Stream. The other methods
/// (startCall/acceptCall/...) must NOT be called while SealedSender is
/// uninitialized — noSuchMethod surfaces a clear error if they are.
class _UnavailableCallService implements CallService {
  @override
  Stream<CallServiceEvent> get events => const Stream<CallServiceEvent>.empty();

  @override
  Stream<CallSasEvent> get sasEvents => const Stream<CallSasEvent>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('VoIP not initialized — SealedSender service unavailable');
  }
}
