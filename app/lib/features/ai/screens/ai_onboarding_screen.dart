/// @file        ai_onboarding_screen.dart
/// @description AI model download onboarding screen. Bound to manager state.
///              Live progress when a background download is in flight.
///              Manual download button when not yet started.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation; model download onboarding screen)
///
/// @functions
///  - AiOnboardingScreen: model download onboarding ConsumerStatefulWidget

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../providers/ai_provider.dart';
import '../service/ai_model_manager.dart';

// _modelSizeDisplay removed — uses AIModelManager.modelSizeDisplay

class AiOnboardingScreen extends ConsumerStatefulWidget {
  const AiOnboardingScreen({super.key});

  @override
  ConsumerState<AiOnboardingScreen> createState() =>
      _AiOnboardingScreenState();
}

class _AiOnboardingScreenState extends ConsumerState<AiOnboardingScreen> {
  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(aiModelManagerProvider);

    return ValueListenableBuilder<ModelDownloadStatus>(
      valueListenable: manager.downloadStatus,
      builder: (context, status, _) {
        return ValueListenableBuilder<double>(
          valueListenable: manager.downloadProgress,
          builder: (context, progress, _) {
            return _buildScreen(context, manager, status, progress);
          },
        );
      },
    );
  }

  Widget _buildScreen(
    BuildContext context,
    AIModelManager manager,
    ModelDownloadStatus status,
    double progress,
  ) {
    final isDownloading = status == ModelDownloadStatus.downloading;
    final isDone = status == ModelDownloadStatus.complete;
    final isError = status == ModelDownloadStatus.error;

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00D2FF).withValues(alpha: 0.2),
                      const Color(0xFF0088CC).withValues(alpha: 0.2),
                    ],
                  ),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: Color(0xFF00D2FF), size: 40),
              ),
              const SizedBox(height: 24),

              const Text(
                'SnowChat AI',
                style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Download the AI model to enable on-device\n'
                'private AI assistant. All processing stays\n'
                'on your device — never sent to any server.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Model size: ~2.5-3.1 GB',
                style: const TextStyle(
                    color: SnowColors.textTertiary, fontSize: 13),
              ),

              const SizedBox(height: 32),

              // Progress / Status
              if (isDownloading) ...[
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: SnowColors.surfaceLight,
                  color: const Color(0xFF00D2FF),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(
                      color: SnowColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Download continues in background',
                  style: TextStyle(
                      color: SnowColors.textTertiary, fontSize: 12),
                ),
              ],

              if (isError) ...[
                const Text(
                  'Download failed',
                  style: TextStyle(color: SnowColors.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
              ],

              if (isDone) ...[
                const Icon(Icons.check_circle,
                    color: SnowColors.primary, size: 48),
                const SizedBox(height: 8),
                const Text('Model ready!',
                    style: TextStyle(
                        color: SnowColors.primary,
                        fontWeight: FontWeight.w600)),
              ],

              const Spacer(),

              // Action button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isDownloading
                      ? null
                      : isDone
                          ? () => context.pushReplacement('/ai-chat')
                          : () => _startManualDownload(manager),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isDone
                        ? 'Start Chatting'
                        : isDownloading
                            ? 'Downloading...'
                            : isError
                                ? 'Retry Download'
                                : 'Download AI Model',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
              ),

              // While downloading, show "you can go back, download keeps running" hint
              if (isDownloading) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text(
                    'Go back — download keeps running',
                    style: TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startManualDownload(AIModelManager manager) async {
    // Wi-Fi check
    final wifi = await manager.isWifiConnected();
    if (!wifi && mounted) {
      final proceed = await _showCellularWarning();
      if (!proceed) return;
    }

    manager.startManualDownload();
  }

  Future<bool> _showCellularWarning() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: SnowColors.surface,
            title: const Text('No Wi-Fi',
                style: TextStyle(color: SnowColors.textPrimary)),
            content: Text(
              'The AI model is ~2.5-3.1 GB. '
              'Downloading over cellular may use significant data.',
              style: const TextStyle(color: SnowColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Download Anyway',
                    style: TextStyle(color: SnowColors.primary)),
              ),
            ],
          ),
        ) ??
        false;
  }
}
