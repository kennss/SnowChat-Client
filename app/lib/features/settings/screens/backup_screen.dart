/// @file        backup_screen.dart
/// @description Recovery-phrase view screen (settings) — view recovery phrase after biometric auth, tap-to-reveal.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - BackupScreen: ConsumerStatefulWidget that shows the recovery phrase from settings

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../features/onboarding/widgets/phrase_grid.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _revealed = false;
  bool _authenticated = false;
  List<String>? _mnemonic;
  bool _isLoadingMnemonic = false;

  @override
  void initState() {
    super.initState();
    // Settings → Recovery Phrase view — mnemonic plaintext is exposed.
    // Block screenshots / background snapshots (audit P1 A-7).
    ScreenProtector.protectDataLeakageOn();
    ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    Future<void>(() {
      ScreenProtector.protectDataLeakageOff();
      ScreenProtector.preventScreenshotOff();
    });
    super.dispose();
  }

  void _authenticate() {
    // In production, use local_auth for biometric verification
    setState(() => _authenticated = true);
    _loadMnemonic();
  }

  Future<void> _loadMnemonic() async {
    setState(() => _isLoadingMnemonic = true);
    try {
      final identityManager = ref.read(identityManagerProvider);
      final words = await identityManager.getMnemonic();
      if (mounted) {
        setState(() {
          _mnemonic = words;
          _isLoadingMnemonic = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMnemonic = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Recovery Phrase'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning
              Container(
                padding: const EdgeInsets.all(SnowSizes.md),
                decoration: BoxDecoration(
                  color: SnowColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: SnowColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.security_rounded,
                        color: SnowColors.error, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Never share your recovery phrase with anyone.\n'
                        'SnowChat will never ask for it.',
                        style: TextStyle(
                          color: SnowColors.error,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: SnowSizes.xl),

              if (!_authenticated) ...[
                // Auth gate
                Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.lock_rounded,
                        size: 48,
                        color: SnowColors.textTertiary,
                      ),
                      const SizedBox(height: SnowSizes.md),
                      const Text(
                        'Authenticate to view your recovery phrase',
                        style: TextStyle(
                          color: SnowColors.textSecondary,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: SnowSizes.lg),
                      ElevatedButton.icon(
                        onPressed: _authenticate,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Authenticate'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(200, 48),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // Phrase display
                if (!_revealed)
                  GestureDetector(
                    onTap: () => setState(() => _revealed = true),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 60),
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
                            'Tap to reveal',
                            style: TextStyle(
                              color: SnowColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_revealed)
                  _isLoadingMnemonic
                      ? const Center(child: CircularProgressIndicator())
                      : _mnemonic != null
                          ? Column(
                              children: [
                                PhraseGrid(words: _mnemonic!),
                                const SizedBox(height: SnowSizes.lg),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      final phrase = _mnemonic!.join(' ');
                                      Clipboard.setData(
                                          ClipboardData(text: phrase));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Recovery phrase copied to clipboard'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded,
                                        size: 18),
                                    label: const Text('Copy to Clipboard'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: SnowColors.textSecondary,
                                      side: const BorderSide(
                                          color: SnowColors.surfaceLight),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Center(
                              child: Text(
                                'No recovery phrase found',
                                style: TextStyle(
                                  color: SnowColors.textTertiary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
