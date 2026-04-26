/// @file        session_store.dart
/// @description Local persistent store for E2EE sessions. Manages Double Ratchet session state per device
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - SessionStore: E2EE session persistent storage class
///  - SessionStore.initialize(): Load session state from DB
///  - SessionStore.getSession(): Look up session for a specific recipient/device
///  - SessionStore.saveSessionState(): Save session state after encrypt/decrypt
///  - SessionStore.deleteSession(): Delete a session
///  - SessionStore.getAllSessions(): Get the list of all sessions
///  - SessionStore.hasSession(): Check whether a session exists

import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';

import '../storage/database.dart';
import '../storage/secure_storage.dart';

/// Local persistence layer for E2EE session states.
///
/// Each session is keyed by (recipientSnowchatId, deviceId) and stores
/// the serialized Double Ratchet state. Session state is updated after
/// every encrypt/decrypt operation because the ratchet advances.
///
/// Storage strategy:
/// - Drift DB (SignalSessions table): serialized session binary blobs
/// - flutter_secure_storage: sensitive key material (identity keys, etc.)
///
/// The crypto agent provides the actual serialization via:
///   - x3dh.dart (session establishment)
///   - double_ratchet.dart (session state serialization/deserialization)
///
/// TODO: Import from crypto agent's files once available:
///   import 'x3dh.dart';
///   import 'double_ratchet.dart';
///   import 'prekey_bundle.dart';
class SessionStore {
  final SnowDatabase _db;
  final SecureStorageService _secureStorage;

  /// In-memory cache of active sessions for fast lookups.
  /// Key format: "recipientSnowId:deviceId"
  final Map<String, SessionEntry> _sessions = {};

  bool _initialized = false;

  SessionStore({
    required SnowDatabase database,
    required SecureStorageService secureStorage,
  })  : _db = database,
        _secureStorage = secureStorage;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  /// Load all persisted sessions from the Drift DB into memory.
  /// Called once during app startup by [SignalSessionManager.initialize].
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final rows = await _db.select(_db.signalSessions).get();

      for (final row in rows) {
        final key = row.recipientDeviceId; // format: "snowId:deviceId"
        _sessions[key] = SessionEntry(
          recipientDeviceId: key,
          sessionState: Uint8List.fromList(row.sessionState),
          updatedAt: row.updatedAt,
        );
      }

      _initialized = true;
      debugPrint(
          '[SessionStore] Loaded ${_sessions.length} sessions from DB');
    } catch (e) {
      debugPrint('[SessionStore] Failed to load sessions: $e');
      // Non-fatal: sessions can be re-established
      _initialized = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Session CRUD
  // ---------------------------------------------------------------------------

  /// Get the session entry for a specific recipient and device.
  /// Returns null if no session exists.
  Future<SessionEntry?> getSession(
    String recipientId,
    String deviceId,
  ) async {
    final key = _makeKey(recipientId, deviceId);
    return _sessions[key];
  }

  /// Check if a session exists for the given recipient and device.
  Future<bool> hasSession(String recipientId, String deviceId) async {
    return _sessions.containsKey(_makeKey(recipientId, deviceId));
  }

  /// Save (insert or update) session state after encrypt/decrypt.
  ///
  /// The actual session binary is obtained from the native Signal layer;
  /// this method persists it to the Drift DB so it survives app restarts.
  ///
  /// [sessionState] is optional -- if null, we store a marker entry
  /// indicating the session exists (the native layer holds the real state).
  Future<void> saveSessionState({
    required String recipientId,
    required String deviceId,
    Uint8List? sessionState,
  }) async {
    final key = _makeKey(recipientId, deviceId);
    final now = DateTime.now();

    // Use a placeholder if no binary state is provided
    // (the native Signal layer manages the actual state)
    final stateBytes = sessionState ?? Uint8List.fromList([0x01]);

    final entry = SessionEntry(
      recipientDeviceId: key,
      sessionState: stateBytes,
      updatedAt: now,
    );

    // Update in-memory cache
    _sessions[key] = entry;

    // Persist to Drift DB
    try {
      await _db.into(_db.signalSessions).insertOnConflictUpdate(
            SignalSessionsCompanion(
              recipientDeviceId: Value(key),
              sessionState: Value(stateBytes),
              updatedAt: Value(now),
            ),
          );
    } catch (e) {
      debugPrint('[SessionStore] Failed to persist session for $key: $e');
      // Non-fatal: the in-memory cache is still valid for this app run
    }
  }

  /// Delete a session for the given recipient and device.
  Future<void> deleteSession(String recipientId, String deviceId) async {
    final key = _makeKey(recipientId, deviceId);
    _sessions.remove(key);

    try {
      await (_db.delete(_db.signalSessions)
            ..where((t) => t.recipientDeviceId.equals(key)))
          .go();
    } catch (e) {
      debugPrint('[SessionStore] Failed to delete session for $key: $e');
    }
  }

  /// Delete all persisted sessions (used during full app reset).
  Future<void> deleteAll() async {
    _sessions.clear();
    try {
      await _db.delete(_db.signalSessions).go();
      debugPrint('[SessionStore] All sessions deleted from DB');
    } catch (e) {
      debugPrint('[SessionStore] Failed to delete all sessions: $e');
    }
  }

  /// Get all active session entries.
  List<SessionEntry> getAllSessions() {
    return _sessions.values.toList();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Build the composite key for a session: "recipientSnowId:deviceId"
  static String _makeKey(String recipientId, String deviceId) {
    return '$recipientId:$deviceId';
  }
}

/// Represents a persisted E2EE session entry.
class SessionEntry {
  /// Composite key: "recipientSnowId:deviceId"
  final String recipientDeviceId;

  /// Serialized Double Ratchet session state (binary blob).
  final Uint8List sessionState;

  /// When this session was last updated (after encrypt/decrypt).
  final DateTime updatedAt;

  const SessionEntry({
    required this.recipientDeviceId,
    required this.sessionState,
    required this.updatedAt,
  });

  /// Extract the recipient SnowChat ID from the composite key.
  String get recipientId => recipientDeviceId.split(':').first;

  /// Extract the device ID from the composite key.
  String get deviceId => recipientDeviceId.split(':').last;
}
