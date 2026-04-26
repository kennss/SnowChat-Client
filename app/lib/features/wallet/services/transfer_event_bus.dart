/// @file        transfer_event_bus.dart
/// @description Wallet V2 Phase 1 — chat-transfer event broadcast bus.
///              EncryptedMessageHandler's transfer_* dispatcher emits;
///              TransferService / UI (Dialog) listen.
///              StreamController.broadcast is safe for multiple subscribers
///              (sender-side toast + recipient-side dialog + service-owned
///              timer all run simultaneously).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-20
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - TransferEvent (sealed class): base type of the 4 subclasses
///  - TransferRequestEvent: A → B new request received (triggers TransferConfirmDialog)
///  - TransferResponseEvent: B → A response received (Accept → broadcast / Decline → toast)
///  - TransferCompletedEvent: A → B completion notice (commit system message after B-side RPC verify)
///  - TransferFailedEvent: A → B explicit failure (dismiss B's dialog immediately + explicit toast)
///  - TransferEventBus.events: full broadcast stream (TransferEvent base type)
///  - TransferEventBus.addRequest(from, req) / addResponse(from, resp) /
///    addCompleted(from, c) / addFailed(from, f): four emit methods
///  - TransferEventBus.dispose(): close controller (Riverpod onDispose)

import 'dart:async';

import '../models/transfer_request.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sealed event hierarchy (Dart 3 sealed)
// ─────────────────────────────────────────────────────────────────────────────

/// Base type of transfer-* events between the E2EE dispatcher and wallet UI/service.
///
/// `sealed` keyword — the compiler warns if a `switch` doesn't handle all 4
/// subclasses. Forces all listeners to update when a new subclass is added.
sealed class TransferEvent {
  const TransferEvent({required this.fromSnowchatId});

  /// Sender SnowChat ID of the event (authenticated sender after E2EE decrypt).
  /// Still valid after Sealed Sender pass-through (extracted on unseal).
  final String fromSnowchatId;
}

/// A → B new transfer request received.
///
/// **Recipient-side handling** (Phase D):
/// - Show TransferConfirmDialog (10-minute countdown, service-owned timer P1-7)
/// - Single dialog per duplicate requestId (replay set auto-dedups)
class TransferRequestEvent extends TransferEvent {
  const TransferRequestEvent({
    required super.fromSnowchatId,
    required this.payload,
  });

  final TransferRequest payload;
}

/// B → A response received.
///
/// **Sender-side handling** (Phase E):
/// - `accepted=true` → verify walletAddressSig (P1-5) + verify network (P1-6) +
///   balance pre-check (P0-4) → on pass, broadcast / on failure, send transfer_failed
/// - `accepted=false` → "Recipient declined" toast (no chat message)
class TransferResponseEvent extends TransferEvent {
  const TransferResponseEvent({
    required super.fromSnowchatId,
    required this.payload,
  });

  final TransferResponse payload;
}

/// A → B transfer-complete notification.
///
/// **Recipient-side handling** (Phase E3 + G):
/// - **Never trust txHash blindly** (P0-3): RPC `getTransaction(txHash)`
///   verifies 4 items (recipient / amount / mint / status); only on pass
///   commit the permanent system message
/// - On verify failure: "Pending verification" → re-query after 30s →
///   "Verification failed" after 5 min
class TransferCompletedEvent extends TransferEvent {
  const TransferCompletedEvent({
    required super.fromSnowchatId,
    required this.payload,
  });

  final TransferCompleted payload;
}

/// A → B explicit transfer failure.
///
/// **Recipient-side handling** (Phase D + G):
/// - Dismiss dialog immediately + explicit reason toast
///   (e.g. "Transfer failed: insufficient balance")
class TransferFailedEvent extends TransferEvent {
  const TransferFailedEvent({
    required super.fromSnowchatId,
    required this.payload,
  });

  final TransferFailed payload;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bus
// ─────────────────────────────────────────────────────────────────────────────

/// Broadcast bus for transfer events (single-writer / multi-reader).
///
/// **Lifecycle**: single Riverpod `Provider` instance. `dispose()` is called
/// from `ref.onDispose` (see providers.dart).
///
/// **Concurrency**: `StreamController.broadcast()` — safe with N concurrent
/// subscribers. Events emitted before subscription are dropped (normal
/// broadcast behavior; no replay guarantee).
/// → A late-starting listener does not receive prior events. This is by
///    design — in-flight transfer state is persisted in the
///    `pending_transfers` table, so dialogs and other UI can rebuild via
///    DAO lookup on startup (recoverPending).
class TransferEventBus {
  TransferEventBus();

  final StreamController<TransferEvent> _controller =
      StreamController<TransferEvent>.broadcast();

  /// All transfer events stream. Listeners downcast via
  /// `is TransferRequestEvent` etc. for per-subclass handling (or use the
  /// Dart 3 `switch` pattern).
  Stream<TransferEvent> get events => _controller.stream;

  /// Emit A → B new request (called by the recipient-side dispatcher).
  void addRequest(String fromSnowchatId, TransferRequest payload) {
    _emit(TransferRequestEvent(
      fromSnowchatId: fromSnowchatId,
      payload: payload,
    ));
  }

  /// Emit B → A response (called by the sender-side dispatcher).
  void addResponse(String fromSnowchatId, TransferResponse payload) {
    _emit(TransferResponseEvent(
      fromSnowchatId: fromSnowchatId,
      payload: payload,
    ));
  }

  /// Emit A → B completion (called by the recipient-side dispatcher).
  void addCompleted(String fromSnowchatId, TransferCompleted payload) {
    _emit(TransferCompletedEvent(
      fromSnowchatId: fromSnowchatId,
      payload: payload,
    ));
  }

  /// Emit A → B explicit failure (called by the recipient-side dispatcher).
  void addFailed(String fromSnowchatId, TransferFailed payload) {
    _emit(TransferFailedEvent(
      fromSnowchatId: fromSnowchatId,
      payload: payload,
    ));
  }

  /// Called on Provider dispose — closes outstanding stream.
  /// Emit attempts after dispose are silent no-ops (StreamController.add
  /// throws StateError when closed → defensively isClosed-check + try/catch).
  Future<void> dispose() async {
    if (_controller.isClosed) return;
    try {
      await _controller.close();
    } catch (_) {
      // Concurrent close-call race — ignore if another path is already closing.
    }
  }

  // Internal: prevent StateError on add to a closed controller (D2 P1-4).
  // Double-defense via isClosed check + try/catch — Dart's event loop is
  // single-threaded, but blocks the race window from micro-task ordering
  // between dispose ↔ emit.
  void _emit(TransferEvent event) {
    if (_controller.isClosed) return;
    try {
      _controller.add(event);
    } catch (_) {
      // Race with dispose — drop event.
    }
  }
}
