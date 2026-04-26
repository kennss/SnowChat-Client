/// @file        summary_sheet.dart
/// @description Chat-room conversation summary BottomSheet.
///              Four states: loading / done / error / AI-not-installed + stale badge + regenerate.
///              Zero-Knowledge: summary body lives in memory only, no disk persistence.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-20)
///
/// @functions
///  - showSummarySheet(): open the summary BottomSheet
///  - _SummarySheet: internal StatefulWidget (provides the regenerate trigger)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants/colors.dart';
import '../../ai/providers/ai_provider.dart';
import '../../ai/providers/summary_provider.dart';
import '../models/message.dart';

const _accent = Color(0xFF00D2FF);

/// Chat-room conversation summary sheet.
/// Reuses an existing summary if one exists on entry; otherwise auto-generates.
/// [messages] is the full message list of the current room (time-ordered).
Future<void> showSummarySheet({
  required BuildContext context,
  required String conversationId,
  required List<Message> messages,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SnowColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (_) => _SummarySheet(
      conversationId: conversationId,
      messages: messages,
    ),
  );
}

class _SummarySheet extends ConsumerStatefulWidget {
  final String conversationId;
  final List<Message> messages;

  const _SummarySheet({
    required this.conversationId,
    required this.messages,
  });

  @override
  ConsumerState<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends ConsumerState<_SummarySheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoGenerate());
  }

  Future<void> _maybeAutoGenerate() async {
    final aiReady = await ref.read(aiAvailableProvider.future);
    if (!aiReady || !mounted) return;

    final state = ref.read(summaryProvider(widget.conversationId));
    // Reuse existing summary if present (only re-run when the user explicitly hits regenerate)
    if (state.text != null && !state.loading) return;
    if (state.loading) return;

    // V1 stability: aiAvailableProvider doesn't auto-init, so lazy init here.
    final aiService = ref.read(onDeviceAIProvider);
    final manager = ref.read(aiModelManagerProvider);
    final ok = await aiService.ensureInitialized(() => manager.modelPath);
    if (!ok || !mounted) return;

    ref
        .read(summaryProvider(widget.conversationId).notifier)
        .generate(widget.messages);
  }

  Future<void> _regenerate() async {
    final notifier = ref.read(summaryProvider(widget.conversationId).notifier);
    notifier.clear();
    await notifier.generate(widget.messages);
  }

  @override
  Widget build(BuildContext context) {
    final aiAsync = ref.watch(aiAvailableProvider);
    final state = ref.watch(summaryProvider(widget.conversationId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHandle(),
            const SizedBox(height: 4),
            _buildHeader(state),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: aiAsync.when(
                  loading: () => _buildLoading('Checking AI...'),
                  error: (e, _) => _buildError('AI 확인 실패: $e'),
                  data: (ready) => ready
                      ? _buildBody(state)
                      : _buildAiMissing(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFooter(state, aiAsync.valueOrNull ?? false),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: SnowColors.textTertiary.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(SummaryState state) {
    final staleCount = state.text != null
        ? widget.messages.length - state.messageCountAtGeneration
        : 0;
    return Row(
      children: [
        const Icon(Icons.auto_awesome, color: _accent, size: 20),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Conversation Summary',
            style: TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (staleCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+$staleCount new',
              style: const TextStyle(
                color: _accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(SummaryState state) {
    if (state.loading && (state.text == null || state.text!.isEmpty)) {
      return _buildLoading('Summarizing ${widget.messages.length} messages...');
    }
    if (state.error != null && (state.text == null || state.text!.isEmpty)) {
      return _buildError(_errorMessage(state.error!));
    }
    if (state.text == null || state.text!.isEmpty) {
      return _buildLoading('Preparing...');
    }
    return _buildBullets(state.text!);
  }

  Widget _buildBullets(String text) {
    final lines = text.split('\n');
    final items = <Widget>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        items.add(const SizedBox(height: 6));
        continue;
      }
      if (line.startsWith('- ')) {
        items.add(_bulletRow(line.substring(2)));
      } else {
        items.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            line,
            style: const TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  Widget _bulletRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7, right: 10),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(_accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.orange.shade300, size: 32),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiMissing() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          const Icon(Icons.cloud_download_outlined,
              color: SnowColors.textSecondary, size: 32),
          const SizedBox(height: 12),
          const Text(
            'AI model not ready',
            style: TextStyle(
              color: SnowColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Download the on-device AI model from Settings\n'
            'to summarize conversations privately.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(SummaryState state, bool aiReady) {
    final hasText = state.text != null && state.text!.isNotEmpty;
    final canRegen = aiReady && !state.loading;
    final staleCount = hasText
        ? widget.messages.length - state.messageCountAtGeneration
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (aiReady)
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: canRegen ? _regenerate : null,
              icon: Icon(
                staleCount > 0 ? Icons.refresh : Icons.autorenew,
                size: 18,
                color: _accent,
              ),
              label: Text(
                staleCount > 0
                    ? 'Regenerate with new messages'
                    : (hasText ? 'Regenerate' : 'Generate'),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _accent.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 12, color: SnowColors.textTertiary),
            SizedBox(width: 4),
            Text(
              'On-device — nothing leaves this phone',
              style: TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _errorMessage(String code) {
    switch (code) {
      case 'too_short':
        return 'Conversation is too short to summarize.';
      case 'empty_response':
        return 'AI returned an empty summary.\nTry regenerating.';
      case 'inference_failed':
        return 'Summary failed.\nTry again in a moment.';
      default:
        return 'Something went wrong.';
    }
  }
}
