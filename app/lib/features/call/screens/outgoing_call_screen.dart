/// @file        outgoing_call_screen.dart
/// @description Outgoing-call screen — avatar + "Calling..." + lock E2EE + cancel button (Phase 8.2 §3.3).
///              Stack + Center + Positioned pattern keeps both portrait/landscape stable.
///              Portrait-locked (initState SystemChrome.setPreferredOrientations).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation; UI: portrait lock + Stack/Center layout — landscape break fix)
///
/// @functions
///  - OutgoingCallScreen.build(): outgoing-call UI

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';


class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({super.key});

  @override
  ConsumerState<OutgoingCallScreen> createState() =>
      _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  /// features/call/CLAUDE.md §3.5: per-end-reason message. ended state
  /// returns to idle after 3s — meanwhile show the user exactly "why it ended".
  String _statusLabel(CallState state, String displayName) {
    if (state.status != CallStatus.ended) return 'Calling…';
    switch (state.endedReason) {
      case 'busy':
        return '$displayName is on another call';
      case 'declined':
        return '$displayName declined the call';
      case 'timeout':
      case 'no_answer':
        return 'No answer';
      case 'failed':
        return 'Call failed';
      case 'permission_denied':
        return 'Microphone permission denied';
      case 'offline':
        return '$displayName is offline';
      case 'ended':
      default:
        return 'Call ended';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callProvider);
    final displayName =
        state.remoteDisplayName ?? state.remoteSnowchatId ?? '...';

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        // Force width 100% — so Column children's crossAxisAlignment.center
        // works against full screen width. (The Stack+Center combo caused
        // left-shift on Android under loose constraints → force with
        // SizedBox.expand)
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.grey.shade800,
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 48, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusLabel(state, displayName),
                        style: const TextStyle(
                            fontSize: 16, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      const _E2EEBadge(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FloatingActionButton(
                      heroTag: 'cancel',
                      backgroundColor: Colors.red,
                      onPressed: () =>
                          ref.read(callProvider.notifier).endCall(),
                      child: const Icon(Icons.call_end,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    const Text('Cancel',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _E2EEBadge extends StatelessWidget {
  const _E2EEBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade600, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.lock, size: 14, color: Colors.greenAccent),
          SizedBox(width: 4),
          Text(
            'E2EE Protected',
            style: TextStyle(color: Colors.greenAccent, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
