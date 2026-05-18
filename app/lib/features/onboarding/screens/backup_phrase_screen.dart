/// @file        backup_phrase_screen.dart
/// @description Recovery-phrase backup screen — show 24-word mnemonic, tap to reveal, confirm written-down then proceed to verification.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-11 (Removed per-screen ScreenProtector wiring — now
///              applied app-wide in main.dart. Earlier Multi-Wallet Phase 1.5
///              2026-04-25 introduced screen_protector for mnemonic-exposing
///              screens (audit P1 A-7); 2026-04-26 header + inline English
///              translation.)
///
/// @functions
///  - BackupPhraseScreen: recovery-phrase backup ConsumerStatefulWidget

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../onboarding_provider.dart';
import '../widgets/phrase_grid.dart';

class BackupPhraseScreen extends ConsumerStatefulWidget {
  const BackupPhraseScreen({super.key});

  @override
  ConsumerState<BackupPhraseScreen> createState() => _BackupPhraseScreenState();
}

class _BackupPhraseScreenState extends ConsumerState<BackupPhraseScreen> {
  bool _revealed = false;

  // Screen capture protection (audit P1 A-7) is applied app-wide in main.dart
  // — no per-screen wiring needed here.

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final mnemonic = state.mnemonic ?? [];

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/create-identity'),
        ),
        title: const Text('Recovery Phrase'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning banner
              Container(
                padding: const EdgeInsets.all(SnowSizes.md),
                decoration: BoxDecoration(
                  color: SnowColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: SnowColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_rounded,
                        color: SnowColors.warning, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Write down these words in order.\nThis is the ONLY way to recover your account.',
                        style: TextStyle(
                          color: SnowColors.warning,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SnowSizes.lg),

              // Reveal toggle
              if (!_revealed)
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _revealed = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 80),
                      decoration: BoxDecoration(
                        color: SnowColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.visibility_rounded,
                              color: SnowColors.primary, size: 32),
                          SizedBox(height: 12),
                          Text(
                            'Tap to reveal your recovery phrase',
                            style: TextStyle(
                              color: SnowColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Make sure no one is looking at your screen',
                            style: TextStyle(
                              color: SnowColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Phrase grid + copy button
              if (_revealed && mnemonic.isNotEmpty) ...[
                PhraseGrid(words: mnemonic),
                const SizedBox(height: SnowSizes.md),

                // Copy All Words button
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final allWords = mnemonic.join(' ');
                      Clipboard.setData(ClipboardData(text: allWords));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Recovery phrase copied!'),
                          backgroundColor: SnowColors.primaryBg,
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.only(
                              bottom: 80, left: 16, right: 16),
                          duration: const Duration(seconds: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy All Words'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SnowColors.primary,
                      side: BorderSide(
                        color: SnowColors.primary.withValues(alpha: 0.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: SnowSizes.xl),
              ],

              const SizedBox(height: SnowSizes.lg),

              // Continue button
              if (_revealed)
                ElevatedButton(
                  onPressed: () {
                    ref.read(onboardingProvider.notifier).proceedToVerify();
                    context.go('/verify-phrase');
                  },
                  child: const Text('I\'ve Written It Down'),
                ),

              const SizedBox(height: SnowSizes.md),
            ],
          ),
        ),
      ),
    );
  }
}
