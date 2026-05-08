/// @file        voip_push_service.dart
/// @description iOS PushKit (VoIP) token registration with the SnowChat
///              server. Listens to flutter_callkit_incoming's
///              `actionDidUpdateDevicePushTokenVoip` event (fired by the
///              native VoipPushBridge in didUpdate(pushCredentials)) and
///              POSTs the hex token to PUT /devices/:deviceId/voip-token.
///              iOS only — no-op on Android.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-29
/// @lastUpdated 2026-04-29 (Phase E-2 #2 fix: poll loop retries on upload
///              failure instead of exiting; window extended 30s → 60s + slow
///              retry 30min. Release-build race fix where the first PUT lost
///              the token forever.)
///
/// @functions
///  - VoipPushService.start(): subscribe to plugin event stream
///  - VoipPushService.dispose(): cancel subscription
///  - VoipPushService._upload(): returns bool — caller retries on failure

library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../storage/secure_storage.dart';

class VoipPushService {
  VoipPushService({
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;
  StreamSubscription<dynamic>? _sub;
  String? _lastUploadedToken;

  /// Start listening + polling. Idempotent — calling twice returns immediately.
  Future<void> start() async {
    debugPrint('[VoipPush] start() entered platform=${Platform.operatingSystem} build=${DateTime.now().toIso8601String()}');
    if (!Platform.isIOS) return;
    if (_sub != null) return;

    // Path 1: subscribe to plugin event stream (CallKitManager also listens
    // — broadcast stream so both should fire). 2026-04-29 field log shows
    // CallKitManager listener fires for actionDidUpdateDevicePushTokenVoip
    // but ours stays silent. Suspected race: stream cached lazily, second
    // listener may miss the first emission. Path 2 below covers the gap.
    _sub = FlutterCallkitIncoming.onEvent.listen((event) async {
      debugPrint('[VoipPush] onEvent fired: ${event?.event}');
      if (event == null) return;
      if (event.event != Event.actionDidUpdateDevicePushTokenVoip) return;

      final token = (event.body['deviceTokenVoIP'] as String?)?.trim() ?? '';
      if (token.isEmpty) {
        debugPrint('[VoipPush] empty token from event — skip');
        return;
      }
      if (token == _lastUploadedToken) return;
      await _upload(token);
    });
    debugPrint('[VoipPush] subscribed to plugin token events');

    // Path 2 (fallback): poll plugin storage every 3s for the first 30s.
    // Plugin's setDevicePushTokenVoIP also writes UserDefaults, so
    // getDevicePushTokenVoIP returns the latest token even if our event
    // listener missed the emission. Upload once it appears + matches the
    // dedup guard.
    unawaited(_pollUntilTokenSeen());
  }

  Future<void> _pollUntilTokenSeen() async {
    // Initial poll: 60 attempts × 1s = 60s. Token usually arrives within 5s,
    // but auth (JWT) and device_id (secure storage) need to be ready first
    // — release builds race differently than debug due to AOT timing.
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final token = (await FlutterCallkitIncoming.getDevicePushTokenVoIP())
            .trim();
        if (token.isEmpty) continue;
        if (token == _lastUploadedToken) return; // already done
        debugPrint('[VoipPush] poll[$i]: plugin token len=${token.length}');
        if (await _upload(token)) return; // success
        // upload failed — continue polling so the next iteration retries
      } catch (e) {
        debugPrint('[VoipPush] poll[$i] failed: $e');
      }
    }
    debugPrint('[VoipPush] initial poll exhausted (60s) — switching to slow retry');
    // Slow retry: every 30s for 30min (60 iterations). Covers cases where
    // the first 60s window expired before auth/device_id was ready.
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 30));
      try {
        final token = (await FlutterCallkitIncoming.getDevicePushTokenVoIP())
            .trim();
        if (token.isEmpty) continue;
        if (token == _lastUploadedToken) return;
        debugPrint('[VoipPush] slowRetry[$i]: token len=${token.length}');
        if (await _upload(token)) return;
      } catch (e) {
        debugPrint('[VoipPush] slowRetry[$i] failed: $e');
      }
    }
    debugPrint('[VoipPush] slow retry exhausted (30min) — gave up');
  }

  /// Returns true on successful upload, false on any failure (deferred or error).
  /// Caller relies on this to decide whether to keep retrying.
  Future<bool> _upload(String token) async {
    final deviceId = await _secureStorage.read('device_id');
    if (deviceId == null || deviceId.isEmpty) {
      debugPrint('[VoipPush] no deviceId yet — defer upload');
      return false;
    }
    try {
      await _apiClient.put(
        ApiEndpoints.deviceVoipToken(deviceId),
        data: {'voipPushToken': token},
      );
      _lastUploadedToken = token;
      debugPrint('[VoipPush] uploaded token len=${token.length}');
      return true;
    } catch (e) {
      debugPrint('[VoipPush] upload failed: $e');
      return false;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
