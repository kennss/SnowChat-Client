/// @file        summary_provider.dart
/// @description Chat room summary cache Provider — memory only (Zero-Knowledge).
///              autoDispose.family → auto-released when leaving conversation.
///              Tracks messageCountAtGeneration → stale badge when new messages arrive.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-26 (header + inline English translation; chat room summary cache provider)
///
/// @functions
///  - SummaryState: summary state (text, loading, error, count, generatedAt)
///  - SummaryNotifier.generate(): generate summary from message list
///  - SummaryNotifier.clear(): reset cache
///  - summaryProvider: per-room summary cache (autoDispose family)

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/models/message.dart';
import '../service/conversation_summarizer.dart';
import '../../settings/settings_provider.dart';
import '../../../app/providers.dart';
import 'ai_provider.dart';

/// Summary state.
/// Note: `text` is the finished summary body; previous `text` may be retained while loading.
@immutable
class SummaryState {
  final String? text;
  final bool loading;
  final String? error;

  /// Message count at the time of summary generation. Used by UI to detect stale state.
  final int messageCountAtGeneration;

  final DateTime? generatedAt;

  const SummaryState({
    this.text,
    this.loading = false,
    this.error,
    this.messageCountAtGeneration = 0,
    this.generatedAt,
  });

  bool get isEmpty => text == null || text!.isEmpty;

  SummaryState copyWith({
    String? text,
    bool? loading,
    Object? error = const _Sentinel(),
    int? messageCountAtGeneration,
    DateTime? generatedAt,
  }) {
    return SummaryState(
      text: text ?? this.text,
      loading: loading ?? this.loading,
      error: error is _Sentinel ? this.error : error as String?,
      messageCountAtGeneration: messageCountAtGeneration ?? this.messageCountAtGeneration,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }
}

class _Sentinel {
  const _Sentinel();
}

class SummaryNotifier extends StateNotifier<SummaryState> {
  final ConversationSummarizer _summarizer;
  final String _mySnowId;
  final String _targetLanguage;
  bool _busy = false;

  SummaryNotifier(this._summarizer, this._mySnowId, this._targetLanguage)
      : super(const SummaryState());

  /// Generate summary. Skip if already loading.
  Future<void> generate(List<Message> messages) async {
    if (_busy) return;
    if (!ConversationSummarizer.canSummarize(messages)) {
      state = state.copyWith(
        error: 'too_short',
        loading: false,
      );
      return;
    }

    _busy = true;
    state = state.copyWith(loading: true, error: null);

    try {
      final result = await _summarizer.summarize(
        messages: messages,
        targetLanguage: _targetLanguage,
        mySnowId: _mySnowId,
      );

      if (!mounted) return;

      if (result.text.isEmpty) {
        state = state.copyWith(
          loading: false,
          error: 'empty_response',
        );
      } else {
        state = SummaryState(
          text: result.text,
          loading: false,
          messageCountAtGeneration: messages.length,
          generatedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('[Summary] generate failed: $e');
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: 'inference_failed',
      );
    } finally {
      _busy = false;
    }
  }

  /// Reset cache.
  void clear() {
    state = const SummaryState();
  }

  /// Determine whether the summary is stale due to new messages.
  bool isStale(int currentMessageCount) {
    if (state.text == null) return false;
    return currentMessageCount > state.messageCountAtGeneration;
  }
}

/// Per-room summary cache Provider.
/// autoDispose: memory released when leaving the room.
final summaryProvider = StateNotifierProvider.autoDispose
    .family<SummaryNotifier, SummaryState, String>(
  (ref, conversationId) {
    final aiService = ref.read(onDeviceAIProvider);
    final summarizer = ConversationSummarizer(aiService);
    final mySnowId = ref.read(currentSnowIdProvider) ?? '';
    final targetLang = ref.read(settingsProvider).preferredLanguage;

    return SummaryNotifier(summarizer, mySnowId, targetLang);
  },
);
