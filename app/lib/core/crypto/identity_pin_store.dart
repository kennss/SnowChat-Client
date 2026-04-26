/// @file        identity_pin_store.dart
/// @description Vuln 2 (Stage A) — TOFU(Trust On First Use) pin store for
///              remote identity keys. Stores the Ed25519 identity key the
///              first time we successfully establish a session with a peer
///              and refuses subsequent sessions if that key changes.
///              Provides the basis for SignalProtocolService to fail-closed
///              and reject when MITM is suspected.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - IdentityPinStore: TOFU pin storage for remote Ed25519 identity keys
///  - getPinned(snowchatId): Returns the previously pinned key bytes, or null
///  - pin(snowchatId, ed25519Key): Stores the key on first establish
///  - unpin(snowchatId): Removes a pin (Stage B/C will expose UI for this)
library;

import 'dart:convert';
import 'dart:typed_data';

import '../storage/secure_storage.dart';

/// Stage A: minimal TOFU pin store.
///
/// Storage layout:
///   key:   `signal_identity_pin:{snowchatId}`
///   value: base64-encoded raw Ed25519 identity key bytes (32 bytes)
///
/// We use SecureStorageService so the value is protected by Keychain (iOS)
/// or Android Keystore-backed EncryptedSharedPreferences. The pin is per-
/// peer-snowchatId; multi-device migration (Stage B/C) will introduce a
/// per-device dimension if needed.
class IdentityPinStore {
  final SecureStorageService _secureStorage;

  static const String _keyPrefix = 'signal_identity_pin:';

  IdentityPinStore(this._secureStorage);

  String _keyFor(String snowchatId) => '$_keyPrefix$snowchatId';

  /// Returns the previously pinned Ed25519 identity key for [snowchatId],
  /// or null if no pin has been recorded yet.
  Future<Uint8List?> getPinned(String snowchatId) async {
    if (snowchatId.isEmpty) return null;
    final stored = await _secureStorage.read(_keyFor(snowchatId));
    if (stored == null || stored.isEmpty) return null;
    try {
      return base64Decode(stored);
    } catch (_) {
      // Corrupt entry — treat as unpinned. Caller will repin.
      return null;
    }
  }

  /// Pin [ed25519Key] (raw 32 bytes) as the canonical identity key for
  /// [snowchatId]. Idempotent for byte-identical inputs.
  Future<void> pin(String snowchatId, Uint8List ed25519Key) async {
    if (snowchatId.isEmpty) {
      throw ArgumentError('snowchatId must not be empty');
    }
    if (ed25519Key.isEmpty) {
      throw ArgumentError('ed25519Key must not be empty');
    }
    await _secureStorage.write(_keyFor(snowchatId), base64Encode(ed25519Key));
  }

  /// Remove a pin. Stage B/C will surface this from a re-verification UI.
  /// Stage A keeps it private (no public unpin path) by convention; callers
  /// that need to clear a pin (e.g. account wipe) may invoke it directly.
  Future<void> unpin(String snowchatId) async {
    if (snowchatId.isEmpty) return;
    await _secureStorage.delete(_keyFor(snowchatId));
  }
}
