/// @file        translation_provider.dart
/// @description Real-time translation cache Provider. Memory only — never persist to drift.
///              Per-room family provider, auto-released when leaving conversation.
///              iOS: Apple Translation API, Android: Gemma E2B.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header + inline English translation; real-time translation cache provider)
///
/// @functions
///  - TranslationNotifier.translate(): request message translation
///  - TranslationNotifier.clear(): reset cache
///  - translationCacheProvider: per-room translation cache (autoDispose)

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../service/language_detector.dart';
import '../service/translation_service.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../../settings/settings_provider.dart';

/// Translation result entry
class TranslationEntry {
  final String translatedText;
  final bool isLoading;

  const TranslationEntry({
    required this.translatedText,
    this.isLoading = false,
  });
}

/// TranslationService Provider.
/// iOS: Apple Translation API, Android: Google ML Kit (on-device NMT).
/// Gemma(OnDeviceAIService) dependency removed — translation uses a dedicated NMT engine,
/// only AI chat/summary uses Gemma.
final translationServiceProvider = Provider<TranslationService>((ref) {
  final service = TranslationService();
  ref.onDispose(service.dispose);
  return service;
});

/// Per-room translation cache — memory only, never persist to drift.
class TranslationNotifier extends StateNotifier<Map<String, TranslationEntry>> {
  final TranslationService _translationService;
  String _preferredLanguage;
  final List<_PendingTranslation> _queue = [];
  bool _processing = false;

  TranslationNotifier(this._translationService, this._preferredLanguage) : super({});

  /// Current target language (for debug/display).
  String get preferredLanguage => _preferredLanguage;

  /// Target language change — discard only the pending queue. Existing translations retained.
  /// So that already-read message translations don't disappear when the user changes the target.
  /// New messages onward will be translated with the new target.
  void updateTarget(String newLang) {
    if (_preferredLanguage == newLang) return;
    debugPrint('[Translation] Target changed: $_preferredLanguage → $newLang '
        '(existing translations retained, new messages use new target)');
    _preferredLanguage = newLang;
    _queue.clear();
    _processing = false;
  }

  /// Request message translation. Enqueue and process sequentially.
  Future<void> translate(String messageId, String plaintext) async {
    if (!mounted) { debugPrint('[Translation] skip: not mounted'); return; }
    if (state.containsKey(messageId)) return;
    if (plaintext.trim().length < 2) { debugPrint('[Translation] skip: too short'); return; }
    if (LanguageDetector.isSameLanguage(plaintext, _preferredLanguage)) {
      debugPrint('[Translation] skip: same language ($_preferredLanguage)');
      return;
    }

    // Prevent duplicate enqueue
    if (_queue.any((p) => p.messageId == messageId)) return;

    debugPrint('[Translation] queued: "${plaintext.substring(0, plaintext.length.clamp(0, 30))}"');
    _queue.add(_PendingTranslation(messageId, plaintext));
    _processQueue();
  }

  void _processQueue() {
    if (_processing || _queue.isEmpty || !mounted) return;
    _processing = true;
    _processNext();
  }

  Future<void> _processNext() async {
    if (_queue.isEmpty || !mounted) {
      _processing = false;
      return;
    }

    final item = _queue.removeAt(0);
    if (state.containsKey(item.messageId)) {
      _processNext();
      return;
    }

    // Set loading state
    if (!mounted) { _processing = false; return; }
    state = {...state, item.messageId: const TranslationEntry(translatedText: '', isLoading: true)};

    try {
      final result = await _translationService.translate(item.plaintext, _preferredLanguage);

      if (!mounted) { _processing = false; return; }
      if (result.isNotEmpty) {
        state = {...state, item.messageId: TranslationEntry(translatedText: result)};
      } else {
        final updated = Map<String, TranslationEntry>.from(state);
        updated.remove(item.messageId);
        state = updated;
      }
    } catch (e) {
      debugPrint('[Translation] Failed for ${item.messageId}: $e');
      if (!mounted) { _processing = false; return; }
      final updated = Map<String, TranslationEntry>.from(state);
      updated.remove(item.messageId);
      state = updated;
    }

    // Process next queue item
    _processNext();
  }

  /// Reset cache
  void clear() {
    _queue.clear();
    _processing = false;
    state = {};
  }
}

class _PendingTranslation {
  final String messageId;
  final String plaintext;
  _PendingTranslation(this.messageId, this.plaintext);
}

/// Per-room translation cache Provider (autoDispose — memory released when leaving room).
///
/// Target language priority:
/// 1. `conversation.autoTranslateTargetLang` (per-room override)
/// 2. `settings.preferredLanguage` (global fallback)
final translationCacheProvider = StateNotifierProvider.autoDispose
    .family<TranslationNotifier, Map<String, TranslationEntry>, String>(
  (ref, conversationId) {
    final translationService = ref.read(translationServiceProvider);

    String resolveLang() {
      final convs = ref.read(conversationListProvider);
      final conv = convs.where((c) => c.id == conversationId).firstOrNull;
      return conv?.autoTranslateTargetLang
          ?? ref.read(settingsProvider).preferredLanguage;
    }

    final notifier = TranslationNotifier(translationService, resolveLang());

    // Detect per-room target change
    ref.listen(conversationListProvider, (_, __) {
      notifier.updateTarget(resolveLang());
    });
    // Detect global preferredLanguage change (only takes effect when room has no override)
    ref.listen(settingsProvider, (_, __) {
      notifier.updateTarget(resolveLang());
    });

    return notifier;
  },
);
