/// @file        callkit_manager.dart
/// @description Phase E-1 — flutter_callkit_incoming Dart integration. Displays
///              incoming call system UI even in background/locked state and
///              exposes user actions (accept/decline/end) as a stream.
///              Integration entry point for iOS CallKit / Android
///              ConnectionService Self-Managed.
///
///              Policy (core/call/CLAUDE.md §7):
///                - includesCallsInRecents = false (block Phone app exposure)
///                - supportsVideo = false (MVP voice only)
///                - maximumCallGroups = 1 (block concurrent calls)
///                - PROPERTY_SELF_MANAGED (Android Telecom DB isolation)
///
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-19
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - CallKitManager.showIncoming(...): show system incoming call UI
///  - CallKitManager.endCall(callId): dismiss system UI (when ended/declined in-app)
///  - CallKitManager.startOutgoing(...): register system active call on outgoing (optional)
///  - CallKitManager.events: user action stream (accept/decline/ended/timeout)
///  - CallKitEvent / CallKitAction: event models
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// CallKit user action kinds.
enum CallKitAction {
  /// System UI accept button.
  accept,

  /// System UI decline / end button.
  decline,

  /// Call duration expired (60s default ringer timeout).
  timeout,

  /// App returns to foreground (UI transitions to the in-app incoming_call_screen).
  callback,
}

/// User action event emitted by CallKit.
@immutable
class CallKitEvent {
  final CallKitAction action;
  final String callId;

  const CallKitEvent({required this.action, required this.callId});

  @override
  String toString() => 'CallKitEvent($action, $callId)';
}

/// System call UI manager (iOS CallKit + Android ConnectionService Self-Managed).
///
/// Usage:
///   1. Create `CallKitManager()` once at app start (register as provider)
///   2. When an incoming call arrives, call `showIncoming(...)` → display system UI
///   3. Subscribe to the `events` stream → receive user actions from the system UI
///   4. On in-app end/decline, call `endCall(callId)` → dismiss system UI
///
/// **Policy guard**: This manager keeps no call metadata. It only knows the callId
/// transiently and the system UI auto-removes it after the call ends (no Phone-app exposure).
class CallKitManager {
  final _eventController = StreamController<CallKitEvent>.broadcast();
  StreamSubscription<CallEvent?>? _packageSub;

  CallKitManager() {
    _bindPackageEvents();
  }

  /// Stream of user system-UI actions (broadcast).
  Stream<CallKitEvent> get events => _eventController.stream;

  /// Display incoming call. callId must match the callId in the signal payload so
  /// we can match it when the user accepts.
  ///
  /// [handle] is the sender ID shown in the system UI (e.g. SnowChat ID prefix).
  /// Phone numbers/emails are not exposed by policy.
  Future<void> showIncoming({
    required String callId,
    required String callerName,
    required String handle,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      handle: handle,
      type: 0, // 0 = audio (MVP supportsVideo=false)
      duration: 60000, // 60s ringer timeout
      textAccept: '수락',
      textDecline: '거절',
      missedCallNotification: const NotificationParams(
        showNotification: false, // Policy: don't record missed calls
        isShowCallback: false,
        subtitle: '',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: '통화 중',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false, // MVP voice only
        maximumCallGroups: 1, // Block concurrent calls
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
        // isCustomNotification=true makes the package boot a separate Flutter engine
        // on ACCEPT and launch MainActivity as a new instance — Riverpod state /
        // auth session / socket connection all re-initialize from scratch, causing
        // the user screen to bounce to onboarding/lock (diagnosed 2026-04-19).
        // Switch to the default system notification so only the main isolate's
        // onNewIntent fires.
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0066FF',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'SnowChat Calls',
        missedCallNotificationChannelName: 'SnowChat Missed', // Channel created, but sending is blocked above
        isShowCallID: false, // Block callId leak in system notification
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// Register a system active call on outgoing (optional — needed for telecom integration
  /// when Android ConnectionService is Self-Managed. iOS does not use startCall directly
  /// and manages the audio session itself).
  Future<void> startOutgoing({
    required String callId,
    required String calleeName,
    required String handle,
  }) async {
    final params = CallKitParams(
      id: callId,
      nameCaller: calleeName,
      handle: handle,
      type: 0,
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
      ),
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        backgroundColor: '#0066FF',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'SnowChat Calls',
      ),
    );
    await FlutterCallkitIncoming.startCall(params);
  }

  /// Dismiss system UI. Called on in-app end/decline/timeout.
  Future<void> endCall(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  /// Immediately end all active system calls (cleanup on restart after force-quit).
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }

  void _bindPackageEvents() {
    _packageSub = FlutterCallkitIncoming.onEvent.listen((rawEvent) {
      // [DIAG-VOIP-2026-04-19] For tracing CallKit raw events. Remove after diagnosis.
      debugPrint('[DIAG:CallKit] raw event=${rawEvent?.event}');
      if (rawEvent == null) return;
      final action = _mapAction(rawEvent.event);
      if (action == null) return;
      final body = rawEvent.body;
      final id = body is Map ? (body['id']?.toString() ?? '') : '';
      if (id.isEmpty) return;
      debugPrint('[DIAG:CallKit] dispatched action=$action callId=$id');
      _eventController.add(CallKitEvent(action: action, callId: id));
    });
  }

  CallKitAction? _mapAction(Event ev) {
    switch (ev) {
      case Event.actionCallAccept:
        return CallKitAction.accept;
      case Event.actionCallDecline:
      case Event.actionCallEnded:
        return CallKitAction.decline;
      case Event.actionCallTimeout:
        return CallKitAction.timeout;
      case Event.actionCallCallback:
        return CallKitAction.callback;
      default:
        return null;
    }
  }

  Future<void> dispose() async {
    await _packageSub?.cancel();
    await _eventController.close();
  }
}
