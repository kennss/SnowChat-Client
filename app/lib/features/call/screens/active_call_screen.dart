/// @file        active_call_screen.dart
/// @description Active call screen — timer, mute/speaker/end, 4-digit SAS (Phase 8.2 §3.3, §24.3).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-05-11 (Removed per-screen ScreenProtector wiring — now
///              applied app-wide one-shot in main.dart. As side benefit the
///              prior iOS dispose race (Off() pinning main thread on audio
///              session teardown → 30s freeze after end button) goes away
///              because Off() is never called anywhere. Earlier 2026-04-26
///              header + inline English translation; UI: English.)
///
/// @functions
///  - ActiveCallScreen.build(): active-call UI
///  - _formatDuration(d): mm:ss format

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';


class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  // [Local elapsed timer — 2026-04-19] If callProvider state's elapsed
  // field is updated every second, all listeners (router, _CallRouteHost)
  // fire every second → GestureDetector recreated every second → tap
  // input dispatch race. Keep only callStartedAt in the provider; do
  // widget-local rebuilds with a screen-only Timer + setState.
  Timer? _ticker;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Lock call screen to portrait — prevents layout breakage on landscape rotation.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    // Screen capture protection is applied app-wide in main.dart — no per-screen
    // wiring needed. See CLAUDE.md §6.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = ref.read(callProvider).callStartedAt;
      if (startedAt == null) return;
      if (!mounted) return;
      setState(() {
        _elapsed = DateTime.now().difference(startedAt);
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Release rotation lock on exit (so other app screens can rotate).
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callProvider);
    final displayName =
        state.remoteDisplayName ?? state.remoteSnowchatId ?? '...';
    final elapsed = _formatDuration(_elapsed);
    final sas = state.sas;

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: E2EE badge + timer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _E2EEBadge(),
                  Text(
                    elapsed,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            CircleAvatar(
              radius: 56,
              backgroundColor: Colors.grey.shade800,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 22,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),
            // Safety Number (SAS) — §24.3
            if (sas != null) _SasDisplay(sas: sas),
            const Spacer(),
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _CircleButton(
                  icon: state.isMuted ? Icons.mic_off : Icons.mic,
                  label: state.isMuted ? 'Unmute' : 'Mute',
                  color:
                      state.isMuted ? Colors.orange : Colors.grey.shade800,
                  onTap: () {
                    debugPrint('[DIAG:ActiveCallScreen] mute tapped');
                    ref.read(callProvider.notifier).toggleMute();
                  },
                ),
                _CircleButton(
                  icon: state.isSpeakerOn
                      ? Icons.volume_up
                      : Icons.volume_down,
                  label: state.isSpeakerOn ? 'Speaker ON' : 'Speaker OFF',
                  color: state.isSpeakerOn
                      ? Colors.blue
                      : Colors.grey.shade800,
                  onTap: () {
                    debugPrint('[DIAG:ActiveCallScreen] speaker tapped');
                    ref.read(callProvider.notifier).toggleSpeaker();
                  },
                ),
                _CircleButton(
                  icon: Icons.call_end,
                  label: 'End',
                  color: Colors.red,
                  onTap: () {
                    debugPrint('[DIAG:ActiveCallScreen] endCall tapped');
                    ref.read(callProvider.notifier).endCall();
                  },
                ),
              ],
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _E2EEBadge extends StatelessWidget {
  const _E2EEBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.lock, size: 14, color: Colors.greenAccent),
          SizedBox(width: 4),
          Text('E2EE',
              style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SasDisplay extends StatelessWidget {
  const _SasDisplay({required this.sas});
  final String sas;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('── Safety Number ──',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Text(
          sas.split('').join(' '),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Verify by voice',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
