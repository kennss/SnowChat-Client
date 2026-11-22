/// @file        call_caller_name_test.dart
/// @description "Show caller name on calls": every system call UI is raised anonymous; once the
///              invite is decrypted, CallNotifier names each window of the call with the name this
///              device knows (CallKitManager.updateCallerName) — only when the setting is on. Covers
///              the Android main-isolate window (call id), the iOS PushKit window (nonce) shown
///              before and after the invite, the short-snowId fallback, the setting off, and a
///              setting that cannot be read.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-23
/// @lastUpdated 2026-11-23
///
/// @functions
///  - _Signaling: CallSignaling fake; no events of its own
///  - _CallKit: CallKitManager fake recording raised windows and caller-name updates
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
  final _events = StreamController<CallSignalingEvent>.broadcast();

  @override
  Stream<CallSignalingEvent> get onSignalingEvent => _events.stream;

  @override
  Future<SendResult> sendSealedSignaling({
    required String recipientSnowchatId,
    required String eventType,
    required Map<String, dynamic> innerPayload,
  }) async =>
      const SendResult.relayed();
}

class _Turn extends Fake implements TurnCredentialManager {}

class _CallKit extends Fake implements CallKitManager {
  final _events = StreamController<CallKitEvent>.broadcast();
  final _shown = StreamController<String>.broadcast();

  /// Ids passed to showIncoming (always anonymous — the API takes no name).
  final raised = <String>[];

  /// (window id, name) of every updateCallerName.
  final named = <(String, String)>[];

  String? shownId;
  DateTime? shownAt;

  /// The plugin raised a CallKit window with [id] (PushKit report).
  void show(String id) {
    shownId = id;
    shownAt = DateTime.now();
    _shown.add(id);
  }

  @override
  Stream<CallKitEvent> get events => _events.stream;
  @override
  Stream<void> get audioSessionActivated => const Stream.empty();
  @override
  Stream<String> get incomingShown => _shown.stream;
  @override
  DateTime? get lastShownIncomingAt => shownAt;
  @override
  String? get lastShownIncomingId => shownId;
  @override
  Future<void> replayPendingFromBackground() async {}
  @override
  void clearLastShownIncomingId() {
    shownId = null;
    shownAt = null;
  }

  @override
  Future<void> endCall(String callId) async {}
  @override
  Future<void> showIncoming({required String callId}) async =>
      raised.add(callId);
  @override
  Future<void> updateCallerName({
    required String callId,
    required String callerName,
  }) async =>
      named.add((callId, callerName));
}

const _caller = 'snow0123456789abcdef0123456789abcdef';
const _callId = '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';
const _nonce = '0c9d8e7f-6a5b-4c3d-8e2f-1a0b9c8d7e6f';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  /// A call from [_caller] rings on a notifier whose setting reads [showName]
  /// (null: no reader). [knownName] is what this device knows for the caller.
  (CallNotifier, _CallKit) ring(
    FakeAsync async, {
    required TargetPlatform platform,
    Future<bool> Function()? showName,
    String? knownName = 'Alice',
    bool pushWindowFirst = false,
  }) {
    debugDefaultTargetPlatformOverride = platform;
    final callKit = _CallKit();
    final service = CallService(signaling: _Signaling(), turnManager: _Turn());
    final notifier = CallNotifier(
      callService: service,
      callKitManager: callKit,
      showCallerNameOnSystemUi: showName,
    );
    if (pushWindowFirst) callKit.show(_nonce);
    service.handleIncomingInvite(
      callId: _callId,
      callerSnowchatId: _caller,
      remoteWantsRelay: false,
      // What the signaling dispatcher passes: CallService.peerName — the
      // name this device knows (contact, then name certificate).
      callerDisplayName: knownName,
    );
    async.flushMicrotasks();
    expect(notifier.state.status, CallStatus.incoming);
    return (notifier, callKit);
  }

  group('Android main isolate', () {
    test('setting on: raised anonymous, then named with the device name', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async,
            platform: TargetPlatform.android, showName: () async => true);
        expect(callKit.raised, [_callId]);
        expect(callKit.named, [(_callId, 'Alice')]);
      });
    });

    test('setting off: raised anonymous and never named', () {
      fakeAsync((async) {
        final (notifier, callKit) = ring(async,
            platform: TargetPlatform.android, showName: () async => false);
        expect(callKit.raised, [_callId]);
        expect(callKit.named, isEmpty);
        // The in-app screens still know the name.
        expect(notifier.state.remoteDisplayName, 'Alice');
      });
    });

    test('no name known: the short snowId the in-app screen shows', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async,
            platform: TargetPlatform.android,
            showName: () async => true,
            knownName: null);
        expect(callKit.named, [(_callId, _caller.substring(0, 12))]);
      });
    });

    test('a setting that cannot be read counts as off', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async,
            platform: TargetPlatform.android,
            showName: () async => throw StateError('keychain locked'));
        expect(callKit.raised, [_callId]);
        expect(callKit.named, isEmpty);
      });
    });

    test('no reader (idle placeholder notifier): never named', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async, platform: TargetPlatform.android);
        expect(callKit.named, isEmpty);
      });
    });
  });

  group('iOS PushKit window', () {
    test('window up before the invite: renamed, Dart raises nothing', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async,
            platform: TargetPlatform.iOS,
            showName: () async => true,
            pushWindowFirst: true);
        expect(callKit.raised, isEmpty);
        expect(callKit.named, [(_nonce, 'Alice')]);
      });
    });

    test('window up after the invite: renamed when it shows', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async,
            platform: TargetPlatform.iOS, showName: () async => true);
        expect(callKit.named, isEmpty, reason: 'no window yet');
        callKit.show(_nonce);
        async.flushMicrotasks();
        expect(callKit.named, [(_nonce, 'Alice')]);
      });
    });

    test('setting off: the window stays anonymous', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async,
            platform: TargetPlatform.iOS,
            showName: () async => false,
            pushWindowFirst: true);
        callKit.show(_nonce);
        async.flushMicrotasks();
        expect(callKit.named, isEmpty);
      });
    });

    test('a window is named once per call', () {
      fakeAsync((async) {
        final (_, callKit) = ring(async,
            platform: TargetPlatform.iOS,
            showName: () async => true,
            pushWindowFirst: true);
        callKit.show(_nonce); // the same window reported again
        async.flushMicrotasks();
        expect(callKit.named, [(_nonce, 'Alice')]);
      });
    });
  });

  test('deviceCallerName: name first, else the 12-character snowId', () {
    expect(CallNotifier.deviceCallerName('Bob', _caller), 'Bob');
    expect(CallNotifier.deviceCallerName('', _caller), _caller.substring(0, 12));
    expect(CallNotifier.deviceCallerName(null, null), isNull);
  });

  test('the anonymous name is the §2.6.1 literal', () {
    expect(kAnonymousCallName, 'SnowChat Call');
  });
}
