/// @file        retry_handler.dart
/// @description Phase 10 P0-E — Sender-side retry request handler. When a recipient
///              fails to decrypt a message, they send a retry request. This handler
///              looks up the original plaintext in MessageSendLog, re-encrypts it
///              under the current (possibly fresh) session, and sends it back.
///              1:1 only (group protocol v2 has no retry — a member asks for
///              the missing key instead).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-12
/// @lastUpdated 2026-11-22 (SC-05: the answer is sealed — sendSealedRetry, with isRetry /
///              originalMessageId inside the payload; never a non-sealed private_message).
///              Earlier 2026-11-20 (v1 groups removed: no group retry request)
///
/// @functions
///  - RetryHandler: Sender-side retry response logic
///  - handleMessageRetryRequest(): Process 1:1 retry request from a recipient
///  - dispose(): Cancel socket event subscriptions

import 'dart:async';

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
///   4. Reset the session, re-encrypt, and send it SEALED ([SealedRetrySender]
///      — EncryptedMessageHandler.sendSealedRetry), with isRetry /
///      originalMessageId inside the payload
///   5. Recipient receives retry response → updates placeholder (P0-F)
///
/// Requests come only for non-sealed rows (the server refuses one for a
/// sealed row), and since 2026-11-22 this build sends none: what is left to
/// answer are rows it sent before the update, and the answer never names
/// the sender to the server (SC-05).
///
/// Security:
///   - Server enforces rate limits (5/min/device)
///   - Server validates requestNonce uniqueness (Redis SET + 5min TTL)
///   - We never log plaintext content in retry operations
/// Sends the sealed answer to a retry request; true when it was sent.
typedef SealedRetrySender = Future<bool> Function({
  required String recipientId,
  required Uint8List loggedPayload,
  required String originalMessageId,
});

class RetryHandler {
  final SignalSessionManager _sessionManager;
  final SocketManager _socketManager;
  final MessageSendLog _messageSendLog;
  final SealedRetrySender _sendSealedRetry;

  StreamSubscription<Map<String, dynamic>>? _messageRetrySub;

  /// Set of nonces we've already processed to prevent replay within session.
  final Set<String> _processedNonces = {};

  /// Maximum nonce cache size to prevent unbounded memory growth.
  static const int _maxNonceCache = 1000;

  RetryHandler({
    required SignalSessionManager sessionManager,
    required SocketManager socketManager,
    required MessageSendLog messageSendLog,
    required SealedRetrySender sendSealedRetry,
  })  : _sessionManager = sessionManager,
        _socketManager = socketManager,
        _messageSendLog = messageSendLog,
        _sendSealedRetry = sendSealedRetry;

  /// Start listening for retry requests from the socket.
  void start() {
    _messageRetrySub = _socketManager.onMessageRetryRequest
        .listen(handleMessageRetryRequest);
    debugPrint('[RetryHandler] started listening for retry requests');
  }

  /// Stop listening and release resources.
  void dispose() {
    _messageRetrySub?.cancel();
    _messageRetrySub = null;
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

      // Step 3: Re-encrypt under the fresh session and send it sealed, with
      // isRetry / originalMessageId inside the payload so the recipient
      // updates the placeholder instead of inserting a new message.
      final sent = await _sendSealedRetry(
        recipientId: requesterSnowchatId,
        loggedPayload: plaintext,
        originalMessageId: messageId,
      );
      debugPrint('[RetryHandler] 1:1 retry response for $messageId '
          '${sent ? 'SENT (sealed)' : 'NOT SENT (sealed path unavailable)'}');
    } catch (e) {
      debugPrint('[RetryHandler] 1:1 retry response FAILED for $messageId: '
          '${e.runtimeType}');
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
