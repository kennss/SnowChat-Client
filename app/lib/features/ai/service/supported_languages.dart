/// @file        supported_languages.dart
/// @description SnowChat supported translation languages. 9 languages stable on both iOS/Android.
///              iOS: Apple Translation API, Android: Google ML Kit (on-device NMT).
///              Both engines officially support the same 9 languages — no per-platform difference.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-19
/// @lastUpdated 2026-04-26 (header + inline English translation; supported translation languages)
///
/// @functions
///  - SupportedLanguages.all(): full list of supported languages
///  - SupportedLanguages.forPlatform(): languages usable on the current platform (iOS/Android identical)
///  - SupportedLanguages.resolveFromLocale(): device locale → preferredLanguage name
///  - SupportedLanguages.toLocaleCode(): preferredLanguage → BCP-47 locale code
///  - SupportedLanguages.nativeLabel(): preferredLanguage → native label
///  - SupportedLanguages.badgeChar(): translation icon badge character

class SupportedLanguage {
  /// Internal identifier. Canonical name stored in DB/settings.
  final String name;

  /// Native label shown to the user.
  final String nativeLabel;

  /// BCP-47 locale code (shared between Apple Translation / ML Kit).
  final String localeCode;

  /// ISO 639-1 language code (for device-locale matching).
  final String iso639;

  /// 1-2-character native badge overlaid on the translation icon.
  /// i18n-safe label used instead of a flag (Apple Translation app pattern).
  final String badgeChar;

  const SupportedLanguage({
    required this.name,
    required this.nativeLabel,
    required this.localeCode,
    required this.iso639,
    required this.badgeChar,
  });
}

class SupportedLanguages {
  SupportedLanguages._();

  /// 9 languages supported by SnowChat. Stable quality on both iOS and Android.
  static const List<SupportedLanguage> _all = [
    SupportedLanguage(
      name: 'English',
      nativeLabel: 'English',
      localeCode: 'en',
      iso639: 'en',
      badgeChar: 'A',
    ),
    SupportedLanguage(
      name: 'Korean',
      nativeLabel: '한국어',
      localeCode: 'ko',
      iso639: 'ko',
      badgeChar: '한',
    ),
    SupportedLanguage(
      name: 'Japanese',
      nativeLabel: '日本語',
      localeCode: 'ja',
      iso639: 'ja',
      badgeChar: 'あ',
    ),
    SupportedLanguage(
      name: 'Chinese',
      nativeLabel: '中文',
      localeCode: 'zh-Hans',
      iso639: 'zh',
      badgeChar: '中',
    ),
    SupportedLanguage(
      name: 'French',
      nativeLabel: 'Français',
      localeCode: 'fr',
      iso639: 'fr',
      badgeChar: 'Fr',
    ),
    SupportedLanguage(
      name: 'German',
      nativeLabel: 'Deutsch',
      localeCode: 'de',
      iso639: 'de',
      badgeChar: 'De',
    ),
    SupportedLanguage(
      name: 'Spanish',
      nativeLabel: 'Español',
      localeCode: 'es',
      iso639: 'es',
      badgeChar: 'Es',
    ),
    SupportedLanguage(
      name: 'Russian',
      nativeLabel: 'Русский',
      localeCode: 'ru',
      iso639: 'ru',
      badgeChar: 'Ру',
    ),
    SupportedLanguage(
      name: 'Arabic',
      nativeLabel: 'العربية',
      localeCode: 'ar',
      iso639: 'ar',
      badgeChar: 'ع',
    ),
  ];

  /// Languages selectable on the current platform.
  /// Returns all 9 on both iOS/Android (engine differences are absorbed).
  static List<SupportedLanguage> forPlatform() => _all;

  /// Full list of supported languages.
  static List<SupportedLanguage> all() => _all;

  /// Look up language by name. Returns null if missing.
  static SupportedLanguage? byName(String name) {
    for (final lang in _all) {
      if (lang.name == name) return lang;
    }
    return null;
  }

  /// Device locale → preferredLanguage name. Unsupported languages fall back to English.
  static String resolveFromLocale(String localeCode) {
    final primary = localeCode.split(RegExp(r'[_-]')).first.toLowerCase();
    for (final lang in _all) {
      if (lang.iso639 == primary) return lang.name;
    }
    return 'English';
  }

  /// preferredLanguage → BCP-47 locale code.
  static String toLocaleCode(String name) {
    return byName(name)?.localeCode ?? 'en';
  }

  /// preferredLanguage → native label.
  static String nativeLabel(String name) {
    return byName(name)?.nativeLabel ?? name;
  }

  /// preferredLanguage → translation icon badge character.
  static String badgeChar(String name) {
    return byName(name)?.badgeChar ?? 'A';
  }
}
