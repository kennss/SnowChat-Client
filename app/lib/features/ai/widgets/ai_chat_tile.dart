/// @file        ai_chat_tile.dart
/// @description SnowChat AI tile pinned to the top of the chat list.
///              Live model download progress. Branches routing by state.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation; pinned AI tile in chat list)
///
/// @functions
///  - AiChatTile: chat list top AI tile ConsumerWidget

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/providers.dart';
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
      onTap: () async {
        if (isReady) {
          context.push('/ai-chat');
        } else if (isDownloading) {
          context.push('/ai-onboarding');
        } else {
          context.push('/ai-onboarding');
        }
      },
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
}
