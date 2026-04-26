/// @file        create_identity_screen.dart
/// @description Identity-creation screen — auto-generate cryptographic keys, show SnowChat ID, proceed to recovery-phrase backup.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - CreateIdentityScreen: identity-creation ConsumerStatefulWidget

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/loading_overlay.dart';
import '../../../shared/widgets/snow_id_display.dart';
import '../onboarding_provider.dart';

class CreateIdentityScreen extends ConsumerStatefulWidget {
  const CreateIdentityScreen({super.key});

  @override
  ConsumerState<CreateIdentityScreen> createState() =>
      _CreateIdentityScreenState();
}

class _CreateIdentityScreenState extends ConsumerState<CreateIdentityScreen> {
  bool _created = false;

  @override
  void initState() {
    super.initState();
    // Auto-create identity on screen open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createIdentity();
    });
  }

  Future<void> _createIdentity() async {
    final displayName = ref.read(onboardingProvider).displayName;
    await ref
        .read(onboardingProvider.notifier)
        .createIdentity(displayName: displayName);

    final state = ref.read(onboardingProvider);
    if (mounted) {
      if (state.error != null) {
        // Show error on this screen — user taps back to change nickname
        setState(() {});
      } else {
        setState(() => _created = true);
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
        title: const Text('Create Identity'),
      ),
      body: LoadingOverlay(
        isLoading: state.isLoading,
        message: 'Generating keys...',
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SnowSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: SnowSizes.xxl),

                // Success icon
                if (_created && state.snowChatId != null) ...[
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: SnowColors.primaryBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 40,
                      color: SnowColors.primary,
                    ),
                  ),

                  const SizedBox(height: SnowSizes.lg),

                  Text(
                    state.displayName != null
                        ? 'Welcome, ${state.displayName}!'
                        : 'Identity Created',
                    style: const TextStyle(
                      color: SnowColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: SnowSizes.md),

                  const Text(
                    'Your unique SnowChat ID:',
                    style: TextStyle(
                      color: SnowColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),

                  const SizedBox(height: SnowSizes.md),

                  // SnowChat ID display
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: SnowColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SnowIdDisplay(
                      snowId: state.snowChatId!,
                      compact: false,
                      fontSize: 13,
                    ),
                  ),

                  const SizedBox(height: SnowSizes.lg),

                  const Text(
                    'This ID is derived from your cryptographic keys.\nShare it with others to receive messages.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),

                  const Spacer(),

                  // Continue to backup
                  ElevatedButton(
                    onPressed: () => context.go('/backup-phrase'),
                    child: const Text('Back Up Recovery Phrase'),
                  ),

                  const SizedBox(height: SnowSizes.md),

                  TextButton(
                    onPressed: () {
                      ref
                          .read(onboardingProvider.notifier)
                          .completeVerification();
                      context.go('/chat');
                    },
                    child: const Text(
                      'Skip for now',
                      style: TextStyle(color: SnowColors.textTertiary),
                    ),
                  ),
                ],

                // Error state
                if (state.error != null && !_created) ...[
                  const SizedBox(height: SnowSizes.xl),
                  Icon(Icons.error_outline_rounded,
                      size: 48, color: SnowColors.error),
                  const SizedBox(height: SnowSizes.md),
                  Text(
                    state.error!,
                    style: const TextStyle(
                        color: SnowColors.error, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: SnowSizes.lg),
                  ElevatedButton(
                    onPressed: () => context.go('/setup-profile'),
                    child: const Text('Change Nickname'),
                  ),
                ],

                const SizedBox(height: SnowSizes.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
