/// @file        language_detector.dart
/// @description Unicode-range-based language detection utility. Runs in pure Dart without AI calls.
///              Used for same-language skip decision during auto-translation.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header + inline English translation; Unicode-range language detection utility)
///
/// @functions
///  - LanguageDetector.detectLanguage(): detect dominant language of text
///  - LanguageDetector.isSameLanguage(): decide whether text matches the user's preferred language

class LanguageDetector {
  LanguageDetector._();

  /// Detect the dominant language of the text by Unicode script ratio.
  /// Returns: 'Korean', 'Japanese', 'Chinese', 'English', 'Spanish', 'French', etc.
  static String detectLanguage(String text) {
    if (text.isEmpty) return 'Unknown';

    int hangul = 0;
    int cjk = 0;
    int hiraganaKatakana = 0;
    int latin = 0;
    int cyrillic = 0;
    int arabic = 0;
    int total = 0;

    for (final rune in text.runes) {
      if (_isWhitespace(rune) || _isPunctuation(rune)) continue;
      total++;

      if (_isHangul(rune)) {
        hangul++;
      } else if (_isHiraganaKatakana(rune)) {
        hiraganaKatakana++;
      } else if (_isCJK(rune)) {
        cjk++;
      } else if (_isLatin(rune)) {
        latin++;
      } else if (_isCyrillic(rune)) {
        cyrillic++;
      } else if (_isArabic(rune)) {
        arabic++;
      }
    }

    if (total == 0) return 'Unknown';

    // Decide by majority script
    final scores = {
      'Korean': hangul,
      'Japanese': hiraganaKatakana,
      'Chinese': cjk,
      'Latin': latin,
      'Cyrillic': cyrillic,
      'Arabic': arabic,
    };

    final dominant = scores.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );

    if (dominant.value == 0) return 'Unknown';

    // Latin is mapped to English by default
    if (dominant.key == 'Latin') return 'English';
    if (dominant.key == 'Cyrillic') return 'Russian';
    if (dominant.key == 'Arabic') return 'Arabic';

    return dominant.key;
  }

  /// Decide whether the text matches the user's preferred language.
  static bool isSameLanguage(String text, String preferredLanguage) {
    final detected = detectLanguage(text);
    if (detected == 'Unknown') return false;

    // Direct match
    if (detected == preferredLanguage) return true;

    // Latin-script languages can't be distinguished by script alone —
    // English/Spanish/French are all Latin. If preferredLanguage is Latin-script,
    // we'd otherwise treat any Latin text as the same language.
    const latinLanguages = {'English', 'Spanish', 'French', 'German', 'Portuguese', 'Italian'};
    if (latinLanguages.contains(detected) && latinLanguages.contains(preferredLanguage)) {
      // Latin-script languages indistinguishable — proceed with translation (return false)
      return false;
    }

    return false;
  }

  // === Unicode range checks ===

  static bool _isHangul(int rune) =>
      (rune >= 0xAC00 && rune <= 0xD7AF) || // Hangul Syllables
      (rune >= 0x1100 && rune <= 0x11FF) || // Hangul Jamo
      (rune >= 0x3130 && rune <= 0x318F);   // Hangul Compatibility Jamo

  static bool _isHiraganaKatakana(int rune) =>
      (rune >= 0x3040 && rune <= 0x309F) || // Hiragana
      (rune >= 0x30A0 && rune <= 0x30FF) || // Katakana
      (rune >= 0x31F0 && rune <= 0x31FF);   // Katakana Phonetic Extensions

  static bool _isCJK(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||  // CJK Unified Ideographs
      (rune >= 0x3400 && rune <= 0x4DBF) ||  // CJK Extension A
      (rune >= 0x20000 && rune <= 0x2A6DF);  // CJK Extension B

  static bool _isLatin(int rune) =>
      (rune >= 0x0041 && rune <= 0x005A) || // A-Z
      (rune >= 0x0061 && rune <= 0x007A) || // a-z
      (rune >= 0x00C0 && rune <= 0x024F);   // Latin Extended (accented)

  static bool _isCyrillic(int rune) =>
      (rune >= 0x0400 && rune <= 0x04FF);

  static bool _isArabic(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF);

  static bool _isWhitespace(int rune) =>
      rune == 0x20 || rune == 0x0A || rune == 0x0D || rune == 0x09;

  static bool _isPunctuation(int rune) =>
      (rune >= 0x21 && rune <= 0x2F) ||
      (rune >= 0x3A && rune <= 0x40) ||
      (rune >= 0x5B && rune <= 0x60) ||
      (rune >= 0x7B && rune <= 0x7E) ||
      (rune >= 0x3000 && rune <= 0x303F);   // CJK Symbols and Punctuation
}
