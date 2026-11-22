/// @file        message_send_log.dart
/// @description Outgoing message log for retransmission — stores recent 1:1 message plaintexts (encrypted at rest) to respond to retry requests on decrypt failure
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-04
/// @lastUpdated 2026-11-20 (1:1 only — v1 groups removed: no isGroup flag, no legacy groupId field on load). Earlier 2026-04-26 (header English translation; Phase 10 P0-A: API redesign — conversationId+isGroup, maxAge 24h, maxEntries 500, 1:1 support)
///
/// @functions
///  - MessageSendLog: Outgoing message log (LRU, encrypted, TTL)
///  - record(): Record a sent 1:1 message
///  - lookup(): Look up a message
///  - conversationIdFor(): Get the conversationId for a message
///  - toJson(): Serialize for persistence
///  - fromJson(): Restore persisted state

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Stores recently sent message plaintexts for retry requests.
///
/// When a recipient fails to decrypt a 1:1 message, they send a
/// retry request back to the original sender. The sender looks up the
/// plaintext in this log and re-sends it via 1:1 E2EE.
///
/// Security:
/// - Entries are stored as raw bytes (encrypted at rest via session store SecretBox)
/// - LRU eviction with max [maxEntries] and [maxAge] TTL
/// - The entire log is persisted inside the session store, which is
///   encrypted with HKDF-derived key from the device's identity private key
class MessageSendLog {
  static const int maxEntries = 500;
  static const Duration maxAge = Duration(hours: 24);

  /// LRU map: messageId -> _LogEntry (insertion order preserved)
  final LinkedHashMap<String, _LogEntry> _log;

  MessageSendLog() : _log = LinkedHashMap<String, _LogEntry>();
  MessageSendLog._(this._log);

  /// Record a sent message for potential retry.
  ///
  /// [conversationId] is the 1:1 conversation of the message.
  void record(
    String messageId,
    Uint8List plaintext, {
    required String conversationId,
  }) {
    // LRU eviction
    if (_log.length >= maxEntries) {
      _log.remove(_log.keys.first); // Remove oldest (LRU)
    }
    _log[messageId] = _LogEntry(
      plaintext: plaintext,
      conversationId: conversationId,
      timestamp: DateTime.now(),
    );
  }

  /// Look up a previously sent message by ID.
  /// Returns null if not found or expired.
  Uint8List? lookup(String messageId) {
    final entry = _log[messageId];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > maxAge) {
      _log.remove(messageId);
      return null;
    }
    return entry.plaintext;
  }

  /// Register a secondary lookup key for an existing entry. Used when the
  /// server assigns a different `messageId` (e.g. `cmod...`) than the
  /// client's locally-generated one (`msg_TS_HASH`). Retry requests arrive
  /// with the server's id, so without this alias `lookup()` returns null
  /// and the retry handler silently SKIPs, blocking the force-reset path
  /// that fixes the broken session.
  ///
  /// 2026-04-24 E2EE deadlock fix: before this method existed, retry
  /// requests from peers could not be fulfilled for messages whose server
  /// id differed from the client id — every message in our pipeline, as
  /// it turns out. Galaxy ↔ emulator-5554 deadlocks were a direct symptom.
  void addAlias(String primaryId, String aliasId) {
    if (primaryId == aliasId) return;
    final entry = _log[primaryId];
    if (entry == null) return;
    _log[aliasId] = entry;
  }

  /// Get the conversationId for a logged message.
  String? conversationIdFor(String messageId) {
    return _log[messageId]?.conversationId;
  }

  /// Serialize for session store persistence.
  Map<String, dynamic> toJson() {
    _prune(); // Clean expired before saving
    final result = <String, dynamic>{};
    for (final entry in _log.entries) {
      result[entry.key] = {
        'plaintext': base64Encode(entry.value.plaintext),
        'conversationId': entry.value.conversationId,
        'timestamp': entry.value.timestamp.millisecondsSinceEpoch,
      };
    }
    return result;
  }

  /// Restore from session store.
  factory MessageSendLog.fromJson(Map<String, dynamic> json) {
    final LinkedHashMap<String, _LogEntry> log = LinkedHashMap();
    for (final entry in json.entries) {
      final data = entry.value as Map<String, dynamic>;
      final timestamp = DateTime.fromMillisecondsSinceEpoch(
          data['timestamp'] as int);
      // Skip expired entries on load
      if (DateTime.now().difference(timestamp) <= maxAge) {
        log[entry.key] = _LogEntry(
          plaintext: base64Decode(data['plaintext'] as String),
          conversationId: data['conversationId'] as String,
          timestamp: timestamp,
        );
      }
    }
    return MessageSendLog._(log);
  }

  /// Remove expired entries.
  void _prune() {
    final now = DateTime.now();
    _log.removeWhere((_, entry) => now.difference(entry.timestamp) > maxAge);
  }
}

class _LogEntry {
  final Uint8List plaintext;
  final String conversationId;
  final DateTime timestamp;

  _LogEntry({
    required this.plaintext,
    required this.conversationId,
    required this.timestamp,
  });
}
