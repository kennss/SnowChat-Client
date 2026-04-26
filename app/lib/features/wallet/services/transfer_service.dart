/// @file        transfer_service.dart
/// @description Wallet V2 Phase E — chat-room transfer orchestration.
///              Combines sender (A) sendRequest + receiver (B)
///              TransferEventBus listener + every P0/P1 security fix on both
///              sides.
///              - P0-1 PendingTransferDao persistence + recoverPending() (Phase E2 wiring separate)
///              - P0-2 Replay check (Phase J P1-D hardened → single dao.findByRequestId check)
///              - P0-3 txHash on-chain verification (RPC getTransaction 4-field deep parser + 30s/5min retry, Phase E3)
///              - P0-4 ATA rent fee + balance pre-check
///              - P1-5 walletAddressSig Ed25519 sign/verify
///              - P1-6 network strict equality
///              - P1-7 service-owned 10-minute timeout timer
///              - P1-8 per-peer pending lock
///              - **P0-A (Phase J follow-up)**: SPL/NFT recipient check — destination ATA
///                must equal derive(expectedRecipient, mint) (deterministic, 0 RPC calls).
///              - **P1-B (Phase J follow-up)**: prevent regression where dialog mount
///                failure triggers auto user_cancel — `_DialogMountFailed` exception →
///                row stays 'pending' + next startup `recoverPendingDialogs()` re-shows
///                rows within the 10-minute active window.
///              - **P1-D (Phase J follow-up)**: hardened dedup — `findByRequestId != null`
///                check blocks the second arrival across every status
///                (pending/sent/completed/failed/timeout).
///              Sending calls sessionManager.encrypt +
///              socketManager.sendPrivateMessage / sendSealedMessage (sealed
///              sender availability branch) directly — transfer wire payload
///              has a different structure than a regular chat payload, so it
///              bypasses EncryptedMessageHandler's sendEncryptedMessage (via
///              dedicated helper _sendTransferControl).
///              Float/double strictly forbidden (wallet/CLAUDE.md §2.1) —
///              amounts are BigInt.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-20
/// @lastUpdated 2026-04-26 (header + inline English translation; Phase J follow-up fix: P0-A SPL recipient ATA derive check + P1-B mount-fail exception + P1-D hardened dedup + recoverPendingDialogs)
///
/// @functions
///  - TransferLockException: thrown on per-peer lock violation (P1-8)
///  - _DialogMountFailed: dialog-mount failure sentinel (P1-B, private)
///  - VerificationResult (enum, Phase E3): confirmed / rpcError / notYetPropagated / fakeOrTampered
///  - TransferService (class)
///    - sendRequest(): sender entry — lock check + drift insert + E2EE send + start timer
///    - dispose(): cancel bus subscription + all timers
///    - recoverPending(): app-startup recovery (P0-1, Phase E2 wire-up)
///    - recoverPendingDialogs(): Phase J P1-B — re-show dialog for pending-recipient
///                                rows still inside the 10-minute active window (called on mount return)
///    - _onEvent(): TransferEventBus.events listen handler (4-type branch)
///    - _onRequest(): receiver-side transfer_request handler (P1-D dedup + dialog + send response)
///    - _resumePendingRequest(): shared helper — `_onRequest` and `recoverPendingDialogs`
///                                reuse the same dialog/response flow (P1-B)
///    - _onResponse(): sender-side transfer_response handling (sig/network/balance verify + broadcast)
///    - _onCompleted(): recipient-side transfer_completed handling (Phase E3: 1st → 30s → 5min retry → fail)
///    - _onFailed(): recipient-side transfer_failed handling (dialog dismiss + reason toast)
///    - _verifyOnChain(): RPC getTransaction 4-field deep parser — returns VerificationResult (Phase E3)
///    - _verifySolTransfer(): SOL transfer verification (SystemProgram transfer destination + lamports)
///    - _verifySplTransfer(): SPL/NFT transfer verification (P0-A destination ATA derive match + amount)
///    - _signWalletAddress(): sign walletAddress with own Ed25519 signing seed
///    - _verifyWalletAddressSig(): verify sig with peer Ed25519 verify key (Phase F: wired via SignalSessionManager.getPeerEd25519PublicKey)
///    - _sendTransferControl(): wrapper to send the 4 payload types (sealed if available)
///    - _sendFailed() / _sendCompleted() / _sendResponse(): helpers for the 4 wire types
///    - _startExpiryTimer() / _cancelExpiryTimer(): per-requestId 10-minute timer management (P1-7)
///  - transferServiceProvider: Riverpod Provider (DI wiring + dispose, Phase F: uses rootNavigatorKey + scaffoldMessengerKey)

library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:solana/dto.dart' as sol_dto;
import 'package:solana/solana.dart' as sol;
import 'package:uuid/uuid.dart';

import '../../../app/app.dart' show rootScaffoldMessengerKey;
import '../../../app/providers.dart';
import '../../../app/router.dart' show rootNavigatorKey;
import '../../../core/crypto/encrypted_message_handler.dart';
import '../../../core/crypto/signal_protocol_service.dart';
import '../../../core/crypto/signal_session_manager.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/storage/daos/conversation_dao.dart';
import '../../../core/storage/daos/message_dao.dart';
import '../../../core/storage/daos/pending_transfer_dao.dart';
import '../../../core/storage/database.dart';
import '../../contacts/contact_provider.dart';
import '../models/transfer_request.dart';
import '../providers/wallet_list_provider.dart';
import '../rpc/rpc_client_provider.dart' hide solanaNetworkProvider;
import '../wallet_provider.dart';
import '../widgets/transfer_confirm_dialog.dart';
import 'transfer_event_bus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Exceptions
// ─────────────────────────────────────────────────────────────────────────────

/// Per-peer pending lock violation (P1-8) — an in-flight transfer is already running for this peer.
class TransferLockException implements Exception {
  TransferLockException(this.message);
  final String message;
  @override
  String toString() => 'TransferLockException: $message';
}

/// Generic transfer failure (balance / network / sig / RPC etc.). Caller shows a toast.
class TransferException implements Exception {
  TransferException(this.message);
  final String message;
  @override
  String toString() => 'TransferException: $message';
}

/// Dialog mount-failure sentinel (Phase J P1-B).
///
/// Situation where the dialog was not shown at all (background / screen
/// lock / rootNavigator unmounted). Must NOT auto-send user_cancel — the
/// user never saw the request, so it must get another chance on next
/// foreground (`recoverPendingDialogs`).
///
/// The `showConfirmDialog` delegate throws when mount fails → `_onRequest`
/// catches it and keeps the row 'pending' + returns.
///
/// **Private**: scoped to this file — external callers must not depend on it.
class _DialogMountFailed implements Exception {
  const _DialogMountFailed();
  @override
  String toString() => '_DialogMountFailed';
}

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

/// Solana base transaction fee (5000 lamports per signature, assuming 1 sig).
/// Used in balance pre-check (P0-4) for additional cost. priority fee is separate.
const int _kSolBaseTxFeeLamports = 5000;

/// SPL ATA rent (sender pays when recipient ATA is missing). Solana standard ~0.002 SOL.
/// fallback: used only when response.ataRentLamports is empty.
const int _kAtaRentLamportsFallback = 2039280;

/// Request expiry (P1-7). spec §2 — 10 minutes.
const Duration _kRequestExpiry = Duration(minutes: 10);

/// 1-hour timeout for recoverPending() — anything 'sent' over 1h becomes timeout.
const Duration _kRecoverTimeout = Duration(hours: 1);

/// Timeout for one-shot RPC calls (getTransaction / getAccountInfo etc.). 8s.
const Duration _kRpcTimeout = Duration(seconds: 8);

/// Phase E3 — RPC propagation wait when 1st txHash verify fails (spec §5.9).
/// A freshly broadcast tx averages ~13-15s from confirmed → finalized → cluster fan-out.
/// 30s is the safety margin (devnet/mainnet alike).
const Duration _kVerifyRetry1 = Duration(seconds: 30);

/// Phase E3 — extra wait until final decision after the 2nd retry failure (spec §5.9).
/// 2nd retry fires 30s after the 1st → final decision at broadcast +5min. So 30 + 270 = 300s.
const Duration _kVerifyRetry2Delay = Duration(seconds: 270);

// ─────────────────────────────────────────────────────────────────────────────
// VerificationResult (Phase E3, spec §5.9)
// ─────────────────────────────────────────────────────────────────────────────

/// txHash on-chain verification result (P0-3, spec §5.9).
///
/// **Retry policy**:
/// - `confirmed`: all 4 fields match → commit permanent system msg.
/// - `rpcError`: transient (network/timeout) → retry allowed (`_onCompleted` 30s/5min).
/// - `notYetPropagated`: tx not yet in cluster → retry allowed (race right after broadcast).
/// - `fakeOrTampered`: tx exists but at least one of recipient/amount/mint/status
///   mismatches → fail immediately (malicious sender — re-query never changes result).
enum VerificationResult {
  /// All 4 fields (recipient, amount, mint, status) match — system msg commit allowed.
  confirmed,

  /// RPC call itself failed (timeout / network / response-parse error). Retry allowed.
  rpcError,

  /// `getTransaction` response is null — tx not yet propagated to cluster
  /// or not yet in existence. 30s/5min retry allowed.
  notYetPropagated,

  /// tx exists but at least one of the 4 verify fields mismatches (malicious fake txHash).
  /// Fail immediately — no retry.
  fakeOrTampered,
}

// ─────────────────────────────────────────────────────────────────────────────
// TransferService
// ─────────────────────────────────────────────────────────────────────────────

/// Wallet V2 Phase 1 transfer-orchestration core.
///
/// **Lifecycle**: single Riverpod `Provider` instance (app lifetime).
/// `dispose()` is called from `ref.onDispose` — clears every timer and
/// StreamSubscription.
///
/// **Two-sided unified flow**: a single TransferEventBus.events listen
/// branches to the 4 wire types. Sender(A) uses sendRequest() as the
/// external entry plus _onResponse / _onCompleted for handling responses to
/// its own request. Recipient(B) uses _onRequest / _onFailed to dialog/handle
/// external requests.
class TransferService {
  TransferService({
    required Ref ref,
    required TransferEventBus eventBus,
    required PendingTransferDao pendingDao,
    required EncryptedMessageHandler e2eeHandler,
    required sol.RpcClient rpcClient,
    required SignalProtocolService signal,
    required SignalSessionManager sessionManager,
    required SocketManager socketManager,
    required MessageDao messageDao,
    required ConversationDao conversationDao,
    required Future<bool?> Function(TransferRequestEvent event) showConfirmDialog,
    required void Function(String message) showToast,
    required void Function(String requestId) dismissDialog,
  })  : _ref = ref,
        _eventBus = eventBus,
        _pendingDao = pendingDao,
        _e2eeHandler = e2eeHandler,
        _rpc = rpcClient,
        _signal = signal,
        _sessionManager = sessionManager,
        _socketManager = socketManager,
        _messageDao = messageDao,
        _conversationDao = conversationDao,
        _showConfirmDialog = showConfirmDialog,
        _showToast = showToast,
        _dismissDialog = dismissDialog {
    _busSub = _eventBus.events.listen(
      _onEvent,
      onError: (Object e, StackTrace st) {
        debugPrint('[TransferService] event bus error: $e');
      },
    );
    debugPrint('[TransferService] constructed + listener armed on '
        'bus=${_eventBus.hashCode}');
  }

  final Ref _ref;
  final TransferEventBus _eventBus;
  final PendingTransferDao _pendingDao;
  // Reserved for future EncryptedMessageHandler integration (Phase F:
  // sealed sender certificate access + sendEncryptedMessage handling
  // transfer payloads). Currently _sendTransferControl calls sessionManager
  // + socketManager directly so this is unused — DI wiring kept so Phase F
  // work can use it immediately.
  // ignore: unused_field
  final EncryptedMessageHandler _e2eeHandler;
  final sol.RpcClient _rpc;
  final SignalProtocolService _signal;
  final SignalSessionManager _sessionManager;
  final SocketManager _socketManager;
  final MessageDao _messageDao;
  final ConversationDao _conversationDao;

  /// UI delegate — show recipient-side dialog. Screen must be active at call
  /// time to display. On timeout / failed, the service calls [_dismissDialog].
  final Future<bool?> Function(TransferRequestEvent event) _showConfirmDialog;
  final void Function(String message) _showToast;
  final void Function(String requestId) _dismissDialog;

  StreamSubscription<TransferEvent>? _busSub;
  final Map<String, Timer> _expiryTimers = <String, Timer>{};

  static const _uuid = Uuid();

  /// Send a transfer request (Phase E entry point).
  ///
  /// **Flow** (spec §3, sender A):
  /// 1. Per-peer pending lock check (P1-8) — when `findActiveForPeer` returns
  ///    a row, throw `TransferLockException` → UI shows a toast.
  /// 2. drift insert (status='pending', role='sender') — persistence (P0-1).
  /// 3. Build TransferRequest payload (uuid v4 + amount + token + mint +
  ///    decimals + network + sentAt).
  /// 4. E2EE send (sealed if available).
  /// 5. Start 10-minute timer (P1-7).
  Future<void> sendRequest({
    required String recipientSnowchatId,
    required BigInt amount,
    required TokenType token,
    String? mint,
    required int decimals,
  }) async {
    if (amount <= BigInt.zero) {
      throw TransferException('amount must be > 0');
    }
    if (token != TokenType.sol && (mint == null || mint.isEmpty)) {
      throw TransferException('mint required for SPL/NFT transfers');
    }
    if (token == TokenType.sol && mint != null) {
      throw TransferException('SOL transfer must not specify mint');
    }

    // Step 1: per-peer lock (P1-8)
    final active = await _pendingDao.findActiveForPeer(recipientSnowchatId);
    if (active != null) {
      throw TransferLockException('Previous transfer pending');
    }

    final requestId = _uuid.v4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final networkWire = _ref.read(solanaNetworkProvider) == SolanaNetwork.devnet
        ? NetworkType.devnet
        : NetworkType.mainnet;

    final request = TransferRequest(
      requestId: requestId,
      amount: amount.toString(),
      token: token,
      mint: mint,
      decimals: decimals,
      network: networkWire,
      sentAt: nowMs,
    );

    // Step 2: drift insert (persist)
    await _pendingDao.upsert(PendingTransfersCompanion(
      requestId: Value(requestId),
      role: const Value('sender'),
      peerSnowchatId: Value(recipientSnowchatId),
      amount: Value(amount.toString()),
      token: Value(token.toJson()),
      mint: Value(mint),
      decimals: Value(decimals),
      network: Value(networkWire.toJson()),
      status: const Value('pending'),
      signature: const Value(null),
      createdAt: Value(nowMs),
      updatedAt: Value(nowMs),
    ));

    // Step 3 + 4: E2EE send
    try {
      await _sendTransferControl(
        recipientSnowchatId: recipientSnowchatId,
        payload: request.toJson(),
      );
      debugPrint('[TransferService] sendRequest dispatched: '
          'requestId=$requestId peer=$recipientSnowchatId '
          'token=${token.toJson()} amount=$amount');
    } catch (e) {
      debugPrint('[TransferService] sendRequest E2EE send failed: $e');
      await _pendingDao.updateStatus(requestId, 'failed');
      _cancelExpiryTimer(requestId);
      rethrow;
    }

    // Step 5: 10-minute timer (P1-7)
    _startExpiryTimer(requestId, recipientSnowchatId);
  }

  /// Called on app termination — clean up bus subscription + all timers.
  Future<void> dispose() async {
    for (final t in _expiryTimers.values) {
      t.cancel();
    }
    _expiryTimers.clear();
    await _busSub?.cancel();
    _busSub = null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase E2 — recoverPending (Phase E2 wire-up: called from app.dart startup)
  // ───────────────────────────────────────────────────────────────────────────

  /// Recover in-flight transfers after app restart (P0-1, spec §5.8).
  ///
  /// **Targets**: `status='sent' && signature != null` (sender role).
  ///
  /// **Branches**:
  /// - confirmed → post-send `transfer_completed` + status='completed'
  /// - failed → `transfer_failed (rpc_error)` + status='failed'
  /// - pending → retain until next startup
  /// - over 1h → `transfer_failed (timeout)` + status='timeout'
  ///
  /// Do NOT await this in app.dart's init phase (slow RPC would block
  /// startup). Async fire-and-forget recommended.
  Future<void> recoverPending() async {
    final List<PendingTransfer> rows;
    try {
      rows = await _pendingDao.findInFlight();
    } catch (e) {
      debugPrint('[TransferService] recoverPending findInFlight failed: $e');
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final row in rows) {
      try {
        // Over 1h — force timeout
        if (nowMs - row.createdAt > _kRecoverTimeout.inMilliseconds) {
          debugPrint('[TransferService] recover: $row.requestId aged out — '
              'timeout');
          await _pendingDao.updateStatus(row.requestId, 'timeout');
          await _sendFailed(
            recipientSnowchatId: row.peerSnowchatId,
            requestId: row.requestId,
            reason: FailureReason.timeout,
          );
          continue;
        }

        final sig = row.signature;
        if (sig == null || sig.isEmpty) {
          // 'sent' without signature is abnormal — clean up
          await _pendingDao.updateStatus(row.requestId, 'failed');
          continue;
        }

        // RPC getSignatureStatuses
        final statuses = await _rpc
            .getSignatureStatuses([sig], searchTransactionHistory: true)
            .timeout(_kRpcTimeout);
        final status = statuses.value.isNotEmpty ? statuses.value.first : null;
        if (status == null) {
          // Still propagating — retain until next startup
          continue;
        }

        if (status.err != null) {
          debugPrint('[TransferService] recover: $row.requestId RPC failed: '
              '${status.err}');
          await _pendingDao.updateStatus(row.requestId, 'failed');
          await _sendFailed(
            recipientSnowchatId: row.peerSnowchatId,
            requestId: row.requestId,
            reason: FailureReason.rpcError,
          );
          continue;
        }

        // confirmed/finalized — post-send transfer_completed
        final isConfirmed = status.confirmationStatus ==
                sol_dto.Commitment.confirmed ||
            status.confirmationStatus == sol_dto.Commitment.finalized;
        if (isConfirmed) {
          await _sendCompleted(
            recipientSnowchatId: row.peerSnowchatId,
            requestId: row.requestId,
            txHash: sig,
            status: TransferCompletedStatus.confirmed,
          );
          await _pendingDao.updateStatus(row.requestId, 'completed');
          // Phase G — sender-side permanent system msg (post-startup recover path).
          // Only role==sender rows are committed here (recipient rows commit
          // after separate verification in _onCompleted). recoverPending only
          // processes sender role, so mark 'sent' directly.
          if (row.role == 'sender') {
            await _commitTransferSystemMessage(
              peerSnowId: row.peerSnowchatId,
              requestId: row.requestId,
              txHash: sig,
              amount: row.amount,
              token: row.token,
              mint: row.mint,
              decimals: row.decimals,
              direction: 'sent',
              network: row.network,
            );
          }
          debugPrint('[TransferService] recover: $row.requestId completed '
              '(post-startup)');
        }
      } catch (e) {
        debugPrint(
            '[TransferService] recover row ${row.requestId} failed: $e');
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Event listener (TransferEventBus dispatch)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _onEvent(TransferEvent event) async {
    debugPrint('[TransferService] _onEvent received ${event.runtimeType} from '
        '${event.fromSnowchatId}');
    try {
      switch (event) {
        case TransferRequestEvent():
          await _onRequest(event);
        case TransferResponseEvent():
          await _onResponse(event);
        case TransferCompletedEvent():
          await _onCompleted(event);
        case TransferFailedEvent():
          await _onFailed(event);
      }
    } catch (e, st) {
      debugPrint('[TransferService] event handler error '
          '(${event.runtimeType}): $e\n$st');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Recipient (B) — transfer_request received
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _onRequest(TransferRequestEvent event) async {
    final req = event.payload;
    final fromSnowId = event.fromSnowchatId;

    // ── Phase J P1-D: hardened dedup ──
    // Instead of the old isProcessed (terminal status only), use
    // findByRequestId to block the second arrival across every status
    // (pending/sent/completed/failed/timeout). Previously, a duplicate
    // requestId arriving as status='pending' passed because
    // isProcessed=false → upsert(insertOrReplace) overwrote the row and the
    // dialog could appear twice. The hardened dao dedup blocks at row
    // existence — strictest + the right way.
    final existing = await _pendingDao.findByRequestId(req.requestId);
    if (existing != null) {
      debugPrint('[TransferService] _onRequest dedup: ${req.requestId} '
          'already exists (status=${existing.status}) — drop');
      return;
    }

    // drift insert (recipient role)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _pendingDao.upsert(PendingTransfersCompanion(
      requestId: Value(req.requestId),
      role: const Value('recipient'),
      peerSnowchatId: Value(fromSnowId),
      amount: Value(req.amount),
      token: Value(req.token.toJson()),
      mint: Value(req.mint),
      decimals: Value(req.decimals),
      network: Value(req.network.toJson()),
      status: const Value('pending'),
      signature: const Value(null),
      createdAt: Value(nowMs),
      updatedAt: Value(nowMs),
    ));

    // Start 10-minute timer (recipient also dismisses dialog + replies on timeout)
    _startExpiryTimer(req.requestId, fromSnowId);

    // Dialog display + response-send flow is shared in _resumePendingRequest
    // (recoverPendingDialogs reuses the same path).
    await _resumePendingRequest(event);
  }

  /// Shared recipient-side dialog-display + response-send flow (Phase J P1-B).
  ///
  /// **Called at**:
  /// - `_onRequest`: right after a new transfer_request arrives (after
  ///   insert + timer).
  /// - `recoverPendingDialogs`: re-display pending recipient rows that were
  ///   retained due to mount failure when the app returns to foreground.
  ///
  /// **Mount-failure branch (P1-B)**: when `_showConfirmDialog` throws
  /// `_DialogMountFailed`, keep row 'pending' + return. Do NOT auto-send
  /// user_cancel (the user never saw the request). Retry on next
  /// foreground.
  Future<void> _resumePendingRequest(TransferRequestEvent event) async {
    final req = event.payload;
    final fromSnowId = event.fromSnowchatId;

    final bool? result;
    try {
      result = await _showConfirmDialog(event);
    } on _DialogMountFailed {
      // P1-B — Dialog never displayed. Keep row 'pending' + do NOT auto-reply.
      // recoverPendingDialogs() re-displays on next foreground return.
      // timer keeps running (sends transfer_failed timeout on expiry).
      debugPrint('[TransferService] _resumePendingRequest: dialog mount failed '
          'for ${req.requestId} — pending retain (will retry on foreground)');
      return;
    } catch (e) {
      debugPrint('[TransferService] _resumePendingRequest dialog error: $e');
      // Other dialog errors → user_cancel (assume the user saw the dialog
      // and aborted abnormally).
      await _pendingDao.updateStatus(req.requestId, 'failed');
      _cancelExpiryTimer(req.requestId);
      return;
    }

    // result=null means timeout or external dismiss — if the timer is still
    // alive, the timer branch handles it, so don't decide here immediately.
    // If the timer already fired, status is timeout, so re-read dao to branch.
    if (result == null) {
      // timer fire-or-pending — if status is already timeout/failed, do not
      // send anything more.
      final cur = await _pendingDao.findByRequestId(req.requestId);
      if (cur != null && cur.status == 'pending') {
        // External dismiss (background tap etc.) — service policy is to
        // reply user_cancel.
        await _sendResponse(
          recipientSnowchatId: fromSnowId,
          requestId: req.requestId,
          accepted: false,
        );
        await _pendingDao.updateStatus(req.requestId, 'failed');
        _cancelExpiryTimer(req.requestId);
      }
      return;
    }

    if (result == false) {
      // Decline
      await _sendResponse(
        recipientSnowchatId: fromSnowId,
        requestId: req.requestId,
        accepted: false,
      );
      await _pendingDao.updateStatus(req.requestId, 'failed');
      _cancelExpiryTimer(req.requestId);
      return;
    }

    // result == true — Accept branch (P0-4 ATA + P1-5 sig)
    // Multi-Wallet Phase 4D: the friend-transfer receive address is unified
    // to the default wallet. If active (the wallet the user is viewing) is
    // a trading-style sub, that diverges from intent. Falls back to active
    // when default is missing.
    final myAddr = _ref.read(defaultWalletAddressProvider) ??
        _ref.read(walletProvider).publicKey;
    if (myAddr == null) {
      debugPrint('[TransferService] _resumePendingRequest: wallet not '
          'initialized');
      await _sendFailed(
        recipientSnowchatId: fromSnowId,
        requestId: req.requestId,
        reason: FailureReason.rpcError,
      );
      await _pendingDao.updateStatus(req.requestId, 'failed');
      _cancelExpiryTimer(req.requestId);
      return;
    }

    // ATA lookup (P0-4) — SPL/NFT only
    bool? ataExists;
    int? ataRentLamports;
    if (req.token != TokenType.sol) {
      try {
        final ata = await sol.findAssociatedTokenAddress(
          owner: sol.Ed25519HDPublicKey.fromBase58(myAddr),
          mint: sol.Ed25519HDPublicKey.fromBase58(req.mint!),
        );
        final info = await _rpc
            .getAccountInfo(
              ata.toBase58(),
              encoding: sol_dto.Encoding.base64,
            )
            .timeout(_kRpcTimeout);
        ataExists = info.value != null;
        ataRentLamports = ataExists ? 0 : _kAtaRentLamportsFallback;
      } catch (e) {
        debugPrint('[TransferService] ATA lookup failed (assume needs create): '
            '$e');
        ataExists = false;
        ataRentLamports = _kAtaRentLamportsFallback;
      }
    }

    // walletAddress signature (P1-5)
    String? sigB64;
    try {
      sigB64 = _signWalletAddress(myAddr);
    } catch (e) {
      debugPrint('[TransferService] _signWalletAddress failed: $e');
      await _sendFailed(
        recipientSnowchatId: fromSnowId,
        requestId: req.requestId,
        reason: FailureReason.signatureInvalid,
      );
      await _pendingDao.updateStatus(req.requestId, 'failed');
      _cancelExpiryTimer(req.requestId);
      return;
    }

    // Send response
    await _sendResponse(
      recipientSnowchatId: fromSnowId,
      requestId: req.requestId,
      accepted: true,
      walletAddress: myAddr,
      walletAddressSig: sigB64,
      ataExists: ataExists,
      ataRentLamports: ataRentLamports,
    );

    // Recipient-side responsibility ends after sending the response
    // (the sender does broadcast). status='completed' is set when
    // transfer_completed is received and RPC verification passes.
    // Setting 'sent' here makes no sense, so leave as 'pending' — response
    // sent but chain result unconfirmed.
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase J P1-B — recoverPendingDialogs (after mount-fail, on foreground return)
  // ───────────────────────────────────────────────────────────────────────────

  /// Re-display dialog for `role='recipient' && status='pending'` rows that
  /// are still within sentAt + 10 minutes (Phase J P1-B).
  ///
  /// **Recommended call sites**: app.dart startup + AppLifecycleState.resumed.
  /// Distinct from `recoverPending` — that one owns RPC verification of
  /// in-flight sender-role tx; this method owns mount-fail recovery for
  /// recipient role.
  ///
  /// **Retry flow**: calls `_resumePendingRequest` — same path as
  /// `_onRequest`. If mount fails again, retain again (until next foreground).
  /// On expiry (10 minutes), the service-owned timer sends transfer_failed
  /// (timeout).
  Future<void> recoverPendingDialogs() async {
    final List<PendingTransfer> candidates;
    try {
      candidates = await _pendingDao.findActiveRecipientPending();
    } catch (e) {
      debugPrint('[TransferService] recoverPendingDialogs query failed: $e');
      return;
    }

    if (candidates.isEmpty) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final row in candidates) {
      try {
        // 10-minute expiry check (expired ones are handled by timer — skip here).
        if (nowMs - row.createdAt > _kRequestExpiry.inMilliseconds) {
          debugPrint('[TransferService] recoverPendingDialogs: ${row.requestId}'
              ' aged out — skip (timer will handle)');
          continue;
        }
        // Skip if the in-memory timer already fired (avoid clash when
        // status is still 'pending' and dialog is re-shown before timer
        // expiry).
        if (!_expiryTimers.containsKey(row.requestId)) {
          // No timer = new process after app restart — restart it.
          _startExpiryTimer(row.requestId, row.peerSnowchatId);
        }
        // Reconstructed TransferRequestEvent — original wire payload is
        // gone, so rebuild from the row's persisted values. nonce(sentAt)
        // falls back to createdAt.
        final event = TransferRequestEvent(
          fromSnowchatId: row.peerSnowchatId,
          payload: TransferRequest(
            requestId: row.requestId,
            amount: row.amount,
            token: TokenType.fromJson(row.token),
            mint: row.mint,
            decimals: row.decimals,
            network: NetworkType.fromJson(row.network),
            sentAt: row.createdAt,
          ),
        );
        await _resumePendingRequest(event);
      } catch (e) {
        debugPrint('[TransferService] recoverPendingDialogs row ${row.requestId}'
            ' failed: $e');
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Sender (A) — transfer_response received
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _onResponse(TransferResponseEvent event) async {
    final resp = event.payload;
    final peer = event.fromSnowchatId;

    final row = await _pendingDao.findByRequestId(resp.requestId);
    if (row == null || row.role != 'sender' || row.peerSnowchatId != peer) {
      debugPrint('[TransferService] _onResponse: no matching sender row for '
          '${resp.requestId} (or peer mismatch) — drop');
      return;
    }
    if (row.status != 'pending') {
      // Already processed — replay or late response after timeout
      debugPrint('[TransferService] _onResponse: ${resp.requestId} status='
          '${row.status} — ignore');
      return;
    }

    // P1-6 Network verification (response has no network field — strong
    // assumption that the responding peer is on the same network as the
    // original request. spec §5.13's "response.network" is only in prose,
    // no wire field → this client verifies strict equality between
    // request.network and my current network. request.network and
    // row.network are guaranteed identical (DB-persisted) — MITM tamper is
    // E2EE's job. So here we verify against my current network.)
    final myCurrentNetwork =
        _ref.read(solanaNetworkProvider) == SolanaNetwork.devnet
            ? NetworkType.devnet
            : NetworkType.mainnet;
    if (NetworkType.fromJson(row.network) != myCurrentNetwork) {
      debugPrint('[TransferService] _onResponse network mismatch: '
          'request=${row.network} current=${myCurrentNetwork.toJson()}');
      await _sendFailed(
        recipientSnowchatId: peer,
        requestId: resp.requestId,
        reason: FailureReason.networkMismatch,
      );
      await _pendingDao.updateStatus(resp.requestId, 'failed');
      _cancelExpiryTimer(resp.requestId);
      _showToast('Transfer failed: network mismatch');
      return;
    }

    // Decline branch
    if (!resp.accepted) {
      _showToast('Recipient declined the transfer');
      await _pendingDao.updateStatus(resp.requestId, 'failed');
      _cancelExpiryTimer(resp.requestId);
      return;
    }

    // P1-5 walletAddress signature verification
    final addr = resp.walletAddress;
    final sig = resp.walletAddressSig;
    if (addr == null || sig == null) {
      // Should have been filtered at the dispatcher, but defensive
      await _sendFailed(
        recipientSnowchatId: peer,
        requestId: resp.requestId,
        reason: FailureReason.signatureInvalid,
      );
      await _pendingDao.updateStatus(resp.requestId, 'failed');
      _cancelExpiryTimer(resp.requestId);
      _showToast('Transfer failed: invalid signature');
      return;
    }
    final sigOk = await _verifyWalletAddressSig(
      peerSnowId: peer,
      walletAddress: addr,
      walletAddressSigB64: sig,
    );
    if (!sigOk) {
      debugPrint('[TransferService] _onResponse: walletAddressSig INVALID '
          'from $peer');
      await _sendFailed(
        recipientSnowchatId: peer,
        requestId: resp.requestId,
        reason: FailureReason.signatureInvalid,
      );
      await _pendingDao.updateStatus(resp.requestId, 'failed');
      _cancelExpiryTimer(resp.requestId);
      _showToast('Transfer failed: signature invalid');
      return;
    }

    // P0-4 balance pre-check
    final amount = BigInt.parse(row.amount);
    final solBalance = _readMyTokenBalance('SOL');
    final mint = row.mint;
    final ataRent = resp.ataExists == false
        ? BigInt.from(resp.ataRentLamports ?? _kAtaRentLamportsFallback)
        : BigInt.zero;
    final txFee = BigInt.from(_kSolBaseTxFeeLamports);

    final tokenType = TokenType.fromJson(row.token);
    bool insufficient = false;
    if (tokenType == TokenType.sol) {
      // SOL: solBalance >= amount + txFee
      if (solBalance < amount + txFee) insufficient = true;
    } else {
      // SPL/NFT: solBalance >= txFee + ataRent && splBalance >= amount
      if (solBalance < txFee + ataRent) insufficient = true;
      if (mint != null) {
        final splBalance = _readMyTokenBalance(mint);
        if (splBalance < amount) insufficient = true;
      } else {
        insufficient = true;
      }
    }
    if (insufficient) {
      await _sendFailed(
        recipientSnowchatId: peer,
        requestId: resp.requestId,
        reason: FailureReason.insufficientBalance,
      );
      await _pendingDao.updateStatus(resp.requestId, 'failed');
      _cancelExpiryTimer(resp.requestId);
      _showToast('Transfer failed: insufficient balance');
      return;
    }

    // Solana TX broadcast (await waitForSignatureStatus(confirmed) — wallet
    // notifier's sendSOL/sendSPLToken internally waits via v0Sender until confirmed).
    final wallet = _ref.read(walletProvider.notifier);
    String? signature;
    try {
      if (tokenType == TokenType.sol) {
        signature = await wallet.sendSOL(
          toAddress: addr,
          lamports: amount,
        );
      } else {
        signature = await wallet.sendSPLToken(
          toAddress: addr,
          tokenMint: mint!,
          amount: amount,
          decimals: row.decimals,
        );
      }
    } catch (e) {
      debugPrint('[TransferService] broadcast failed: $e');
      await _sendFailed(
        recipientSnowchatId: peer,
        requestId: resp.requestId,
        reason: FailureReason.rpcError,
      );
      await _pendingDao.updateStatus(resp.requestId, 'failed');
      _cancelExpiryTimer(resp.requestId);
      _showToast('Transfer failed: ${_truncateError(e)}');
      return;
    }

    // Persist signature + status='sent'
    await _pendingDao.updateSignature(
      requestId: resp.requestId,
      signature: signature,
    );

    // Send transfer_completed
    try {
      await _sendCompleted(
        recipientSnowchatId: peer,
        requestId: resp.requestId,
        txHash: signature,
        status: TransferCompletedStatus.confirmed,
      );
      await _pendingDao.updateStatus(resp.requestId, 'completed');
      _cancelExpiryTimer(resp.requestId);
    } catch (e) {
      // tx is on chain but transfer_completed send failed — recoverPending
      // posts it on next startup after querying the RPC result.
      debugPrint('[TransferService] transfer_completed send failed (will '
          'retry on next startup via recoverPending): $e');
    }

    // Phase G — sender-side permanent system msg ("Sent X SOL"). spec §6.4.
    // Commit at the moment broadcast succeeds + tx is persisted (regardless
    // of whether the recipient-side confirmation send succeeded —
    // recoverPending handles that later).
    await _commitTransferSystemMessage(
      peerSnowId: peer,
      requestId: resp.requestId,
      txHash: signature,
      amount: row.amount,
      token: row.token,
      mint: row.mint,
      decimals: row.decimals,
      direction: 'sent',
      network: row.network,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Recipient (B) — transfer_completed received (P0-3 RPC verification)
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _onCompleted(TransferCompletedEvent event) async {
    final c = event.payload;
    final peer = event.fromSnowchatId;
    final row = await _pendingDao.findByRequestId(c.requestId);
    if (row == null || row.role != 'recipient' || row.peerSnowchatId != peer) {
      debugPrint('[TransferService] _onCompleted: no matching recipient row '
          'for ${c.requestId} — drop');
      return;
    }
    if (const ['completed', 'failed', 'timeout'].contains(row.status)) {
      debugPrint('[TransferService] _onCompleted: ${c.requestId} terminal '
          '${row.status} — ignore');
      return;
    }

    // Multi-Wallet Phase 4D: receive address uses default. Same source as
    // _resumePendingRequest — the walletAddress filled at response time and
    // myAddr at onCompleted verification must match (with the same default,
    // the race window is short).
    final myAddr = _ref.read(defaultWalletAddressProvider) ??
        _ref.read(walletProvider).publicKey;
    if (myAddr == null) {
      debugPrint('[TransferService] _onCompleted: wallet not initialized');
      return;
    }

    // Case where the sender sent transfer_completed (status=failed) after
    // a broadcast failure. Skip on-chain verification and fail immediately
    // (spec §4.3 status enum 'failed').
    if (c.status == TransferCompletedStatus.failed) {
      debugPrint('[TransferService] _onCompleted: sender reported failed '
          '${c.requestId}');
      _showToast('Transfer failed');
      await _pendingDao.updateStatus(c.requestId, 'failed');
      _cancelExpiryTimer(c.requestId);
      return;
    }

    final expectedAmount = BigInt.parse(row.amount);
    final tokenType = TokenType.fromJson(row.token);

    // ─── Phase E3 retry logic (spec §5.9) ───
    // 1st immediate → 2nd after 30s → 3rd at broadcast +5min (=30+270s)
    // → final fail.
    // fakeOrTampered fails immediately at any stage (chain-baked fact does
    // not change). confirmed → commit + status='completed' immediately.
    // notYetPropagated/rpcError → retry.

    Future<VerificationResult> attempt() => _verifyOnChain(
          txHash: c.txHash,
          expectedRecipient: myAddr,
          expectedAmount: expectedAmount,
          expectedMint: row.mint,
          tokenType: tokenType,
        );

    Future<void> commitConfirmed() async {
      await _commitTransferSystemMessage(
        peerSnowId: peer,
        requestId: c.requestId,
        txHash: c.txHash,
        amount: row.amount,
        token: row.token,
        mint: row.mint,
        decimals: row.decimals,
        direction: 'received',
        network: row.network,
      );
      await _pendingDao.updateStatus(c.requestId, 'completed');
      _cancelExpiryTimer(c.requestId);
    }

    Future<void> failTampered() async {
      // 4-field mismatch — fail immediately. Retry pointless (chain-baked
      // fact does not change).
      debugPrint('[TransferService] _verifyOnChain fakeOrTampered for '
          '${c.requestId} — fail immediately');
      _showToast('Transfer verification failed for ${_truncateTx(c.txHash)}');
      await _pendingDao.updateStatus(c.requestId, 'failed');
      _cancelExpiryTimer(c.requestId);
    }

    /// Right before the next retry, check if another path (cancel/timeout)
    /// flipped status to terminal. Returns true to skip retry.
    Future<bool> shouldStop() async {
      final cur = await _pendingDao.findByRequestId(c.requestId);
      if (cur == null ||
          const ['completed', 'failed', 'timeout'].contains(cur.status)) {
        debugPrint('[TransferService] _onCompleted: ${c.requestId} terminal '
            'during retry — skip');
        return true;
      }
      return false;
    }

    // ── 1st (immediate) ──
    final r1 = await attempt();
    if (r1 == VerificationResult.confirmed) {
      await commitConfirmed();
      return;
    }
    if (r1 == VerificationResult.fakeOrTampered) {
      await failTampered();
      return;
    }

    // 1st unconfirmed — placeholder system msg (UX: shows "verifying").
    debugPrint('[TransferService] _onCompleted: ${c.requestId} attempt 1 '
        '$r1 — schedule 30s retry');
    await _commitPendingVerificationSystemMessage(
      peerSnowId: peer,
      txHash: c.txHash,
    );

    // ── 2nd (after 30s, RPC propagation wait) ──
    await Future<void>.delayed(_kVerifyRetry1);
    if (await shouldStop()) return;

    final r2 = await attempt();
    if (r2 == VerificationResult.confirmed) {
      await commitConfirmed();
      return;
    }
    if (r2 == VerificationResult.fakeOrTampered) {
      await failTampered();
      return;
    }

    debugPrint('[TransferService] _onCompleted: ${c.requestId} attempt 2 '
        '$r2 — schedule 270s retry');

    // ── 3rd (broadcast +5min = 30s + 270s) ──
    await Future<void>.delayed(_kVerifyRetry2Delay);
    if (await shouldStop()) return;

    final r3 = await attempt();
    if (r3 == VerificationResult.confirmed) {
      await commitConfirmed();
      return;
    }
    if (r3 == VerificationResult.fakeOrTampered) {
      await failTampered();
      return;
    }

    // ── final fail ──
    // Even after 5 minutes the tx isn't visible in the cluster or RPC keeps
    // failing → strong likelihood of fake txHash. Explicit toast for the
    // user + status='failed'.
    debugPrint('[TransferService] _onCompleted: ${c.requestId} final fail '
        '(attempt 3 $r3)');
    _showToast('Transfer verification failed for ${_truncateTx(c.txHash)}');
    await _pendingDao.updateStatus(c.requestId, 'failed');
    _cancelExpiryTimer(c.requestId);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Recipient (B) — transfer_failed received
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _onFailed(TransferFailedEvent event) async {
    final f = event.payload;
    final row = await _pendingDao.findByRequestId(f.requestId);
    if (row == null) {
      debugPrint('[TransferService] _onFailed: unknown requestId ${f.requestId}'
          ' — drop');
      return;
    }
    // Cover both directions (v1.0.2 fix):
    //  - recipient role: A failed before broadcast → sends transfer_failed
    //                    to B (dialog dismiss + toast)
    //  - sender role:    B failed inside accept (walletAddressSig generation
    //                    failure, ATA lookup fail etc.) → sends transfer_failed
    //                    to A (A-side toast + status='failed' + timer cancel)
    //  Previous code ignored the sender branch, causing the "nothing
    //  happens" UI freeze.
    if (row.role == 'recipient') {
      _dismissDialog(f.requestId);
      _showToast('Transfer failed: ${_humanReason(f.reason)}');
    } else {
      // row.role == 'sender': peer (B) failed during accept handling → notify sender(A)
      _showToast('Recipient could not process transfer: '
          '${_humanReason(f.reason)}');
    }
    await _pendingDao.updateStatus(f.requestId, 'failed');
    _cancelExpiryTimer(f.requestId);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P0-3 RPC verification — getTransaction 4 fields (recipient/amount/mint/status)
  // Phase E3: hardened with deep parser — returns VerificationResult enum.
  // ───────────────────────────────────────────────────────────────────────────

  /// Verify the 4 chain-side fields of txHash (spec §5.9, P0-3).
  ///
  /// **The 4 fields**:
  /// 1. **recipient**: For SOL, destination == expectedRecipient (Base58).
  ///    For SPL, mint match in postTokenBalances + amount delta>0 check
  ///    (precise owner verification reinforced by ATA address =
  ///    derive(expectedRecipient, mint)).
  /// 2. **amount**: SOL — ix.lamports == expectedAmount; SPL — token balance
  ///    delta (post - pre) >= expectedAmount.
  /// 3. **mint**: For SPL/NFT, postTokenBalances[i].mint == expectedMint.
  ///    For SOL, expectedMint==null is assumed.
  /// 4. **status**: confirmed (RPC call with commitment 'confirmed' +
  ///    meta.err==null).
  ///
  /// **Return branches** (`VerificationResult` enum, decides retry policy):
  /// - `confirmed`: all 4 fields match.
  /// - `notYetPropagated`: getTransaction returned null (not in cluster yet).
  /// - `rpcError`: timeout / parse error / other transient RPC fault.
  /// - `fakeOrTampered`: tx exists but at least one of the 4 fields mismatches (malicious sender).
  ///
  /// `fakeOrTampered` is not retried — chain-baked fact, re-query yields the same result.
  Future<VerificationResult> _verifyOnChain({
    required String txHash,
    required String expectedRecipient,
    required BigInt expectedAmount,
    required String? expectedMint,
    required TokenType tokenType,
  }) async {
    sol_dto.TransactionDetails? tx;
    try {
      tx = await _rpc
          .getTransaction(
            txHash,
            commitment: sol_dto.Commitment.confirmed,
            encoding: sol_dto.Encoding.jsonParsed,
          )
          .timeout(_kRpcTimeout);
    } catch (e) {
      // timeout / network / response-parse transient error — retry allowed.
      debugPrint('[TransferService] _verifyOnChain RPC error: $e');
      return VerificationResult.rpcError;
    }

    if (tx == null) {
      // Not yet in cluster — race right after broadcast. retry allowed.
      debugPrint('[TransferService] _verifyOnChain: tx not found yet ($txHash)');
      return VerificationResult.notYetPropagated;
    }

    // 4. status = confirmed/finalized: getTransaction(commitment=confirmed)
    //    being non-null implies at least confirmed. err must be null for success.
    if (tx.meta?.err != null) {
      debugPrint('[TransferService] _verifyOnChain: tx err=${tx.meta!.err} '
          '($txHash)');
      // Chain-baked failure — re-query yields same. Treat as fakeOrTampered.
      return VerificationResult.fakeOrTampered;
    }

    try {
      // jsonParsed branch — ParsedTransaction → ParsedMessage → instructions.
      final inner = tx.transaction;
      if (inner is! sol_dto.ParsedTransaction) {
        // raw encoding fallback — this path was called with jsonParsed so
        // effectively unreachable. If reached, treat as parse failure →
        // retry allowed (RPC response variant).
        debugPrint('[TransferService] _verifyOnChain: not a ParsedTransaction '
            '— treat as rpcError');
        return VerificationResult.rpcError;
      }
      final msg = inner.message;
      if (msg is! sol_dto.ParsedMessage) {
        debugPrint('[TransferService] _verifyOnChain: not a ParsedMessage '
            '— treat as rpcError');
        return VerificationResult.rpcError;
      }

      if (tokenType == TokenType.sol) {
        return _verifySolTransfer(
          parsed: msg,
          expectedRecipient: expectedRecipient,
          expectedAmount: expectedAmount,
        );
      } else {
        // SPL / NFT — postTokenBalances + instructions + ATA derive
        // verification (Phase J P0-A — async call).
        return await _verifySplTransfer(
          parsed: msg,
          meta: tx.meta,
          expectedRecipient: expectedRecipient,
          expectedAmount: expectedAmount,
          expectedMint: expectedMint,
        );
      }
    } catch (e, st) {
      // Unexpected during parsing — RPC response schema may have changed.
      // retry allowed.
      debugPrint('[TransferService] _verifyOnChain parse error: $e\n$st');
      return VerificationResult.rpcError;
    }
  }

  /// SOL transfer verification (all 4 fields exact).
  ///
  /// confirmed if any SystemProgram transfer instruction (`program == 'system'`,
  /// `parsed.type == 'transfer'`) has (destination == expectedRecipient
  /// && lamports == expectedAmount). All mismatch → fakeOrTampered.
  ///
  /// inner instructions / lookup tables are out of V1.0 scope (V2 deferred):
  /// this method only inspects top-level instructions — assumes a plain
  /// simple-transfer tx structure.
  VerificationResult _verifySolTransfer({
    required sol_dto.ParsedMessage parsed,
    required String expectedRecipient,
    required BigInt expectedAmount,
  }) {
    bool sawAnyTransfer = false;
    for (final ix in parsed.instructions) {
      if (ix is! sol_dto.ParsedInstructionSystem) continue;
      final inner = ix.parsed;
      if (inner is! sol_dto.ParsedSystemTransferInstruction) continue;
      sawAnyTransfer = true;
      final info = inner.info;
      // Base58 destination comparison. lamports converted int → BigInt
      // (Solana max u64 < 2^64, Dart int is 64-bit signed; 1 SOL=1e9 << 2^53
      // so safe).
      if (info.destination == expectedRecipient &&
          BigInt.from(info.lamports) == expectedAmount) {
        debugPrint('[TransferService] _verifySolTransfer: matched '
            'dest=$expectedRecipient lamports=${info.lamports}');
        return VerificationResult.confirmed;
      }
    }
    debugPrint('[TransferService] _verifySolTransfer: no matching transfer '
        '(saw=$sawAnyTransfer expectedRecipient=$expectedRecipient '
        'expectedAmount=$expectedAmount)');
    // No Transfer ix at all, or expectations mismatch → fake.
    return VerificationResult.fakeOrTampered;
  }

  /// SPL/NFT transfer verification (Phase J P0-A — adds recipient ATA derive matching).
  ///
  /// **Risk of the previous placeholder** (found in the Phase J audit):
  /// recipient verification was a bare `final _ = expectedRecipient;`. A
  /// malicious sender A could send a transfer to another friend C, then
  /// forward that txHash to B — once amount + mint matched, it was judged
  /// confirmed → B committed a permanent system msg for a transfer they
  /// never received (asset-loss risk). This fix blocks that vector.
  ///
  /// **Verification steps (4 fields)**:
  /// 1. **instruction exists**: `spl-token` + (transfer | transferChecked).
  /// 2. **amount**: ix.info.amount (transfer) or ix.info.tokenAmount.amount
  ///    (transferChecked) equals expectedAmount.
  /// 3. **recipient (P0-A)**: `expectedAta = derive(expectedRecipient, mint)` →
  ///    ix.info.destination == expectedAta. ATA is deterministic, so the
  ///    match is exact with zero RPC calls. Anyone else's ATA →
  ///    fakeOrTampered immediately.
  /// 4. **mint**: expectedMint must appear in postTokenBalances or
  ///    preTokenBalances. transferChecked self-verifies mint but this is an
  ///    extra safety net.
  ///
  /// **Derive-failure case**: if `findAssociatedTokenAddress` throws
  /// (invalid input pubkey etc.), return `rpcError` (retry allowed) —
  /// derive failure isn't a chain-baked fact, so retry can be meaningful.
  Future<VerificationResult> _verifySplTransfer({
    required sol_dto.ParsedMessage parsed,
    required sol_dto.Meta? meta,
    required String expectedRecipient,
    required BigInt expectedAmount,
    required String? expectedMint,
  }) async {
    if (expectedMint == null || expectedMint.isEmpty) {
      // SPL/NFT but expectedMint is empty — dispatcher-side validation
      // missed it; consistency violation. Immediately fakeOrTampered (retry
      // meaningless).
      debugPrint('[TransferService] _verifySplTransfer: expectedMint missing');
      return VerificationResult.fakeOrTampered;
    }

    // ── P0-A: derive expected destination ATA (Phase J fix) ──
    // ATA is deterministic — `findAssociatedTokenAddress(owner, mint)`
    // behaves sync-like (PDA derive is just hash + a few bump iterations).
    // 0 RPC calls. Throws on invalid input pubkey → catch and return
    // rpcError (potentially malicious input, but not a chain-baked fact,
    // so retry is allowed for now).
    final String expectedAtaBase58;
    try {
      final ataPubkey = await sol.findAssociatedTokenAddress(
        owner: sol.Ed25519HDPublicKey.fromBase58(expectedRecipient),
        mint: sol.Ed25519HDPublicKey.fromBase58(expectedMint),
      );
      expectedAtaBase58 = ataPubkey.toBase58();
    } catch (e) {
      debugPrint('[TransferService] _verifySplTransfer: ATA derive failed '
          '(owner=$expectedRecipient mint=$expectedMint): $e');
      return VerificationResult.rpcError;
    }

    // ── 1 + 2 + 3: search spl-token transfer/transferChecked for an ix
    //              matching amount + destination at once ──
    // confirmed requires a single ix matching both. If one ix matches
    // amount only and another matches destination only, it's a forgery
    // (split tx) → check both fields on the same ix.
    bool sawAnyTokenIx = false;
    bool sawAmountMatch = false;
    bool sawDestMatch = false;
    bool fullyMatched = false;
    for (final ix in parsed.instructions) {
      if (ix is! sol_dto.ParsedInstructionSplToken) continue;
      sawAnyTokenIx = true;
      final inner = ix.parsed;
      String? rawAmount;
      String? destination;
      if (inner is sol_dto.ParsedSplTokenTransferInstruction) {
        rawAmount = inner.info.amount;
        destination = inner.info.destination;
      } else if (inner is sol_dto.ParsedSplTokenTransferCheckedInstruction) {
        rawAmount = inner.info.tokenAmount.amount;
        destination = inner.info.destination;
      }
      if (rawAmount == null || destination == null) continue;
      final ixAmount = BigInt.tryParse(rawAmount);
      if (ixAmount == null) continue;

      final amountOk = ixAmount == expectedAmount;
      final destOk = destination == expectedAtaBase58;
      if (amountOk) sawAmountMatch = true;
      if (destOk) sawDestMatch = true;
      if (amountOk && destOk) {
        fullyMatched = true;
        break;
      }
    }
    if (!fullyMatched) {
      // Diagnostic — log so it's clear which field mismatched.
      debugPrint('[TransferService] _verifySplTransfer: NOT fully matched '
          '(sawAnyTokenIx=$sawAnyTokenIx sawAmountMatch=$sawAmountMatch '
          'sawDestMatch=$sawDestMatch expectedAmount=$expectedAmount '
          'expectedAta=$expectedAtaBase58 expectedRecipient=$expectedRecipient)');
      return VerificationResult.fakeOrTampered;
    }

    // ── 4. extra mint verification (postTokenBalances / preTokenBalances) ──
    // transferChecked self-verifies mint inside the token program, but
    // post/pre balances mint matching adds an extra check for ix-forgery
    // vs balance consistency.
    final balances = <sol_dto.TokenBalance>[];
    if (meta?.postTokenBalances != null) {
      balances.addAll(meta!.postTokenBalances);
    }
    if (meta?.preTokenBalances != null) {
      balances.addAll(meta!.preTokenBalances);
    }
    final mintMatched = balances.any((b) => b.mint == expectedMint);
    if (!mintMatched) {
      debugPrint('[TransferService] _verifySplTransfer: mint mismatch '
          '(expected=$expectedMint balanceCount=${balances.length})');
      return VerificationResult.fakeOrTampered;
    }

    debugPrint('[TransferService] _verifySplTransfer: confirmed '
        '(amount=$expectedAmount mint=$expectedMint dest=$expectedAtaBase58 '
        'recipient=$expectedRecipient)');
    return VerificationResult.confirmed;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // P1-5 Ed25519 sign / verify (pinenacl)
  // ───────────────────────────────────────────────────────────────────────────

  /// Sign walletAddress (UTF-8 bytes) with this device's Signal Ed25519
  /// identity key → return base64. Throws if the signing seed is missing.
  String _signWalletAddress(String walletAddress) {
    final seed = _signal.signingKeySeed;
    if (seed == null) {
      throw StateError('signing seed unavailable — Signal not initialized');
    }
    // pinenacl 0.6.0 — `SigningKey({required Uint8List seed})` is the standard
    // ctor. No `ed.Seed` wrapper function — pass the 32-byte seed Uint8List
    // directly.
    final signingKey = ed.SigningKey(seed: Uint8List.fromList(seed));
    final signedMsg = signingKey.sign(
      Uint8List.fromList(utf8.encode(walletAddress)),
    );
    // SignedMessage.signature 64-byte
    return base64Encode(signedMsg.signature.toUint8List());
  }

  /// Verify walletAddress + sig using the peer's Signal Ed25519 verify key.
  ///
  /// **Phase F (2026-04-20)**: wired SignalSessionManager.getPeerEd25519PublicKey
  /// public helper — TOFU pin cache first + server prekey bundle fallback.
  /// Resolves the issue where the previous placeholder
  /// (`_resolvePeerEd25519` → returned null) made every response fail with
  /// sigInvalid.
  ///
  /// Verification steps:
  /// 1. Look up peer Ed25519 via SignalSessionManager.getPeerEd25519PublicKey
  /// 2. pinenacl `VerifyKey(ed25519).verify(signature, walletAddress.bytes)`
  /// 3. Any step failing → false (conservative fail-closed).
  Future<bool> _verifyWalletAddressSig({
    required String peerSnowId,
    required String walletAddress,
    required String walletAddressSigB64,
  }) async {
    try {
      final ed25519 = await _sessionManager.getPeerEd25519PublicKey(peerSnowId);
      if (ed25519 == null) {
        debugPrint('[TransferService] _verifyWalletAddressSig: no Ed25519 for '
            '$peerSnowId — cannot verify (treat as fail)');
        return false;
      }
      final verifyKey = ed.VerifyKey(Uint8List.fromList(ed25519));
      final sig = base64Decode(walletAddressSigB64);
      final ok = verifyKey.verify(
        signature: ed.Signature(Uint8List.fromList(sig)),
        message: Uint8List.fromList(utf8.encode(walletAddress)),
      );
      return ok;
    } catch (e) {
      debugPrint('[TransferService] _verifyWalletAddressSig error: $e');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Wire send helpers (4 type)
  // ───────────────────────────────────────────────────────────────────────────

  /// Encrypt payload (`{type: transfer_*, ...}`) via E2EE and send through a single socket.
  ///
  /// **If sealed sender is available**, use `sealed_message`, else
  /// `private_message`. Differs from regular chat sendEncryptedMessage:
  /// bypasses `_buildPayload`'s text/type structure — payload itself is the
  /// wire JSON. The recipient-side dispatcher branches on `payload['type']`.
  Future<void> _sendTransferControl({
    required String recipientSnowchatId,
    required Map<String, dynamic> payload,
  }) async {
    final mySnowId = _ref.read(currentSnowIdProvider);
    if (mySnowId == null) {
      throw StateError('TransferService: mySnowId not initialized');
    }

    // Step 1: ensure session
    await _sessionManager.ensureSession(recipientSnowchatId);

    // Step 2: encrypt
    final plaintext =
        Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final deviceId =
        await _sessionManager.getDeviceIdForRecipient(recipientSnowchatId);
    final encrypted = await _sessionManager.encrypt(
      recipientSnowchatId,
      deviceId,
      plaintext,
    );
    final ciphertext = encrypted['ciphertext'] as Uint8List;

    // Step 3: wire send.
    //
    // Sealed sender variant: spec §5.4 recommends Sealed Sender V2.
    // However, this Phase E lacks a public accessor on
    // EncryptedMessageHandler's SenderCertificate cache (a Phase F
    // deliverable), so the bypass path is undefined. Always uses plain
    // `private_message` — Double Ratchet alone provides full E2EE.
    // The sealed wrap activates this branch once Phase F adds
    // `getOrFetchSenderCertificate()` public on EncryptedMessageHandler.
    final clientMessageId = 'transfer_${_uuid.v4()}';
    _socketManager.sendPrivateMessage({
      'recipientId': recipientSnowchatId,
      'encryptedContent': base64Encode(ciphertext),
      'type': 'e2ee_text',
      'messageType': encrypted['messageType'] as int,
      'clientMessageId': clientMessageId,
    });
  }

  Future<void> _sendResponse({
    required String recipientSnowchatId,
    required String requestId,
    required bool accepted,
    String? walletAddress,
    String? walletAddressSig,
    bool? ataExists,
    int? ataRentLamports,
  }) async {
    final payload = TransferResponse(
      requestId: requestId,
      accepted: accepted,
      walletAddress: accepted ? walletAddress : null,
      walletAddressSig: accepted ? walletAddressSig : null,
      ataExists: ataExists,
      ataRentLamports: ataRentLamports,
    ).toJson();
    await _sendTransferControl(
      recipientSnowchatId: recipientSnowchatId,
      payload: payload,
    );
  }

  Future<void> _sendCompleted({
    required String recipientSnowchatId,
    required String requestId,
    required String txHash,
    required TransferCompletedStatus status,
  }) async {
    final payload = TransferCompleted(
      requestId: requestId,
      txHash: txHash,
      status: status,
    ).toJson();
    await _sendTransferControl(
      recipientSnowchatId: recipientSnowchatId,
      payload: payload,
    );
  }

  Future<void> _sendFailed({
    required String recipientSnowchatId,
    required String requestId,
    required FailureReason reason,
  }) async {
    final payload = TransferFailed(
      requestId: requestId,
      reason: reason,
    ).toJson();
    try {
      await _sendTransferControl(
        recipientSnowchatId: recipientSnowchatId,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[TransferService] _sendFailed wire error (ignore): $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────────

  /// Look up lamports keyed by mint (or 'SOL') in walletProvider's
  /// balance.tokens. 0 if missing.
  BigInt _readMyTokenBalance(String mintOrSol) {
    final bal = _ref.read(walletProvider).balance;
    if (bal == null) return BigInt.zero;
    for (final t in bal.tokens) {
      if (t.mint == mintOrSol) return t.balanceLamports;
    }
    return BigInt.zero;
  }

  /// FailureReason → user-facing English message.
  String _humanReason(FailureReason reason) {
    switch (reason) {
      case FailureReason.insufficientBalance:
        return 'insufficient balance';
      case FailureReason.rpcError:
        return 'network error';
      case FailureReason.userCancel:
        return 'cancelled';
      case FailureReason.networkMismatch:
        return 'network mismatch';
      case FailureReason.signatureInvalid:
        return 'signature invalid';
      case FailureReason.ataCreateFailed:
        return 'token account creation failed';
      case FailureReason.timeout:
        return 'timed out';
    }
  }

  String _truncateError(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}...' : s;
  }

  /// Truncate a Solana tx hash (Base58 ~88 chars) to 7 chars — for toast/UI.
  String _truncateTx(String txHash) {
    if (txHash.length <= 7) return txHash;
    return '${txHash.substring(0, 7)}...';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // System message commit (permanent) — handled by _TransferCompletedBubble in Phase G integration
  // ───────────────────────────────────────────────────────────────────────────

  /// Phase G — permanent system message for both sides. Branch sender/recipient
  /// via `direction`. `_TransferCompletedBubble` displays "Sent / Received"
  /// label + 7-char tx hash + Solana explorer link (per-network cluster) from
  /// metadata. No TTL (transaction record).
  Future<void> _commitTransferSystemMessage({
    required String peerSnowId,
    required String requestId,
    required String txHash,
    required String amount,
    required String token,
    required String? mint,
    required int decimals,
    required String direction, // 'sent' | 'received'
    required String network, // 'devnet' | 'mainnet'
  }) async {
    try {
      final conv = await _conversationDao.findDirectByParticipant(peerSnowId);
      if (conv == null) {
        debugPrint('[TransferService] commit: no conversation for $peerSnowId');
        return;
      }
      await _messageDao.insertLocalSystemMessage(
        conversationId: conv.id,
        // text is the fallback for environments without Phase G; the normal path uses _TransferCompletedBubble.
        text: direction == 'sent' ? 'Transfer sent' : 'Transfer received',
        eventType: 'transfer_completed',
        metadata: <String, dynamic>{
          'requestId': requestId,
          'txHash': txHash,
          'amount': amount,
          'token': token,
          // ignore: use_null_aware_elements — Dart 3.x lint suggests `?'mint':`
          // syntax but that targets nullable VALUES on non-nullable key spreads
          // — `'mint'` key is non-nullable while `mint` value can be null.
          // Conditional collection element is the correct idiom here.
          if (mint != null) 'mint': mint,
          'decimals': decimals,
          'direction': direction,
          'network': network,
        },
        // No TTL (kept permanently as transaction proof, spec §6.4).
      );
    } catch (e) {
      debugPrint('[TransferService] _commitTransferSystemMessage error: $e');
    }
  }

  Future<void> _commitPendingVerificationSystemMessage({
    required String peerSnowId,
    required String txHash,
  }) async {
    try {
      final conv = await _conversationDao.findDirectByParticipant(peerSnowId);
      if (conv == null) return;
      await _messageDao.insertLocalSystemMessage(
        conversationId: conv.id,
        text: 'Transfer pending verification',
        eventType: 'transfer_pending_verification',
        metadata: <String, dynamic>{'txHash': txHash},
        expiresInSeconds: 300, // Auto-cleanup after 5 minutes — Phase E3 retry cleans up.
      );
    } catch (e) {
      debugPrint('[TransferService] _commitPendingVerification error: $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Per-requestId 10-minute timer (P1-7) — service-owned
  // ───────────────────────────────────────────────────────────────────────────

  void _startExpiryTimer(String requestId, String peerSnowId) {
    _cancelExpiryTimer(requestId);
    _expiryTimers[requestId] = Timer(_kRequestExpiry, () async {
      _expiryTimers.remove(requestId);
      try {
        final row = await _pendingDao.findByRequestId(requestId);
        if (row == null) return;
        if (row.status != 'pending' && row.status != 'sent') return;

        debugPrint('[TransferService] expiry fire: $requestId (role=${row.role})');
        await _pendingDao.updateStatus(requestId, 'timeout');
        // Dismiss dialog (recipient side might still have dialog up)
        _dismissDialog(requestId);
        // Send transfer_failed (timeout) — V1 spec §4.4 promotion.
        await _sendFailed(
          recipientSnowchatId: peerSnowId,
          requestId: requestId,
          reason: FailureReason.timeout,
        );
      } catch (e) {
        debugPrint('[TransferService] expiry timer error: $e');
      }
    });
  }

  void _cancelExpiryTimer(String requestId) {
    final t = _expiryTimers.remove(requestId);
    t?.cancel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Riverpod Provider
// ─────────────────────────────────────────────────────────────────────────────

/// Wallet V2 Phase E + F — TransferService DI.
///
/// **Lifecycle**: single instance for app lifetime. `ref.onDispose` calls
/// service.dispose (cleans up timers + bus subscription).
///
/// **Phase F UI delegate wiring**:
/// - `showConfirmDialog`: invokes `showTransferConfirmDialog` with
///   rootNavigatorKey's currentContext → bottom sheet → returns
///   Future<bool?>. Looks up displayName from contact cache and passes it
///   to the dialog header.
/// - `showToast`: application-level SnackBar via rootScaffoldMessengerKey.
///   Requires a mounted Scaffold to display — safe fallback (debug log).
/// - `dismissDialog`: assumes the bottom sheet is the top of the stack and
///   pops via rootNavigator. Silent skip if stack is empty or another modal
///   is on top.
final transferServiceProvider = Provider<TransferService>((ref) {
  // Per-requestId dismiss key. Register on dialog display, lookup on
  // dismiss call. The bottom sheet itself does not expose a NavigatorState
  // handle — handled by a single pop(). Race where multiple dialogs nest
  // simultaneously is simplified to V1 (1:1 transfers only).
  final activeDialogIds = <String>{};

  final service = TransferService(
    ref: ref,
    eventBus: ref.read(transferEventBusProvider),
    pendingDao: ref.read(snowDatabaseProvider).pendingTransferDao,
    e2eeHandler: ref.read(encryptedMessageHandlerProvider),
    rpcClient: ref.read(rpcClientProvider),
    signal: ref.read(signalProtocolServiceProvider),
    sessionManager: ref.read(signalSessionManagerProvider),
    socketManager: ref.read(socketManagerProvider),
    messageDao: ref.read(messageDaoProvider),
    conversationDao: ref.read(conversationDaoProvider),
    showConfirmDialog: (event) async {
      final navState = rootNavigatorKey.currentState;
      final ctx = rootNavigatorKey.currentContext;
      if (navState == null || ctx == null) {
        // Phase J P1-B: rootNavigator not ready (background / screen lock
        // / VoIP incoming call etc.) — throw _DialogMountFailed → service
        // keeps row 'pending' + recoverPendingDialogs re-displays on next
        // foreground return.
        // Previously returned null → service auto-sent user_cancel = a
        // request the user never saw was being declined (no asset-loss
        // risk, but a UX regression).
        debugPrint('[TransferService] showConfirmDialog: rootNavigator not '
            'mounted — throw _DialogMountFailed for ${event.payload.requestId}');
        throw const _DialogMountFailed();
      }
      // Look up displayName from the contact cache (1:1 send already
      // requires contact registration, but ensures the latest nickname).
      String? displayName;
      try {
        final contacts = ref.read(contactProvider);
        final found = contacts
            .where((c) => c.snowChatId == event.fromSnowchatId)
            .firstOrNull;
        if (found?.displayName != null && found!.displayName!.isNotEmpty) {
          displayName = found.displayName;
        }
      } catch (e) {
        debugPrint('[TransferService] showConfirmDialog contact lookup '
            'failed (non-fatal): $e');
      }
      activeDialogIds.add(event.payload.requestId);
      try {
        return await showTransferConfirmDialog(
          ctx,
          fromSnowchatId: event.fromSnowchatId,
          fromDisplayName: displayName,
          request: event.payload,
        );
      } finally {
        activeDialogIds.remove(event.payload.requestId);
      }
    },
    showToast: (msg) {
      final messenger = rootScaffoldMessengerKey.currentState;
      if (messenger == null) {
        debugPrint('[TransferService] showToast: messenger not mounted — '
            'drop "$msg"');
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    },
    dismissDialog: (requestId) {
      // Pop only when the dialog is active. (race: timer fires after the
      // dialog has already closed via user input — in that case
      // activeDialogIds is cleaned up so we skip.)
      if (!activeDialogIds.contains(requestId)) return;
      final navState = rootNavigatorKey.currentState;
      if (navState == null) return;
      try {
        // Assume the bottom sheet is at the top of the stack. Pop only
        // when canPop=true. pop(null) → showModalBottomSheet's
        // Future<bool?> resolves null → same branch as caller's timeout
        // handling.
        if (navState.canPop()) {
          navState.pop<bool?>(null);
        }
      } catch (e) {
        debugPrint('[TransferService] dismissDialog pop failed: $e');
      } finally {
        activeDialogIds.remove(requestId);
      }
    },
  );
  ref.onDispose(() => service.dispose());
  return service;
});

// ─────────────────────────────────────────────────────────────────────────────
// PendingTransferDao Provider (add if missing)
// ─────────────────────────────────────────────────────────────────────────────

/// Phase E — drift `pending_transfers` DAO Provider. Accessed via
/// snowDatabaseProvider for a single instance (owned by the database).
final pendingTransferDaoProvider = Provider<PendingTransferDao>((ref) {
  return ref.read(snowDatabaseProvider).pendingTransferDao;
});
