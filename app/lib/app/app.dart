/// @file        app.dart
/// @description Root widget of the SnowChat app + Material theme + notification tap routing
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-07 (expiredHard listener now attempts silent
///              challenge-response re-auth via local identity
///              (Keystore/Keychain) before falling back to SnackBar +
///              /welcome nav. 2026-05-07 server-side
///              publish-before-subscribe race occasionally bounced
///              both iPhone + Galaxy users to onboarding screen even
///              though their identity was intact; this client-side
///              guard recovers silently when the server is healthy.
///              Earlier 2026-05-06: cold-launch auto-download of the
///              Gemma 4 E2B AI model removed — single-point gating now
///              lives on the SnowChat AI tile (ai_chat_tile.dart);
///              iPhone 13 (4 GB) testing showed the eager 2.9 GB fetch
///              made the whole app unusable for low-RAM devices that
///              could never load the model in the first place. Earlier
///              same-day option 1 hardening: idle listener queries
///              snowchat/keyguard and runs SystemNavigator.pop()
///              instead of router.pop() when the keyguard is still
///              locked, so the chat / wallet route underneath /call
///              does not become visible on the lock screen via
///              MainActivity's showWhenLocked manifest flag.
///              Earlier 2026-05-03 (Phase 11): TokenManager.events
///              expiredHard listener — SnackBar + nav to /welcome.)
///
/// @functions
///  - SnowChatApp: app root ConsumerWidget, configures MaterialApp.router
///  - snowTheme(): factory for Material ThemeData based on dark mode
///  - rootScaffoldMessengerKey: global ScaffoldMessenger handle (Wallet V2 Phase F)

import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/diagnostics/diag_log.dart';
import '../core/network/token_manager.dart';
import '../shared/constants/colors.dart';
import 'package:go_router/go_router.dart';

import 'deeplink_handler.dart';
import 'providers.dart';
import 'router.dart';

/// MethodChannel into MainActivity's KeyguardManager bridge. Returns true
/// when the device is currently locked (PIN/pattern/biometric required to
/// dismiss the keyguard). iOS has no equivalent surface — CallKit is the
/// system-level call host there, not our Activity — so this is Android-only.
const _keyguardChannel = MethodChannel('snowchat/keyguard');

Future<bool> _isKeyguardLocked() async {
  if (!Platform.isAndroid) return false;
  try {
    final locked = await _keyguardChannel.invokeMethod<bool>('isLocked');
    diagLog('SnowChatDiag', '[keyguard] isLocked → ${locked ?? false}');
    return locked ?? false;
  } catch (e) {
    diagLog('SnowChatDiag', '[keyguard] isLocked ERROR: $e — assuming false');
    return false;
  }
}

/// At /call → idle transition, finish the Activity if the keyguard is
/// still locked; otherwise just pop /call.
///
/// Why finish on locked: MainActivity's manifest carries showWhenLocked=true
/// so the call path can render /call without forcing PIN entry. That same
/// flag would otherwise leave the underlying chat / wallet route visible
/// on top of the keyguard once /call is popped — a security regression.
/// SystemNavigator.pop() finishes the Activity, returning the user to
/// the lock screen.
Future<void> _maybeFinishOnKeyguardElsePop(GoRouter router) async {
  diagLog('SnowChatDiag', '[idleClose] enter');
  if (await _isKeyguardLocked()) {
    diagLog('SnowChatDiag', '[idleClose] keyguard locked → SystemNavigator.pop');
    await SystemNavigator.pop();
    return;
  }
  // Unlocked path: do nothing here. _CallRouteHost (router.dart) already
  // popped /call synchronously the moment status flipped to idle; the user
  // is now on the underlying chat / wallet route they had open before the
  // call, which is the desired UX when the device was already unlocked.
  diagLog('SnowChatDiag', '[idleClose] keyguard unlocked → no-op');
}

/// Backwards compat alias — router.dart's rootNavigatorKey points at GoRouter's
/// main navigator, so global dialog display reuses it.
final securityAlertNavigatorKey = rootNavigatorKey;

/// Wallet V2 Phase F — global ScaffoldMessenger handle. Used by TransferService
/// to show toasts (transfer declined / failed / network mismatch, etc.) regardless
/// of screen lifecycle. Wired to MaterialApp.scaffoldMessengerKey.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 2026-05-07 Auto re-auth dedup flag.
///
/// `expiredHard` event listener (below) tries challenge-response re-auth first
/// using the local identity (Keystore/Keychain). Multiple expiredHard fires
/// (e.g. simultaneous API call failures all hitting 401 in the same window)
/// would otherwise spawn parallel authenticate() calls. This guard ensures
/// only the first one runs; the rest noop until it settles.
bool _autoReauthInflight = false;

/// 2026-05-07 (+267) — one-shot guard for the expiredHard event listener.
/// `events.listen()` was previously called inside `build()`, so every Riverpod
/// rebuild of SnowChatApp added another listener; in the field a single
/// expiredHard fired ~40 redundant listener invocations (Galaxy logcat
/// 22:14:48). The flag below makes registration idempotent — only the first
/// build path subscribes; the subscription lives for the app lifetime so
/// no `cancel` path is needed.
bool _tokenEventListenerRegistered = false;

class SnowChatApp extends ConsumerWidget {
  const SnowChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // [+248 reverted 2026-05-05] Removed prior eager `ref.read(callProvider)`.
    // It was meant to kick the dependency chain before appStartupProvider
    // gates the tree, racing the cold-launch DECLINE 3s window. But it bound
    // ref.listen<CallState>(callProvider, ...) to a freshly-built _IdleCallNotifier
    // instance whose underlying _UnavailableCallService throws on acceptCall —
    // resulting in iOS FG/BG receive flow: CallKit accept fires (green capsule)
    // but the listener attached to _IdleCallNotifier never sees the
    // incoming → connecting/active transition (real CallNotifier rebuild
    // creates a fresh state stream). Symptom: green CallKit indicator
    // appears, ActiveCallScreen never pushes. Decline race is handled by
    // the BG isolate D-2 pipeline once that lands, not here.

    // Wait for app startup initialization (secure storage check) before routing
    final startup = ref.watch(appStartupProvider);

    return startup.when(
      data: (_) {
        final router = ref.watch(routerProvider);

        // Eagerly initialize services that must run at app start
        final db = ref.read(snowDatabaseProvider); // DB persistence

        // Perf: Pre-warm drift — trigger LazyDatabase.resolve + onCreate/onUpgrade
        // in background so first real query (from chat screens / restoreIdentity)
        // doesn't block PIN setup UI. Saves ~1.9s on iOS fresh install where
        // CREATE TABLE ×10 + indexes runs inside drift.
        unawaited(db.customStatement('SELECT 1').catchError((e) {
          debugPrint('[AppStartup] drift pre-warm failed: $e');
        }));

        ref.read(pushServiceProvider);  // Push notification listener
        ref.read(voipPushServiceProvider);  // iOS PushKit (Phase E-2)
        // Phase E-2 v3.1: keep VoIP native bridge + base-URL push alive so
        // CallAcceptCoordinator drains envelopes whenever a CallKit accept
        // arrives, regardless of route. The FutureProvider auto-fires once
        // authTokenProvider transitions non-null.
        ref.read(voipNativeBridgeProvider);
        ref.watch(voipNativeBaseUrlPushProvider);

        // 2026-05-06: cold-launch auto-download removed. The AI flow is now
        // gated by DeviceCapability on the SnowChat AI tile (ai_chat_tile.dart);
        // an explicit tap on the tile is what triggers the 2.9 GB fetch via
        // /ai-onboarding → startManualDownload. iPhone 13 (4 GB) field
        // testing showed the eager download — followed by an OOM during
        // model load — bricked the app for users whose hardware can never
        // run Gemma 4 E2B in the first place. The status-disk-sync side
        // effect (fresh AIModelManager instance defaulting to idle even
        // when the file already lives on disk) is preserved by
        // aiModelManagerProvider firing syncStatusFromDisk() on first
        // read; a returning user with the model installed sees the
        // "On-Device" badge as soon as the chat list builds.

        // SealedSender auto-init — watches authToken changes.
        // Right after onboarding when authToken is created, automatically fetches
        // the server verify key + updates sealedSenderServiceProvider state →
        // chain rebuild reaches callProvider.
        ref.watch(sealedSenderAutoInitProvider);

        // FCM push token auto-sync — watches authToken changes. The fresh-signup
        // path (onboarding → register → authenticate) sets authToken without
        // restarting the app, so PushService.initialize()'s inline register call
        // (which ran at boot before device_id existed) is the only attempt
        // unless this watcher kicks. Keeping it alive here ensures the
        // null→non-null transition triggers retryTokenRegistration().
        ref.watch(pushTokenAutoSyncProvider);

        // Phase 8.1-D: Wire notification tap → chat room navigation
        ref.read(notificationServiceProvider).onNotificationTap =
            (conversationId) {
          router.go('/chat/$conversationId');
        };

        // FCM: Background tap → app opened from notification
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          final convId = message.data['conversationId'] as String?;
          if (convId != null && convId.isNotEmpty) {
            router.go('/chat/$convId');
          }
        });

        // FCM: Terminated state → app opened from notification
        FirebaseMessaging.instance.getInitialMessage().then((message) {
          if (message != null) {
            final convId = message.data['conversationId'] as String?;
            if (convId != null && convId.isNotEmpty) {
              router.go('/chat/$convId');
            }
          }
        });

        // Phase 1 invite deeplink (snowchat://invite/<code>) — wire app_links
        // cold + warm streams. canNavigateNow gate: only push /invite when the
        // user has completed onboarding + unlocked PIN (otherwise queue and
        // consume on /chat mount). Phase 2 will extend to https Universal Link.
        unawaited(DeeplinkHandler.instance.start(
          router,
          canNavigateNow: () =>
              ref.read(isOnboardedProvider) &&
              !ref.read(requiresPinSetupProvider) &&
              !ref.read(isLockedProvider),
        ));

        // Phase 6: Single global router that drains all incoming messages
        // through the MessageQueue. ChatNotifier no longer subscribes to
        // socket events for messages — it only watches drift.
        ref.read(globalMessageRouterProvider).start();

        // Phase 8.2 VoIP — eager init of CallNotifier so its CallSignaling
        // subscriber to onSealedCallSignaling is registered before any
        // incoming call arrives. Without this, the SocketManager's
        // broadcast stream has zero listeners on the receiver side and
        // the inbound `sealed_call_signaling` event is silently dropped
        // (chicken-and-egg: incoming UI cannot mount because the listener
        // that would surface it never ran). Subsequent rebuilds when the
        // SealedSenderService finishes initializing will reuse the same
        // notifier via Riverpod identity.
        ref.read(callProvider);

        // Phase 8.2 VoIP — receiver-side auto-navigation to /call.
        // chat_screen pushes /call manually for the caller after startCall(),
        // but the callee path has no UI handler — without this the receiver
        // stays on the chat list while WebRTC negotiates in the background.
        //
        // [2026-04-19 root cause] Prior attempt: yield a frame via
        // addPostFrameCallback → on iPhone receiver the callback itself never fired.
        // Cause: when the incoming signal arrives, no widget watches callProvider
        // (/call not mounted, no other watchers) → Riverpod doesn't schedule a frame
        // → it sits in the postFrame queue forever. Android worked by accident
        // because the native CallKit ACCEPT intent forcibly triggered a foreground frame.
        // Fix: call router.push directly — push triggers navigator markNeedsBuild →
        // frame is scheduled.
        ref.listen<CallState>(callProvider, (prev, next) {
          // outgoing/incoming/connecting/active — every stage of the call lifecycle.
          // If outgoing is missed, on the caller side chat_screen's `await startCall()`
          // blocks until WebRTC setup completes (~5-6s) before pushing → UI shows late.
          final isInCall = next.status == CallStatus.outgoing ||
              next.status == CallStatus.incoming ||
              next.status == CallStatus.connecting ||
              next.status == CallStatus.active;
          if (!isInCall) return;
          if (prev?.status == next.status) return;
          // 2026-05-05 — v211 revert, WhatsApp/Signal 정책 채택. incoming UI
          // 는 OS-level CallKit (iOS) / ConnectionService (Android) 가 단독
          // 소유. Dart auto-push 차단해서 in-app IncomingCallScreen 미표시.
          //
          // 분기:
          //  - 모든 플랫폼/lifecycle: incoming → /call route push 안 함
          //
          // 사유:
          //  - WhatsApp/Signal 패턴 — banner only. 사용자가 banner 학습됨.
          //  - v211 의 dual-UI (iOS FG 에서 banner + in-app full screen 동시)
          //    가 UX 혼란 (사용자 보고: "수신 처리 배너와 수신 화면 둘 다").
          //  - v207 원래 의도였고 PushKit native CallKit 표시는 신뢰 가능.
          //  - small top banner 가 놓칠 위험은 학습으로 해결. dual-UI 보다는 명료함이 우선.
          //
          // 영향: iOS FG 수신 시 사용자는 CallKit small banner 만 보게 됨.
          // accept 시 CallKit accept event → CallNotifier acceptCall path 그대로.
          // 기존 IncomingCallScreen widget 은 라우트로 도달 불가 (router 의
          // `case CallStatus.incoming` branch 는 dead code 지만 router 단순성
          // 위해 남김 — 향후 정리 가능).
          if (next.status == CallStatus.incoming) {
            diagLog(
              'routePush',
              'skip /call — status=incoming (CallKit/ConnectionService owns UI)',
            );
            return;
          }
          // GoRouter doesn't dedupe if /call is already on the stack, so check
          // currentConfiguration before pushing (prevents duplicate stack entries).
          final currentPath = router.routerDelegate.currentConfiguration.uri.path;
          if (currentPath == '/call') {
            diagLog(
              'routePush',
              'skip /call — already on /call (status=${next.status})',
            );
            return;
          }
          diagLog(
            'routePush',
            'push /call status=${next.status} prev=${prev?.status} '
                'currentPath=$currentPath',
          );
          router.push('/call');
        });

        // 2026-05-04 fix: BG-resilient auto-pop for /call when status returns
        // to idle. The widget-tree level `ref.listen` inside `_CallRouteHost`
        // (router.dart:585) only fires when the widget actually rebuilds —
        // when the app is backgrounded during a call and the call ends in
        // BG, that listener may not fire (Flutter pauses non-essential
        // rebuilds). This global listener fires regardless.
        //
        // 2026-05-06 keyguard branch: when the keyguard is still locked at
        // call end, finish the Activity instead of popping into the
        // underlying route. MainActivity carries showWhenLocked=true so a
        // call accepted on a locked phone can render /call without forcing
        // PIN entry; that flag also keeps the underlying route visible
        // over the lock screen unless the Activity itself is finished.
        // SystemNavigator.pop() finishes the Activity, returning the user
        // to the lock screen.
        ref.listen<CallState>(callProvider, (prev, next) {
          if (next.status == CallStatus.idle &&
              prev?.status != CallStatus.idle) {
            // currentPath logged for diagnostics, but the keyguard finish
            // logic must NOT gate on it. Other listeners (router.dart's
            // _CallRouteHost listener + post-frame callback) pop /call
            // synchronously the moment status becomes idle, so by the
            // time this async-aware listener fires the route is already
            // on /chat (or whatever was underneath). The lock screen
            // exposure is the same regardless of which route is now on
            // top — we have to query the keyguard and finish the
            // Activity if locked, irrespective of currentPath.
            final currentPath =
                router.routerDelegate.currentConfiguration.uri.path;
            diagLog(
              'SnowChatDiag',
              '[idleListener] transition → idle, currentPath=$currentPath '
                  'prev=${prev?.status}',
            );
            _maybeFinishOnKeyguardElsePop(router);
          }
        });

        final sm = ref.read(socketManagerProvider);

        // Phase 11 — TokenManager.events expiredHard handler.
        //
        // 2026-05-07 (refresh-race recovery) — server-side false-positive
        // family revoke (publish-before-subscribe race, fixed in
        // RefreshTokenManager 2026-05-07) used to bounce both iPhone +
        // Galaxy callers all the way to onboarding screen even though the
        // local identity (Keystore/Keychain) was intact. Recovery only via
        // user manual swipe-restart so cold-start path picks up the
        // identity again.
        //
        // 정공법 — try challenge-response re-auth FIRST before showing
        // SnackBar / navigating to /welcome. Local identity persists across
        // token wipes (it lives in secure storage, not in TokenManager state),
        // so any 3×-refresh-failure can be silently recovered as long as the
        // server is reachable and the user hasn't actually logged out.
        //
        // Fallback (no local identity OR challenge re-auth fails): existing
        // behavior — SnackBar + nav to /welcome. User then enters Restore
        // from Backup or creates a fresh identity.
        //
        // The 3× internal refresh exhausted path inside TokenManager already
        // cleared the TokenSnapshot before emitting expiredHard, so calling
        // authenticate() here goes via the auth-exempt /auth/challenge +
        // /auth/verify pair (api_client.dart:46-52) — no recursive ensureFresh
        // deadlock.
        ref.listen<TokenSnapshot?>(tokenSnapshotProvider, (_, __) {});
        // 2026-05-07 (+267) — one-shot listener registration. Pre-fix this
        // ran on every Consumer rebuild and accumulated dozens of duplicate
        // subscriptions; Galaxy logcat 22:14:48 showed 40 listeners reacting
        // to a single expiredHard event.
        if (!_tokenEventListenerRegistered) {
          _tokenEventListenerRegistered = true;
          ref.read(tokenManagerProvider).events.listen((event) async {
            if (event.type != TokenEventType.expiredHard) return;
            if (_autoReauthInflight) {
              debugPrint('[TokenManager:expiredHard] auto re-auth already '
                  'in-flight — second event suppressed');
              return;
            }
            _autoReauthInflight = true;
            try {
              // (1) Local identity check. SnowChat 의 identity 는 Keystore/
              // Keychain 에 영속, TokenManager.clear() 영향 안 받음. 있으면
              // challenge-response 로 자동 재인증 가능.
              final identityManager = ref.read(identityManagerProvider);
              final hasLocal = await identityManager.hasIdentity();

              if (hasLocal) {
                try {
                  final authService = ref.read(authServiceProvider);
                  final snapshot = await authService.authenticate();
                  await ref.read(tokenManagerProvider).setFromLogin(snapshot);
                  debugPrint('[TokenManager:expiredHard] auto re-auth '
                      'succeeded — staying on current route, no UI change');
                  return;
                } catch (e) {
                  debugPrint('[TokenManager:expiredHard] auto re-auth '
                      'failed: ${e.runtimeType} — falling back');
                  // fall through to fallback flow
                }
              } else {
                debugPrint('[TokenManager:expiredHard] no local identity — '
                    'going to /welcome');
              }

              // Fallback. Behavior depends on app lifecycle:
              //
              // FG (resumed):
              //   SnackBar + router.go('/welcome'). User sees the message and
              //   the welcome screen takes them through Restore-from-Backup
              //   or fresh identity creation.
              //
              // BG (paused/inactive/hidden/detached):
              //   router.go() is silently dropped because the framework is
              //   not painting frames; the user would resume to a /chat
              //   screen with broken auth state and SnackBar already gone
              //   (Galaxy field report 2026-05-07). Instead `SystemNavigator.pop()`
              //   exits the app cleanly. Next launch goes through cold-start
              //   which always tries challenge re-auth via the secure-storage
              //   identity, and recovers transparently when the original
              //   failure was transient (network blip during BG proactive
              //   refresh).
              final lifecycle = WidgetsBinding.instance.lifecycleState;
              final isResumed = lifecycle == AppLifecycleState.resumed;
              if (!isResumed) {
                debugPrint('[TokenManager:expiredHard] app in $lifecycle — '
                    'SystemNavigator.pop() so cold-start recovers');
                try {
                  await SystemNavigator.pop();
                } catch (e) {
                  debugPrint('[TokenManager:expiredHard] pop failed: $e');
                }
                return;
              }
              final messenger = rootScaffoldMessengerKey.currentState;
              messenger?.showSnackBar(
                const SnackBar(
                  content: Text('Session expired. Please log in again.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              // Defer the nav so the SnackBar gets a frame before route change.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  router.go('/welcome');
                } catch (e) {
                  debugPrint('[TokenManager:expiredHard] nav failed: $e');
                }
              });
            } finally {
              _autoReauthInflight = false;
            }
          });
        }

        // Listen for security alerts via socket
        sm.onUnauthorizedLoginAttempt.listen((_) {
          final ctx = securityAlertNavigatorKey.currentContext;
          if (ctx != null) {
            showDialog(
              context: ctx,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                backgroundColor: SnowColors.surface,
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: SnowColors.error, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Security Alert',
                          style:
                              TextStyle(color: SnowColors.error, fontSize: 18)),
                    ),
                  ],
                ),
                content: const Text(
                  'Another device attempted to access your account.\n\n'
                  'If this wasn\'t you, your recovery phrase may be compromised. '
                  'Consider creating a new identity and transferring your assets.',
                  style:
                      TextStyle(color: SnowColors.textSecondary, height: 1.5),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
            );
          }
        });

        // [2026-04-19] Removed outer Navigator wrapper — root cause of the
        // receiver-side symptom where GoRouter push reached /call but _CallRouteHost
        // never mounted. The outer Navigator wrapped GoRouter's RouterDelegate output
        // a second time and blocked route-change propagation. securityAlert dialog
        // can produce the same effect via GoRouter's _rootNavigatorKey
        // (router.dart's rootNavigatorKey).
        return MaterialApp.router(
          title: 'SnowChat',
          debugShowCheckedModeBanner: false,
          theme: snowTheme(),
          routerConfig: router,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
        );
      },
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: snowTheme(),
        home: const Scaffold(
          backgroundColor: SnowColors.background,
          body: Center(
            child: CircularProgressIndicator(color: SnowColors.primary),
          ),
        ),
      ),
      error: (_, __) {
        // On error, still show router (will go to welcome)
        final router = ref.watch(routerProvider);
        return MaterialApp.router(
          title: 'SnowChat',
          debugShowCheckedModeBanner: false,
          theme: snowTheme(),
          routerConfig: router,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
        );
      },
    );
  }
}

ThemeData snowTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SnowColors.background,
      colorScheme: const ColorScheme.dark(
        primary: SnowColors.primary,
        surface: SnowColors.surface,
        error: SnowColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SnowColors.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: SnowColors.primary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: SnowColors.surface,
        selectedItemColor: SnowColors.primary,
        unselectedItemColor: SnowColors.textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: const CardThemeData(
        color: SnowColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SnowColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: SnowColors.textTertiary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: SnowColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: SnowColors.textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: SnowColors.textTertiary, fontSize: 12),
      ),
      dividerTheme: const DividerThemeData(
        color: SnowColors.divider,
        thickness: 0.5,
        space: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SnowColors.primary,
          foregroundColor: SnowColors.background,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SnowColors.primary,
          side: const BorderSide(color: SnowColors.primary),
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

