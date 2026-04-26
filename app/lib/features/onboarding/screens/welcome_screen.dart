/// @file        welcome_screen.dart
/// @description Onboarding entry screen — SnowChat logo, intro text, create-identity/restore buttons.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - WelcomeScreen: onboarding entry StatelessWidget

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SnowSizes.lg),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo / Icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: SnowColors.primaryBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SnowColors.primary.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.ac_unit_rounded,
                  size: 48,
                  color: SnowColors.primary,
                ),
              ),

              const SizedBox(height: SnowSizes.xl),

              // Title
              const Text(
                'SnowChat',
                style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: SnowSizes.md),

              // Subtitle
              const Text(
                'End-to-end encrypted messaging\nwith built-in wallet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),

              const Spacer(flex: 3),

              // Create Identity button
              ElevatedButton(
                onPressed: () => context.go('/setup-profile'),
                child: const Text('Create New Identity'),
              ),

              const SizedBox(height: SnowSizes.md),

              // Restore button
              OutlinedButton(
                onPressed: () => context.go('/restore'),
                child: const Text('Restore from Backup'),
              ),

              const SizedBox(height: SnowSizes.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
