/// @file        pin_login_screen.dart
/// @description The app lock. PasscodeLockView asks for the app passcode in the
///              input its kind needs (six digits on a keypad that submits on
///              the sixth; a custom numeric code on the keypad with OK; a
///              letters-and-digits code in a text field), checks it ONCE when
///              submitted, shows the wait after too many wrong entries
///              (PasscodeStore, kept on disk), and offers Face ID / Touch ID /
///              fingerprint first when the user turned it on. PinLoginScreen is
///              the cold-start route (/pin-login); the same view is the
///              overlay of AppLockGate when the app comes back from the
///              background.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-11-22 (PasscodeLockView: the input follows the passcode kind; checked once on
///              submit — it was checked on every digit from the 4th, which showed the PIN length
///              and dropped digits typed during a check; waits kept on disk with growing steps;
///              biometric unlock when enabled; shared by /pin-login and the auto-lock overlay).
///              Earlier 2026-11-20 ("Forgot PIN?" opens /pin-reset). Earlier 2026-08-03 (F2: wrap the
///              Spacer-based PIN layout in LayoutBuilder + ConstrainedBox(minHeight=viewport) +
///              IntrinsicHeight + SingleChildScrollView so a short screen / large font scrolls
///              instead of overflowing the keypad — no visual change on normal devices). Earlier
///              2026-04-26 (header English translation)
///
/// @functions
///  - PinLoginScreen: the cold-start lock route
///  - PasscodeLockView: the lock UI (onUnlocked / onForgot)
///  - _PasscodeLockViewState._submit(): check the entry once
///  - _PasscodeLockViewState._tryBiometric(): biometric unlock when enabled
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../app/providers.dart';
import '../../../core/security/passcode.dart';
import '../../../shared/constants/colors.dart';

/// The cold-start lock route (/pin-login).
class PinLoginScreen extends ConsumerWidget {
  const PinLoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PasscodeLockView(
      onUnlocked: () {
        ref.read(isLockedProvider.notifier).state = false;
        context.go('/chat');
      },
      onForgot: () => context.go('/pin-reset'),
    );
  }
}

/// Asks for the app passcode. [onUnlocked] runs once it was right (or the
/// biometric check passed); [onForgot] on "Forgot passcode?".
class PasscodeLockView extends ConsumerStatefulWidget {
  const PasscodeLockView({
    super.key,
    required this.onUnlocked,
    required this.onForgot,
    this.biometrics,
  });

  final VoidCallback onUnlocked;
  final VoidCallback onForgot;

  /// The biometric check (tests pass a fake); the device's by default.
  final Future<bool> Function()? biometrics;

  @override
  ConsumerState<PasscodeLockView> createState() => _PasscodeLockViewState();
}

class _PasscodeLockViewState extends ConsumerState<PasscodeLockView> {
  PasscodeKind? _kind;
  String _entry = '';
  final _textController = TextEditingController();
  bool _checking = false;
  String? _error;
  Duration _wait = Duration.zero;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = ref.read(passcodeStoreProvider);
    final kind = await store.kind();
    final wait = await store.lockedFor();
    if (!mounted) return;
    setState(() => _kind = kind ?? PasscodeKind.numeric);
    if (wait > Duration.zero) _startWait(wait);
    // The stored value, not the settings state: at a cold start the lock
    // screen can come up before SettingsNotifier has loaded it.
    if (await ref.read(secureStorageProvider).getBiometricLock() && mounted) {
      unawaited(_tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    final check = widget.biometrics ?? _deviceBiometrics;
    bool ok;
    try {
      ok = await check();
    } catch (_) {
      ok = false;
    }
    if (ok && mounted) widget.onUnlocked();
  }

  static Future<bool> _deviceBiometrics() async {
    final auth = LocalAuthentication();
    if (!await auth.canCheckBiometrics) return false;
    return auth.authenticate(
      localizedReason: 'Unlock SnowChat',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
  }

  bool get _blocked => _checking || _wait > Duration.zero;

  void _onDigit(String digit) {
    final kind = _kind;
    if (kind == null || _blocked) return;
    if (_entry.length >= kind.maxLength) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
    // Six digits: submitted on the sixth, like iOS. Other kinds: OK.
    if (kind == PasscodeKind.numeric6 && _entry.length == 6) {
      unawaited(_submit());
    }
  }

  void _onBackspace() {
    if (_blocked || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  /// Check the entry once.
  Future<void> _submit() async {
    final entry = _kind == PasscodeKind.alphanumeric
        ? _textController.text
        : _entry;
    if (entry.isEmpty || _blocked) return;
    setState(() => _checking = true);
    final result = await ref.read(passcodeStoreProvider).check(entry);
    if (!mounted) return;
    switch (result) {
      case PasscodeAccepted():
        widget.onUnlocked();
        return;
      case PasscodeRejected(:final wait, :final attemptsLeft):
        setState(() {
          _checking = false;
          _entry = '';
          _textController.clear();
          _error = wait > Duration.zero
              ? null
              : 'Wrong passcode. $attemptsLeft '
                  '${attemptsLeft == 1 ? 'attempt' : 'attempts'} left.';
        });
        if (wait > Duration.zero) _startWait(wait);
      case PasscodeLockedOut(:final wait):
        setState(() {
          _checking = false;
          _entry = '';
          _textController.clear();
        });
        _startWait(wait);
    }
  }

  void _startWait(Duration wait) {
    _waitTimer?.cancel();
    setState(() => _wait = wait);
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {
        _wait -= const Duration(seconds: 1);
        if (_wait <= Duration.zero) {
          _wait = Duration.zero;
          timer.cancel();
        }
      });
    });
  }

  String get _waitText {
    final s = _wait.inSeconds;
    final text = s >= 60 ? '${(s / 60).ceil()} min' : '$s s';
    return 'Too many attempts. Try again in $text.';
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    return Scaffold(
      backgroundColor: SnowColors.background,
      body: SafeArea(
        // Scroll + ConstrainedBox(min=viewport) + IntrinsicHeight keeps the
        // Spacers working when there is room and scrolls when there is not
        // (short screen / large font).
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    _lockIcon(),
                    const SizedBox(height: 16),
                    _displayName(),
                    const Text(
                      'Enter your passcode',
                      style: TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (kind == null)
                      const SizedBox(height: 14)
                    else if (kind == PasscodeKind.alphanumeric)
                      _textEntry()
                    else
                      _dots(kind),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 20,
                      child: Text(
                        _wait > Duration.zero ? _waitText : (_error ?? ''),
                        style: const TextStyle(
                          color: SnowColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Spacer(flex: 1),
                    if (kind != null && kind != PasscodeKind.alphanumeric)
                      _keypad(kind),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: widget.onForgot,
                      child: const Text(
                        'Forgot passcode?',
                        style: TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lockIcon() => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: SnowColors.primaryBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: SnowColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: const Icon(Icons.lock_rounded, size: 28, color: SnowColors.primary),
      );

  Widget _displayName() => FutureBuilder<String?>(
        future: ref.read(secureStorageProvider).getDisplayName(),
        builder: (context, snap) {
          final name = snap.data;
          if (name == null || name.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              name,
              style: const TextStyle(
                color: SnowColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      );

  /// Six fixed dots for a six-digit code; for a custom numeric code one dot
  /// per digit typed (the stored length is never shown).
  Widget _dots(PasscodeKind kind) {
    final count = kind == PasscodeKind.numeric6 ? 6 : _entry.length;
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (index) {
          final filled = index < _entry.length;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? SnowColors.primary : SnowColors.surfaceLight,
                border: filled
                    ? null
                    : Border.all(color: SnowColors.textTertiary, width: 1),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _textEntry() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: TextField(
          key: const Key('passcode-text'),
          controller: _textController,
          enabled: !_blocked,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => unawaited(_submit()),
          style: const TextStyle(color: SnowColors.textPrimary, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Passcode',
            hintStyle: const TextStyle(color: SnowColors.textTertiary),
            filled: true,
            fillColor: SnowColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded,
                  color: SnowColors.primary),
              onPressed: _blocked ? null : () => unawaited(_submit()),
            ),
          ),
        ),
      );

  Widget _keypad(PasscodeKind kind) {
    // A custom numeric code is submitted with OK (bottom left).
    final ok = kind == PasscodeKind.numeric ? 'ok' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          _row(['1', '2', '3']),
          const SizedBox(height: 16),
          _row(['4', '5', '6']),
          const SizedBox(height: 16),
          _row(['7', '8', '9']),
          const SizedBox(height: 16),
          _row([ok, '0', 'backspace']),
        ],
      ),
    );
  }

  Widget _row(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key.isEmpty) return const SizedBox(width: 72, height: 72);
        if (key == 'backspace') {
          return _key(
            onTap: _onBackspace,
            child: const Icon(Icons.backspace_rounded,
                color: SnowColors.textPrimary, size: 24),
          );
        }
        if (key == 'ok') {
          return _key(
            onTap: () => unawaited(_submit()),
            child: const Text(
              'OK',
              style: TextStyle(
                color: SnowColors.primary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return _key(
          onTap: () => _onDigit(key),
          child: Text(
            key,
            style: const TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w400,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _key({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      onTap: _blocked ? null : onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: SnowColors.surfaceVariant,
        ),
        child: Center(child: child),
      ),
    );
  }
}
