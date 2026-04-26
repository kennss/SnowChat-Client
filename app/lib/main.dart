/// @file        main.dart
/// @description App entry point. DNS cache override, Firebase init, system UI setup, ProviderScope init
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; Phase 8.2 §25 Phase I: FCM Voice Push — incoming_call branch)
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/call/voip_push_handler.dart';
import 'core/network/api_endpoints.dart';

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
    return;
  }
  debugPrint('[FCM] Background message: ${message.data}');
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
