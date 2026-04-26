/// @file        secure_storage.dart
/// @description flutter_secure_storage wrapper. Secure storage backed by iOS Keychain / Android EncryptedSharedPreferences.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-19)
///
/// @functions
///  - SecureStorageService: secure storage wrapper class
///  - SecureStorageService.read(): read value by key
///  - SecureStorageService.write(): write value by key
///  - SecureStorageService.delete(): delete value by key
///  - SecureStorageService.containsKey(): check whether a key exists
///  - SecureStorageService.deleteAll(): delete everything
///  - SecureStorageService.readAll(): read everything
///  - SecureStorageService.storePin(hashedPin): store hashed PIN
///  - SecureStorageService.getPin(): read stored PIN hash
///  - SecureStorageService.verifyPin(input): verify input PIN via hash comparison
///  - SecureStorageService.hasPin(): check whether a PIN is set
///  - SecureStorageService.storeDisplayName(name): store nickname
///  - SecureStorageService.getDisplayName(): read nickname
///  - SecureStorageService.storePreferredLanguage(name): store translation target language
///  - SecureStorageService.getPreferredLanguage(): read stored translation target language

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../crypto/hkdf.dart' show sha256;

/// Wrapper around flutter_secure_storage.
/// iOS: Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
/// Android: EncryptedSharedPreferences (Android Keystore backend)
class SecureStorageService {
  late final FlutterSecureStorage _storage;

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

  void _logFirstAccess(String op, int elapsed) {
    if (!_firstAccessLogged) {
      _firstAccessLogged = true;
      debugPrint('[Perf] 🔑 secure_storage FIRST ACCESS ($op): ${elapsed}ms '
          '(includes Keystore MasterKey unwrap)');
    }
  }

  Future<String?> read(String key) async {
    final _sw = Stopwatch()..start();
    final result = await _storage.read(key: key);
    _logFirstAccess('read:$key', _sw.elapsedMilliseconds);
    return result;
  }

  Future<void> write(String key, String value) async {
    final _sw = Stopwatch()..start();
    await _storage.write(key: key, value: value);
    _logFirstAccess('write:$key', _sw.elapsedMilliseconds);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<bool> containsKey(String key) async {
    return _storage.containsKey(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  Future<Map<String, String>> readAll() async {
    return _storage.readAll();
  }

  // --- PIN management ---

  static const _pinHashKey = 'pin_hash';
  static const _displayNameKey = 'display_name';
  static const _preferredLanguageKey = 'preferred_lang';
  static const _callAlwaysRelayKey = 'call_always_relay';
  static const _callRequirePinKey = 'call_require_pin';

  /// Hash a raw PIN string with SHA-256. Returns hex-encoded hash.
  /// Never stores or logs the raw PIN.
  String _hashPin(String rawPin) {
    final bytes = Uint8List.fromList(utf8.encode(rawPin));
    final hash = sha256(bytes);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Store a PIN as a SHA-256 hash. The raw PIN is never persisted.
  Future<void> storePin(String rawPin) async {
    final hashed = _hashPin(rawPin);
    await write(_pinHashKey, hashed);
  }

  /// Get the stored PIN hash, or null if no PIN is set.
  Future<String?> getPin() async {
    return read(_pinHashKey);
  }

  /// Verify a PIN input against the stored hash.
  /// Returns true if the input matches, false otherwise.
  Future<bool> verifyPin(String input) async {
    final storedHash = await getPin();
    if (storedHash == null) return false;
    final inputHash = _hashPin(input);
    return storedHash == inputHash;
  }

  /// Check whether a PIN has been set.
  Future<bool> hasPin() async {
    return containsKey(_pinHashKey);
  }

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
}
