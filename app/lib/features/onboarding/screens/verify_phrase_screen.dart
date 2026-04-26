/// @file        verify_phrase_screen.dart
/// @description Recovery-phrase verification screen — verify backup by checking 3 random word positions.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - VerifyPhraseScreen: recovery-phrase verification ConsumerStatefulWidget

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/toast.dart';
import '../onboarding_provider.dart';

class VerifyPhraseScreen extends ConsumerStatefulWidget {
  const VerifyPhraseScreen({super.key});

  @override
  ConsumerState<VerifyPhraseScreen> createState() => _VerifyPhraseScreenState();
}

class _VerifyPhraseScreenState extends ConsumerState<VerifyPhraseScreen> {
  late List<int> _verifyIndices;
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, bool> _verified = {};
  int _wordCount = 24;

  @override
  void initState() {
    super.initState();
    // Mnemonic verification screen — user enters words → block
    // screenshots / background snapshots (audit P1 A-7).
    ScreenProtector.protectDataLeakageOn();
    ScreenProtector.preventScreenshotOn();

    // Pick 3 random word positions to verify
    final mnemonic = ref.read(onboardingProvider).mnemonic;
    _wordCount = mnemonic?.length ?? 24;
    final random = Random();
    final indices = List.generate(_wordCount, (i) => i)..shuffle(random);
    _verifyIndices = indices.take(3).toList()..sort();

    for (final idx in _verifyIndices) {
      _controllers[idx] = TextEditingController();
      _verified[idx] = false;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    Future<void>(() {
      ScreenProtector.protectDataLeakageOff();
      ScreenProtector.preventScreenshotOff();
    });
    super.dispose();
  }

  void _checkWord(int index, String input) {
    final mnemonic = ref.read(onboardingProvider).mnemonic;
    if (mnemonic == null) return;

    setState(() {
      _verified[index] = input.trim().toLowerCase() ==
          mnemonic[index].toLowerCase();
    });
  }

  bool get _allVerified => _verified.values.every((v) => v);

  void _complete() {
    if (_allVerified) {
      ref.read(onboardingProvider.notifier).completeVerification();
      context.go('/chat');
    } else {
      SnowToast.show(
        context,
        message: 'Please verify all words correctly',
        type: ToastType.warning,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/backup-phrase'),
        ),
        title: const Text('Verify Phrase'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verify your recovery phrase',
                style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: SnowSizes.sm),
              const Text(
                'Enter the words at the specified positions to confirm you\'ve saved your phrase.',
                style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: SnowSizes.xl),

              // Verification fields
              ...List.generate(_verifyIndices.length, (i) {
                final idx = _verifyIndices[i];
                final isCorrect = _verified[idx] ?? false;
                final hasInput =
                    _controllers[idx]!.text.trim().isNotEmpty;

                return Padding(
                  padding: const EdgeInsets.only(bottom: SnowSizes.md),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          'Word ${idx + 1}',
                          style: const TextStyle(
                            color: SnowColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controllers[idx],
                          onChanged: (v) => _checkWord(idx, v),
                          style: const TextStyle(
                            color: SnowColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter word ${idx + 1}',
                            suffixIcon: hasInput
                                ? Icon(
                                    isCorrect
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    color: isCorrect
                                        ? SnowColors.success
                                        : SnowColors.error,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 24),

              // Complete button
              ElevatedButton(
                onPressed: _allVerified ? _complete : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _allVerified
                      ? SnowColors.primary
                      : SnowColors.surfaceLight,
                  foregroundColor: _allVerified
                      ? SnowColors.background
                      : SnowColors.textTertiary,
                ),
                child: const Text('Complete Setup'),
              ),

              const SizedBox(height: SnowSizes.md),
            ],
          ),
        ),
      ),
    );
  }
}
