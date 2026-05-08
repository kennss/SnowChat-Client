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
/// @lastUpdated 2026-05-03 (v205: startOutgoing IOSParams pin
///              audioSessionPreferredSampleRate=48_000 + IOBufferDuration=0.005
///              to match WebRTC's expected rate and the accept-path
///              CXAnswerCallAction setup. Defaulted to 44.1 kHz pre-v205 which
///              forced iOS to resample on top of the v204 priority handoff —
///              one of the contributing factors to outbound AURemoteIO not
///              constructing.)
/// Earlier:     2026-05-01 (v201: endCall UUID format guard. Outgoing calls and
///              socket-only incoming have null _activeCallKitNonce so caller
///              fell back to state.callId (32-hex internal hash). The fork's iOS
///              plugin force-unwraps UUID(uuidString: data.uuid)! and crashed
///              the Runner process — the symptom was "iPhone caller endCall →
///              process dies → unawaited call_end signal never sent → Galaxy
///              stays ringing → next iPhone incoming has no audio". Skip silently
///              when id is not UUID-shaped; no CallKit window exists with that
///              id anyway.)
///
/// @functions
///  - CallKitManager.showIncoming(...): show system incoming call UI
///  - CallKitManager.endCall(callId): dismiss system UI (when ended/declined in-app)
///  - CallKitManager.startOutgoing(...): register system active call on outgoing (optional)
///  - CallKitManager.events: user action stream (accept/decline/ended/timeout)
///  - CallKitEvent / CallKitAction: event models
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
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

  // Phase 8.2 v2.2 — Audio session lifecycle stream. CallKit fires didActivate
  // after granting PhoneCall priority; the plugin forwards it as
  // ACTION_CALL_TOGGLE_AUDIO_SESSION (isActivate=true). CallService awaits this
  // before starting WebRTC. Single-source-of-truth via this manager — earlier
  // path A (CallService subscribing to the same EventChannel directly) was
  // removed because EventChannel.receiveBroadcastStream() is single-subscriber
  // at the native onListen layer; the second listener overwrites the first sink.
  final _audioActivatedController = StreamController<void>.broadcast();
  StreamSubscription<CallEvent?>? _packageSub;

  // VoipNativeBridge channel — used to invoke replay methods that recover
  // events lost during BG→FG transitions when the FlutterEngine isolate was
  // paused at sendEvent time.
  static const _voipNativeChannel = MethodChannel('snowchat/voip_native');

  CallKitManager() {
    _bindPackageEvents();
  }

  /// Stream of user system-UI actions (broadcast).
  Stream<CallKitEvent> get events => _eventController.stream;

  /// Stream of audio session activation events from CallKit's didActivate
  /// callback (broadcast). Fired with `null` payload — this is a one-bit
  /// signal that the session has reached PhoneCall priority and WebRTC is
  /// safe to start.
  Stream<void> get audioSessionActivated => _audioActivatedController.stream;

  // Phase 8.2 v2.4 — Broadcast every actionCallIncoming nonce so consumers
  // (CallNotifier) can wire the alias map even when actionCallIncoming arrives
  // AFTER the envelope-decrypt path has already pushed the state to incoming.
  // The lastShownIncomingId getter alone is insufficient: PushKit ordering
  // means the in-app envelope-decrypt path can fire `_onServiceEvent(incoming)`
  // before the plugin emits `actionCallIncoming` to Dart, so the synchronous
  // lookup at incoming-state time finds null. The stream gives us the late
  // notification too — both paths are idempotent on `_aliasMap.register`.
  final _incomingShownController = StreamController<String>.broadcast();
  Stream<String> get incomingShown => _incomingShownController.stream;

  // Phase 8.2 v2.3 — Capture the most recent CallKit incoming-UI id (the
  // PushKit nonce). PushKit shows CallKit with id=nonce; the Dart-side
  // envelope decryption surfaces a different internal callId. CallNotifier
  // reads this on `CallServiceStatus.incoming` to register the alias map
  // entry (nonce ↔ envelope callId), so subsequent ACTION_CALL_ACCEPT
  // events (whose callId == nonce) pass the stale-event guard.
  String? _lastShownIncomingId;
  DateTime? _lastShownIncomingAt;
  static const _incomingIdTtl = Duration(seconds: 60);

  /// Last `id` seen on `Event.actionCallIncoming`, or null if none / TTL expired.
  String? get lastShownIncomingId {
    final at = _lastShownIncomingAt;
    if (at == null) return null;
    if (DateTime.now().difference(at) > _incomingIdTtl) {
      _lastShownIncomingId = null;
      _lastShownIncomingAt = null;
      return null;
    }
    return _lastShownIncomingId;
  }

  /// Clear the cached incoming id (e.g. after a successful alias register
  /// or call end) so a stale entry doesn't leak across calls.
  void clearLastShownIncomingId() {
    _lastShownIncomingId = null;
    _lastShownIncomingAt = null;
  }

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
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: false, // Policy: don't record missed calls
        isShowCallback: false,
        subtitle: '',
      ),
      callingNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Ongoing call',
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

  /// Register a system active call on outgoing.
  ///
  /// iOS (v204, 2026-05-03): MUST be called for outbound calls. CallKit needs
  /// to drive the audio session via CXStartCallAction →
  /// provider:didActivate:audioSession: so AURemoteIO gets ClientPriority=
  /// PhoneCall — without it mic capture and output routing silently fail
  /// (caller and callee both heard zero audio in pre-v204 behavior even
  /// though WebRTC reported Connected). Caller awaits the same Completer<void>
  /// that acceptCall uses (CallService.startCall L233-261).
  ///
  /// Android: needed for ConnectionService Self-Managed integration so the
  /// system telecom layer recognizes the active call.
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
        // v205 (2026-05-03): match WebRTC's expected sample rate (48 kHz) and
        // the accept-path setup (SwiftFlutterCallkitIncomingPlugin.swift:779,
        // CXAnswerCallAction handler). Without this override the plugin's
        // configureAudioSession defaults to 44_100, forcing iOS to resample —
        // an additional friction on top of the v204 priority handoff that may
        // contribute to AURemoteIO startup failures on the outbound path.
        audioSessionPreferredSampleRate: 48000.0,
        audioSessionPreferredIOBufferDuration: 0.005,
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
  ///
  /// v201: id MUST be UUID(8-4-4-4-12) format. The fork's iOS plugin
  /// force-unwraps `UUID(uuidString: data.uuid)!`
  /// (SwiftFlutterCallkitIncomingPlugin.swift:378, CallManager.swift:25),
  /// crashing the Runner process on non-UUID input. Outgoing calls and
  /// socket-only incoming calls never registered a CallKit window on iOS
  /// (showIncoming guards on Platform.isAndroid), so the caller falls back
  /// to `state.callId` — a 32-char internal hash, not a UUID — which is what
  /// triggered the chronic "iPhone process dies on endCall" symptom (Galaxy
  /// keeps ringing because the unawaited call_end signal never went out).
  /// Skip silently when the id isn't UUID-shaped: there's no CallKit window
  /// to dismiss anyway. Android plugin uses the string id directly so it's
  /// unaffected by the validation.
  Future<void> endCall(String callId) async {
    if (!_uuidPattern.hasMatch(callId)) {
      debugPrint('[CallKitManager] endCall skipped — id is not UUID-shaped '
          '(no CallKit window registered with this id; would crash iOS plugin)');
      return;
    }
    await FlutterCallkitIncoming.endCall(callId);
  }

  static final _uuidPattern = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );

  /// Immediately end all active system calls (cleanup on restart after force-quit).
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }

  void _bindPackageEvents() {
    _packageSub = FlutterCallkitIncoming.onEvent.listen((rawEvent) {
      // [DIAG-VOIP-2026-04-19] For tracing CallKit raw events. Remove after diagnosis.
      debugPrint('[DIAG:CallKit] raw event=${rawEvent?.event}');
      if (rawEvent == null) return;

      // Phase 8.2 v2.2 — handle audio session toggle separately. The plugin
      // emits ACTION_CALL_TOGGLE_AUDIO_SESSION from provider:didActivate and
      // didDeactivate (body: {isActivate: bool}). _mapAction returns null for
      // it, so we intercept upstream and broadcast on _audioActivatedController.
      if (rawEvent.event == Event.actionCallToggleAudioSession) {
        final body = rawEvent.body;
        if (body is Map && body['isActivate'] == true) {
          debugPrint('[DIAG:CallKit] audio session activated → broadcast');
          _audioActivatedController.add(null);
        }
        return;
      }

      // Phase 8.2 v2.3/v2.4 — capture the nonce that PushKit used to raise
      // the CallKit UI. CallNotifier consumes this both via the synchronous
      // `lastShownIncomingId` getter (path: actionCallIncoming arrives BEFORE
      // _onServiceEvent(incoming)) AND via the `incomingShown` broadcast
      // stream (path: actionCallIncoming arrives AFTER, observed in v2.3 logs
      // — PushKit envelope decrypt is faster than the plugin's UI dispatch).
      if (rawEvent.event == Event.actionCallIncoming) {
        final body = rawEvent.body;
        if (body is Map) {
          final id = body['id']?.toString();
          if (id != null && id.isNotEmpty) {
            _lastShownIncomingId = id;
            _lastShownIncomingAt = DateTime.now();
            debugPrint('[DIAG:CallKit] captured lastShownIncomingId=$id');
            _incomingShownController.add(id);
          }
        }
        return;
      }

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

  /// Phase 8.2 v2.2 — Replay events that may have been dropped while the
  /// FlutterEngine isolate was paused (typical BG→FG transition). Plugin
  /// caches the last ACCEPT and the last didActivate timestamp for 5s; this
  /// invocation tells it to re-dispatch them so the standard event flow
  /// catches up.
  ///
  /// Order matters: ACCEPT replay first so CallNotifier creates the audio
  /// session Completer (via prepareAudioSessionAwaiter) before the ACTIVATED
  /// replay arrives — otherwise the second event has nothing to complete.
  /// Even if the underlying calls are async, the plugin schedules them on the
  /// same Flutter platform queue, so the order is preserved.
  ///
  /// Idempotent: every accept/activated handler downstream guards against
  /// duplicate processing (CallNotifier checks state.status; CallService
  /// guards Completer.isCompleted). Calling this multiple times is safe.
  Future<void> replayPendingFromBackground() async {
    if (!Platform.isIOS) return;
    debugPrint('[CallKit] replayPendingFromBackground — invoking plugin replay');
    try {
      await _voipNativeChannel.invokeMethod('replayLastAcceptIfRecent');
    } catch (e) {
      debugPrint('[CallKit] replayLastAcceptIfRecent invoke failed: $e');
    }
    try {
      await _voipNativeChannel.invokeMethod('replayLastActivationIfRecent');
    } catch (e) {
      debugPrint('[CallKit] replayLastActivationIfRecent invoke failed: $e');
    }
  }

  Future<void> dispose() async {
    await _packageSub?.cancel();
    await _eventController.close();
    await _audioActivatedController.close();
    await _incomingShownController.close();
  }
}
