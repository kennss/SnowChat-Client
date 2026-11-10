/// @file        database_key_manager.dart
/// @description At-rest protection level 1 — owns the 256-bit SQLCipher key of
///              the drift message database. The key is a random 32-byte value
///              (hex-encoded) stored in SecureStorageService under the app-global
///              flutter_secure_storage config: iOS Keychain class
///              AfterFirstUnlockThisDeviceOnly (readable by the VoIP / PushKit /
///              FCM / message-queue background paths once the device has been
///              unlocked once since boot, never part of a backup or a device
///              migration) and Android EncryptedSharedPreferences (Keystore).
///
///              Safety rules (see resolve()):
///               - "key absent" is only trusted after positive evidence that
///                 secure storage is readable right now (a known-present key
///                 reads back, or a probe value round-trips). On iOS a locked
///                 keychain (BFU) can surface as a plain `null` read, so a bare
///                 null is never taken as "absent".
///               - If storage is not readable: nothing is created and nothing is
///                 deleted; DatabaseKeyUnavailableException is thrown so the
///                 caller retries on a later query.
///               - Only the caller allowed to create (the main isolate) ever
///                 generates a key; creation is serialized inside the isolate
///                 and the stored value is re-read after the write, so every
///                 opener uses whatever is actually persisted.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-11
/// @lastUpdated 2026-11-11
///
/// @functions
///  - DatabaseKeyUnavailableException: storage unreadable / caller may not create
///  - DbKeyResolution: resolved hex key + whether it was created now
///  - DatabaseKeyManager.resolve(): read the key, or create it once when safe
///  - DatabaseKeyManager.deleteKey(): drop the key (only after the DB files)
///  - DatabaseKeyManager.isValidHexKey(): format check for a stored key
///
/// @notes
///  - keyName value is a 64-char lowercase hex string (32 bytes). It is
///    passed to SQLCipher as a raw key (`x'...'`), so no PBKDF2 runs at open.
///  - Key material is NEVER logged; log lines only carry outcomes.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../crypto/verified_identity_store.dart';
import 'secure_storage.dart';

/// Thrown when the database key cannot be resolved safely right now: secure
/// storage is not readable (iOS before first unlock / keychain error) or the
/// key is absent and this caller is not allowed to create one. Retryable —
/// nothing was created or deleted.
class DatabaseKeyUnavailableException implements Exception {
  final String reason;
  const DatabaseKeyUnavailableException(this.reason);

  @override
  String toString() => 'DatabaseKeyUnavailableException: $reason';
}

/// Result of [DatabaseKeyManager.resolve].
class DbKeyResolution {
  /// 64-char lowercase hex (32 bytes). Never log this.
  final String hexKey;

  /// True when this call generated and persisted the key (fresh database).
  final bool created;

  const DbKeyResolution(this.hexKey, {required this.created});
}

class DatabaseKeyManager {
  /// Secure-storage slot of the drift database key.
  static const String keyName = 'snowchat_db_key_v1';

  /// Scratch slot used only to prove that secure storage is readable when no
  /// known-present key exists yet (fresh install, pre-onboarding).
  static const String probeKeyName = 'snowchat_db_key_probe';

  static const int keyLengthBytes = 32;

  /// Per-isolate serialization: concurrent resolve() calls in one isolate
  /// share a single in-flight operation, so two keys can never be generated
  /// by racing openers in the same isolate.
  static Future<DbKeyResolution>? _inFlight;

  final SecureStorageService _storage;
  final Random _random;

  DatabaseKeyManager(this._storage, {Random? random})
      : _random = random ?? Random.secure();

  static bool isValidHexKey(String? v) =>
      v != null &&
      v.length == keyLengthBytes * 2 &&
      RegExp(r'^[0-9a-f]+$').hasMatch(v);

  /// Resolve the database key.
  ///
  /// [allowCreate]: only the main isolate passes true. Every other caller can
  /// only read an existing key — absent ⇒ [DatabaseKeyUnavailableException].
  ///
  /// [onBeforeCreate] runs after the key was confirmed absent on readable
  /// storage and before the new key is written — the caller deletes any
  /// database file left without a key there (legacy plaintext or orphaned
  /// ciphertext). It never runs when storage is unreadable.
  Future<DbKeyResolution> resolve({
    required bool allowCreate,
    required Future<void> Function() onBeforeCreate,
  }) {
    final pending = _inFlight;
    if (pending != null) return pending;
    final op = _resolve(allowCreate: allowCreate, onBeforeCreate: onBeforeCreate);
    _inFlight = op;
    // Clear the slot whatever the outcome so a later call re-reads storage
    // (e.g. after the keychain became readable).
    op.whenComplete(() {
      if (identical(_inFlight, op)) _inFlight = null;
    }).ignore();
    return op;
  }

  Future<DbKeyResolution> _resolve({
    required bool allowCreate,
    required Future<void> Function() onBeforeCreate,
  }) async {
    // 1. Fast path — the key is there.
    final first = await _readKeyOrThrow();
    if (first != null) return DbKeyResolution(_checked(first), created: false);

    // 2. A null read is ambiguous on iOS (a locked keychain can answer
    //    "not found"). Require positive evidence that storage is readable.
    if (!await _storageReadable()) {
      throw const DatabaseKeyUnavailableException(
          'secure storage not readable (locked / BFU) — key absence unproven');
    }

    // 3. Storage is readable: this read is authoritative.
    final second = await _readKeyOrThrow();
    if (second != null) return DbKeyResolution(_checked(second), created: false);

    if (!allowCreate) {
      throw const DatabaseKeyUnavailableException(
          'database key absent and this isolate may not create it');
    }

    // 4. Genuinely absent — clear whatever database is left without a key,
    //    then create the key.
    await onBeforeCreate();
    final generated = _generateHexKey();
    await _storage.write(keyName, generated);

    // 5. Re-read and use what is actually persisted. If another writer won a
    //    race, its value is adopted so every opener agrees on one key.
    final stored = await _readKeyOrThrow();
    if (stored == null) {
      throw const DatabaseKeyUnavailableException(
          'database key write did not persist');
    }
    final created = stored == generated;
    if (!created) {
      debugPrint('[DB-Key] concurrent key creation detected — adopting the '
          'persisted key');
    }
    return DbKeyResolution(_checked(stored), created: created);
  }

  /// Delete the key. Callers delete the database files FIRST, then the key
  /// (see deleteEncryptedDatabase), so a crash in between never leaves a
  /// populated database without its key.
  Future<void> deleteKey() => _storage.delete(keyName);

  Future<String?> _readKeyOrThrow() async {
    try {
      return await _storage.read(keyName);
    } catch (e) {
      // Platform error (iOS errSecInteractionNotAllowed, Android Keystore
      // failure, …). Never treated as "absent".
      throw DatabaseKeyUnavailableException(
          'secure storage read failed (${e.runtimeType})');
    }
  }

  String _checked(String v) {
    if (!isValidHexKey(v)) {
      // A malformed stored key can decrypt nothing. Refusing loudly beats
      // silently replacing it (which would orphan the existing database).
      throw StateError('[DB-Key] stored database key is malformed '
          '(length ${v.length}) — refusing to open the database');
    }
    return v;
  }

  /// Positive-evidence readability check (same idea as
  /// VerifiedIdentityStore's BFU guard): a key that exists on every onboarded
  /// install reads back, or — on a fresh install where nothing exists yet — a
  /// random probe value written now reads back identically. Any exception or
  /// mismatch ⇒ not readable.
  Future<bool> _storageReadable() async {
    try {
      final known = await _storage.read(VerifiedIdentityStore.unlockProbeKey);
      if (known != null && known.isNotEmpty) return true;
    } catch (_) {
      return false;
    }
    try {
      final nonce = _generateHexKey();
      await _storage.write(probeKeyName, nonce);
      final back = await _storage.read(probeKeyName);
      try {
        await _storage.delete(probeKeyName);
      } catch (_) {/* best-effort cleanup */}
      return back == nonce;
    } catch (_) {
      return false;
    }
  }

  String _generateHexKey() {
    final sb = StringBuffer();
    for (var i = 0; i < keyLengthBytes; i++) {
      sb.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Test hook: drop a dangling in-flight slot between tests.
  @visibleForTesting
  static void resetForTest() => _inFlight = null;
}
