/// @file        incoming_call_screen.dart
/// @description Incoming-call screen — accept/decline (Phase 8.2 §3.3, features/call/CLAUDE.md §3.2).
///              iOS/Android system call UI (CallKit/ConnectionService) takes priority;
///              this screen is shown only when the user opens the app directly.
///              Stack + Center + Positioned + portrait lock for stable layout.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation; UI: portrait lock + Stack/Center layout)
///
/// @functions
///  - IncomingCallScreen.build(): incoming-call UI

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../settings/settings_provider.dart';


class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key});

  @override
  ConsumerState<IncomingCallScreen> createState() =>
      _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
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

  @override
  Widget build(BuildContext context) {
    debugPrint('[DIAG:IncomingCallScreen] BUILD');
    final state = ref.watch(callProvider);
    final displayName =
        state.remoteDisplayName ?? state.remoteSnowchatId ?? '...';

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
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
                      const Text(
                        'Incoming voice call',
                        style: TextStyle(
                            fontSize: 16, color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      _E2EEBadge(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        FloatingActionButton(
                          heroTag: 'decline',
                          backgroundColor: Colors.red,
                          onPressed: () =>
                              ref.read(callProvider.notifier).declineCall(),
                          child: const Icon(Icons.call_end,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text('Decline',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                    Column(
                      children: [
                        FloatingActionButton(
                          heroTag: 'accept',
                          backgroundColor: Colors.green,
                          onPressed: () {
                            // Phase F: apply the callee user's Always Relay preference.
                            // Both sides OR'd, so even if caller is false, relay if callee is true.
                            final localAlwaysRelay = ref
                                .read(settingsProvider)
                                .callAlwaysRelay;
                            ref.read(callProvider.notifier).acceptCall(
                                localAlwaysRelay: localAlwaysRelay);
                          },
                          child:
                              const Icon(Icons.call, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text('Accept',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
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
          Text('E2EE Protected',
              style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
        ],
      ),
    );
  }
}
