/// @file        secure_storage.dart
/// @description flutter_secure_storage wrapper. Secure storage backed by iOS Keychain / Android EncryptedSharedPreferences.
///              Phase E-2 v3.1: a small allowlist of keys (auth_token,
///              auth_refresh_token, device_id) is routed through the iOS-only
///              `snowchat/keychain_relaxed` MethodChannel so they're stored
///              under kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly. This
///              lets the native CallAcceptCoordinator read them in the
///              post-CallKit-accept window where the device may still be
///              locked at the WhenUnlocked level.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (the PIN API (storePin / getPin / verifyPin / hasPin, unsalted SHA-256) moved to
///              PasscodeStore — salted Argon2id; auto-lock delay and biometric lock persisted).
///              Earlier 2026-04-30 (Phase E-2 v3.1: relaxed-key routing for VoIP
///              accept fetch; auth_refresh_token added to allowlist so BFU
///              JWT refresh after expiry is unblocked)
///
/// @functions
///  - SecureStorageService: secure storage wrapper class
///  - SecureStorageService.read(): read value by key
///  - SecureStorageService.write(): write value by key
///  - SecureStorageService.delete(): delete value by key
///  - SecureStorageService.containsKey(): check whether a key exists
///  - SecureStorageService.deleteAll(): delete everything
///  - SecureStorageService.readAll(): read everything
///  - SecureStorageService.storeAutoLockSeconds() / getAutoLockSeconds(): app auto-lock delay
///  - SecureStorageService.storeBiometricLock() / getBiometricLock(): biometric unlock on/off
///    (the app passcode itself is core/security/passcode.dart — PasscodeStore)
///  - SecureStorageService.storeDisplayName(name): store nickname
///  - SecureStorageService.getDisplayName(): read nickname
///  - SecureStorageService.storePreferredLanguage(name): store translation target language
///  - SecureStorageService.getPreferredLanguage(): read stored translation target language

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper around flutter_secure_storage.
/// iOS: Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
/// Android: EncryptedSharedPreferences (Android Keystore backend)
class SecureStorageService {
  late final FlutterSecureStorage _storage;

  /// Phase E-2 v3.1 (N-Maj-1): keys we route to a *relaxed*
  /// (AfterFirstUnlockThisDeviceOnly) keychain class via the
  /// `snowchat/keychain_relaxed` MethodChannel on iOS. Required so
  /// CallAcceptCoordinator can read them from native code in the
  /// post-CallKit-accept window where the device may still be locked at
  /// the WhenUnlocked level.
  ///
  /// auth_refresh_token is in the allowlist (was missing in v2): without
  /// it, BFU after JWT 1h expiry would refresh-fail → silent re-login
  /// blocked → user stuck unable to receive calls until next foreground unlock.
  static const Set<String> _relaxedKeys = {
    // Phase 11 (2026-05-03): primary token slot. AfterFirstUnlock 필수 —
    // BG VoIP / lock 상태에서 TokenManager 가 hydrate / refresh 시 read.
    // 누락 시 device-locked 상태 첫 push 도착 시 silent token-fetch 실패.
    'auth_tokens_v2',
    // Legacy slots (kept for one-time migration in TokenManager.hydrateFromStorage).
    // Hydrate succeeds → bundled v2 envelope written + these deleted.
    // Keep relaxed accessibility until migration drains.
    'auth_token',
    'auth_refresh_token',
    'device_id',
  };

  static const MethodChannel _relaxedChannel =
      MethodChannel('snowchat/keychain_relaxed');

  /// Perf measurement: isolate the Keystore MasterKey unwrap cost that happens only on first access.
  bool _firstAccessLogged = false;

  SecureStorageService() {
    _storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
  }

  bool _isRelaxed(String key) =>
      Platform.isIOS && _relaxedKeys.contains(key);

  void _logFirstAccess(String op, int elapsed) {
    if (!_firstAccessLogged) {
      _firstAccessLogged = true;
      debugPrint('[Perf] 🔑 secure_storage FIRST ACCESS ($op): ${elapsed}ms '
          '(includes Keystore MasterKey unwrap)');
    }
  }

  Future<String?> read(String key) async {
    final sw = Stopwatch()..start();
    if (_isRelaxed(key)) {
      final result =
          await _relaxedChannel.invokeMethod<String?>('read', {'key': key});
      _logFirstAccess('read:$key(relaxed)', sw.elapsedMilliseconds);
      return result;
    }
    final result = await _storage.read(key: key);
    _logFirstAccess('read:$key', sw.elapsedMilliseconds);
    return result;
  }

  Future<void> write(String key, String value) async {
    final sw = Stopwatch()..start();
    if (_isRelaxed(key)) {
      await _relaxedChannel
          .invokeMethod<void>('write', {'key': key, 'value': value});
      _logFirstAccess('write:$key(relaxed)', sw.elapsedMilliseconds);
      return;
    }
    await _storage.write(key: key, value: value);
    _logFirstAccess('write:$key', sw.elapsedMilliseconds);
  }

  Future<void> delete(String key) async {
    if (_isRelaxed(key)) {
      await _relaxedChannel.invokeMethod<void>('delete', {'key': key});
      return;
    }
    await _storage.delete(key: key);
  }

  Future<bool> containsKey(String key) async {
    if (_isRelaxed(key)) {
      final v = await _relaxedChannel
          .invokeMethod<String?>('read', {'key': key});
      return v != null;
    }
    return _storage.containsKey(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
    if (Platform.isIOS) {
      // Phase E-2 v3.1: also wipe the relaxed channel entries (they live in
      // the same keychain service but are written through SecItemAdd with a
      // different accessibility, so they aren't in _storage's namespace cache).
      for (final key in _relaxedKeys) {
        try {
          await _relaxedChannel.invokeMethod<void>('delete', {'key': key});
        } catch (_) {/* best-effort */}
      }
    }
  }

  Future<Map<String, String>> readAll() async {
    return _storage.readAll();
  }

  // --- PIN management ---

  static const _displayNameKey = 'display_name';
  static const _preferredLanguageKey = 'preferred_lang';
  static const _callAlwaysRelayKey = 'call_always_relay';
  static const _callRequirePinKey = 'call_require_pin';
  static const _autoLockSecondsKey = 'app_auto_lock_seconds';
  static const _biometricLockKey = 'app_biometric_lock';

  /// Store display name (nickname).
  Future<void> storeDisplayName(String name) async {
    await write(_displayNameKey, name);
  }

  /// Get stored display name, or null if not set.
  Future<String?> getDisplayName() async {
    return read(_displayNameKey);
  }

  /// Store preferred translation target language (e.g. 'Korean', 'English').
  Future<void> storePreferredLanguage(String name) async {
    await write(_preferredLanguageKey, name);
  }

  /// Get stored preferred translation target language, or null if not set.
  Future<String?> getPreferredLanguage() async {
    return read(_preferredLanguageKey);
  }

  /// Phase F: Store "Always Relay" preference for VoIP calls. When true, the
  /// peer connection is forced through the TURN server (`iceTransportPolicy:
  /// relay`) — IP anonymization. Both sides are OR'd, so if either is true it goes relay.
  Future<void> storeCallAlwaysRelay(bool enabled) async {
    await write(_callAlwaysRelayKey, enabled ? 'true' : 'false');
  }

  /// Phase F: Get the stored "Always Relay" preference. Defaults to false
  /// (P2P preferred — lower latency, lower bandwidth on TURN).
  Future<bool> getCallAlwaysRelay() async {
    final stored = await read(_callAlwaysRelayKey);
    return stored == 'true';
  }

  /// Phase I (§25): whether to require PIN on call accept. default false (Signal/WhatsApp
  /// UX — CallKit Accept bypasses PIN and goes straight into the call). When set to true,
  /// the accept path is held until PIN is unlocked.
  Future<void> storeCallRequirePin(bool enabled) async {
    await write(_callRequirePinKey, enabled ? 'true' : 'false');
  }

  /// Phase I (§25): whether to require PIN on call accept. default false.
  Future<bool> getCallRequirePin() async {
    final stored = await read(_callRequirePinKey);
    return stored == 'true';
  }

  /// How long the app may stay in the background before it locks again
  /// (seconds; 0 = at once). Null when never set (the default applies).
  Future<void> storeAutoLockSeconds(int seconds) async {
    await write(_autoLockSecondsKey, '$seconds');
  }

  Future<int?> getAutoLockSeconds() async =>
      int.tryParse(await read(_autoLockSecondsKey) ?? '');

  /// Whether the lock screen offers Face ID / Touch ID / fingerprint first.
  Future<void> storeBiometricLock(bool enabled) async {
    await write(_biometricLockKey, enabled ? 'true' : 'false');
  }

  Future<bool> getBiometricLock() async =>
      await read(_biometricLockKey) == 'true';
}
