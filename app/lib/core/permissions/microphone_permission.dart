/// @file        microphone_permission.dart
/// @description Asks for the microphone once, on the first run of the app
///              (and once on the first run of a build that has this, for an
///              install that never decided). A call answered from the lock
///              screen cannot show the system prompt: the app is not in front,
///              getUserMedia waits on a prompt nobody sees, no answer reaches
///              the caller, and the caller rings until its timeout (found on
///              the 1003 TestFlight build, 2026-11-22). Asking up front makes
///              sure the answer is known before the first call arrives.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (askStartupPrompts — notifications then the microphone, one prompt at a time: two notification requests at once made Android answer the microphone \"denied\" behind the dialog on the first 1005 run). Earlier 2026-11-22
///
/// @functions
///  - askStartupPrompts(): the system prompts of a start, one at a time —
///    notifications, then the microphone (once)
///  - askMicrophoneOnce(): the system prompt on the first run; nothing after
///  - microphoneGranted(): whether the microphone may be used now (no prompt)
///
/// Notes:
///  - The microphone is one permission for the whole app (voice messages
///    and calls), so it lives here and not in core/call: call code never
///    imports `record` or makes an AudioRecorder (core/call/CLAUDE.md §2.3,
///    no recording in the call path). It only asks microphoneGranted().
///  - The prompt comes from `record` (AudioRecorder.hasPermission), the
///    package voice messages already use for the same permission. Nothing
///    is recorded here.
///    permission_handler is not used: on iOS each of its permissions has to
///    be compiled in by a Podfile macro, and without it a request answers
///    "denied" without asking.
///  - One prompt at a time. Android shows one permission request at a time
///    and answers a second request made while the first is on screen with
///    "denied" — no prompt shown. On the first 1005 run the notification
///    prompt was asked twice at once (FirebaseMessaging and the local
///    notification plugin, which answered `false` at once), the microphone
///    went right after the second, was answered "denied" behind the
///    notification prompt, and the marker kept it from ever being asked.
///    So the notification prompt is asked in one place only — here, through
///    FirebaseMessaging, which waits for the answer — and the microphone
///    after it.
///  - "Asked" is a marker file in the documents directory, like the
///    fresh-install marker: it goes with an uninstall, and so does the
///    system's answer on iOS. Without the marker, Android would ask again on
///    every start after a "deny".
library;

import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const String _markerName = 'microphone_permission_asked';

Future<void>? _asking;
Future<void>? _startup;

/// The system prompts of a start, one at a time: notifications (asked on
/// every start; the system shows nothing once decided — iOS also registers
/// for APNs on it), then the microphone on the first run. The only place
/// either is asked at start.
Future<void> askStartupPrompts() => _startup ??= _askStartup();

Future<void> _askStartup() async {
  try {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[StartupPrompts] notifications: '
        '${settings.authorizationStatus.name}');
  } catch (e) {
    debugPrint('[StartupPrompts] notification prompt failed (non-fatal): '
        '${e.runtimeType}');
  }
  await askMicrophoneOnce();
}

/// Ask for the microphone if this install has not asked yet. Safe to call
/// more than once; never throws.
Future<void> askMicrophoneOnce() => _asking ??= _askOnce();

Future<void> _askOnce() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final marker = File(p.join(dir.path, _markerName));
    if (await marker.exists()) return;
    final recorder = AudioRecorder();
    try {
      final granted = await recorder.hasPermission();
      debugPrint('[MicPermission] first-run answer: granted=$granted');
    } finally {
      await recorder.dispose();
    }
    await marker.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
  } catch (e) {
    // Not asked this time: the next start tries again.
    debugPrint('[MicPermission] first-run ask failed (non-fatal): $e');
    _asking = null;
  }
}

/// Whether the microphone may be used now. Never shows a prompt.
Future<bool> microphoneGranted() async {
  final recorder = AudioRecorder();
  try {
    return await recorder.hasPermission(request: false);
  } catch (_) {
    return false;
  } finally {
    await recorder.dispose();
  }
}
