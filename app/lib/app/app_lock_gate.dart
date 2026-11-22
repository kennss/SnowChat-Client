/// @file        app_lock_gate.dart
/// @description Locks the app again when it comes back from the background
///              after the user's auto-lock delay (Settings → Auto-lock,
///              default one minute). The lock is an overlay above the routes
///              — the screen underneath (an open chat, a draft) stays as it
///              was — and is set aside while a call is in progress, as the
///              cold-start lock lets calls through today. The cold start keeps
///              its own route (/pin-login), which this never shows over.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - AppLockGate: MaterialApp.builder wrapper; lifecycle → AppLockController
///
/// Notes:
///  - The router is not rebuilt: routerProvider watches isLockedProvider and a
///    change there would replace the whole route stack (an open call screen
///    included). This lock has its own state (appLockProvider).
///  - The overlay is a fresh Overlay so the lock's text field (letters
///    passcode) has the overlay it needs above the Navigator.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/security/app_lock.dart';
import '../features/call/providers/call_provider.dart';
import '../features/onboarding/screens/pin_login_screen.dart';
import '../features/settings/settings_provider.dart';
import 'keyboard_behavior.dart';
import 'providers.dart';
import 'router.dart' show rootNavigatorKey;

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final lock = ref.read(appLockProvider.notifier);
    switch (lifecycle) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        lock.wentToBackground();
      case AppLifecycleState.resumed:
        _cameBack(lock);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _cameBack(AppLockController lock) async {
    final hasPasscode = await ref.read(passcodeStoreProvider).has();
    if (!mounted) return;
    final canLock = hasPasscode &&
        ref.read(isOnboardedProvider) &&
        !ref.read(requiresPinSetupProvider) &&
        !ref.read(isLockedProvider);
    lock.cameBack(
      delay: Duration(seconds: ref.read(settingsProvider).autoLockSeconds),
      canLock: canLock,
    );
    if (ref.read(appLockProvider)) dismissKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider);
    final inCall = ref.watch(callProvider.select((s) => s.status)) !=
        CallStatus.idle;
    if (!locked || inCall) return widget.child;
    return Stack(
      children: [
        // Underneath: kept mounted (state kept), not reachable.
        ExcludeSemantics(child: IgnorePointer(child: widget.child)),
        Positioned.fill(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => PasscodeLockView(
                  onUnlocked: () => ref.read(appLockProvider.notifier).unlock(),
                  onForgot: () {
                    // The reset proves the account with its recovery phrase
                    // and goes back to /pin-login when abandoned — the app
                    // stays locked either way.
                    ref.read(appLockProvider.notifier).unlock();
                    rootNavigatorKey.currentContext?.go('/pin-reset');
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
