/// @file        restore_screen.dart
/// @description Identity-restore screen — paste all 24 words at once or enter via text input to restore.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-11 (Removed per-screen ScreenProtector wiring — now
///              applied app-wide in main.dart. Earlier 2026-04-26 header +
///              inline English translation.)
///
/// @functions
///  - RestoreScreen: identity-restore ConsumerStatefulWidget

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/loading_overlay.dart';
import '../../../shared/widgets/toast.dart';
import '../../../app/providers.dart';
import '../onboarding_provider.dart';

class RestoreScreen extends ConsumerStatefulWidget {
  const RestoreScreen({super.key});

  @override
  ConsumerState<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends ConsumerState<RestoreScreen> {
  final _controller = TextEditingController();
  List<String> _words = [];
  String? _validationError;

  bool get _isValidWordCount =>
      _words.length == 12 || _words.length == 24;

  // Screen capture protection (audit P1 A-7) is applied app-wide in main.dart
  // — no per-screen wiring needed here.

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parseWords(String text) {
    final words = text
        .trim()
        .split(RegExp(r'[\s,\n]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.toLowerCase())
        .toList();
    setState(() {
      _words = words;
      _validationError = null;
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _controller.text = data.text!;
      _parseWords(data.text!);
    } else {
      if (mounted) {
        SnowToast.show(context, message: 'Clipboard is empty', type: ToastType.warning);
      }
    }
  }

  Future<void> _restore() async {
    if (_words.length != 12 && _words.length != 24) {
      setState(() {
        _validationError = 'Please enter 12 or 24 words (currently ${_words.length})';
      });
      return;
    }

    final notifier = ref.read(onboardingProvider.notifier);
    final restoreSw = Stopwatch()..start();
    debugPrint('[Perf] ▶️ restore button pressed');
    await notifier.restoreIdentity(_words);
    debugPrint('[Perf] ▶️ restoreIdentity returned at '
        '${restoreSw.elapsedMilliseconds}ms');

    final state = ref.read(onboardingProvider);
    if (state.error != null) {
      if (mounted) {
        SnowToast.show(context, message: state.error!, type: ToastType.error);
      }
    } else {
      if (state.isNewUserFromRestore) {
        // New user via restore — needs nickname setup
        if (mounted) {
          debugPrint('[Perf] ▶️ go /setup-profile (new user) at '
              '${restoreSw.elapsedMilliseconds}ms');
          context.go('/setup-profile?restore=true');
        }
      } else {
        // Phase 8.7 round 5: existing user on the server, but the local
        // device has no PIN yet (this restore is on a fresh install).
        // Force the setup-profile screen instead of /chat — otherwise the
        // user reaches the main app with no PIN lock at all and every
        // subsequent process restart bypasses the lock screen.
        final secureStorage = ref.read(secureStorageProvider);
        final pinSw = Stopwatch()..start();
        final hasPin = await secureStorage.hasPin();
        debugPrint('[Perf] ▶️ secureStorage.hasPin: '
            '${pinSw.elapsedMilliseconds}ms');
        if (!mounted) return;
        if (!hasPin) {
          debugPrint('[Perf] ▶️ go /setup-profile (existing user, no PIN) at '
              '${restoreSw.elapsedMilliseconds}ms');
          context.go('/setup-profile?restore=true');
        } else {
          notifier.completeVerification();
          debugPrint('[Perf] ▶️ go /chat at ${restoreSw.elapsedMilliseconds}ms');
          context.go('/chat');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/welcome'),
        ),
        title: const Text('Restore Identity'),
      ),
      body: LoadingOverlay(
        isLoading: state.isLoading,
        message: 'Restoring identity...',
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SnowSizes.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter your recovery phrase',
                        style: TextStyle(
                          color: SnowColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: SnowSizes.sm),
                      const Text(
                        'Paste or type your 12 or 24 words separated by spaces.',
                        style: TextStyle(
                          color: SnowColors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: SnowSizes.lg),

                      // Paste button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.paste_rounded, size: 20),
                          label: const Text('Paste from Clipboard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SnowColors.primary,
                            side: BorderSide(
                              color: SnowColors.primary.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),

                      const SizedBox(height: SnowSizes.lg),

                      // Single text area for all 24 words
                      TextField(
                        controller: _controller,
                        onChanged: _parseWords,
                        maxLines: 6,
                        style: const TextStyle(
                          color: SnowColors.textPrimary,
                          fontSize: 16,
                          height: 1.8,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: 'fortune knee forum web interest cry sausage basket orient broken fork jacket...',
                          hintStyle: TextStyle(
                            color: SnowColors.textTertiary.withValues(alpha: 0.3),
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: SnowColors.surfaceVariant,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: SnowColors.primary,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),

                      const SizedBox(height: SnowSizes.md),

                      // Word count indicator
                      Row(
                        children: [
                          Icon(
                            _isValidWordCount
                                ? Icons.check_circle_rounded
                                : Icons.info_outline_rounded,
                            size: 16,
                            color: _isValidWordCount
                                ? SnowColors.primary
                                : SnowColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_words.length} words${_isValidWordCount ? ' ✓' : ' (12 or 24)'}',
                            style: TextStyle(
                              color: _isValidWordCount
                                  ? SnowColors.primary
                                  : SnowColors.textTertiary,
                              fontSize: 13,
                              fontWeight: _isValidWordCount
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),

                      // Parsed words preview
                      if (_words.isNotEmpty) ...[
                        const SizedBox(height: SnowSizes.md),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _words.asMap().entries.map((e) {
                            final maxWords = _words.length <= 12 ? 12 : 24;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: SnowColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: e.key < maxWords
                                      ? SnowColors.primary.withValues(alpha: 0.2)
                                      : SnowColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                '${e.key + 1}. ${e.value}',
                                style: TextStyle(
                                  color: e.key < maxWords
                                      ? SnowColors.textPrimary
                                      : SnowColors.error,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // Validation error
                      if (_validationError != null) ...[
                        const SizedBox(height: SnowSizes.md),
                        Text(
                          _validationError!,
                          style: const TextStyle(
                            color: SnowColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Restore button
              Padding(
                padding: const EdgeInsets.all(SnowSizes.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isValidWordCount ? _restore : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isValidWordCount
                          ? SnowColors.primary
                          : SnowColors.surfaceLight,
                      foregroundColor: _isValidWordCount
                          ? SnowColors.background
                          : SnowColors.textTertiary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Restore',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
