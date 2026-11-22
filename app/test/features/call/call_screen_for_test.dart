/// @file        call_screen_for_test.dart
/// @description Which call screen the app draws for each call state — the
///              mapping the /call route and the app lock share (SC-19): the
///              lock shows exactly this above itself during a call.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): callScreenFor / appDrawnCallScreen for every status
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/call/providers/call_provider.dart';
import 'package:snowchat/features/call/screens/active_call_screen.dart';
import 'package:snowchat/features/call/screens/call_screen_for.dart';
import 'package:snowchat/features/call/screens/incoming_call_screen.dart';
import 'package:snowchat/features/call/screens/outgoing_call_screen.dart';

void main() {
  test('every call state but idle has a screen', () {
    expect(callScreenFor(CallStatus.idle), isNull);
    expect(callScreenFor(CallStatus.outgoing), isA<OutgoingCallScreen>());
    expect(callScreenFor(CallStatus.incoming), isA<IncomingCallScreen>());
    for (final s in [CallStatus.connecting, CallStatus.active, CallStatus.ended]) {
      expect(callScreenFor(s), isA<ActiveCallScreen>(), reason: '$s');
    }
  });

  test('while the system UI rings the app draws nothing (the lock stays alone)', () {
    expect(appDrawnCallScreen(CallStatus.incoming, inAppIncoming: false), isNull);
    expect(
      appDrawnCallScreen(CallStatus.incoming, inAppIncoming: true),
      isA<IncomingCallScreen>(),
    );
  });

  test('once answered, or when calling out, the call screen is drawn', () {
    for (final s in [
      CallStatus.outgoing,
      CallStatus.connecting,
      CallStatus.active,
      CallStatus.ended,
    ]) {
      expect(appDrawnCallScreen(s, inAppIncoming: false), isNotNull, reason: '$s');
    }
    expect(appDrawnCallScreen(CallStatus.idle, inAppIncoming: false), isNull);
  });
}
