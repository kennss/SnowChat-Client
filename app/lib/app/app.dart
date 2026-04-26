/// @file        app.dart
/// @description Root widget of the SnowChat app + Material theme + notification tap routing
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; AI model status disk sync — prevents cold start trap)
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/ai/providers/ai_provider.dart';
import '../shared/constants/colors.dart';
import 'deeplink_handler.dart';
import 'providers.dart';
import 'router.dart';

/// Backwards compat alias — router.dart's rootNavigatorKey points at GoRouter's
/// main navigator, so global dialog display reuses it.
final securityAlertNavigatorKey = rootNavigatorKey;

/// Wallet V2 Phase F — global ScaffoldMessenger handle. Used by TransferService
/// to show toasts (transfer declined / failed / network mismatch, etc.) regardless
/// of screen lifecycle. Wired to MaterialApp.scaffoldMessengerKey.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class SnowChatApp extends ConsumerWidget {
  const SnowChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

        // AI model status disk sync — every cold start creates a fresh
        // AIModelManager instance whose downloadStatus ValueNotifier resets to idle.
        // Even when a 2.5GB model sits perfectly fine on disk, if status is idle the
        // onboarding screen shows the "Download AI Model" button — and tapping it
        // wipes the existing file and re-downloads from scratch (UX trap).
        // startBackgroundDownload() syncs status=complete when installed and returns —
        // when not installed + on WiFi, kicks off auto download; on cellular, stays idle.
        unawaited(ref.read(aiModelManagerProvider).startBackgroundDownload());

        // SealedSender auto-init — watches authToken changes.
        // Right after onboarding when authToken is created, automatically fetches
        // the server verify key + updates sealedSenderServiceProvider state →
        // chain rebuild reaches callProvider.
        ref.watch(sealedSenderAutoInitProvider);

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
          // Android: incoming stage is owned exclusively by the system Toast
          // (ConnectionService). Showing Flutter IncomingCallScreen concurrently
          // confuses the user across two UIs, and only the Toast's ACCEPT intent
          // works — Flutter's accept button becomes a dead-button. Once status
          // transitions to connecting/active, ActiveCallScreen takes over (post-accept).
          // iOS doesn't have PushKit implemented, so Flutter UI handles incoming too.
          if (Platform.isAndroid && next.status == CallStatus.incoming) {
            return;
          }
          // GoRouter doesn't dedupe if /call is already on the stack, so check
          // currentConfiguration before pushing (prevents duplicate stack entries).
          final currentPath = router.routerDelegate.currentConfiguration.uri.path;
          if (currentPath == '/call') return;
          router.push('/call');
        });

        final sm = ref.read(socketManagerProvider);

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

