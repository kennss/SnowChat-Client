/// @file        voip_push_handler.dart
/// @description FCM Voice Push (Android) background isolate entry point.
///              Receives data-only payload { type:'incoming_call', nonce, expiresAt }
///              and displays the CallKit incoming UI on Android. Exposed as a
///              static class interface so the FirebaseMessaging background
///              isolate can invoke it directly even when the app is killed.
///
///              Zero-Trace policy (§2.6.1):
///                - CallKit display name is anonymous "SnowChat Call" (Signal pattern, decided in §25.3).
///                - Actual caller info is verified by the main isolate after user Accept via
///                  `/api/v2/calls/pending/:nonce` fetch + decrypt.
///                - This handler receives/stores/logs no metadata other than the nonce.
///
///              iOS path: handled natively by SwiftFlutterCallkitIncomingPlugin
///              via PushKit since the Apple Dev cert was obtained on 2026-04-29
///              (Phase E-2). This Dart-side handler skips iOS to prevent the
///              dual-UI regression where both the native PushKit path and an
///              accidental FCM delivery would race to call showCallkitIncoming.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-21
/// @lastUpdated 2026-05-05 (Z-fix: prefer data['callId'] over data['nonce']
///              for CallKitParams.id. Unifies Telecom Connection id with the
///              main isolate's socket-path registration → fork same-id dedup
///              gate prevents zombie Connection. Falls back to nonce when the
///              server hasn't been upgraded yet — graceful rolling deploy.
///              §2.6.2). Earlier 2026-05-03 (v210: explicit iOS guard.)
///
/// @functions
///  - VoipPushHandler.handleIncomingCall(data): FCM data payload → CallKit display (Android only)
library;

import 'dart:io' show Platform;

import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Same 32-byte base64url regex (43 chars) as the server `routes/calls.ts` /
/// `PushNotificationService.sendVoipIncomingCall`.
// Accepts BOTH base64url(43) AND standard UUID(36 with hyphens). The server
// switched from randomBytes(32).toString('base64url') to randomUUID() because
// the iOS plugin's UUID(uuidString:) force-unwraps and crashes on base64url
// (Phase E-2 hardening 2026-04-29). Without this widening the Android FCM
// voice push silently dropped on regex mismatch.
final _noncePattern = RegExp(
  r'^([A-Za-z0-9_-]{43}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$',
);

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
  ///
  /// Platform: Android only. iOS PushKit is handled by the native
  /// SwiftFlutterCallkitIncomingPlugin path; this Dart handler skips iOS.
  static Future<void> handleIncomingCall(Map<String, dynamic> data) async {
    // v210 (2026-05-03): explicit iOS guard. The dual-UI symptom user
    // reported on 2026-05-03 ("3-4 incoming screens repeating, two-tap
    // required") traced to multiple paths racing to call
    // showCallkitIncoming. iOS post-PushKit-cert MUST go through the
    // native SwiftFlutterCallkitIncomingPlugin pushRegistry handler;
    // any Dart-side reportNewIncomingCall on iOS would either duplicate
    // the CallKit window or trip iOS 14.5+ "PushKit payload not
    // fulfilled" throttling (see call_provider.dart 2026-04-29 revert).
    if (Platform.isIOS) return;

    final nonce = data['nonce'];
    if (nonce is! String || !_noncePattern.hasMatch(nonce)) return;

    // Z-fix (2026-05-05) — prefer envelope callId over server-allocated nonce
    // when present, so the BG-isolate-registered Telecom Connection shares the
    // same id as the main-isolate's socket-path registration. Same id → fork's
    // CallkitIncomingBroadcastReceiver same-id dedup short-circuits the second
    // addNewIncomingCall → single Connection per call → no zombie on endCall.
    //
    // Falls back to nonce when the server hasn't been upgraded yet (rolling
    // deploy) or the field is missing for any other reason. The fallback is
    // safe because the existing alias mechanism in CallNotifier still
    // reconciles the two ids on actionCallIncoming (call_provider.dart).
    //
    // callId pattern is identical to nonce (UUID 36 hex). Reuse the same regex
    // gate so a malformed value defaults back to the nonce path.
    final callId = data['callId'];
    final unifiedId = (callId is String && _noncePattern.hasMatch(callId))
        ? callId
        : nonce;

    final params = CallKitParams(
      id: unifiedId,
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
        // iOS path is unreachable here (v210 guard above). IOSParams is
        // kept for structural consistency with the plugin's required
        // CallKitParams shape — values follow §7 policy.
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
