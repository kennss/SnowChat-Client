/// @file        call_screen_for.dart
/// @description The screen this app draws for a call in a given state. One
///              mapping for the two places that draw it: the /call route and
///              the app lock, which shows the call above itself while the
///              rest of the app stays locked (SC-19).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - callScreenFor(): the call screen for a status, or null when there is no call
///  - appDrawnCallScreen(): the call screen the app draws itself now — none
///    while the system UI rings
library;

import 'package:flutter/widgets.dart';

import '../providers/call_provider.dart';
import 'active_call_screen.dart';
import 'incoming_call_screen.dart';
import 'outgoing_call_screen.dart';

/// The call screen for [status]; null for [CallStatus.idle].
///
/// `incoming` maps to the in-app incoming screen. Whether the app shows it at
/// all is the caller's decision: while CallKit (iOS) or ConnectionService
/// (Android) owns the incoming UI, the app draws none
/// (CallState.inAppIncoming is false).
Widget? callScreenFor(CallStatus status) {
  switch (status) {
    case CallStatus.outgoing:
      return const OutgoingCallScreen();
    case CallStatus.incoming:
      return const IncomingCallScreen();
    case CallStatus.connecting:
    case CallStatus.active:
    case CallStatus.ended:
      return const ActiveCallScreen();
    case CallStatus.idle:
      return null;
  }
}

/// The call screen the app draws itself for a call in [status]: null when
/// there is no call, and while CallKit (iOS) or ConnectionService (Android)
/// shows the incoming call ([inAppIncoming] false) — one incoming UI, never
/// two (v211).
Widget? appDrawnCallScreen(CallStatus status, {required bool inAppIncoming}) {
  if (status == CallStatus.incoming && !inAppIncoming) return null;
  return callScreenFor(status);
}
