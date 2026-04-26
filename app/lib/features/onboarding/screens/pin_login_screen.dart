/// @file        pin_login_screen.dart
/// @description PIN unlock screen — numeric keypad, PIN dot indicator, 30s lockout after 5 failures.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - PinLoginScreen: PIN-unlock ConsumerStatefulWidget
///  - _onKeyTap(String): handle numeric key input
///  - _onBackspace(): delete last input
///  - _verifyPin(): verify PIN and unlock

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../app/providers.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  String _enteredPin = '';
  int _failedAttempts = 0;
  bool _isLocked = false;
  int _lockSecondsRemaining = 0;
  Timer? _lockTimer;
  bool _isVerifying = false;
  String? _error;

  /// Maximum PIN length (stored PIN may be 4-6 digits;
  /// we accept up to 6 digits and auto-verify when length matches stored PIN length).
  static const _maxPinLength = 6;
  static const _maxAttempts = 5;
  static const _lockDurationSeconds = 30;

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  void _onKeyTap(String digit) {
    if (_isLocked || _isVerifying) return;
    if (_enteredPin.length >= _maxPinLength) return;

    setState(() {
      _enteredPin += digit;
      _error = null;
    });

    // Auto-verify at each possible PIN length (4, 5, 6)
    if (_enteredPin.length >= 4 && !_isVerifying) {
      _tryVerifyPin();
    }
  }

  void _onBackspace() {
    if (_isLocked || _isVerifying) return;
    if (_enteredPin.isEmpty) return;

    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      _error = null;
    });
  }

  Future<void> _tryVerifyPin() async {
    setState(() => _isVerifying = true);

    final secureStorage = ref.read(secureStorageProvider);
    final isValid = await secureStorage.verifyPin(_enteredPin);

    if (!mounted) return;

    if (isValid) {
      ref.read(isLockedProvider.notifier).state = false;
      context.go('/chat');
      return;
    }

    // Not valid yet — if max length reached, count as failed attempt
    if (_enteredPin.length >= _maxPinLength) {
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        _startLockTimer();
      }
      setState(() {
        _enteredPin = '';
        _isVerifying = false;
        _error = _isLocked
            ? 'Too many attempts, try again in ${_lockSecondsRemaining}s'
            : 'Wrong PIN. ${_maxAttempts - _failedAttempts} attempts remaining.';
      });
    } else {
      // Still entering — keep going silently
      setState(() => _isVerifying = false);
    }
  }

  Future<void> _verifyPin() async {
    setState(() => _isVerifying = true);

    final secureStorage = ref.read(secureStorageProvider);
    final isValid = await secureStorage.verifyPin(_enteredPin);

    if (!mounted) return;

    if (isValid) {
      ref.read(isLockedProvider.notifier).state = false;
      context.go('/chat');
    } else {
      _failedAttempts++;

      if (_failedAttempts >= _maxAttempts) {
        _startLockTimer();
      }

      setState(() {
        _enteredPin = '';
        _isVerifying = false;
        _error = _isLocked
            ? 'Too many attempts, try again in ${_lockSecondsRemaining}s'
            : 'Wrong PIN. ${_maxAttempts - _failedAttempts} attempts remaining.';
      });
    }
  }

  void _startLockTimer() {
    setState(() {
      _isLocked = true;
      _lockSecondsRemaining = _lockDurationSeconds;
    });

    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _lockSecondsRemaining--;
        if (_lockSecondsRemaining <= 0) {
          _isLocked = false;
          _failedAttempts = 0;
          _error = null;
          timer.cancel();
        } else {
          _error =
              'Too many attempts, try again in ${_lockSecondsRemaining}s';
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // Lock icon
            Container(
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
              child: const Icon(
                Icons.lock_rounded,
                size: 28,
                color: SnowColors.primary,
              ),
            ),

            const SizedBox(height: 16),

            // Display name
            FutureBuilder<String?>(
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
            ),

            // Title
            const Text(
              'Enter your PIN',
              style: TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 32),

            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_maxPinLength, (index) {
                final isFilled = index < _enteredPin.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? SnowColors.primary
                          : SnowColors.surfaceLight,
                      border: isFilled
                          ? null
                          : Border.all(
                              color: SnowColors.textTertiary,
                              width: 1,
                            ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 16),

            // Error message
            SizedBox(
              height: 20,
              child: _error != null
                  ? Text(
                      _error!,
                      style: const TextStyle(
                        color: SnowColors.error,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),

            const Spacer(flex: 1),

            // Numeric keypad
            _buildKeypad(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          _buildKeypadRow(['1', '2', '3']),
          const SizedBox(height: 16),
          _buildKeypadRow(['4', '5', '6']),
          const SizedBox(height: 16),
          _buildKeypadRow(['7', '8', '9']),
          const SizedBox(height: 16),
          _buildKeypadRow(['', '0', 'backspace']),
        ],
      ),
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) {
        if (key.isEmpty) {
          return const SizedBox(width: 72, height: 72);
        }
        if (key == 'backspace') {
          return _buildKeyButton(
            onTap: _onBackspace,
            child: const Icon(
              Icons.backspace_rounded,
              color: SnowColors.textPrimary,
              size: 24,
            ),
          );
        }
        return _buildKeyButton(
          onTap: () => _onKeyTap(key),
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

  Widget _buildKeyButton({
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: (_isLocked || _isVerifying) ? null : onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SnowColors.surfaceVariant,
        ),
        child: Center(child: child),
      ),
    );
  }
}
