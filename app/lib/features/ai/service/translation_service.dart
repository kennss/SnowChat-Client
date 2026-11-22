/// @file        translation_service.dart
/// @description Per-platform translation service abstraction.
///              iOS: Apple Translation API (on-device, iOS 18+)
///              Android: Google ML Kit Translation + Language ID (on-device
///              NMT, requires Play Services) via the native TranslationBridge
///              (android/.../TranslationBridge.kt, channel
///              `snowchat/mlkit_translation`).
///              Both fully on-device — Zero-Knowledge preserved. Dart only
///              calls a platform channel; no ML Kit code lives in Dart, so the
///              iOS app links no ML Kit at all.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-11-11 (Android ML Kit moved behind a native MethodChannel;
///              google_mlkit_* Flutter plugins removed — they linked the
///              GoogleMLKit pods into iOS, which has no arm64-simulator slice).
///              Message text / translations are no longer logged (lengths only).
///              Earlier 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TranslationService.translate(): translate text (auto-branches per platform)
///  - TranslationService.isAvailable(): check whether translation is available
///  - TranslationService.dispose(): release the native ML Kit translators (Android)

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'supported_languages.dart';

/// iOS Apple Translation API channel
const _appleTranslationChannel = MethodChannel('com.snowchat/apple_translation');

/// Android ML Kit translation channel (TranslationBridge.kt).
const _mlkitTranslationChannel = MethodChannel('snowchat/mlkit_translation');

class TranslationService {
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

      // Never log message text — locale and length only.
      debugPrint('[TranslationService] Apple: ${text.length} chars (→$targetLocale)');

      final result = await _appleTranslationChannel.invokeMethod<String>('translate', {
        'text': text,
        'targetLang': targetLocale,
        if (detectedLang != null) 'sourceLang': detectedLang,
      });

      debugPrint('[TranslationService] Apple result: ${result?.length ?? 0} chars');
      return result?.trim() ?? '';
    } catch (e) {
      debugPrint('[TranslationService] Apple Translation failed: $e');
      return '';
    }
  }

  /// Android: Google ML Kit on-device NMT (native TranslationBridge).
  /// Source detection, the 9-language allowlist, same-language skip, the
  /// per-pair translator cache and model download all run natively. A null
  /// reply means there is nothing to translate.
  Future<String> _translateWithMLKit(String text, String preferredLanguage) async {
    try {
      final targetCode = SupportedLanguages.toLocaleCode(preferredLanguage);
      final result = await _mlkitTranslationChannel.invokeMethod<String>('translate', {
        'text': text,
        'targetLang': targetCode,
      });
      final translated = result?.trim() ?? '';
      // Length only — never the text.
      debugPrint('[TranslationService] ML Kit result: ${translated.length} chars (→$targetCode)');
      return translated;
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

  /// Call on app shutdown — release the native ML Kit translators and the
  /// language identifier (Android). iOS keeps no per-service native state.
  void dispose() {
    if (Platform.isAndroid) {
      _mlkitTranslationChannel.invokeMethod<void>('dispose').catchError((Object e) {
        debugPrint('[TranslationService] ML Kit dispose failed: $e');
      });
    }
  }
}
