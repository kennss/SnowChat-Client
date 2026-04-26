/// @file        translation_service.dart
/// @description Per-platform translation service abstraction.
///              iOS: Apple Translation API (on-device, iOS 18+)
///              Android: Google ML Kit Translation (on-device NMT, requires Play Services)
///              Both fully on-device — Zero-Knowledge preserved.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-26 (header + inline English translation; per-platform translation service abstraction)
///
/// @functions
///  - TranslationService.translate(): translate text (auto-branches per platform)
///  - TranslationService.isAvailable(): check whether translation is available
///  - TranslationService.dispose(): release ML Kit translator resources

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'supported_languages.dart';

/// iOS Apple Translation API channel
const _appleTranslationChannel = MethodChannel('com.snowchat/apple_translation');

class TranslationService {
  /// Android ML Kit per-language-pair translator cache.
  /// key: "${source}→${target}" (BCP-47), value: OnDeviceTranslator.
  final Map<String, OnDeviceTranslator> _mlkitCache = {};

  /// Android ML Kit language identifier (auto-detect source language).
  LanguageIdentifier? _langIdentifier;

  /// Cache of target-language models already downloaded (prevents re-download).
  final Set<String> _downloadedModels = {};

  TranslationService({dynamic aiService});

  /// Translate text. Branches per platform automatically.
  Future<String> translate(String text, String preferredLanguage) async {
    if (Platform.isIOS) {
      return _translateWithApple(text, preferredLanguage);
    } else {
      return _translateWithMLKit(text, preferredLanguage);
    }
  }

  /// Whether translation is available
  Future<bool> isAvailable() async {
    if (Platform.isIOS) {
      try {
        final result = await _appleTranslationChannel.invokeMethod<bool>('isAvailable');
        return result ?? false;
      } catch (e) {
        debugPrint('[TranslationService] Apple Translation not available: $e');
        return false;
      }
    } else {
      // Android: ML Kit works as long as Play Services is present (Galaxy/Google/Xiaomi global, etc.)
      return true;
    }
  }

  /// iOS: Apple Translation API
  Future<String> _translateWithApple(String text, String preferredLanguage) async {
    try {
      final targetLocale = SupportedLanguages.toLocaleCode(preferredLanguage);
      final detectedLang = SupportedLanguages.byName(
        _detectHeuristic(text),
      )?.localeCode;

      debugPrint('[TranslationService] Apple: "$text" (→$targetLocale)');

      final result = await _appleTranslationChannel.invokeMethod<String>('translate', {
        'text': text,
        'targetLang': targetLocale,
        if (detectedLang != null) 'sourceLang': detectedLang,
      });

      debugPrint('[TranslationService] Apple result: "$result"');
      return result?.trim() ?? '';
    } catch (e) {
      debugPrint('[TranslationService] Apple Translation failed: $e');
      return '';
    }
  }

  /// Android: Google ML Kit on-device NMT
  Future<String> _translateWithMLKit(String text, String preferredLanguage) async {
    try {
      final targetCode = SupportedLanguages.toLocaleCode(preferredLanguage);
      final targetLang = _bcpToMLKit(targetCode);
      if (targetLang == null) {
        debugPrint('[TranslationService] ML Kit: unsupported target $targetCode');
        return '';
      }

      // 1. Detect source language (ML Kit Language ID — supports 110+ languages)
      _langIdentifier ??= LanguageIdentifier(confidenceThreshold: 0.5);
      final sourceCode = await _langIdentifier!.identifyLanguage(text);
      if (sourceCode == 'und') {
        debugPrint('[TranslationService] ML Kit: source language undetermined');
        return '';
      }
      final sourceLang = _bcpToMLKit(sourceCode);
      if (sourceLang == null) {
        debugPrint('[TranslationService] ML Kit: unsupported source $sourceCode');
        return '';
      }

      // 2. Skip when source and target are the same language
      if (sourceLang == targetLang) {
        debugPrint('[TranslationService] ML Kit: same language skip ($sourceCode)');
        return '';
      }

      // 3. Look up translator cache or create + ensure model is downloaded
      final key = '${sourceLang.bcpCode}→${targetLang.bcpCode}';
      OnDeviceTranslator? translator = _mlkitCache[key];
      if (translator == null) {
        translator = OnDeviceTranslator(
          sourceLanguage: sourceLang,
          targetLanguage: targetLang,
        );
        _mlkitCache[key] = translator;

        // Model download (WiFi required if not cached — ~30MB per language pair)
        if (!_downloadedModels.contains(key)) {
          debugPrint('[TranslationService] ML Kit: downloading model $key');
          final manager = OnDeviceTranslatorModelManager();
          final srcDownloaded = await manager.downloadModel(
            sourceLang.bcpCode,
            isWifiRequired: false,
          );
          final tgtDownloaded = await manager.downloadModel(
            targetLang.bcpCode,
            isWifiRequired: false,
          );
          if (!srcDownloaded || !tgtDownloaded) {
            debugPrint('[TranslationService] ML Kit: model download failed');
            return '';
          }
          _downloadedModels.add(key);
        }
      }

      // 4. Run translation
      final translated = await translator.translateText(text);
      debugPrint('[TranslationService] ML Kit: "$text" → "$translated"');
      return translated.trim();
    } catch (e) {
      debugPrint('[TranslationService] ML Kit Translation failed: $e');
      return '';
    }
  }

  /// Simple iOS script detection (works without ML Kit).
  /// Apple Translation API also detects internally if source is omitted,
  /// but providing a hint improves session cache efficiency.
  String _detectHeuristic(String text) {
    for (final rune in text.runes) {
      if (rune >= 0xAC00 && rune <= 0xD7AF) return 'Korean';
      if ((rune >= 0x3040 && rune <= 0x309F) ||
          (rune >= 0x30A0 && rune <= 0x30FF)) return 'Japanese';
      if (rune >= 0x4E00 && rune <= 0x9FFF) return 'Chinese';
      if (rune >= 0x0400 && rune <= 0x04FF) return 'Russian';
      if (rune >= 0x0600 && rune <= 0x06FF) return 'Arabic';
    }
    return 'English'; // Latin script fallback
  }

  /// BCP-47 locale code → ML Kit TranslateLanguage enum.
  /// ML Kit supports 50+ languages, but only SnowChat's 9 are mapped here.
  TranslateLanguage? _bcpToMLKit(String code) {
    // Extract primary language code from 'zh-Hans', 'zh_CN', etc.
    final primary = code.split(RegExp(r'[_-]')).first.toLowerCase();
    switch (primary) {
      case 'en': return TranslateLanguage.english;
      case 'ko': return TranslateLanguage.korean;
      case 'ja': return TranslateLanguage.japanese;
      case 'zh': return TranslateLanguage.chinese;
      case 'fr': return TranslateLanguage.french;
      case 'de': return TranslateLanguage.german;
      case 'es': return TranslateLanguage.spanish;
      case 'ru': return TranslateLanguage.russian;
      case 'ar': return TranslateLanguage.arabic;
      default: return null;
    }
  }

  /// Call on app shutdown — release all ML Kit translators and the language identifier.
  void dispose() {
    for (final t in _mlkitCache.values) {
      t.close();
    }
    _mlkitCache.clear();
    _langIdentifier?.close();
    _langIdentifier = null;
  }
}
