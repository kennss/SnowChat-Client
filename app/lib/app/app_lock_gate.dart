/// @file        app_lock_gate.dart
/// @description Locks the app again when it comes back from the background
///              after the user's auto-lock delay (Settings → Auto-lock,
///              default one minute). The lock is an overlay above the routes
///              — the screen underneath (an open chat, a draft) stays as it
///              was. A call does not lift it: the call screen the app draws
///              is shown above the lock, and everything else stays locked
///              until the passcode is entered (SC-19). The cold start keeps
///              its own route (/pin-login), which this never shows over.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (SC-19: the lock stays up during a call — before,
///              any call state but idle removed it, and while CallKit /
///              ConnectionService rang (no in-app screen) the whole app was
///              usable under the system banner; _CallAboveLock)
///
/// @functions
///  - AppLockGate: MaterialApp.builder wrapper; lifecycle → AppLockController
///  - _CallAboveLock: the app's own call screen, drawn above the lock
///
/// Notes:
///  - The router is not rebuilt: routerProvider watches isLockedProvider and a
///    change there would replace the whole route stack (an open call screen
///    included). This lock has its own state (appLockProvider).
///  - The overlay is a fresh Overlay so the lock's text field (letters
///    passcode) has the overlay it needs above the Navigator. The call screen
///    is a second entry of the same Overlay (its buttons' tooltips need one).
///  - Which call screen: the one the /call route would show
///    (appDrawnCallScreen). While CallKit or ConnectionService owns the incoming
///    UI (CallState.inAppIncoming false) the app draws none, so only the
///    lock shows; answering there moves the call to `connecting`, and the
///    call screen comes up above the lock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/security/app_lock.dart';
import '../features/call/screens/call_screen_for.dart';
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
    if (!locked) return widget.child;
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
              OverlayEntry(builder: (_) => const _CallAboveLock()),
            ],
          ),
        ),
      ],
    );
  }
}

/// The call screen the app draws, above the lock: the rest of the app stays
/// locked while a call rings or runs. Nothing (and nothing to hit — the lock
/// below takes the taps) when there is no call, or while CallKit /
/// ConnectionService shows the incoming call itself.
class _CallAboveLock extends ConsumerWidget {
  const _CallAboveLock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (status, inAppIncoming) = ref.watch(
      callProvider.select((s) => (s.status, s.inAppIncoming)),
    );
    final screen = appDrawnCallScreen(status, inAppIncoming: inAppIncoming);
    if (screen == null) return const SizedBox.shrink();
    // The call screens paint a translucent black (black87): on the /call
    // route nothing is painted under them, here the lock is. An opaque ground
    // keeps the lock's keypad from showing through.
    return ColoredBox(color: Colors.black, child: screen);
  }
}
