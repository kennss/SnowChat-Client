/// @file        setup_profile_screen.dart
/// @description Profile-setup screen — nickname input, PIN creation (4-6 digits), PIN confirmation.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SetupProfileScreen: profile-setup ConsumerStatefulWidget
///  - _isValid: input validation (nickname 2-20 chars, PIN 4-6 digits, PIN match)
///  - _onContinue(): on validation pass, save profile via onboarding provider and advance

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../app/providers.dart';
import '../onboarding_provider.dart';

class SetupProfileScreen extends ConsumerStatefulWidget {
  /// If true, this screen is part of the restore flow.
  /// After profile setup, navigates to /chat instead of /create-identity.
  final bool isRestore;

  const SetupProfileScreen({super.key, this.isRestore = false});

  @override
  ConsumerState<SetupProfileScreen> createState() =>
      _SetupProfileScreenState();
}

class _SetupProfileScreenState extends ConsumerState<SetupProfileScreen> {
  final _nicknameController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  final _nicknameFocus = FocusNode();
  final _pinFocus = FocusNode();
  final _pinConfirmFocus = FocusNode();
  String? _existingNickname;

  String? _nicknameError;
  String? _pinError;
  String? _pinConfirmError;

  Stopwatch? _entrySw;

  @override
  void initState() {
    super.initState();
    _entrySw = Stopwatch()..start();
    debugPrint('[Perf] 🎨 SetupProfile initState (isRestore=${widget.isRestore})');
    if (widget.isRestore) {
      _populateExistingNickname();
    }
    // Measure timing after first frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[Perf] 🎨 SetupProfile first frame rendered: '
          '${_entrySw?.elapsedMilliseconds}ms');
    });
    // Second frame (after post-layout — when UI starts responding)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[Perf] 🎨 SetupProfile second frame (post-layout): '
            '${_entrySw?.elapsedMilliseconds}ms');
      });
    });
  }

  /// Populate nickname field with the display name already fetched by
  /// restoreIdentity (stored in OnboardingState.displayName).
  ///
  /// Perf: Previously this screen did its own GET /users/$snowId — a
  /// duplicate round-trip that took ~1.3s on iOS post-restore due to
  /// concurrent network contention (prekey upload, socket connect, etc).
  /// Reading from state is instant.
  void _populateExistingNickname() {
    final existing = ref.read(onboardingProvider).displayName;
    if (existing == null || existing.isEmpty) {
      debugPrint('[Perf] 🎨 SetupProfile: no cached displayName in state');
      return;
    }
    _existingNickname = existing;
    _nicknameController.text = existing;
    debugPrint('[Perf] 🎨 SetupProfile nickname populated from state at entry+'
        '${_entrySw?.elapsedMilliseconds}ms');
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    _nicknameFocus.dispose();
    _pinFocus.dispose();
    _pinConfirmFocus.dispose();
    super.dispose();
  }

  bool get _isValid {
    final nickname = _nicknameController.text.trim();
    final pin = _pinController.text;
    final pinConfirm = _pinConfirmController.text;

    return nickname.length >= 2 &&
        nickname.length <= 20 &&
        pin.length >= 4 &&
        pin.length <= 6 &&
        pin == pinConfirm;
  }

  void _validate() {
    final nickname = _nicknameController.text.trim();
    final pin = _pinController.text;
    final pinConfirm = _pinConfirmController.text;

    setState(() {
      // Nickname validation
      if (nickname.isEmpty) {
        _nicknameError = null; // Don't show error for empty (not submitted yet)
      } else if (nickname.length < 2) {
        _nicknameError = 'Nickname must be at least 2 characters';
      } else if (nickname.length > 20) {
        _nicknameError = 'Nickname must be 20 characters or less';
      } else {
        _nicknameError = null;
      }

      // PIN validation
      if (pin.isEmpty) {
        _pinError = null;
      } else if (pin.length < 4) {
        _pinError = 'PIN must be at least 4 digits';
      } else {
        _pinError = null;
      }

      // PIN confirmation validation
      if (pinConfirm.isEmpty) {
        _pinConfirmError = null;
      } else if (pin != pinConfirm) {
        _pinConfirmError = 'PINs do not match';
      } else {
        _pinConfirmError = null;
      }
    });
  }

  Future<void> _onContinue() async {
    if (!_isValid) return;

    final nickname = _nicknameController.text.trim();
    final pin = _pinController.text;

    await ref
        .read(onboardingProvider.notifier)
        .setProfile(nickname: nickname, pin: pin);

    if (!mounted) return;

    if (widget.isRestore) {
      // Phase 8.7 round 8 — double-authenticate self-lockout fix:
      //
      // Restore flow has TWO sub-paths:
      //  (a) Mnemonic for an unknown user (server has no record) —
      //      restoreIdentity() sets isNewUser=true and skips authenticate.
      //      SetupProfileScreen must then run registerAndAuthenticate() to
      //      actually create the server row + get a JWT.
      //  (b) Mnemonic for an existing server user with no PIN on this
      //      device (round 5 fix forces setup-profile here) —
      //      restoreIdentity() ALREADY called authenticate() successfully
      //      and stored a JWT in authTokenProvider.
      //
      // Before this fix, both paths unconditionally called
      // registerAndAuthenticate(), which re-ran authenticate() in path (b)
      // and hit the user's OWN freshly-opened socket with the
      // "Another device is already logged in" guard — permanent self-
      // lockout. The round 7 stale-socket cleanup did not help because
      // that first socket was genuinely live.
      //
      // Detect path (b) by the presence of a JWT, and just complete +
      // navigate. Path (a) keeps the old register + auth sequence.
      final alreadyAuthed = ref.read(authTokenProvider) != null;
      if (alreadyAuthed) {
        ref.read(onboardingProvider.notifier).completeVerification();
        context.go('/chat');
        return;
      }
      final success = await ref
          .read(onboardingProvider.notifier)
          .registerAndAuthenticate(nickname);
      if (!mounted) return;
      if (success) {
        ref.read(onboardingProvider.notifier).completeVerification();
        context.go('/chat');
      }
      // If failed, error is shown via onboardingProvider.error (in build)
    } else {
      // New identity flow: proceed to create identity
      context.go('/create-identity');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/welcome'),
        ),
        title: const Text('Set Up Profile'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SnowSizes.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: SnowSizes.md),

                    // Show error from previous attempt (e.g. nickname taken)
                    if (ref.watch(onboardingProvider).error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: SnowSizes.md),
                        decoration: BoxDecoration(
                          color: SnowColors.error.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SnowColors.error.withAlpha(77)),
                        ),
                        child: Text(
                          ref.watch(onboardingProvider).error!,
                          style: const TextStyle(
                            color: SnowColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],

                    // Restore mode: show existing nickname, skip input
                    if (widget.isRestore && _existingNickname != null) ...[
                      const Text(
                        'Welcome back!',
                        style: TextStyle(
                          color: SnowColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: SnowSizes.sm),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: SnowColors.primaryBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: SnowColors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_rounded,
                                color: SnowColors.primary, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              _existingNickname!,
                              style: const TextStyle(
                                color: SnowColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: SnowSizes.sm),
                      const Text(
                        'Set a new PIN for this device.',
                        style: TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    // New identity mode: nickname input
                    if (!widget.isRestore || _existingNickname == null) ...[
                      const Text(
                        'Choose a nickname',
                        style: TextStyle(
                          color: SnowColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: SnowSizes.sm),
                      const Text(
                        'This is how others will see you in SnowChat.',
                        style: TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: SnowSizes.md),

                      // Nickname field
                      TextField(
                      controller: _nicknameController,
                      focusNode: _nicknameFocus,
                      onChanged: (_) => _validate(),
                      onSubmitted: (_) => _pinFocus.requestFocus(),
                      textInputAction: TextInputAction.next,
                      maxLength: 20,
                      style: const TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Nickname',
                        hintStyle: const TextStyle(
                          color: SnowColors.textTertiary,
                        ),
                        counterStyle: const TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 11,
                        ),
                        errorText: _nicknameError,
                        filled: true,
                        fillColor: SnowColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.primary,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.error,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.error,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    ], // end if (!widget.isRestore || _existingNickname == null)

                    const SizedBox(height: SnowSizes.xl),

                    // PIN section
                    const Text(
                      'Create a PIN',
                      style: TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: SnowSizes.sm),
                    const Text(
                      'Your PIN is used to unlock the app and authorize transactions. Choose 4-6 digits.',
                      style: TextStyle(
                        color: SnowColors.textTertiary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: SnowSizes.md),

                    // PIN field
                    TextField(
                      controller: _pinController,
                      focusNode: _pinFocus,
                      onChanged: (_) => _validate(),
                      onSubmitted: (_) => _pinConfirmFocus.requestFocus(),
                      textInputAction: TextInputAction.next,
                      obscureText: true,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 20,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        hintText: 'PIN',
                        hintStyle: const TextStyle(
                          color: SnowColors.textTertiary,
                          letterSpacing: 0,
                        ),
                        counterStyle: const TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 11,
                        ),
                        errorText: _pinError,
                        filled: true,
                        fillColor: SnowColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.primary,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.error,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.error,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),

                    const SizedBox(height: SnowSizes.md),

                    // PIN confirm field
                    TextField(
                      controller: _pinConfirmController,
                      focusNode: _pinConfirmFocus,
                      onChanged: (_) => _validate(),
                      onSubmitted: (_) {
                        if (_isValid) _onContinue();
                      },
                      textInputAction: TextInputAction.done,
                      obscureText: true,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 20,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Confirm PIN',
                        hintStyle: const TextStyle(
                          color: SnowColors.textTertiary,
                          letterSpacing: 0,
                        ),
                        counterStyle: const TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 11,
                        ),
                        errorText: _pinConfirmError,
                        filled: true,
                        fillColor: SnowColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.primary,
                            width: 1.5,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.error,
                            width: 1.5,
                          ),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: SnowColors.error,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Continue button
            Padding(
              padding: const EdgeInsets.all(SnowSizes.lg),
              child: ElevatedButton(
                onPressed: _isValid ? _onContinue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isValid ? SnowColors.primary : SnowColors.surfaceLight,
                  foregroundColor: _isValid
                      ? SnowColors.background
                      : SnowColors.textTertiary,
                ),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
