/// @file        call_service_ring_timeout_test.dart
/// @description The callee-side ring timeout of CallService: an incoming call that nobody
///              answers is declined on this device after CallService.incomingRingTimeout
///              (call_end reason 'timeout' to the caller, status ended), whether or not a
///              system call UI was raised; an accepted or ended call is never declined by it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - _Signaling: records the sealed signaling CallService sends; no events of its own
///  - main(): the cases

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/call/call_service.dart';
import 'package:snowchat/core/call/call_signaling.dart';
import 'package:snowchat/core/call/turn_credential_manager.dart';

class _Signaling extends Fake implements CallSignaling {
  final sent = <(String, String, Map<String, dynamic>)>[];
  final _events = StreamController<CallSignalingEvent>.broadcast();

  @override
  Stream<CallSignalingEvent> get onSignalingEvent => _events.stream;

  @override
  Future<SendResult> sendSealedSignaling({
    required String recipientSnowchatId,
    required String eventType,
    required Map<String, dynamic> innerPayload,
  }) async {
    sent.add((recipientSnowchatId, eventType, innerPayload));
    return const SendResult.relayed();
  }
}

class _Turn extends Fake implements TurnCredentialManager {}

const _caller = 'snow0123456789abcdef0123456789abcdef';
const _callId = '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  (CallService, _Signaling, List<CallServiceEvent>) ringing() {
    final signaling = _Signaling();
    final service = CallService(signaling: signaling, turnManager: _Turn());
    final events = <CallServiceEvent>[];
    service.events.listen(events.add);
    service.handleIncomingInvite(
      callId: _callId,
      callerSnowchatId: _caller,
      remoteWantsRelay: false,
    );
    return (service, signaling, events);
  }

  test('an unanswered incoming call is declined after the ring timeout', () {
    fakeAsync((async) {
      final (_, signaling, events) = ringing();
      async.flushMicrotasks();
      expect(events.last.status, CallServiceStatus.incoming);

      async.elapse(CallService.incomingRingTimeout - const Duration(seconds: 1));
      expect(signaling.sent, isEmpty, reason: 'still ringing before the timeout');

      async.elapse(const Duration(seconds: 2));
      expect(signaling.sent, hasLength(1));
      final (to, type, payload) = signaling.sent.single;
      expect(to, _caller);
      expect(type, 'call_end');
      expect(payload, {'callId': _callId, 'reason': 'timeout'});
      expect(events.last.status, CallServiceStatus.ended);
      expect(events.last.endedReason, 'timeout');
    });
  });

  test('a call ended before the timeout is not declined again', () {
    fakeAsync((async) {
      final (service, signaling, _) = ringing();
      async.flushMicrotasks();
      unawaited(service.declineCall());
      async.flushMicrotasks();
      expect(signaling.sent.map((e) => e.$3['reason']), ['declined']);

      async.elapse(CallService.incomingRingTimeout + const Duration(seconds: 5));
      expect(signaling.sent, hasLength(1), reason: 'the timer died with the call');
    });
  });

  test('a later call keeps its own full ring time', () {
    fakeAsync((async) {
      final (service, signaling, _) = ringing();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 30));
      unawaited(service.declineCall());
      async.flushMicrotasks();
      // Past the anti-replay window, a new call with another id rings.
      async.elapse(const Duration(seconds: 61));
      const second = '7a2d3c9f-2e3b-4d4c-8f90-1b2c3d4e5f60';
      service.handleIncomingInvite(
        callId: second,
        callerSnowchatId: _caller,
        remoteWantsRelay: false,
      );
      async.flushMicrotasks();
      async.elapse(CallService.incomingRingTimeout - const Duration(seconds: 1));
      expect(signaling.sent.map((e) => e.$3['callId']), [_callId]);
      async.elapse(const Duration(seconds: 2));
      expect(signaling.sent.last.$3, {'callId': second, 'reason': 'timeout'});
    });
  });
}
