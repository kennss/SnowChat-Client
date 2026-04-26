/// @file        retry_handler.dart
/// @description Phase 10 P0-E — Sender-side retry request handler. When a recipient
///              fails to decrypt a message, they send a retry request. This handler
///              looks up the original plaintext in MessageSendLog, re-encrypts it
///              under the current (possibly fresh) session, and sends it back.
///              Supports both 1:1 and group retry requests.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-12
/// @lastUpdated 2026-04-24
///
/// @functions
///  - RetryHandler: Sender-side retry response logic
///  - handleMessageRetryRequest(): Process 1:1 retry request from a recipient
///  - handleGroupMessageRetryRequest(): Process group retry request (re-sends as 1:1 pairwise)
///  - dispose(): Cancel socket event subscriptions

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../crypto/message_send_log.dart';
import '../crypto/signal_session_manager.dart';
import '../network/socket_manager.dart';

/// Handles incoming retry requests when THIS device is the original sender.
///
/// Flow (1:1):
///   1. Recipient fails to decrypt → emits `message_retry_request`
///   2. Server validates + relays to us
///   3. We look up plaintext in MessageSendLog
///   4. Re-encrypt under current session → send via `private_message`
///   5. Recipient receives retry response → updates placeholder (P0-F)
///
/// Flow (group):
///   1. Recipient fails to decrypt group Sender Key message
///   2. Server validates group membership + relays
///   3. We look up plaintext in MessageSendLog
///   4. Re-encrypt as 1:1 pairwise (NOT Sender Key — avoids SKDM dependency)
///   5. Recipient receives retry response → updates placeholder (P0-F)
///
/// Security:
///   - Server enforces rate limits (5/min/device for 1:1, 3/min/device/group)
///   - Server validates requestNonce uniqueness (Redis SET + 5min TTL)
///   - We never log plaintext content in retry operations
class RetryHandler {
  final SignalSessionManager _sessionManager;
  final SocketManager _socketManager;
  final MessageSendLog _messageSendLog;

  StreamSubscription<Map<String, dynamic>>? _messageRetrySub;
  StreamSubscription<Map<String, dynamic>>? _groupRetrySub;

  /// Set of nonces we've already processed to prevent replay within session.
  final Set<String> _processedNonces = {};

  /// Maximum nonce cache size to prevent unbounded memory growth.
  static const int _maxNonceCache = 1000;

  RetryHandler({
    required SignalSessionManager sessionManager,
    required SocketManager socketManager,
    required MessageSendLog messageSendLog,
  })  : _sessionManager = sessionManager,
        _socketManager = socketManager,
        _messageSendLog = messageSendLog;

  /// Start listening for retry requests from the socket.
  void start() {
    _messageRetrySub = _socketManager.onMessageRetryRequest
        .listen(handleMessageRetryRequest);
    _groupRetrySub = _socketManager.onGroupMessageRetryRequest
        .listen(handleGroupMessageRetryRequest);
    debugPrint('[RetryHandler] started listening for retry requests');
  }

  /// Stop listening and release resources.
  void dispose() {
    _messageRetrySub?.cancel();
    _groupRetrySub?.cancel();
    _messageRetrySub = null;
    _groupRetrySub = null;
  }

  /// Handle a 1:1 retry request from a recipient who failed to decrypt.
  ///
  /// The server has already validated:
  /// - JWT authentication
  /// - The requester is the actual recipient of the message
  /// - requestNonce is unique (not replayed)
  /// - Rate limit has not been exceeded
  Future<void> handleMessageRetryRequest(Map<String, dynamic> data) async {
    final messageId = data['messageId'] as String?;
    final requesterSnowchatId = data['requesterSnowchatId'] as String?;
    final requestNonce = data['requestNonce'] as String?;

    if (messageId == null || requesterSnowchatId == null) {
      debugPrint('[RetryHandler] 1:1 retry request missing required fields');
      return;
    }

    // Client-side nonce dedup (defense in depth — server already checks)
    if (requestNonce != null && !_checkAndRecordNonce(requestNonce)) {
      debugPrint('[RetryHandler] 1:1 retry REJECTED: duplicate nonce');
      return;
    }

    debugPrint('[RetryHandler] 1:1 retry request: msgId=$messageId '
        'requester=$requesterSnowchatId');

    // Step 1: Look up plaintext in MessageSendLog
    final plaintext = _messageSendLog.lookup(messageId);
    if (plaintext == null) {
      debugPrint('[RetryHandler] 1:1 retry SKIPPED: no log entry for '
          '$messageId (expired or not found)');
      return;
    }

    try {
      // Step 2: Force a session reset before re-encrypting.
      //
      // 2026-04-24 deadlock fix: the peer would not emit a retry request
      // unless its local session is broken. Re-encrypting under the
      // existing session reproduces the same broken ciphertext — both
      // sides loop forever because neither side ever archives the
      // diverged ratchet. Forcing archiveAndResetSession here guarantees
      // the next encrypt uses a fresh X3DH prekey bundle, which the peer
      // will bootstrap as a new inbound session on arrival.
      //
      // `force: true` bypasses the 5-min cooldown because the retry
      // request itself is proof the current session is unusable —
      // rate-limiting this path only extends the deadlock.
      await _sessionManager.archiveAndResetSession(
        requesterSnowchatId,
        force: true,
      );

      // Step 3: Re-encrypt for requester under the fresh session
      final deviceId =
          await _sessionManager.getDeviceIdForRecipient(requesterSnowchatId);
      final encrypted = await _sessionManager.encrypt(
        requesterSnowchatId,
        deviceId,
        plaintext,
      );

      // Step 4: Send via socket with isRetry metadata so the recipient
      // knows to update the placeholder instead of inserting a new message.
      _socketManager.sendPrivateMessage({
        'recipientId': requesterSnowchatId,
        'encryptedContent':
            base64Encode(encrypted['ciphertext'] as Uint8List),
        'messageType': encrypted['messageType'] as int,
        'type': 'e2ee_text',
        'clientMessageId': 'retry_$messageId',
        'metadata': jsonEncode({
          'isRetry': true,
          'originalMessageId': messageId,
        }),
      });

      debugPrint('[RetryHandler] 1:1 retry response SENT for $messageId '
          'to $requesterSnowchatId');
    } catch (e) {
      debugPrint('[RetryHandler] 1:1 retry response FAILED for $messageId: $e');
    }
  }

  /// Handle a group retry request from a recipient who failed to decrypt.
  ///
  /// Re-sends the message as a 1:1 pairwise fallback (NOT via Sender Key)
  /// because the recipient's Sender Key state may be corrupted or missing.
  Future<void> handleGroupMessageRetryRequest(
      Map<String, dynamic> data) async {
    final groupId = data['groupId'] as String?;
    final messageId = data['messageId'] as String?;
    final requesterSnowchatId = data['requesterSnowchatId'] as String?;
    final requestNonce = data['requestNonce'] as String?;

    if (groupId == null ||
        messageId == null ||
        requesterSnowchatId == null) {
      debugPrint('[RetryHandler] group retry request missing required fields');
      return;
    }

    // Client-side nonce dedup
    if (requestNonce != null && !_checkAndRecordNonce(requestNonce)) {
      debugPrint('[RetryHandler] group retry REJECTED: duplicate nonce');
      return;
    }

    debugPrint('[RetryHandler] group retry request: msgId=$messageId '
        'group=$groupId requester=$requesterSnowchatId');

    // Step 1: Look up plaintext in MessageSendLog
    final plaintext = _messageSendLog.lookup(messageId);
    if (plaintext == null) {
      debugPrint('[RetryHandler] group retry SKIPPED: no log entry for '
          '$messageId (expired or not found)');
      return;
    }

    try {
      // Step 2: Force session reset before re-encrypting (see 1:1 handler
      // above for full rationale — 2026-04-24 deadlock fix).
      await _sessionManager.archiveAndResetSession(
        requesterSnowchatId,
        force: true,
      );

      // Step 3: Re-encrypt as 1:1 pairwise (avoids SKDM dependency)
      final deviceId =
          await _sessionManager.getDeviceIdForRecipient(requesterSnowchatId);
      final encrypted = await _sessionManager.encrypt(
        requesterSnowchatId,
        deviceId,
        plaintext,
      );

      // Step 4: Send as 1:1 E2EE with retry metadata.
      // Include groupChatId so the server skips 1:1 conversation creation
      // and the receiver routes this to the group conversation, not 1:1.
      _socketManager.sendPrivateMessage({
        'recipientId': requesterSnowchatId,
        'encryptedContent':
            base64Encode(encrypted['ciphertext'] as Uint8List),
        'messageType': encrypted['messageType'] as int,
        'type': 'e2ee_text',
        'groupChatId': groupId,
        'clientMessageId': 'retry_${groupId}_$messageId',
        'metadata': jsonEncode({
          'isRetry': true,
          'originalMessageId': messageId,
          'groupId': groupId,
        }),
      });

      debugPrint('[RetryHandler] group retry response SENT for $messageId '
          '(group=$groupId) to $requesterSnowchatId');
    } catch (e) {
      debugPrint('[RetryHandler] group retry response FAILED for '
          '$messageId: $e');
    }
  }

  /// Check and record a nonce. Returns true if the nonce is new (not seen before).
  bool _checkAndRecordNonce(String nonce) {
    if (_processedNonces.contains(nonce)) return false;
    // Evict oldest entries if cache is full
    if (_processedNonces.length >= _maxNonceCache) {
      // Remove ~25% of entries (FIFO approximation via iterator)
      final toRemove = _processedNonces.take(_maxNonceCache ~/ 4).toList();
      _processedNonces.removeAll(toRemove);
    }
    _processedNonces.add(nonce);
    return true;
  }
}
