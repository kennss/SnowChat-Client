/// @file        providers.dart
/// @description Global Riverpod providers. DI for auth, crypto, network, storage, messaging, calls.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-27 (wallet removed: no solanaNetworkProvider, no transferEventBusProvider,
///              no transfer recovery at startup; the message handler takes no transfer bus).
///              Earlier 2026-11-23 (callProvider gets the "Show caller name on calls" reader — SettingsNotifier.callShowCallerNameForCall). Earlier 2026-11-22 (notificationServiceProvider no longer asks the microphone — askStartupPrompts in PushService owns the start prompts). Earlier 2026-11-22 (review fixes: contactSyncProvider runs a ContactSyncRunner — one run at a
///              time, one timer, cancelled on dispose, re-armed when a block / unblock makes the
///              backup write due sooner (writeSoon, 1–10 minutes later); a contact notice is handed
///              on with its answer mark; the queue names an unnamed sender from this device's names
///              (peerName); a peer's prekey message makes the next message to it carry the name
///              certificate again (onNewInboundSession → NameCertService.forgetAnnounced); the outbox
///              reads the server's status events (statusEvents — the delivered mark); community
///              avatars through communityAvatarBytesProvider — authHeaderProvider is gone (no file
///              is fetched by a URL any more). No account or
///              conversation id in a log line — logRef). Earlier 2026-11-22 (friend graph off the server — design 2026-11-22: contactDaoProvider,
///              nameCertServiceProvider, contactStoreProvider, contactLookupProvider,
///              contactBackupProvider and contactSyncProvider (restore once, block tags replaced,
///              the periodic backup write — on every connect and on a timer); the queue hands
///              contact notices to the contact store (a local notification while the app is open)
///              and name certificates to NameCertService; a block / unblock writes the backup at
///              once; the outbox attaches name certificates; pendingFriendBadgeProvider counts the
///              received requests on this device; no presenceServiceProvider (no presence);
///              contactRestoreNoticeProvider — the restore notice not shown yet; the outbox tells
///              the contact store what the server said about a recipient (onRecipientChecked)).
///              Earlier 2026-11-22 (appBadgeUpdaterProvider writes the unread sum again on every resume — a pushed badge stayed after the message was read as it arrived; the microphone is asked once on the first run, right after the notification prompt — askMicrophoneOnce; a first call answered from the lock screen could not show the prompt and never connected. SC-18: after a group message is sent while the socket is down, the queue is fetched — this device's own row is acknowledged before the server's push grace runs out, so the sender's phone shows no notification of its own message. Also: sealedSenderAutoInitProvider builds SealedSenderService from the server
///              keys pinned in the build — no /auth/server-key fetch, SC-06; the session manager's
///              sessionResetNotifier is the handler's sealed sendSealedSessionReset, SC-05; CallService
///              gets the fingerprint signing seed and the peer's bound Ed25519 key, SC-10). Earlier 2026-11-22 (passcodeStoreProvider — the app passcode, salted Argon2id; startup asks it
///              whether a passcode is set). Earlier 2026-11-21 (directOutboxProvider — the 1:1 outbox). Earlier 2026-11-21 (X1: blockListProvider — the accounts this user blocked, on this device, synced on connect; wired into the decrypt and the call signaling; P5.6: the status of a sent group message is written by the sink in the outbox's transaction, not by a listener afterwards; sealed sender init no longer gives up for the session — past its quick retries it tries again on the next socket connect or every 3 minutes; groups and calls stood on it; P5.6: no automatic accept of group invites — both conditions it stood on were the server's to make; a group invite is kept on disk by the 1:1 queue before it is acknowledged, whether or not the group runtime is up). Earlier 2026-11-21 (identity: no verifiedLookup wiring, no Safety Number v1 row drop at startup (old data), the identity-change handler is instantiated instead of assigned to unused fields). Earlier 2026-11-20 (group protocol v2 has no build flag — it runs wherever the server keys are pinned. v1 groups removed: no groupSessionManagerProvider; the message router takes no E2EE handler or account id; PushService takes no socket manager. Group protocol v2: no runtime without server keys trusted for the environment — gv2_trusted_keys.dart; the outbox's send results are written to the message rows, and the Chats list is told when a group changes; the runtime gets the group key backup — Gv2BackupClient and IdentityManager.deriveGroupBackupKey). Earlier 2026-11-13 (group protocol v2: gv2RuntimeProvider — built behind AppConfig.enableGroupsV2 once an account is signed in and the sealed sender service is up; group actions (create, invite, accept) with the invite message on the sealed 1:1 path and the friend + confirmed-identity rule for accepting without asking; takes the rows of the group queue from the socket and from MessageQueue.fetchPending, acknowledges them, and stores verified group messages through Gv2AppMessageSink). Earlier 2026-11-11 (At-rest protection level 1: snowDatabaseProvider opens the drift DB through SQLCipher via openEncryptedDatabase (random 256-bit key in secure storage, key creation main-isolate only, retry after a locked keychain); deleteDriftDatabaseFile(storage) deletes the DB files then the key; the iOS fresh-install keychain purge moved into ensureFreshInstallSecureStoragePurge() (memoized) and is awaited by the DB opener before the key is read; startup applies the attachments-dir protection). Earlier 2026-11-10 (B-2 Identity Binding v1: identityPinStoreProvider → verifiedIdentityStoreProvider (wired to IdentityVerificationDao for the verified-peer lookup and to IdentityChangeHandler for user-visible identity events); app startup drops pre-v2 Safety Number rows once per launch (idempotent)). Earlier 2026-11-08 (ENABLE_WALLET=false hardening: TransferService is no longer instantiated at startup when AppConfig.enableWallet is false, so incoming transfer requests cannot raise a confirm dialog). Earlier 2026-08-04 (deleteDriftDatabaseFile(): remove snowchat.db + WAL/SHM on app reset / account delete so a newly created identity does not inherit the prior account's conversations — path co-located with _openDb). Earlier 2026-05-03 (Phase 11 — TokenManager 도입. authTokenProvider →
///              tokenSnapshotProvider 로 derived. tokenManagerProvider KeepAlive
///              SSoT. AuthService 의 onTokenRefresh callback 폐기. socket /
///              push token sync 도 events stream 으로 listen)
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
///  - snowDatabaseProvider: SnowDatabase provider (SQLCipher-encrypted, see encrypted_database.dart)
///  - ensureFreshInstallSecureStoragePurge(): memoized iOS fresh-install keychain purge (startup + DB opener)
///  - deleteDriftDatabaseFile(storage): reset / account delete — DB files, then the DB key
///  - messageDaoProvider: MessageDao provider (drift DB SSoT)
///  - conversationDaoProvider: ConversationDao provider (drift DB SSoT)
///  - sessionStoreProvider: SessionStore provider
///  - signalSessionManagerProvider: SignalSessionManager provider
///  - fileServiceProvider: FileService provider
///  - encryptedMessageHandlerProvider: EncryptedMessageHandler provider
///  - notificationServiceProvider: NotificationService provider
///  - pushServiceProvider: PushService provider
///  - pushTokenAutoSyncProvider: auto-registers the FCM token whenever authToken transitions to non-null (fresh signup / restore / login / restart)
///  - contactDaoProvider / contactStoreProvider / nameCertServiceProvider / contactLookupProvider /
///    contactBackupProvider / contactSyncProvider: the friend list on this device (core/contacts)
///  - pendingFriendBadgeProvider: received friend requests on this device (Friends tab badge)
///  - contactRestoreNoticeProvider: the restore notice not shown yet (the main shell shows it)
///  - communityAvatarBytesProvider: a community avatar's image (POST /files/fetch), per file id
///  - linkPreviewServiceProvider: LinkPreviewService provider

import '../core/security/passcode.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/blocking/block_list.dart';
import '../core/contacts/contact_backup.dart';
import '../core/contacts/contact_lookup.dart';
import '../core/contacts/contact_notice.dart';
import '../core/contacts/contact_store.dart';
import '../core/contacts/contact_sync_runner.dart';
import '../core/contacts/name_cert_service.dart';
import '../core/call/call_service.dart';
import '../core/call/call_signaling.dart';
import '../core/call/callkit_manager.dart';
import '../core/call/turn_credential_manager.dart';
import '../core/crypto/sealed_trusted_keys.dart' show sealedTrustedServerKeys;
import '../core/crypto/encrypted_message_handler.dart';
import '../core/crypto/identity_change_handler.dart';
import '../features/call/providers/call_provider.dart';

// Phase 8.2: re-export CallState/CallStatus/CallNotifier so screens don't need
// to import call_provider.dart directly.
export '../features/call/providers/call_provider.dart' show CallState, CallStatus, CallNotifier;
import '../core/crypto/sealed_sender.dart';
import '../core/crypto/sender_certificate_manager.dart';
import '../features/chat/providers/expiring_message_manager.dart';
import '../features/chat/providers/mark_read_helper.dart';
import '../core/group_v2/gv2_outbox.dart' show Gv2MessageSent;
import '../core/group_v2/gv2_pairwise_crypto.dart';
import '../core/group_v2/gv2_runtime.dart';
import '../core/group_v2/gv2_trusted_keys.dart';
import '../core/messaging/direct_outbox.dart';
import '../core/messaging/global_message_router.dart';
import '../core/messaging/gv2_message_sink.dart';
import '../core/messaging/message_queue.dart';
import '../core/call/voip_push_service.dart';
import '../core/network/voip_native_bridge.dart';
import '../core/notifications/notification_service.dart';
import '../shared/services/badge_service.dart';
import '../core/notifications/push_service.dart';
import '../core/crypto/identity_manager.dart';
import '../core/crypto/verified_identity_store.dart';
import '../core/crypto/session_store.dart';
import '../core/crypto/signal_protocol_service.dart';
import '../core/crypto/signal_session_manager.dart';
import '../core/network/api_client.dart';
import '../core/network/api_endpoints.dart';
import '../core/network/file_service.dart';
import '../core/network/contact_backup_client.dart';
import '../core/network/gv2_backup_client.dart';
import '../core/network/link_preview_service.dart';
import '../core/network/socket_manager.dart';
import '../core/network/auth_service.dart';
import '../core/network/token_manager.dart';
import '../core/storage/database.dart';
import '../core/storage/daos/message_dao.dart';
import '../core/storage/daos/conversation_dao.dart';
import '../core/storage/daos/attachment_dao.dart';
import '../core/storage/daos/ai_message_dao.dart';
import '../core/storage/daos/identity_verification_dao.dart';
import '../core/storage/daos/contact_dao.dart';
import '../core/storage/secure_storage.dart';
import '../core/storage/encrypted_database.dart';
import '../core/storage/local_file_protection.dart';
import '../features/settings/settings_provider.dart';
import '../core/diagnostics/log_ref.dart';

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

/// Step 0 of app startup, also awaited by the database opener before it reads
/// the database key: iOS Keychain fresh-install detection (Phase 8.7 TODO #8).
/// Memoized per process so both callers share one run.
Future<void>? _freshInstallPurge;
Future<void> ensureFreshInstallSecureStoragePurge(
        SecureStorageService secureStorage) =>
    _freshInstallPurge ??= _runFreshInstallSecureStoragePurge(secureStorage);

Future<void> _runFreshInstallSecureStoragePurge(
    SecureStorageService secureStorage) async {
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
}

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
  //   (4) walk into the full chat history + mnemonic.
  // With this, step (2) restarts the user in a true fresh-install state.
  await ensureFreshInstallSecureStoragePurge(secureStorage);

  // Level-1 at-rest protection: create / protect the attachments directory
  // (iOS backup exclusion + CompleteUnlessOpen, sweep of existing files).
  unawaited(AttachmentStorage.ensureDirectory().then((_) {},
      onError: (Object e) =>
          debugPrint('[AppStartup] attachments dir protection failed: $e')));

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
  debugPrint('[AppStartup] Identity found: ${logRef(snowId)}');

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
  final hasPin = await ref.read(passcodeStoreProvider).has();
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

  // Step 3.5 (B-2): instantiate the identity-change handler so identity
  // store events emitted during the cold-start queue drain are rendered.
  ref.read(identityChangeHandlerProvider);

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
  }

  return true;
});

// --- Secure storage ---
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// The app passcode (salted Argon2id record; core/security/passcode.dart).
final passcodeStoreProvider = Provider<PasscodeStore>((ref) {
  return PasscodeStore(ref.read(secureStorageProvider));
});

// --- Verified Identity Store (B-2 Identity Binding v1) ---
final verifiedIdentityStoreProvider = Provider<VerifiedIdentityStore>((ref) {
  final store = VerifiedIdentityStore(ref.read(secureStorageProvider));
  ref.onDispose(store.dispose);
  return store;
});

// --- Signal Protocol Service (Pure Dart) ---
final signalProtocolServiceProvider = Provider<SignalProtocolService>((ref) {
  return SignalProtocolService(
    identityStore: ref.read(verifiedIdentityStoreProvider),
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

  // expiredHard from TokenManager: the session is over (tokenManager.clear()
  // already ran inside _doRefresh). No request can be authorized any more —
  // the server drops this device's push tokens itself when it refuses the
  // expired refresh token.
  final eventSub = tokenManager.events.listen((event) {
    if (event.type == TokenEventType.expiredHard) manager.disconnect();
  });

  ref.onDispose(() {
    eventSub.cancel();
    manager.dispose();
  });

  return manager;
});

// --- Local Database (Drift) ---
// File-based persistent database, encrypted at rest with SQLCipher (level 1,
// 2026-11-11). Location, key handling, legacy-plaintext removal and the
// retry-after-locked-keychain behaviour live in encrypted_database.dart.
QueryExecutor _openDb(SecureStorageService storage) {
  return openEncryptedDatabase(
    storage: storage,
    // Only the isolate that ran main() may CREATE the key; any other isolate
    // can only read it. Combined with the per-isolate serialization and the
    // read-after-write in DatabaseKeyManager, one database never gets two keys.
    allowKeyCreation: TokenManager.isMainIsolateOwnerSync(),
    // A stale key left in the iOS Keychain by a previous install must be
    // purged before it could be adopted for a new database.
    awaitBeforeKeyAccess: () => ensureFreshInstallSecureStoragePurge(storage),
  );
}

/// Delete the encrypted drift database (+ WAL/SHM, quarantine and legacy
/// plaintext files) and THEN its key. Used by the app-reset / account-delete
/// flow so that a newly created identity does NOT inherit the previous
/// account's conversations and messages. The SnowDatabase connection must be
/// close()d BEFORE calling this; afterwards invalidate [snowDatabaseProvider]
/// so the next access opens a fresh, empty database under a fresh key.
Future<void> deleteDriftDatabaseFile(SecureStorageService storage) =>
    deleteEncryptedDatabase(storage);

final snowDatabaseProvider = Provider<SnowDatabase>((ref) {
  final db = SnowDatabase(_openDb(ref.read(secureStorageProvider)));
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

/// Subscribes to the drift unread-sum stream and pushes the value to the
/// OS launcher badge (iOS aps.badge from server pushes covers the killed /
/// BG path; this provider keeps the badge accurate while the app is alive
/// — read-receipts, navigations, and any drift mutation that changes
/// unread counts flow through here). app.dart must `ref.watch` this for
/// the subscription to stay live.
///
/// The badge has a second writer: a push's aps.badge (the server's count of
/// rows not yet acknowledged when it pushed). A message read as it arrived
/// (its chat open — opened by tapping that very push) never moves the drift
/// sum, so nothing here would correct the pushed count: on every resume the
/// current sum is written again, whatever was written last.
final appBadgeUpdaterProvider = Provider<void>((ref) {
  final dao = ref.read(conversationDaoProvider);
  var latest = 0;
  final sub = dao.watchTotalUnreadCount().listen((count) {
    latest = count;
    BadgeService.instance.setCount(count);
  });
  final lifecycle = AppLifecycleListener(
    onResume: () => BadgeService.instance.setCount(latest, force: true),
  );
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(sub.cancel());
  });
});

final attachmentDaoProvider = Provider<AttachmentDao>((ref) {
  return ref.read(snowDatabaseProvider).attachmentDao;
});

// --- Identity Verification DAO (P0-2: Safety Number 60-digit verification) ---
final identityVerificationDaoProvider = Provider<IdentityVerificationDao>((ref) {
  return ref.read(snowDatabaseProvider).identityVerificationDao;
});

// --- Identity Change Handler (B-2) ---
//
// Renders VerifiedIdentityStore events (a bound peer's device keys changed;
// an identity binding rejected or missing): latches the rejection in
// IdentityVerificationDao, inserts a system message, and broadcasts an event
// for the chat banner.
final identityChangeHandlerProvider = Provider<IdentityChangeHandler>((ref) {
  final handler = IdentityChangeHandler(
    dao: ref.read(identityVerificationDaoProvider),
    messageDao: ref.read(messageDaoProvider),
    conversationDao: ref.read(conversationDaoProvider),
  );
  // B-2: identity events (device keys changed, binding rejected) are
  // rendered from the store stream.
  handler.attachStore(ref.read(verifiedIdentityStoreProvider));
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
  );
});

// --- File Service ---
final fileServiceProvider = Provider<FileService>((ref) {
  return FileService(apiClient: ref.read(apiClientProvider));
});

// --- Phase 10.1: Sealed Sender Service ---
// Null until sealedSenderAutoInitProvider populates it (after auth completes).
// While null, 1:1 sends wait (no non-sealed fallback, A-4) and calls are unavailable.
final sealedSenderServiceProvider = StateProvider<SealedSenderService?>((ref) {
  return null;
});

// Activates SealedSender once an account is signed in (authToken set) and
// clears it on logout. The server's verify keys are the ones pinned in this
// build (sealed_trusted_keys.dart, SC-06 of the 2026-11-10 report) — no
// /auth/server-key fetch: a key the server hands out at run time is never
// trusted, and an app started offline has Sealed Sender at once (calls and
// group protocol v2 stand on it). callSignalingProvider / callServiceProvider
// / callProvider rebuild when the service appears, swapping
// _IdleCallNotifier for the real CallNotifier — no app restart needed.
//
// Must be watched somewhere to stay alive — both appStartupProvider and
// app.dart ref.read/watch it.
final sealedSenderAutoInitProvider = FutureProvider<void>((ref) async {
  final token = ref.watch(authTokenProvider);
  if (token == null) {
    // Reset on logout
    ref.read(sealedSenderServiceProvider.notifier).state = null;
    return;
  }
  if (ref.read(sealedSenderServiceProvider) != null) return; // already active
  final keys = sealedTrustedServerKeys;
  if (keys == null || keys.isEmpty) {
    // A build for an environment it pins no key for (the release scripts
    // refuse to build one — tool/require_server_keys.dart).
    debugPrint('[SealedSender] no server key pinned for this environment — '
        'Sealed Sender stays off');
    return;
  }
  ref.read(sealedSenderServiceProvider.notifier).state =
      SealedSenderService(trustedServerKeys: keys);
  debugPrint('[SealedSender] activated (pinned server keys)');
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

// --- Community avatars ---
/// The image of a community's avatar (its uploaded file [fileId]), fetched
/// once with the account's login — POST /files/fetch, the file id in the
/// body, never in a URL — and kept for the run. Null when it cannot be
/// fetched (the avatar shows initials).
final communityAvatarBytesProvider =
    FutureProvider.family<Uint8List?, String>((ref, fileId) async {
  try {
    return await ref.read(fileServiceProvider).downloadEncryptedFile(fileId);
  } catch (e) {
    debugPrint('[Avatar] community avatar not fetched: ${e.runtimeType}');
    return null;
  }
});

// --- Blocked accounts (X1) ---
// The accounts this user blocked, on this device: read once, and brought in
// step with the server now and on every connect (BlockList.sync). What a
// blocked account sends is refused where it is decrypted.
final blockListProvider = Provider<BlockList>((ref) {
  final list = BlockList(
    store: ref.read(snowDatabaseProvider).blockListDao,
    api: ref.read(apiClientProvider),
    mySnowId: () => ref.read(currentSnowIdProvider) ?? '',
  );
  unawaited(list.load());
  unawaited(list.sync());
  final connection = ref.read(socketManagerProvider).onConnectionChange.listen(
    (connected) {
      if (connected) unawaited(list.sync());
    },
  );
  ref.onDispose(() {
    unawaited(connection.cancel());
    list.dispose();
  });
  return list;
});

/// The accounts this user blocked, as they change (after the stored list
/// was read).
final blockedAccountsProvider = StreamProvider<Set<String>>((ref) async* {
  final list = ref.watch(blockListProvider);
  await list.load();
  yield list.blocked;
  yield* list.changes;
});

// --- The friend list on this device (design 2026-11-22-friend-graph-off-server) ---

final contactDaoProvider = Provider<ContactDao>(
    (ref) => ref.read(snowDatabaseProvider).contactDao);

/// Names from name certificates: this account's own (fetched, cached) and
/// the peers' (verified offline against the pinned Sealed Sender keys).
final nameCertServiceProvider = Provider<NameCertService>((ref) {
  final api = ref.read(apiClientProvider);
  final service = NameCertService(
    dao: ref.read(contactDaoProvider),
    conversations: ref.read(conversationDaoProvider),
    fetchOwn: () async {
      final res = await api.post<dynamic>(ApiEndpoints.nameCert, data: {});
      final data = res.data;
      final cert = data is Map ? data['cert'] : null;
      if (cert is! String) throw const FormatException('name certificate');
      return base64Decode(cert);
    },
    trustedKeys: sealedTrustedServerKeys,
    mySnowId: () => ref.read(currentSnowIdProvider) ?? '',
  );
  // The names an incoming call reads synchronously (cachedName).
  unawaited(service.warmUp());
  return service;
});

/// The rows and rules of the friend list; notices go through the 1:1
/// outbox, the user's own choices are vouched for.
// Typed: it and directOutboxProvider read each other (lazily, inside
// closures), which top-level inference cannot follow.
final Provider<ContactStore> contactStoreProvider =
    Provider<ContactStore>((ref) {
  return ContactStore(
    dao: ref.read(contactDaoProvider),
    send: (peer, notice) =>
        ref.read(directOutboxProvider).enqueueNotice(peer: peer, notice: notice),
    vouch: ref.read(verifiedIdentityStoreProvider).vouch,
  );
});

/// Finding an account by nickname or snowId (key checked against the id).
final contactLookupProvider =
    Provider<ContactLookup>((ref) => ContactLookup(ref.read(apiClientProvider)));

/// The sealed contact backup. A block or an unblock writes it at once.
final contactBackupProvider = Provider<ContactBackup>((ref) {
  final blocks = ref.read(blockListProvider);
  final verified = ref.read(verifiedIdentityStoreProvider);
  final backup = ContactBackup(
    dao: ref.read(contactDaoProvider),
    api: ContactBackupClient(ref.read(apiClientProvider)),
    key: ref.read(identityManagerProvider).deriveContactBackupKey,
    hooks: ContactBackupHooks(
      blockedAccounts: blocks.blockedWithNames,
      mergeBlocks: blocks.mergeRestored,
      replaceServerBlocks: blocks.replaceOnServer,
      restoredInMyList: (snowId, accountPub) async {
        await verified.vouch(snowId, VouchSource.restored);
        if (accountPub != null) await verified.pinAccountKey(snowId, accountPub);
      },
    ),
  );
  blocks.onUserChange = () => unawaited(backup.writeSoon());
  // A block tag key version that changed replaces the server's tags once.
  blocks.onKeyVersion = (v) => unawaited(backup.noteBlockKeyVersion(v));
  ref.onDispose(() {
    blocks.onUserChange = null;
    blocks.onKeyVersion = null;
  });
  return backup;
});

/// Runs the contact backup while an account is signed in: restore once on a
/// new install, replace the server's block tags when due, and the periodic
/// write — at start, on every connect, when the next write is due and when
/// a block / unblock made it due sooner (ContactSyncRunner). Watched by
/// app.dart.
final contactSyncProvider = Provider<void>((ref) {
  final snowId = ref.watch(currentSnowIdProvider);
  final token = ref.watch(authTokenProvider);
  if (snowId == null || snowId.isEmpty || token == null) return;
  final runner = ContactSyncRunner(
    backup: ref.read(contactBackupProvider),
    connectionChanges: ref.read(socketManagerProvider).onConnectionChange,
  )..start();
  ref.onDispose(runner.dispose);
});

/// The restore notice not shown yet (design §5.10): what the restore of this
/// install found — a backup and its date, or none — until the user saw it
/// (ContactBackup.dismissRestoreNotice). Null otherwise. The main shell
/// shows it once.
final contactRestoreNoticeProvider =
    StreamProvider<ContactRestoreReport?>((ref) {
  final snowId = ref.watch(currentSnowIdProvider);
  if (snowId == null || snowId.isEmpty) return Stream.value(null);
  return ref.watch(contactBackupProvider).watchRestoreNotice();
});

/// What a sealed contact notice does here: the contact store takes it, the
/// name certificate it carried names the sender, and — while the app is in
/// the foreground — a request or an acceptance gets a local notification
/// (in the background the server's "New message" push covers it).
Future<void> _applyContactNotice(
  Ref ref,
  String sender,
  String notice,
  String? nameCert,
  bool isAnswer,
) async {
  final store = ref.read(contactStoreProvider);
  final names = ref.read(nameCertServiceProvider);
  if (notice == contactRemovedType) {
    await store.onContactRemoved(sender);
    return;
  }
  if (notice != contactAddedType) return;
  final effect = await store.onContactAdded(sender, isAnswer: isAnswer);
  if (nameCert != null) await names.receive(sender, nameCert);
  if (effect == ContactNoticeEffect.none) return;
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    return;
  }
  final name = await names.nameOf(sender) ?? shortSnowId(sender);
  await NotificationService().showFriendNotification(
    name: name,
    peer: sender,
    accepted: effect == ContactNoticeEffect.requestAccepted,
  );
}

/// A snowId shortened for display when no name is known.
String shortSnowId(String snowId) => snowId.length > 12
    ? '${snowId.substring(0, 8)}…${snowId.substring(snowId.length - 4)}'
    : snowId;

// --- Encrypted Message Handler ---
final encryptedMessageHandlerProvider =
    Provider<EncryptedMessageHandler>((ref) {
  final handler = EncryptedMessageHandler(
    sessionManager: ref.read(signalSessionManagerProvider),
    socketManager: ref.read(socketManagerProvider),
    fileService: ref.read(fileServiceProvider),
    sealedSenderService: ref.read(sealedSenderServiceProvider),
    senderCertificateManager: ref.read(senderCertificateManagerProvider),
    isBlocked: ref.read(blockListProvider).isBlocked,
    // A peer started a new session (it may have reinstalled): its next
    // message from this account carries the name certificate again.
    onNewInboundSession: (peer) =>
        ref.read(nameCertServiceProvider).forgetAnnounced(peer),
  );
  // B-2: instantiating the handler subscribes it to identity store events.
  ref.read(identityChangeHandlerProvider);
  // SC-05: the session manager's session_reset notice goes sealed, through
  // the handler (never a non-sealed private_message).
  ref.read(signalSessionManagerProvider).sessionResetNotifier =
      handler.sendSealedSessionReset;

  // Sealed Sender lazy-wire — sealedSenderServiceProvider is a
  // StateProvider that flips from null to an activated service once an
  // account is signed in (sealedSenderAutoInitProvider). The handler was built with
  // the still-null snapshot (read above), so without this listener
  // _sealedSenderService stayed null forever and isSealedSenderAvailable
  // returned false — observed 2026-05-13 +287: chat_provider's sealed
  // branch logic was correct but every send fell through to regular DR
  // because the runtime check kept seeing null. callSignalingProvider
  // already uses ref.watch so VoIP was fine; switching the message
  // handler to watch would force rebuild + dispose churn across every
  // consumer (messageQueue, chat_provider family, ...). The setter
  // approach updates the single live instance in-place.
  ref.listen<SealedSenderService?>(sealedSenderServiceProvider,
      (prev, next) {
    if (prev != null || next == null) return;
    final certMgr = ref.read(senderCertificateManagerProvider);
    handler.wireSealedSender(service: next, manager: certMgr);
    debugPrint('[Providers] Sealed Sender wired into EncryptedMessageHandler '
        '(certMgr=${certMgr != null})');
  });

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
  // Group protocol v2 invites are kept on disk here, before their message
  // is acknowledged — whether or not the group runtime is up yet. The
  // runtime takes them in when it drains (it is told at once when it runs).
  final database = ref.read(snowDatabaseProvider);
  queue.onGv2Invite = (sender, invite, messageId) async {
    final stored = await database.gv2InboxStore.storeInvite(
      serverRowId: messageId,
      senderSnowId: sender,
      invite: invite,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (stored) queue.onGv2InviteKept?.call();
  };
  // Contact notices go to the contact store (before the ack); a message's
  // name certificate names its sender (before it is stored and notified).
  queue.onContactNotice = (sender, notice, nameCert, isAnswer) =>
      _applyContactNotice(ref, sender, notice, nameCert, isAnswer);
  // A message from a sender whose room has no name yet: the name this
  // device knows (the list, certificates) before the short snowId.
  queue.peerName = (snowId) => ref.read(nameCertServiceProvider).nameOf(snowId);
  queue.onPeerNameCert = (sender, cert) async {
    await ref.read(nameCertServiceProvider).receive(sender, cert);
  };
  // B-2: instantiating the handler subscribes it to identity store events.
  ref.read(identityChangeHandlerProvider);
  return queue;
});

// --- The 1:1 outbox ---
// Sends outgoing 1:1 messages whenever the socket is connected and keeps them
// until the server acks them (core/messaging/direct_outbox.dart). Started
// with the global router (app.dart); one instance for the app.
final Provider<DirectOutbox> directOutboxProvider =
    Provider<DirectOutbox>((ref) {
  final socket = ref.read(socketManagerProvider);
  final db = ref.read(snowDatabaseProvider);
  final outbox = DirectOutbox(
    jobs: db.directOutboxDao,
    messages: ref.read(messageDaoProvider),
    attachments: ref.read(attachmentDaoProvider),
    // Read at each send: the handler is rebuilt when sealed sender comes up.
    handler: () => ref.read(encryptedMessageHandlerProvider),
    isConnected: () => socket.isReadyToSend,
    connectionChanges: socket.onConnectionChange,
    // The server's status events (they name each send by its wire id).
    statusEvents: socket.onMessageStatus,
    upload: (data, hash) =>
        ref.read(fileServiceProvider).uploadEncryptedFile(data, hash),
    documentsPath: () async => (await getApplicationDocumentsDirectory()).path,
    expiring: ref.read(expiringMessageManagerProvider),
    // This account's name goes with a contact notice and with the first
    // message to a peer (and the next one after a rename).
    nameCerts: ref.read(nameCertServiceProvider),
    // The server's word on a recipient goes to the friend list: an account
    // it refuses again and again as not existing shows as unavailable.
    onRecipientChecked: (peer, notFound) {
      final store = ref.read(contactStoreProvider);
      return notFound
          ? store.noteRecipientNotFound(peer)
          : store.noteRecipientReached(peer);
    },
  );
  ref.onDispose(() => unawaited(outbox.stop()));
  return outbox;
});

// --- Phase 6: Global Message Router (socket → queue) ---
final globalMessageRouterProvider = Provider<GlobalMessageRouter>((ref) {
  final router = GlobalMessageRouter(
    socketManager: ref.read(socketManagerProvider),
    queue: ref.read(messageQueueProvider),
    sessionManager: ref.read(signalSessionManagerProvider),
  );
  ref.onDispose(router.stop);
  return router;
});

// --- Group protocol v2 ---
//
// Null while this build pins no server keys for its environment, nobody is
// signed in, or the sealed sender
// service is not up yet: until then the rows of the group queue stay on the
// server (nothing takes them from the REST fetch, and a `gv2_message` from
// the socket is not acknowledged). Once built, it takes both and works on
// every connect. Watched by app.dart so that it is rebuilt when what it
// depends on changes.
final gv2RuntimeProvider = Provider<Gv2Runtime?>((ref) {
  // No server keys trusted for this environment (a build whose keys are not
  // pinned yet): group protocol v2 does not run.
  final trustedKeys = gv2TrustedServerKeys;
  if (trustedKeys == null) return null;
  final snowId = ref.watch(currentSnowIdProvider);
  final sealed = ref.watch(sealedSenderServiceProvider);
  final certificates = ref.watch(senderCertificateManagerProvider);
  if (snowId == null || snowId.isEmpty || sealed == null || certificates == null) {
    return null;
  }

  final db = ref.read(snowDatabaseProvider);
  final api = ref.read(apiClientProvider);
  final socket = ref.read(socketManagerProvider);
  final sessions = ref.read(signalSessionManagerProvider);
  final identity = ref.read(identityManagerProvider);
  final verified = ref.read(verifiedIdentityStoreProvider);
  final queue = ref.read(messageQueueProvider);
  final e2ee = ref.read(encryptedMessageHandlerProvider);

  final sink = Gv2AppMessageSink(
    groups: db.gv2Store,
    messages: ref.read(messageDaoProvider),
    conversations: ref.read(conversationDaoProvider),
    attachments: ref.read(attachmentDaoProvider),
    viewing: MarkReadHelper.isConversationActive,
    documentsDir: () async => (await getApplicationDocumentsDirectory()).path,
    onStored: (m) => queue.gv2MessageStored(
      groupId: m.groupId,
      messageId: m.messageId,
      senderSnowId: m.senderSnowId,
      plaintext: m.payload.text,
      type: m.payload.type,
      metadata: m.payload.metadata,
      ttlSeconds: m.payload.ttlSeconds,
      viewing: m.viewing,
      groupName: m.groupName,
      senderName: m.senderName,
      receivedAtMs: m.receivedAtMs,
    ),
    onRemoved: queue.gv2MessagesRemoved,
    // The Chats list follows a group that changed on this device (created,
    // joined, renamed, left); the open chat shows new rows by itself.
    onGroupChanged: (groupId, _) => queue.gv2GroupChanged(groupId),
  );
  final runtime = Gv2Runtime(
    db: db,
    mySnowId: snowId,
    authenticatedPost: (path) async => (await api.post<Object?>(path)).data,
    // The account key this device already holds for a peer (Identity
    // Binding v1): a member claiming that snowId must show the same key.
    pinnedAccountKey: (peer) async => (await verified.get(peer))?.accountPublicKey,
    crypto: Gv2SealedPairwiseCrypto(
      sealed: sealed,
      certificate: certificates.getCertificate,
      sessions: Gv2SessionManagerSessions(sessions),
    ),
    myDeviceId: sessions.getDeviceId,
    memberKey: identity.deriveGroupMemberKey,
    memberCert: (groupId, issuedAtMs) => identity.signGroupMemberCert(
      groupId: groupId,
      issuedAtMs: issuedAtMs,
    ),
    accountPublicKey: () async {
      final key = await identity.getPublicKey();
      if (key == null) throw StateError('No identity key available');
      return key;
    },
    // The invite message travels the ordinary sealed 1:1 path.
    sendInvite: (recipient, invite) =>
        e2ee.sendSealedGroupInvite(recipientId: recipient, invite: invite),
    // Every invite waits for the user (no automatic accept — P5.6).
    // Over the socket when it is up, else with the 1:1 acknowledgements'
    // REST route. Throws when neither took it: the inbox tries again.
    ack: (ids) async {
      if (socket.isConnected) {
        try {
          await socket.sendGv2Ack(ids);
          return;
        } catch (_) {
          // Fall through to REST.
        }
      }
      await api.post<Object?>(ApiEndpoints.ackMessages, data: {'gv2Ids': ids});
    },
    sink: sink,
    // The list of this account's groups, sealed under a key from the
    // recovery phrase (design §9.8): a reinstall finds its groups there.
    backupApi: Gv2BackupClient(api),
    backupKey: identity.deriveGroupBackupKey,
    trustedKeys: trustedKeys,
    // X1: an invite from an account this user blocked is dropped.
    isBlocked: ref.read(blockListProvider).isBlocked,
  );

  queue.onGv2Rows = runtime.receive;
  // An invite the 1:1 queue kept (an inbox row) is taken in on a drain.
  queue.onGv2InviteKept = () => unawaited(runtime.pump());
  final rows = socket.onGv2Row.listen(
    (row) => unawaited(runtime.receive([row])),
  );
  final connection = socket.onConnectionChange.listen((connected) {
    if (connected) unawaited(runtime.pump());
  });
  // SC-18: a message to a group comes back to this account too (the
  // recipient set is the roster), and the server pushes every row not
  // acknowledged a few seconds after the send — it is not told which row is
  // the sender's. Over the socket that row arrives and is acknowledged at
  // once; without one it is fetched here, so this phone shows no
  // notification of its own message.
  final sent = runtime.sendEvents.listen((event) {
    if (event is Gv2MessageSent && !socket.isConnected) {
      unawaited(queue.fetchPending());
    }
  });
  // What became of the messages this account queued (the row of a message
  // the server took reads "sent", one that will never go reads "failed" —
  // a group shows no "delivered", design §12) is written by the sink in the
  // outbox's own transaction (Gv2AppMessageSink.outgoing).
  // What waited — on the server while this was not running, and on this
  // device from the last run.
  unawaited(queue.fetchPending());
  unawaited(runtime.pump());
  ref.onDispose(() {
    queue.onGv2Rows = null;
    queue.onGv2InviteKept = null;
    unawaited(rows.cancel());
    unawaited(connection.cancel());
    unawaited(sent.cancel());
    runtime.dispose();
  });
  return runtime;
});

// --- Notification Service ---
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  // Initialize async — callers should await initialize() before showing
  // notifications. The prompts (notifications, then the microphone) are
  // PushService's, through askStartupPrompts.
  unawaited(service.initialize());
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

// --- Link Preview Service ---
final linkPreviewServiceProvider = Provider<LinkPreviewService>((ref) {
  return LinkPreviewService();
});

// --- Friend Request Badge ---
/// The received friend requests on this device (contact rows the account
/// added this user to, not added back, not declined). The router shows it
/// on the Friends tab.
final pendingFriendBadgeProvider = StreamProvider<int>((ref) {
  return ref.watch(contactStoreProvider).watch().map((rows) => rows
      .where((r) => r.isVisible && r.label == ContactLabel.requestReceived)
      .length);
});

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
    // X1: a blocked account's call signals go nowhere.
    isBlocked: ref.read(blockListProvider).isBlocked,
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
    // SC-10: DTLS fingerprints are signed with this device's Signal-layer
    // Ed25519 key and checked against the peer's account-bound one.
    fingerprintSigningSeed: () =>
        signaling.sessionManager.signal.signingKeySeed,
    peerFingerprintKey: signaling.sessionManager.getPeerEd25519PublicKey,
    // An incoming call is named by this device (contact, then certificate),
    // never by the name the caller puts in its invite.
    peerName: ref.read(nameCertServiceProvider).cachedName,
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
    // "Show caller name on calls": waits for the stored value, false while
    // it cannot be read — a system call UI stays "SnowChat Call" then.
    showCallerNameOnSystemUi: () =>
        ref.read(settingsProvider.notifier).callShowCallerNameForCall(),
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
      : _ref = ref,
        super(
          callService: _UnavailableCallService(),
          callKitManager: ref.read(callKitManagerProvider),
        );

  final Ref _ref;

  /// Bug D self-heal (2026-06-08): SealedSender wasn't ready when this notifier
  /// was built (sealedSenderAutoInit's fetch failed, or it exhausted its retry
  /// loop while the device was offline). Instead of the raw placeholder throw,
  /// kick a re-init — the user is clearly online and interacting now — so the
  /// next tap can succeed once sealedSenderServiceProvider flips and callProvider
  /// rebuilds into the real CallNotifier. We intentionally do NOT transition to
  /// `outgoing` (no phantom OutgoingCallScreen for a call that never started).
  @override
  Future<void> startCall({
    required String recipientSnowchatId,
    required bool alwaysRelay,
    String? remoteDisplayName,
  }) async {
    _ref.invalidate(sealedSenderAutoInitProvider);
    throw StateError(
        'Call service is still starting up — please try again in a moment.');
  }
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
