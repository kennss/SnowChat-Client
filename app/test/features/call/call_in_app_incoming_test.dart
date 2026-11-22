/// @file        call_in_app_incoming_test.dart
/// @description V3 of the VoIP ring-end design (TO-DO/2026-11-21-voip-ring-end-design.md): on
///              iOS in the foreground, a ringing call with no CallKit window gets the in-app
///              incoming screen (CallState.inAppIncoming) after CallNotifier.inAppIncomingGrace;
///              a CallKit window shown for it prevents that; a late window takes over a call
///              still ringing in-app; a late window for a call already handled in-app is closed
///              and its events never touch the call; nothing of this happens on Android.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - _Signaling: records sealed signaling; no events of its own
///  - _CallKit: a CallKitManager whose shown windows and events the test drives
///  - main(): the cases

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/call/call_service.dart';
import 'package:snowchat/core/call/call_signaling.dart';
import 'package:snowchat/core/call/callkit_manager.dart';
import 'package:snowchat/core/call/turn_credential_manager.dart';
import 'package:snowchat/features/call/providers/call_provider.dart';

class _Signaling extends Fake implements CallSignaling {
  final sent = <(String, Map<String, dynamic>)>[];
  final _events = StreamController<CallSignalingEvent>.broadcast();

  @override
  Stream<CallSignalingEvent> get onSignalingEvent => _events.stream;

  @override
  Future<SendResult> sendSealedSignaling({
    required String recipientSnowchatId,
    required String eventType,
    required Map<String, dynamic> innerPayload,
  }) async {
    sent.add((eventType, innerPayload));
    return const SendResult.relayed();
  }
}

class _Turn extends Fake implements TurnCredentialManager {}

class _CallKit extends Fake implements CallKitManager {
  final _events = StreamController<CallKitEvent>.broadcast();
  final _shown = StreamController<String>.broadcast();
  final ended = <String>[];
  DateTime? shownAt;

  /// The plugin raised a CallKit window with [id] now.
  void show(String id) {
    shownAt = DateTime.now();
    _shown.add(id);
  }

  void emit(CallKitAction action, String id) =>
      _events.add(CallKitEvent(action: action, callId: id));

  @override
  Stream<CallKitEvent> get events => _events.stream;
  @override
  Stream<void> get audioSessionActivated => const Stream.empty();
  @override
  Stream<String> get incomingShown => _shown.stream;
  @override
  DateTime? get lastShownIncomingAt => shownAt;
  @override
  String? get lastShownIncomingId => null;
  @override
  Future<void> replayPendingFromBackground() async {}
  @override
  void clearLastShownIncomingId() => shownAt = null;
  @override
  Future<void> endCall(String callId) async => ended.add(callId);
}

const _caller = 'snow0123456789abcdef0123456789abcdef';
const _callId = '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';
// A PushKit nonce: base64url, 43 characters.
const _nonce = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  (CallNotifier, CallService, _Signaling, _CallKit) ringing(FakeAsync async,
      {bool callKitFirst = false}) {
    final signaling = _Signaling();
    final callKit = _CallKit();
    final service = CallService(signaling: signaling, turnManager: _Turn());
    final notifier = CallNotifier(callService: service, callKitManager: callKit);
    if (callKitFirst) callKit.show(_nonce);
    service.handleIncomingInvite(
      callId: _callId,
      callerSnowchatId: _caller,
      remoteWantsRelay: false,
    );
    async.flushMicrotasks();
    expect(notifier.state.status, CallStatus.incoming);
    return (notifier, service, signaling, callKit);
  }

  test('no CallKit window: the in-app screen after the grace period', () {
    fakeAsync((async) {
      final (notifier, _, _, _) = ringing(async);
      async.elapse(CallNotifier.inAppIncomingGrace - const Duration(milliseconds: 100));
      expect(notifier.state.inAppIncoming, isFalse);
      async.elapse(const Duration(milliseconds: 200));
      expect(notifier.state.inAppIncoming, isTrue);
    });
  });

  test('a CallKit window already shown for the call: no in-app screen', () {
    fakeAsync((async) {
      final (notifier, _, _, _) = ringing(async, callKitFirst: true);
      async.elapse(CallNotifier.inAppIncomingGrace * 2);
      expect(notifier.state.inAppIncoming, isFalse);
    });
  });

  test('a CallKit window inside the grace period: no in-app screen', () {
    fakeAsync((async) {
      final (notifier, _, _, callKit) = ringing(async);
      async.elapse(const Duration(seconds: 1));
      callKit.show(_nonce);
      async.elapse(CallNotifier.inAppIncomingGrace * 2);
      expect(notifier.state.inAppIncoming, isFalse);
    });
  });

  test('a late CallKit window takes over a call still ringing in-app', () {
    fakeAsync((async) {
      final (notifier, _, _, callKit) = ringing(async);
      async.elapse(CallNotifier.inAppIncomingGrace + const Duration(seconds: 1));
      expect(notifier.state.inAppIncoming, isTrue);
      callKit.show(_nonce);
      async.flushMicrotasks();
      expect(notifier.state.inAppIncoming, isFalse);
      expect(notifier.state.status, CallStatus.incoming);
      expect(callKit.ended, isEmpty, reason: 'the window is the UI now');
    });
  });

  test('a late window for a call handled in-app is closed and ignored', () {
    fakeAsync((async) {
      final (notifier, _, signaling, callKit) = ringing(async);
      async.elapse(CallNotifier.inAppIncomingGrace + const Duration(seconds: 1));
      expect(notifier.state.inAppIncoming, isTrue);
      // Declined on the in-app screen.
      unawaited(notifier.declineCall());
      // _cleanup finishes on a later macrotask; stay inside the 3 s ended
      // phase (ended → idle).
      async.elapse(const Duration(milliseconds: 500));
      expect(notifier.state.status, CallStatus.ended);
      final sentBefore = signaling.sent.length;

      final endedBefore = callKit.ended.length;
      callKit.show(_nonce);
      async.flushMicrotasks();
      expect(callKit.ended.skip(endedBefore), [_nonce],
          reason: 'the stray window is closed');
      // Closing it fires its own end event: it must not reach the call.
      callKit.emit(CallKitAction.decline, _nonce);
      async.flushMicrotasks();
      expect(signaling.sent.length, sentBefore);
    });
  });

  test('a call that began ringing in the background gets the screen on resume',
      () {
    fakeAsync((async) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final (notifier, _, _, _) = ringing(async);
      async.elapse(CallNotifier.inAppIncomingGrace * 2);
      expect(notifier.state.inAppIncoming, isFalse, reason: 'not while hidden');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.elapse(CallNotifier.inAppIncomingGrace + const Duration(milliseconds: 100));
      expect(notifier.state.inAppIncoming, isTrue);
    });
  });

  test('Android never shows the in-app incoming screen', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    fakeAsync((async) {
      final (notifier, _, _, _) = ringing(async);
      async.elapse(CallNotifier.inAppIncomingGrace * 2);
      expect(notifier.state.inAppIncoming, isFalse);
    });
  });
}
