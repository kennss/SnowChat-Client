/// @file        global_message_router.dart
/// @description Phase 6 — Subscribes to all incoming socket envelopes and forwards
///              them to the MessageQueue for serial processing, answers the server's
///              prekey requests and triggers the initial fetch.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-11-22 (no message_deleted handler: the server sends no such event any more — its
///              unsend route is gone; a peer's delete-for-everyone is the sealed unsend control the
///              message queue applies — so the router takes no message / attachment DAO or ref).
///              Earlier 2026-11-22 (no RetryHandler: the server relays no retry requests any more — Part 3 E;
///              nothing on this device asks for a message again or answers such a request). Earlier 2026-11-22 (RetryHandler answers sealed, through EncryptedMessageHandler.sendSealedRetry
///              — SC-05). Earlier 2026-11-21 (description: no SKDM requests since v1 groups are gone). Earlier 2026-11-20 (v1 groups removed: no sender_key_request answer, no group_messages_cleared handler. message_deleted — the one place a remote unsend is applied — removes only a peer's own message in the 1:1 room with that peer (the row's sender is its room), so never this account's message and never a group's; it also cancels the message's expiry timer). Earlier 2026-11-10 (B-2 §5.7: IdentityBindingInvalidException / IdentityKeyChangedException handled as terminal — logged once, never retried). Earlier 2026-08-06 (_handleMessageDeleted now resolves the owning conversationId before deleting the row and calls ConversationListNotifier.refreshPreviewAfterDelete() afterward, so a group/non-sealed delete-for-everyone of the last message doesn't leave the removed text lingering in the Chats-list preview). Earlier 2026-04-26 (header + inline English translation; Vuln 2 Stage B: force_prekey_upload listener → uploadPreKeys)
///
/// @functions
///  - GlobalMessageRouter: Bridges SocketManager streams → MessageQueue
///  - start(): Subscribe to socket events and trigger initial fetch
///  - stop(): Cancel all subscriptions
///  - _handleIncomingEnvelope(): Forward envelope to MessageQueue
///  - _handleConnectionChange(): Re-fetch pending messages on reconnect + prekey replenishment (P1-B)
///  - _handlePrekeysLow(): Server notified prekeys are depleted — trigger immediate replenishment (P1-B)
///  - _handleForcePrekeyUpload(): Vuln 2 Stage B — server requests Ed25519 verify key re-upload

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../crypto/signal_session_manager.dart';
import '../network/socket_manager.dart';
import 'message_queue.dart';

class GlobalMessageRouter {
  final SocketManager _socketManager;
  final MessageQueue _queue;
  final SignalSessionManager _sessionMgr;

  StreamSubscription<Map<String, dynamic>>? _envelopeSub;
  StreamSubscription<bool>? _connectionSub;

  /// Phase 10 P1-B: Server emits `prekeys_low` when one-time prekeys are
  /// nearly exhausted. We listen here and trigger immediate replenishment.
  StreamSubscription<void>? _prekeysLowSub;

  /// Vuln 2 Stage B: server emits `force_prekey_upload` when our device row
  /// is missing identityKeyEd25519 (legacy registration before Phase 5).
  /// Trigger uploadPreKeys() so the server gets the verify key.
  StreamSubscription<Map<String, dynamic>>? _forcePrekeyUploadSub;

  bool _started = false;

  GlobalMessageRouter({
    required SocketManager socketManager,
    required MessageQueue queue,
    required SignalSessionManager sessionManager,
  })  : _socketManager = socketManager,
        _queue = queue,
        _sessionMgr = sessionManager;

  /// Begin routing. Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    _envelopeSub = _socketManager.onIncomingEnvelope.listen(_handleIncomingEnvelope);
    _connectionSub = _socketManager.onConnectionChange.listen(_handleConnectionChange);

    // Phase 10 P1-B: Replenish prekeys when server signals low count.
    _prekeysLowSub = _socketManager.onPrekeysLow.listen((_) => _handlePrekeysLow());

    // Vuln 2 Stage B: server requested Ed25519 re-upload (missing on a device).
    _forcePrekeyUploadSub =
        _socketManager.onForcePrekeyUpload.listen(_handleForcePrekeyUpload);

    debugPrint('[GlobalMessageRouter] started');

    // If we are already connected at startup, kick off an initial fetch.
    if (_socketManager.isConnected) {
      _queue.fetchPending();
    }
  }

  /// Stop routing.
  void stop() {
    _envelopeSub?.cancel();
    _connectionSub?.cancel();
    _prekeysLowSub?.cancel();
    _forcePrekeyUploadSub?.cancel();
    _envelopeSub = null;
    _connectionSub = null;
    _prekeysLowSub = null;
    _forcePrekeyUploadSub = null;
    _started = false;
  }

  // ---------------------------------------------------------------------------
  // Handlers
  // ---------------------------------------------------------------------------

  void _handleIncomingEnvelope(Map<String, dynamic> envelope) {
    // [DIAG] Bug 1/2 diagnostic: trace whether GlobalMessageRouter listener fired and forwarding to the queue
    final id = envelope['id'] ?? envelope['messageId'];
    final type = envelope['type'] ?? 'unknown';
    debugPrint('[DIAG:Router] forwarding to MessageQueue: id=$id type=$type');
    _queue.enqueue(envelope);
  }

  void _handleConnectionChange(bool connected) {
    if (connected) {
      debugPrint('[DIAG:Router] socket reconnected, triggering fetchPending + prekey check');
      _queue.fetchPending();

      // Phase 10 P1-B (Mechanism 5): Replenish prekeys on every reconnect.
      // Signal checks prekey count on every socket connect to prevent
      // prekey exhaustion during offline periods.
      _sessionMgr.checkPreKeyCount().catchError((e) {
        debugPrint('[GlobalMessageRouter] prekey check on reconnect failed: $e');
      });
    } else {
      debugPrint('[DIAG:Router] socket disconnected');
    }
  }

  /// Phase 10 P1-B (Mechanism 5): Server emitted `prekeys_low` — a recipient
  /// consumed one of our one-time prekeys and the remaining count dropped
  /// below threshold. Trigger immediate prekey generation and upload.
  void _handlePrekeysLow() {
    debugPrint('[GlobalMessageRouter] prekeys_low event — triggering replenishment');
    _sessionMgr.checkPreKeyCount().catchError((e) {
      debugPrint('[GlobalMessageRouter] prekey replenishment failed: $e');
    });
  }

  /// Vuln 2 Stage B — server-side `KeyDistributionService.fetchPreKeyBundle`
  /// found a device row missing identityKeyEd25519 and asked us to re-upload.
  /// `uploadPreKeys()` is in-flight-guarded so duplicate emits collapse to a
  /// single network roundtrip; safe to invoke unconditionally on every event.
  void _handleForcePrekeyUpload(Map<String, dynamic> data) {
    final reason = data['reason'] as String? ?? 'unknown';
    debugPrint('[GlobalMessageRouter] force_prekey_upload received '
        '(reason=$reason) — triggering uploadPreKeys');
    _sessionMgr.uploadPreKeys().catchError((e) {
      debugPrint('[GlobalMessageRouter] uploadPreKeys after '
          'force_prekey_upload failed (will retry on socket reconnect): $e');
    });
  }
}
