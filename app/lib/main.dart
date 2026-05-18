/// @file        main.dart
/// @description App entry point. DNS cache override, Firebase init, system UI setup, ProviderScope init
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-11 (App-wide screen capture protection — moved
///              ScreenProtector.protectDataLeakageOn() + preventScreenshotOn()
///              from per-screen wiring (5 screens) to single one-shot init in
///              main() before runApp. Never toggled off — every SnowChat
///              screen is sensitive by policy (Zero-Knowledge + Sovereignty
///              Stack narrative). Side benefit: the iOS "Off() at dispose
///              races with audio session teardown → 30s freeze after end
///              button" workaround (active_call_screen 2026-04-17) no longer
///              needed because Off() is never called. Android FLAG_SECURE
///              blocks capture + recording + thumbnails. iOS uses screen_protector
///              UISecureTextField wrap — Flutter widget capture shows black,
///              but texture-backed GPU surfaces (WebRTC video, raw bitmap
///              renders) may bypass — verify visually after install. Earlier
///              2026-05-06 (Fix E — _firebaseBackgroundHandler now branches on
///              type='call_cancel' to dismiss Telecom Connection from the BG
///              isolate without booting the main engine. Solves the cold-start
///              "Galaxy keeps ringing after iPhone cancels" matrix that only
///              reproduces when callee is locked / swipe-dismissed). Earlier
///              2026-05-03 (Phase 11 — TokenManager.registerMainIsolateOwner()
///              call so BG isolates can detect main isolate presence and refuse
///              token refresh. Pairs with TokenManager.isMainIsolateOwnerSync().)
///
/// @functions
///  - main(): app initialization and run
///  - _firebaseBackgroundHandler(): FCM background message handler
///  - _CachedDnsHttpOverrides: workaround for Dart DNS bug — resolve once at app start, then cache

import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'app/app.dart';
import 'core/call/voip_push_handler.dart';
import 'core/network/api_endpoints.dart';
import 'core/network/token_manager.dart';

/// Workaround for Dart VM DNS resolver failing on some Android devices
/// (OS-level DNS works, but Dart's InternetAddress.lookup() returns empty).
/// Pre-resolves the production hostname at app startup and injects the IP
/// via HttpClient.connectionFactory. SNI uses original hostname for SSL.
class _CachedDnsHttpOverrides extends HttpOverrides {
  final String _host;
  final String _ip;
  _CachedDnsHttpOverrides(this._host, this._ip);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory =
        (Uri uri, String? proxyHost, int? proxyPort) async {
      final targetHost = (uri.host == _host) ? _ip : uri.host;
      final port = uri.port != 0
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80);
      // Connect raw TCP to resolved IP
      final socket = await Socket.connect(targetHost, port,
          timeout: const Duration(seconds: 15));
      if (uri.scheme == 'https') {
        // Upgrade to TLS with original hostname for SNI (certificate match)
        final secure = SecureSocket.secure(socket, host: uri.host);
        return ConnectionTask.fromSocket(secure, () => socket.destroy());
      }
      return ConnectionTask.fromSocket(Future.value(socket), () => socket.destroy());
    };
    return client;
  }
}

/// FCM background message handler — must be top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final type = message.data['type'];
  // Phase I (Phase 8.2 §25): FCM Voice Push — show CallKit incoming UI even
  // when the app is killed/backgrounded. Zero plaintext metadata leak, anonymous display.
  if (type == 'incoming_call') {
    await VoipPushHandler.handleIncomingCall(message.data);

    // [D-1 verification 2026-05-05]
    //
    // FlutterCallkitIncomingPlugin.sendEvent broadcasts to every
    // EventCallbackHandler registered via onAttachedToEngine — one per
    // FlutterEngine. If the BG FlutterEngine attaches the plugin, a
    // listener registered here in the BG isolate should receive decline
    // events even though the main isolate has not booted.
    //
    // If this listener fires on decline (verified via Process.run('log')
    // → logcat 'BG_LISTENER_TEST'), option D is feasible: we can move
    // the entire cold-launch decline pipeline into the BG isolate and
    // skip the Activity-launch dance entirely. If it never fires, option
    // D is architecturally dead and we escalate to option C (dedicated
    // Dart entry point).
    await _bgLog('listener registering after CallKit raised');
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;
      await _bgLog('event received action=${event.event.name}');
    });
    return;
  }
  // Fix E (2026-05-06) — caller-cancel cold-start path.
  // Server (callHandler.ts reuse-branch) fires this FCM data-only when a caller
  // cancels and the callee process is dead. Dismiss the Telecom Connection
  // raised by the original 'incoming_call' push so the phone stops ringing
  // immediately instead of waiting for the plugin's 30s ringer auto-timeout.
  // The missed-call system message inserts later when the user opens SnowChat
  // and the queued call_end envelope (Fix C) surfaces via socket reconnect →
  // CallSignaling.injectEnvelope → _onIncoming → CallService fallback.
  //
  // BG isolate can call FlutterCallkitIncoming.endCall directly — the plugin's
  // Android implementation routes through Telecom regardless of main engine
  // presence. iOS does not reach this branch (Apple PushKit only delivers
  // 'incoming_call' type pushes; we never send 'call_cancel' to iOS).
  if (type == 'call_cancel') {
    final callId = message.data['callId'] as String?;
    await _bgLog('call_cancel received callId=$callId');
    if (callId != null && callId.isNotEmpty) {
      try {
        await FlutterCallkitIncoming.endCall(callId);
        await _bgLog('call_cancel endCall dispatched callId=$callId');
      } catch (e) {
        await _bgLog('call_cancel endCall error: ${e.runtimeType}');
      }
    }
    return;
  }
  debugPrint('[FCM] Background message: ${message.data}');
}

/// Emit a logcat line from the BG isolate via the Android `log` system
/// utility. Works in release builds where Dart `print` / `debugPrint` are
/// stripped. No permissions required (`/system/bin/log` is universally
/// callable).
Future<void> _bgLog(String msg) async {
  try {
    await Process.run('log', ['-t', 'BG_LISTENER_TEST', msg]);
  } catch (_) {
    // Best-effort diagnostic — never propagate.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-resolve production DNS at startup (workaround for Dart VM DNS bug).
  // Some Android devices fail InternetAddress.lookup() while OS DNS works.
  await ApiEndpoints.resolveProductionDns();
  if (ApiEndpoints.resolvedIp != null) {
    HttpOverrides.global = _CachedDnsHttpOverrides(
      ApiEndpoints.prodHost,
      ApiEndpoints.resolvedIp!,
    );
    debugPrint('[DNS] Override active: ${ApiEndpoints.prodHost} → ${ApiEndpoints.resolvedIp}');
  }

  // Phase 8.1: Firebase initialization
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  // Phase 11: register the main-isolate marker port. BG isolates (FCM bg
  // handler etc.) lookup this port — absence = "I'm not main, refuse to
  // refresh JWT". Without this, a parallel isolate could trigger a refresh
  // that wins the server-side jti CAS and clobbers main isolate's snapshot.
  TokenManager.registerMainIsolateOwner();

  // App-wide screen capture protection — one-shot init, never toggled off.
  // Every SnowChat screen is sensitive by policy; rather than per-screen wiring
  // (which the codebase had on 5 screens until 2026-05-11) we apply protection
  // globally. Recipients are also protected automatically: when both sides run
  // SnowChat the sent messages are blocked from screenshot on the receiving
  // device too. Side-channel attacks (camera-of-another-phone) remain unblockable
  // — communicate that honestly in marketing copy.
  //
  // Android: FLAG_SECURE — blocks screenshot, screen recording, recents
  // thumbnail. Official Android API, fully reliable.
  // iOS: UISecureTextField wrap (screen_protector implementation) — Flutter
  // widget content renders black in screenshots / screen recording / AirPlay
  // mirroring. Undocumented Apple behavior used by Signal, Bitwarden, 1Password.
  // Texture-backed GPU surfaces (WebRTC video, raw bitmap renders) may bypass —
  // those code paths need explicit verification post-install. CLAUDE.md §6.
  await ScreenProtector.protectDataLeakageOn();
  await ScreenProtector.preventScreenshotOn();

  // Force dark status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    const ProviderScope(
      child: SnowChatApp(),
    ),
  );
}
