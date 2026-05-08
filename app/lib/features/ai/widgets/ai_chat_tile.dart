/// @file        ai_chat_tile.dart
/// @description SnowChat AI tile pinned to the top of the chat list.
///              Live model download progress. Branches routing by state.
///              Single point of RAM gating: a tap on this tile is the only
///              way the user enters the AI flow, so the hardware check
///              lives here and nowhere else. Cold-launch auto-download
///              was removed (app.dart) because the user's intent is now
///              what triggers the 2.9 GB fetch.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-05-06 (RAM gate on tap — DeviceCapability.canRunAI
///              denies < 7000 MB devices with an English dialog before
///              any download / model load can start. iPhone 13 (4 GB)
///              testing showed the cold-launch auto-download made the
///              whole app unusable, then the model load OOMed on entry.)
///
/// @functions
///  - AiChatTile: chat list top AI tile ConsumerWidget
///  - _handleTap(): RAM gate, then route by download status
///  - _showAiUnsupportedDialog(): English-only "AI unavailable" dialog

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
import '../../../core/device/device_capability.dart';
import '../../../shared/constants/colors.dart';
import '../../../core/storage/database.dart';
import '../../../core/storage/daos/ai_message_dao.dart';
import '../providers/ai_provider.dart';
import '../service/ai_model_manager.dart';

class AiChatTile extends ConsumerWidget {
  const AiChatTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(aiModelManagerProvider);
    final dao = ref.watch(aiMessageDaoProvider);

    return ValueListenableBuilder<ModelDownloadStatus>(
      valueListenable: manager.downloadStatus,
      builder: (context, status, _) {
        return ValueListenableBuilder<double>(
          valueListenable: manager.downloadProgress,
          builder: (context, progress, _) {
            return _buildTile(context, ref, dao, manager, status, progress);
          },
        );
      },
    );
  }

  Widget _buildTile(
    BuildContext context,
    WidgetRef ref,
    AiMessageDao dao,
    AIModelManager manager,
    ModelDownloadStatus status,
    double progress,
  ) {
    final isDownloading = status == ModelDownloadStatus.downloading;
    final isReady = status == ModelDownloadStatus.complete;

    // Subtitle: progress while downloading, last message otherwise
    Widget subtitle;
    if (isDownloading) {
      subtitle = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Downloading model... ${(progress * 100).toInt()}%',
            style: const TextStyle(
              color: Color(0xFF00D2FF),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: SnowColors.surfaceLight,
            color: const Color(0xFF00D2FF),
            minHeight: 2,
          ),
        ],
      );
    } else if (!isReady && status != ModelDownloadStatus.error) {
      subtitle = const Text(
        'Tap to set up AI assistant',
        style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
      );
    } else if (status == ModelDownloadStatus.error) {
      subtitle = const Text(
        'Download failed — tap to retry',
        style: TextStyle(color: SnowColors.error, fontSize: 13),
      );
    } else {
      subtitle = StreamBuilder<AiMessage?>(
        stream: dao.watchMessages().map(
            (list) => list.isNotEmpty ? list.first : null),
        builder: (context, snapshot) {
          final lastMessage = snapshot.data;
          final text = lastMessage?.content ?? 'Ask me anything';
          final preview =
              text.length > 40 ? '${text.substring(0, 40)}...' : text;
          return Text(
            preview,
            style: const TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        },
      );
    }

    return ListTile(
      onTap: () => _handleTap(context, isReady),
      leading: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF00D2FF), Color(0xFF0088CC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
      ),
      title: const Row(
        children: [
          Text(
            'SnowChat AI',
            style: TextStyle(
              color: SnowColors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          SizedBox(width: 6),
          Icon(Icons.lock_outline, color: Color(0xFF00D2FF), size: 14),
        ],
      ),
      subtitle: subtitle,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isReady)
            StreamBuilder<AiMessage?>(
              stream: dao.watchMessages().map(
                  (list) => list.isNotEmpty ? list.first : null),
              builder: (context, snapshot) {
                final lastMessage = snapshot.data;
                if (lastMessage == null) return const SizedBox.shrink();
                return Text(
                  _formatTime(lastMessage.createdAt),
                  style: const TextStyle(
                    color: SnowColors.textTertiary,
                    fontSize: 12,
                  ),
                );
              },
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00D2FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isDownloading
                  ? '${(progress * 100).toInt()}%'
                  : 'On-Device',
              style: const TextStyle(
                color: Color(0xFF00D2FF),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }

  /// Tap handler. Runs the RAM gate first; on insufficient hardware shows
  /// the English unsupported dialog and returns without routing. On
  /// pass, routes to /ai-chat when the model is ready, otherwise to
  /// /ai-onboarding (which carries the manual download button — no more
  /// auto-download from cold launch).
  Future<void> _handleTap(BuildContext context, bool isReady) async {
    final canRun = await DeviceCapability.canRunAI();
    if (!context.mounted) return;
    if (!canRun) {
      final ramMB = await DeviceCapability.totalRamMB();
      if (!context.mounted) return;
      await _showAiUnsupportedDialog(context, ramMB);
      return;
    }
    if (isReady) {
      context.push('/ai-chat');
    } else {
      context.push('/ai-onboarding');
    }
  }

  Future<void> _showAiUnsupportedDialog(
      BuildContext context, int ramMB) async {
    final ramGB = (ramMB / 1024).toStringAsFixed(1);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'AI Assistant Unavailable',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: Text(
          'This device does not meet the hardware requirements to run '
          'SnowChat AI on-device.\n\n'
          'Required: 8 GB RAM\n'
          'Your device: $ramGB GB\n\n'
          'Supported devices:\n'
          '• iPhone 15 Pro / Pro Max or later\n'
          '• iPhone 16 series (all models)\n'
          '• Galaxy S22+ / S23+ / S24+ / S25+\n'
          '• Pixel 7 or later',
          style: const TextStyle(
            color: SnowColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'OK',
              style: TextStyle(color: Color(0xFF00D2FF)),
            ),
          ),
        ],
      ),
    );
  }
}
