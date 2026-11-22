/// @file        settings_provider.dart
/// @description Settings state-management Provider — notifications, biometric, read receipts, typing, link previews, disappearing messages, translation language.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-23 (callShowCallerName — system call screens show the caller's name,
///              default on; callShowCallerNameForCall() is what call code reads: it waits for the
///              stored value and answers false while that value cannot be read).
///              Earlier 2026-11-22 (autoLockSeconds — lock again after the app was in the background that long,
///              default 1 min; biometricLockEnabled is persisted — it was lost on restart).
///              Earlier 2026-04-26 (header + inline English translation; Phase I §25: callRequirePin toggle added)
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
///  - setAutoLockSeconds(): auto-lock delay after the app goes to the background (default 60 s)
///  - setBiometricLock(): biometric unlock (now persisted)
///  - setCallShowCallerName(): caller name on system call screens (persisted, default on)
///  - callShowCallerNameForCall(): the stored value for a call — false while it cannot be read

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

  /// How long the app may stay in the background before it locks again,
  /// in seconds (0 = at once). Cold start always locks.
  final int autoLockSeconds;

  /// Whether the system call screens (iOS CallKit, Android incoming call
  /// notification and screen) show the name this device knows for the other
  /// party. Off: "SnowChat Call" only. The name never comes from the server.
  /// Default on (Signal-like). In-app call screens always show the name.
  final bool callShowCallerName;

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
    this.autoLockSeconds = kDefaultAutoLockSeconds,
    this.callShowCallerName = true,
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
    int? autoLockSeconds,
    bool? callShowCallerName,
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
      autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      callShowCallerName: callShowCallerName ?? this.callShowCallerName,
    );
  }
}

/// Auto-lock default: one minute in the background (design decision
/// 2026-11-22 — a messenger opened often, still locked when left).
const int kDefaultAutoLockSeconds = 60;

/// Auto-lock choices offered in settings (seconds): at once, 1, 5, 15, 60 min.
const List<int> kAutoLockChoices = [0, 60, 300, 900, 3600];

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SecureStorageService _storage;

  SettingsNotifier(this._storage)
      : super(SettingsState(preferredLanguage: _initialLanguage())) {
    _loadPersistedLanguage();
    _loadCallAlwaysRelay();
    _loadCallRequirePin();
    _loadLock();
    _loadCallShowCallerName();
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

  /// Face ID / Touch ID / fingerprint first on the lock screen. Persisted
  /// (it used to be forgotten on restart).
  Future<void> setBiometricLock(bool value) async {
    state = state.copyWith(biometricLockEnabled: value);
    await _storage.storeBiometricLock(value);
  }

  /// Auto-lock delay ([kAutoLockChoices]).
  Future<void> setAutoLockSeconds(int seconds) async {
    state = state.copyWith(autoLockSeconds: seconds);
    await _storage.storeAutoLockSeconds(seconds);
  }

  Future<void> _loadLock() async {
    final biometric = await _storage.getBiometricLock();
    final autoLock = await _storage.getAutoLockSeconds();
    if (!mounted) return;
    state = state.copyWith(
      biometricLockEnabled: biometric,
      autoLockSeconds: autoLock,
    );
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

  /// True once [SettingsState.callShowCallerName] holds the stored value (or
  /// one the user set) rather than the default.
  bool _callShowCallerNameKnown = false;

  /// "Show caller name on calls" toggle. Persisted immediately.
  Future<void> setCallShowCallerName(bool enabled) async {
    _callShowCallerNameKnown = true;
    state = state.copyWith(callShowCallerName: enabled);
    await _storage.storeCallShowCallerName(enabled);
  }

  /// Whether this call's system UI may show the caller's name. Waits for the
  /// stored value — a call can cold-start the app before the startup load
  /// finished, and the default (on) must not stand in for a stored "off".
  /// While the store cannot be read (device locked since boot) the answer is
  /// false: the system UI stays "SnowChat Call". The next call reads again.
  Future<bool> callShowCallerNameForCall() async {
    if (!_callShowCallerNameKnown) await _loadCallShowCallerName();
    return _callShowCallerNameKnown && state.callShowCallerName;
  }

  /// Load the persisted callShowCallerName. Absent = on. A read error leaves
  /// the value unknown (see [callShowCallerNameForCall]).
  Future<void> _loadCallShowCallerName() async {
    final bool stored;
    try {
      stored = await _storage.getCallShowCallerName();
    } catch (_) {
      return;
    }
    if (!mounted || _callShowCallerNameKnown) return;
    _callShowCallerNameKnown = true;
    if (stored != state.callShowCallerName) {
      state = state.copyWith(callShowCallerName: stored);
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.read(secureStorageProvider));
});
