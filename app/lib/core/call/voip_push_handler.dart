/// @file        voip_push_handler.dart
/// @description FCM Voice Push (Phase I, Phase 8.2 §25) background isolate entry point.
///              Receives data-only payload { type:'incoming_call', nonce, expiresAt }
///              and displays the CallKit incoming UI. Exposed as a static class
///              interface so the FirebaseMessaging background isolate can invoke
///              it directly even when the app is killed.
///
///              Zero-Trace policy (§2.6.1):
///                - CallKit display name is anonymous "SnowChat Call" (Signal pattern, decided in §25.3).
///                - Actual caller info is verified by the main isolate after user Accept via
///                  `/api/v2/calls/pending/:nonce` fetch + decrypt.
///                - This handler receives/stores/logs no metadata other than the nonce.
///
///              iOS asymmetry: this path is Android-only (§25.7). iOS PushKit is deferred
///              → `Documentation/TO-DO/ios-voip-push.md`.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-21
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - VoipPushHandler.handleIncomingCall(data): FCM data payload → CallKit display
library;

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Same 32-byte base64url regex (43 chars) as the server `routes/calls.ts` /
/// `PushNotificationService.sendVoipIncomingCall`.
final _noncePattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

class VoipPushHandler {
  /// Called from the FCM background isolate when a `type == 'incoming_call'` message arrives.
  ///
  /// Allowed input: `{ nonce: <43-char base64url>, expiresAt?: <unix ms str> }`.
  /// Other fields are ignored. If nonce doesn't match the pattern, return silently
  /// (avoid a meaningless CallKit display).
  ///
  /// CallKit display uses `callId = nonce` — when the user Accepts, the same id flows
  /// through the main isolate's `CallKitManager.events` stream and `CallNotifier` can
  /// take the pending path branch (detected via nonce pattern).
  static Future<void> handleIncomingCall(Map<String, dynamic> data) async {
    final nonce = data['nonce'];
    if (nonce is! String || !_noncePattern.hasMatch(nonce)) return;

    final params = CallKitParams(
      id: nonce,
      nameCaller: 'SnowChat Call', // Anonymous (Signal pattern, §25.3)
      handle: '', // No phone number / snow ID exposure
      type: 0, // audio only
      duration: 30000, // 30s ringer timeout
      textAccept: '수락',
      textDecline: '거절',
      missedCallNotification: const NotificationParams(
        showNotification: false, // Policy §2.2: don't record missed calls
        isShowCallback: false,
        subtitle: '',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: '통화 중',
      ),
      ios: const IOSParams(
        // iOS PushKit is deferred at Phase I — this path doesn't actually run.
        // IOSParams is set for structural consistency, but follows policy §7.
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
      android: const AndroidParams(
        // Same principle as decided in callkit_manager.dart.
        // isCustomNotification=true boots a separate Flutter engine → Riverpod /
        // auth re-init → bouncing to onboarding (diagnosed 2026-04-19).
        // Forced to false so only the main isolate onNewIntent path fires.
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0066FF',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'SnowChat Calls',
        missedCallNotificationChannelName: 'SnowChat Missed',
        isShowCallID: false, // Block callId/nonce leak in system notification
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }
}
