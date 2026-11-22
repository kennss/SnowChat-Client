/// @file        translation_provider.dart
/// @description Real-time translation cache Provider. Memory only — never persist to drift.
///              Per-room family provider, alive exactly while that room's chat
///              screen is open (the screen holds a subscription) and released
///              when leaving. The cache drives itself: it translates the room's
///              recent incoming messages when created, when new messages arrive,
///              and when auto-translate is switched on or the target changes.
///              iOS: Apple Translation API, Android: Google ML Kit (native).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-11-11 (cache drives its own translations — ChatNotifier no longer
///              pushes into it, which lost results in an empty or reopened room;
///              single processing loop; results for a stale target are dropped;
///              untranslatable messages are not retried; logs carry lengths only).
///              Earlier 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TranslationNotifier.translate(): request message translation
///  - TranslationNotifier.updateTarget(): switch target language (drops stale work)
///  - TranslationNotifier.clear(): reset cache
///  - recentIncomingForTranslation(): the messages a room auto-translates (top-level)
///  - translationCacheProvider: per-room translation cache (autoDispose, self-driving)

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart' show currentSnowIdProvider;
import '../service/language_detector.dart';
import '../service/translation_service.dart';
import '../../chat/models/message.dart';
import '../../chat/providers/chat_provider.dart';
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

  /// Bumped on every target change. A translation that started under an older
  /// generation is discarded instead of being stored for the wrong target.
  int _generation = 0;

  /// Messages already tried for the current target that produced no
  /// translation (same language, unsupported, engine failure). Not retried
  /// while this cache lives — a reopened room (new cache) tries again.
  final Set<String> _settled = {};

  TranslationNotifier(this._translationService, this._preferredLanguage) : super({});

  /// Current target language (for debug/display).
  String get preferredLanguage => _preferredLanguage;

  /// Target language change — discard pending and in-flight work. Existing
  /// translations are retained so already-read messages don't lose theirs;
  /// new messages use the new target.
  void updateTarget(String newLang) {
    if (_preferredLanguage == newLang) return;
    debugPrint('[Translation] Target changed: $_preferredLanguage → $newLang '
        '(existing translations retained, new messages use new target)');
    _preferredLanguage = newLang;
    _generation++;
    _queue.clear();
    _settled.clear();
  }

  /// Request message translation. Enqueued and processed one at a time.
  void translate(String messageId, String plaintext) {
    if (!mounted) return;
    if (state.containsKey(messageId) || _settled.contains(messageId)) return;
    if (_queue.any((p) => p.messageId == messageId)) return;
    if (plaintext.trim().length < 2 ||
        LanguageDetector.isSameLanguage(plaintext, _preferredLanguage)) {
      _settled.add(messageId);
      return;
    }

    // Never log message text — length only.
    debugPrint('[Translation] queued: ${plaintext.length} chars');
    _queue.add(_PendingTranslation(messageId, plaintext));
    _processQueue();
  }

  void _processQueue() {
    if (_processing || _queue.isEmpty || !mounted) return;
    _processing = true;
    _processNext();
  }

  Future<void> _processNext() async {
    while (mounted && _queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      if (state.containsKey(item.messageId)) continue;

      final generation = _generation;
      state = {...state, item.messageId: const TranslationEntry(translatedText: '', isLoading: true)};

      String result;
      try {
        result = await _translationService.translate(item.plaintext, _preferredLanguage);
      } catch (e) {
        debugPrint('[Translation] Failed for ${item.messageId}: ${e.runtimeType}');
        result = '';
      }
      if (!mounted) break;

      final updated = Map<String, TranslationEntry>.from(state);
      if (generation != _generation) {
        // Target changed while this was in flight — drop the stale result.
        updated.remove(item.messageId);
      } else if (result.isNotEmpty) {
        updated[item.messageId] = TranslationEntry(translatedText: result);
      } else {
        updated.remove(item.messageId);
        _settled.add(item.messageId);
      }
      debugPrint('[Translation] ${item.messageId}: '
          '${generation != _generation ? 'stale target, dropped' : result.isEmpty ? 'no translation' : '${result.length} chars'}');
      state = updated;
    }
    _processing = false;
  }

  /// Reset cache
  void clear() {
    _generation++;
    _queue.clear();
    _settled.clear();
    state = {};
  }
}

class _PendingTranslation {
  final String messageId;
  final String plaintext;
  _PendingTranslation(this.messageId, this.plaintext);
}

/// The messages a room auto-translates: the 10 most recent incoming text
/// messages with content (outgoing, files, voice and system rows excluded).
List<Message> recentIncomingForTranslation(List<Message> messages, String? myId) {
  final incoming = messages
      .where((m) =>
          m.senderSnowchatId != myId &&
          m.type == MessageType.text &&
          m.plaintext.isNotEmpty)
      .toList();
  return incoming.length > 10 ? incoming.sublist(incoming.length - 10) : incoming;
}

/// Per-room translation cache Provider (autoDispose — memory released when leaving room).
///
/// Lifetime: the chat screen holds a subscription for as long as the room is
/// open, so the cache exists independently of how many message bubbles are
/// on screen. It drives its own work from the room's messages:
///  - on creation (room opened / reopened),
///  - when the message list changes (new incoming message),
///  - when the room's auto-translate switch or target language changes.
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

    bool autoTranslateOn() => ref
            .read(conversationListProvider)
            .where((c) => c.id == conversationId)
            .firstOrNull
            ?.autoTranslateEnabled ??
        false;

    final notifier = TranslationNotifier(translationService, resolveLang());

    void enqueueRecent() {
      if (!notifier.mounted || !autoTranslateOn()) return;
      final messages = ref.read(chatProvider(conversationId)).messages;
      final myId = ref.read(currentSnowIdProvider);
      for (final m in recentIncomingForTranslation(messages, myId)) {
        notifier.translate(m.id, m.plaintext);
      }
    }

    // New / changed messages in this room.
    ref.listen(chatProvider(conversationId).select((s) => s.messages),
        (_, __) => enqueueRecent());
    // Per-room switch or target change (and conversation-list refreshes).
    ref.listen(conversationListProvider, (_, __) {
      notifier.updateTarget(resolveLang());
      enqueueRecent();
    });
    // Global preferredLanguage change (only takes effect when room has no override).
    ref.listen(settingsProvider, (_, __) {
      notifier.updateTarget(resolveLang());
      enqueueRecent();
    });

    // Room opened: translate what is already there. Deferred so the notifier
    // is registered as this provider's value before its state changes.
    Future.microtask(enqueueRecent);

    return notifier;
  },
);
