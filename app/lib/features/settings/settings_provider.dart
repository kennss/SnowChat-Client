/// @file        settings_provider.dart
/// @description Settings state-management Provider — notifications, biometric, read receipts, typing, link previews, disappearing messages, translation language.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; Phase I §25: callRequirePin toggle added)
///
/// @functions
///  - SettingsState: settings-state data class
///  - SettingsNotifier: StateNotifier managing settings state
///  - settingsProvider: StateNotifierProvider exposing settings state
///  - setNotifications(): notifications setting
///  - setBiometricLock(): biometric-lock setting
///  - setReadReceipts(): read-receipts setting
///  - setTypingIndicators(): typing-indicator setting
///  - setLinkPreviews(): link-preview setting
///  - setDisappearingMessages(): disappearing-messages TTL setting
///  - setPreferredLanguage(): translation target-language setting (persisted to secure_storage)
///  - setCallAlwaysRelay(): VoIP call IP anonymization — force TURN relay (persisted)
///  - setCallRequirePin(): require PIN on call accept — default false (Signal UX)

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/storage/secure_storage.dart';
import '../ai/service/supported_languages.dart';

class SettingsState {
  final bool notificationsEnabled;
  final bool biometricLockEnabled;
  final bool readReceipts;
  final bool typingIndicators;
  final bool linkPreviews;
  final int? disappearingMessagesTtl; // seconds, null = off
  final String preferredLanguage; // AI auto-translate target language
  final bool callAlwaysRelay; // Phase F: VoIP IP anonymization (force TURN relay)
  /// Phase I (§25): whether to require PIN on call accept.
  /// default false — Signal/WhatsApp-style UX (CallKit Accept → straight to call).
  /// If set true, the accept path is held after CallKit Accept until PIN
  /// unlock + auto-resume right after PIN unlock.
  final bool callRequirePin;

  const SettingsState({
    this.notificationsEnabled = true,
    this.biometricLockEnabled = false,
    this.readReceipts = true,
    this.typingIndicators = true,
    this.linkPreviews = false,
    this.disappearingMessagesTtl,
    required this.preferredLanguage,
    this.callAlwaysRelay = false,
    this.callRequirePin = false,
  });

  SettingsState copyWith({
    bool? notificationsEnabled,
    bool? biometricLockEnabled,
    bool? readReceipts,
    bool? typingIndicators,
    bool? linkPreviews,
    int? disappearingMessagesTtl,
    String? preferredLanguage,
    bool? callAlwaysRelay,
    bool? callRequirePin,
  }) {
    return SettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      biometricLockEnabled: biometricLockEnabled ?? this.biometricLockEnabled,
      readReceipts: readReceipts ?? this.readReceipts,
      typingIndicators: typingIndicators ?? this.typingIndicators,
      linkPreviews: linkPreviews ?? this.linkPreviews,
      disappearingMessagesTtl:
          disappearingMessagesTtl ?? this.disappearingMessagesTtl,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      callAlwaysRelay: callAlwaysRelay ?? this.callAlwaysRelay,
      callRequirePin: callRequirePin ?? this.callRequirePin,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SecureStorageService _storage;

  SettingsNotifier(this._storage)
      : super(SettingsState(preferredLanguage: _initialLanguage())) {
    _loadPersistedLanguage();
    _loadCallAlwaysRelay();
    _loadCallRequirePin();
  }

  /// Initial language from device locale. Falls back to English for unsupported locales.
  static String _initialLanguage() {
    final locale = PlatformDispatcher.instance.locale.toLanguageTag();
    return SupportedLanguages.resolveFromLocale(locale);
  }

  /// Load persisted language at app startup — keeps device locale if none saved.
  Future<void> _loadPersistedLanguage() async {
    final stored = await _storage.getPreferredLanguage();
    if (stored == null) return;
    // Ignore if the saved language isn't supported on the current platform (e.g. iOS→Android switch)
    final supported = SupportedLanguages.forPlatform();
    if (!supported.any((l) => l.name == stored)) return;
    if (!mounted) return;
    state = state.copyWith(preferredLanguage: stored);
  }

  void setNotifications(bool value) {
    state = state.copyWith(notificationsEnabled: value);
  }

  void setBiometricLock(bool value) {
    state = state.copyWith(biometricLockEnabled: value);
  }

  void setReadReceipts(bool value) {
    state = state.copyWith(readReceipts: value);
  }

  void setTypingIndicators(bool value) {
    state = state.copyWith(typingIndicators: value);
  }

  void setLinkPreviews(bool value) {
    state = state.copyWith(linkPreviews: value);
  }

  void setDisappearingMessages(int? ttlSeconds) {
    state = state.copyWith(disappearingMessagesTtl: ttlSeconds);
  }

  Future<void> setPreferredLanguage(String lang) async {
    state = state.copyWith(preferredLanguage: lang);
    await _storage.storePreferredLanguage(lang);
  }

  /// Phase F: VoIP "Always Relay" toggle. Stores only own preference —
  /// at call time both sides are OR'd, so either side being true forces
  /// relay (call_service.dart:196). Default false (prefer P2P, low
  /// latency + zero TURN load).
  Future<void> setCallAlwaysRelay(bool enabled) async {
    state = state.copyWith(callAlwaysRelay: enabled);
    await _storage.storeCallAlwaysRelay(enabled);
  }

  /// Load persisted callAlwaysRelay at app startup. Keeps default false if none saved.
  Future<void> _loadCallAlwaysRelay() async {
    final stored = await _storage.getCallAlwaysRelay();
    if (!mounted) return;
    if (stored != state.callAlwaysRelay) {
      state = state.copyWith(callAlwaysRelay: stored);
    }
  }

  /// Phase I (§25): require-PIN-on-call-accept toggle. Persisted immediately.
  /// default false — Signal/WhatsApp style (CallKit Accept → straight to call).
  Future<void> setCallRequirePin(bool enabled) async {
    state = state.copyWith(callRequirePin: enabled);
    await _storage.storeCallRequirePin(enabled);
  }

  /// Load persisted callRequirePin at app startup. Keeps default false if none saved.
  Future<void> _loadCallRequirePin() async {
    final stored = await _storage.getCallRequirePin();
    if (!mounted) return;
    if (stored != state.callRequirePin) {
      state = state.copyWith(callRequirePin: stored);
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.read(secureStorageProvider));
});
