/// @file        message_queue.dart
/// @description Phase 6 — Single serial processing queue for ALL incoming messages
///              (1:1, group, SKDM, system). Eliminates race conditions by ensuring
///              every message goes through one worker, in order, with atomic state mutation.
///              ACKs the server only after successful processing.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-05-14 (sealed routing 정공법: decrypted.conversationId is the sender's server-CUID — meaningless to the receiver and the source of phantom rows when both canonical + foreign-id rows coexist post-dedupe. Stop trusting it; always resolve by findDirectByParticipant, deterministic snow-id fallback when no row yet.)
///
/// @functions
///  - MessageQueue: Single-worker FIFO queue for incoming message envelopes
///  - enqueue(envelope): Add an envelope to the queue (called by GlobalMessageRouter)
///  - fetchPending(): Pull all pending+delivered messages from server queue and enqueue
///  - _processNext(): Worker loop — drains queue serially
///  - _processOne(envelope): Dispatch a single envelope by type
///  - _processPrivate1to1(envelope): Decrypt 1:1 e2ee_text via Double Ratchet
///  - _processSKDM(envelope): Decrypt 1:1 SKDM and install into SenderKeyManager
///  - _processGroupMessage(envelope): Decrypt group Sender Key payload
///  - _processGroupMetadataKey(envelope): Decrypt + store incoming GMK (Phase 8.8)
///  - _processSealedMessage(envelope): Sealed Sender unseal + DR decrypt → drift insert
///  - _processSystem(envelope): Insert server-generated system message
///  - _processIncomingAttachments(): Insert attachment rows + trigger encrypted-blob download
///  - _downloadAttachment(): Download + decrypt + persist a single file attachment
///  - _insertDecryptionFailedPlaceholder(): insert placeholder row on dead-letter (required before ACK)
///  - _emitRetryRequest(): emit retry request socket event after dead-letter (1:1, group, sealed branches)
///  - _enqueueAck(messageId): Buffer ACK for batch send
///  - _flushAcks(): Flush pending ACKs to server (debounced)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:path_provider/path_provider.dart';

import '../../features/chat/models/message.dart' show Message, MessageType;
import '../../features/chat/providers/expiring_message_manager.dart';
import '../../features/chat/providers/mark_read_helper.dart';
import '../crypto/encrypted_message_handler.dart';
import '../crypto/file_encryptor.dart';
import '../crypto/group_metadata_crypto.dart';
import '../crypto/identity_change_handler.dart';
import '../crypto/identity_key_changed_exception.dart';
import '../crypto/sender_key.dart' show SenderKeyDistributionMessage;
import '../crypto/signal_session_manager.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/file_service.dart';
import '../network/socket_manager.dart';
import '../notifications/notification_service.dart';
import '../storage/daos/attachment_dao.dart';
import '../storage/daos/conversation_dao.dart';
import '../storage/daos/message_dao.dart';
import '../storage/database.dart';
import '../storage/tables/attachments_table.dart';
import '../../shared/services/message_banner_service.dart';
import '../../shared/widgets/message_banner.dart';

/// Type alias for the message envelope JSON map.
typedef Envelope = Map<String, dynamic>;

/// Thrown when a group message can't be decrypted because the sender's
/// SKDM hasn't arrived yet. The queue holds these in [_pendingSKDM] until
/// the SKDM arrives via [_processSKDM]; they're never dead-lettered.
class _AwaitingSKDMException implements Exception {
  final String groupId;
  final String senderSnow;
  _AwaitingSKDMException(this.groupId, this.senderSnow);
}

class _QueuedItem {
  final Envelope envelope;
  final DateTime enqueuedAt;
  int retryCount;

  /// Tracks how many times this item has been through the "remove SKDM →
  /// re-request SKDM → park → drain" cycle in [_processGroupMessage].
  /// HMAC chain ratchet is one-way: if the sender's chain has advanced past
  /// the message's iteration, no fresh SKDM will ever help decrypt it.
  /// After [_maxSkdmRetries] cycles, give up and insert a placeholder.
  int skdmRetryCount;
  _QueuedItem(this.envelope, this.enqueuedAt)
      : retryCount = 0,
        skdmRetryCount = 0;
}

class MessageQueue {
  final SignalSessionManager _sessionMgr;
  final EncryptedMessageHandler _e2eeHandler;
  final MessageDao _messageDao;
  final ConversationDao _conversationDao;
  final AttachmentDao _attachmentDao;

  /// Phase 8.8: Called when a GMK is received and stored.
  /// Allows conversation list to refresh group names.
  void Function(String groupId)? onGmkReceived;

  /// Called when MessageQueue creates a new conversation in drift.
  /// ConversationListNotifier subscribes to merge it into in-memory state.
  void Function(String convId, String senderSnowId)? onNewConversation;

  /// Called after a Sealed Sender message has been unsealed and inserted
  /// into drift. The wire-level envelope hides the sender (zero-knowledge),
  /// so the live socket listener in ConversationListNotifier skips sealed
  /// envelopes ("SKIP own/null sender=null"). Without this callback the
  /// in-memory list never increments unread or refreshes the last-message
  /// preview for the remapped conversation. ConversationListNotifier wires
  /// this and runs the same UPDATE branch that non-sealed messages get.
  void Function(
    String convId,
    String senderSnowId,
    String preview,
    DateTime msgTime,
  )? onSealedMessageDecoded;
  final FileService _fileService;
  final ExpiringMessageManager _expiringManager;
  final ApiClient _apiClient;
  final SocketManager _socketManager;
  final String Function() _myIdResolver;

  /// Optional handler for IdentityKeyChangedException routing. When wired,
  /// ratchet failures caused by a TOFU key change get the dedicated Safety
  /// Number pipeline (recompute, latch in IdentityVerificationDao, system
  /// message) instead of the generic placeholder + retry-request flow.
  IdentityChangeHandler? identityChangeHandler;

  /// FIFO queue of pending envelopes.
  final List<_QueuedItem> _queue = [];

  /// Group messages waiting for an SKDM. Keyed by "groupId:senderSnow".
  /// Drained when the matching SKDM is installed via [_processSKDM].
  /// Never dead-lettered — they wait indefinitely until the SKDM arrives or
  /// the user navigates away.
  final Map<String, List<_QueuedItem>> _pendingSKDM = {};

  /// Worker is currently draining the queue.
  bool _processing = false;

  /// Completes when the worker transitions from draining → idle. Created
  /// lazily in [_kickWorker]; resolved in [_drain]'s finally block. Used
  /// by [waitForIdle] so callers (e.g. ConversationListNotifier) can know
  /// when all enqueued messages have been processed and conversation rows
  /// have landed in drift.
  Completer<void>? _idleCompleter;

  /// Pending ACK message IDs (batched).
  final List<String> _pendingAcks = [];
  Timer? _ackFlushTimer;

  /// Debounce window for ACK flushing.
  ///
  /// Phase 8.7 round 3: shortened from 500ms → 50ms. The longer window was
  /// designed to coalesce ACKs for batch processing throughput, but it also
  /// widened the failure window between drift commit and the network ACK
  /// being on the wire. With drift now running synchronous=FULL the commit
  /// itself dominates the latency budget, so we can afford a tighter
  /// debounce. The flush is also called explicitly by [_drain] after the
  /// queue empties (see _kickWorker / fetchPending paths) so even this
  /// short timer is just a safety net.
  static const Duration _ackFlushDelay = Duration(milliseconds: 50);

  /// Maximum retries before dropping a message (dead letter).
  /// Only applies to actual decryption errors — NOT to messages waiting for
  /// SKDM, which are held indefinitely in [_pendingSKDM].
  static const int _maxRetries = 5;

  /// Maximum SKDM re-request cycles before giving up on a group message.
  /// HMAC chain ratchet is one-way: if the sender's chain advanced past the
  /// message's iteration (e.g. iter=0 message but sender is now at iter=2),
  /// getExistingSKDM() returns the current state and no fresh SKDM will ever
  /// recover the old message key. After this many cycles, insert a placeholder
  /// and ACK to prevent an infinite CPU-burning loop.
  static const int _maxSkdmRetries = 2;

  /// Backoff intervals between retries (cumulative).
  static const List<Duration> _retryBackoff = [
    Duration(milliseconds: 200),
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 20),
  ];

  /// Set of message IDs that failed [_maxRetries] times — dropped to prevent
  /// infinite loops. They will not be re-processed in this session.
  final Set<String> _deadLetters = {};

  /// 2026-05-04 — Signal-style VoIP signaling persistence (Phase 8.2).
  /// Server enqueues mid-call sealed envelopes (call_answer / rtc_answer /
  /// ICE / call_end) into MessageQueue with metadata.voip=true when the
  /// recipient is offline. On reconnect-fetch, [_processSealedMessage]
  /// surfaces these via this callback to CallSignaling.injectEnvelope —
  /// reusing the existing Sealed Sender unseal + DR decrypt pipeline so
  /// CallService state machine sees the same events as the live socket
  /// path. Without this hook, mid-call signaling to a briefly-offline
  /// peer is permanently lost (user report 2026-05-04: outgoing iPhone
  /// disconnects during long-idle Galaxy cold launch → Galaxy's
  /// call_answer never reaches iPhone → infinite ringback).
  final Future<void> Function(String envelopeBase64)? injectVoipEnvelope;

  MessageQueue({
    required SignalSessionManager sessionManager,
    required EncryptedMessageHandler e2eeHandler,
    required MessageDao messageDao,
    required ConversationDao conversationDao,
    required AttachmentDao attachmentDao,
    required FileService fileService,
    required ExpiringMessageManager expiringManager,
    required SnowDatabase database, // reserved for future cross-table txns
    required ApiClient apiClient,
    required SocketManager socketManager,
    required String Function() myIdResolver,
    this.injectVoipEnvelope,
  })  : _sessionMgr = sessionManager,
        _e2eeHandler = e2eeHandler,
        _messageDao = messageDao,
        _conversationDao = conversationDao,
        _attachmentDao = attachmentDao,
        _fileService = fileService,
        _expiringManager = expiringManager,
        _apiClient = apiClient,
        _socketManager = socketManager,
        _myIdResolver = myIdResolver {
    // Phase 8.7 Bug E: drain parked SKDM queue when the server reports
    // that the upstream sender is offline.
    _senderKeyRequestFailedSub = _socketManager.onSenderKeyRequestFailed
        .listen(_handleSenderKeyRequestFailed);
  }

  StreamSubscription<Map<String, dynamic>>? _senderKeyRequestFailedSub;
  // Phase 8.7 Bug E: dedupe system messages so a single offline sender does
  // not produce one banner per parked envelope.
  final Set<String> _offlineSenderNotified = <String>{};

  /// Current queue depth (for diagnostics / backpressure).
  int get depth => _queue.length;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Enqueue an envelope. Called by GlobalMessageRouter for socket events
  /// and by [fetchPending] for REST API results.
  void enqueue(Envelope envelope) {
    final messageId = (envelope['id'] ?? envelope['messageId']) as String?;
    if (messageId == null) {
      debugPrint('[DIAG:Queue] enqueue REJECTED: missing id, '
          'envelope keys=${envelope.keys.toList()}');
      return;
    }
    if (_deadLetters.contains(messageId)) {
      debugPrint('[DIAG:Queue] enqueue REJECTED: dead letter $messageId');
      return;
    }
    // Dedup: skip if already queued (prevents fetchPending race re-enqueue).
    if (_queue.any((q) =>
        (q.envelope['id'] ?? q.envelope['messageId']) == messageId)) {
      debugPrint('[DIAG:Queue] enqueue REJECTED: already queued $messageId');
      return;
    }
    _queue.add(_QueuedItem(envelope, DateTime.now()));
    debugPrint('[DIAG:Queue] enqueued $messageId '
        '(type=${envelope['type']} depth=${_queue.length})');
    _kickWorker();
  }

  /// Guard: prevent concurrent fetchPending calls. The second caller awaits
  /// the in-flight fetch instead of issuing a duplicate REST request that
  /// returns the same un-ACK'd messages and double-enqueues them.
  bool _fetchingPending = false;

  /// Fetch all pending+delivered messages from the server queue and enqueue them.
  /// Called on app start, socket reconnect, and chat re-entry.
  Future<void> fetchPending() async {
    if (_fetchingPending) {
      debugPrint('[DIAG:Queue] fetchPending: SKIPPED (already in progress)');
      return;
    }
    _fetchingPending = true;
    try {
      debugPrint('[DIAG:Queue] fetchPending: starting REST fetch');
      final response = await _apiClient.get(ApiEndpoints.fetchMessages);
      final data = response.data;
      if (data is! Map || data['messages'] is! List) {
        debugPrint('[DIAG:Queue] fetchPending: empty/malformed response');
        return;
      }

      final list = (data['messages'] as List)
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();

      // Server returns ASC order, but enforce defensively.
      list.sort((a, b) {
        final ta = DateTime.tryParse(
                (a['serverTimestamp'] ?? a['timestamp'] ?? '') as String? ??
                    '') ??
            DateTime(1970);
        final tb = DateTime.tryParse(
                (b['serverTimestamp'] ?? b['timestamp'] ?? '') as String? ??
                    '') ??
            DateTime(1970);
        return ta.compareTo(tb);
      });

      debugPrint('[DIAG:Queue] fetchPending: server returned ${list.length} messages');
      for (final env in list) {
        final id = env['id'] ?? env['messageId'];
        final type = env['type'];
        final groupChatId = env['groupChatId'];
        final convId = env['conversationId'];
        debugPrint('[DIAG:Queue] fetchPending: re-enqueuing $id '
            'type=$type groupChatId=$groupChatId convId=$convId');
        enqueue(env);
      }
      // Wait for the worker to finish processing the just-enqueued items
      // so that callers can read drift state immediately after.
      await waitForIdle();
      debugPrint('[DIAG:Queue] fetchPending: completed (worker idle)');
    } catch (e) {
      debugPrint('[DIAG:Queue] fetchPending FAILED: $e');
    } finally {
      _fetchingPending = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Worker
  // ---------------------------------------------------------------------------

  void _kickWorker() {
    if (_processing) return;
    _processing = true;
    _idleCompleter ??= Completer<void>();
    // Detach from current call stack so the caller's await chain doesn't
    // wait for queue drain.
    Future(() => _drain());
  }

  /// Returns a Future that completes once the worker has drained any
  /// currently-queued items. If the queue is already idle, completes
  /// immediately. Used by callers that need to read from drift AFTER
  /// fetchPending's results have been processed.
  Future<void> waitForIdle() {
    if (!_processing && _queue.isEmpty) return Future.value();
    _idleCompleter ??= Completer<void>();
    return _idleCompleter!.future;
  }

  /// Phase X (2026-04-26) — show top in-app banner when an incoming
  /// message belongs to a conversation the user is NOT actively viewing.
  /// Mirrors Signal/WhatsApp behaviour. Active conversation → silent
  /// (caller's `isViewing` flag is the same MarkReadHelper check the
  /// banner service repeats internally — no double check, just signature
  /// passthrough). Empty plaintext (system / metadata-only) → skip.
  void _maybeShowMessageBanner({
    required bool isViewing,
    required String conversationId,
    required String senderId,
    required String? plaintext,
  }) {
    if (isViewing) return;
    final preview = (plaintext ?? '').replaceAll('\n', ' ').trim();
    if (preview.isEmpty) return;
    MessageBannerService.instance.maybeShow(
      BannerMessageData(
        conversationId: conversationId,
        senderName: senderId, // MVP: snow id; contact name lookup later
        preview: preview,
        snowId: senderId,
      ),
    );
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        final messageId = (item.envelope['id'] ?? item.envelope['messageId'])
            as String?;
        if (messageId == null) continue;

        try {
          await _processOne(item.envelope);
          // Phase 8.7 round 3 — ack/drift atomicity guarantee:
          // 1. _processOne has fully awaited drift insert + commit. Drift now
          //    runs under PRAGMA synchronous=FULL + journal_mode=WAL, so the
          //    commit() return guarantees the row is fsync'd to disk.
          // 2. Defensively re-read the row before acking. If the read miss
          //    (row absent / different id), we treat it as a processing
          //    failure and let the retry path handle it instead of acking
          //    a phantom message — protects against drift schema mismatches
          //    or partial writes that survived synchronous=FULL.
          // 3. Only after the verify do we enqueue the ack.
          final type = (item.envelope['type'] ?? '') as String;
          // Control messages (SKDM, GMK) and consumed SESSION_RESETs don't
          // land in localMessages. Skip drift-verify and ACK directly.
          final isControl = type == 'sender_key_distribution' ||
              type == 'group_metadata_key' ||
              item.envelope['_sessionResetConsumed'] == true;
          if (!isControl) {
            final committed = await _messageDao.getMessageById(messageId);
            if (committed == null) {
              throw StateError(
                'drift commit verify FAILED for $messageId — row absent '
                'after _processOne returned. Refusing to ack; will retry.',
              );
            }
          }
          _enqueueAck(messageId);
          debugPrint('[DIAG:Queue] $messageId PROCESSED OK (type=$type)');
        } on _AwaitingSKDMException catch (await_) {
          // Hold the message until the matching SKDM arrives. Do NOT ACK,
          // do NOT increment retry count. The server will keep the row in
          // 'delivered' state until we ACK it.
          //
          // However, cap the SKDM re-request cycle to prevent infinite loops
          // (e.g. corrupt SKDM that keeps failing after re-request because
          // getExistingSKDM returns the same broken state).
          item.skdmRetryCount++;
          if (item.skdmRetryCount > _maxSkdmRetries) {
            debugPrint('[DIAG:Queue] $messageId SKDM retry limit exceeded '
                '(${item.skdmRetryCount} > $_maxSkdmRetries) — dead-lettering');
            _deadLetters.add(messageId);
            await _insertDecryptionFailedPlaceholder(
              item.envelope,
              messageId,
              'skdm_retry_exhausted',
            );
            _enqueueAck(messageId);
            continue;
          }
          final key = '${await_.groupId}:${await_.senderSnow}';
          _pendingSKDM.putIfAbsent(key, () => []).add(item);
          debugPrint('[DIAG:Queue] $messageId PARKED waiting for SKDM '
              '${await_.senderSnow}@${await_.groupId} '
              '(${_pendingSKDM[key]!.length} pending, '
              'skdmRetry=${item.skdmRetryCount}/$_maxSkdmRetries)');
        } on IdentityKeyChangedException catch (idChange) {
          // P0-2 Stage B: a TOFU key change must NOT trigger
          // archiveAndResetSession nor a retry request. The peer's identity
          // is in dispute — silently re-handshaking would erase the warning
          // and let an attacker continue the session under the new key.
          // Instead: route to IdentityChangeHandler (recompute Safety Number,
          // latch in IdentityVerificationDao, insert "key changed" system
          // message) and ACK so the server stops re-delivering.
          _deadLetters.add(messageId);
          final convId = (item.envelope['conversationId'] ??
              idChange.peerSnowchatId) as String?;
          final handler = identityChangeHandler;
          if (handler != null) {
            try {
              await handler.handleMismatch(
                peerSnowchatId: idChange.peerSnowchatId,
                conversationId: convId,
                oldKey: idChange.expectedKey,
                newKey: idChange.actualKey,
              );
            } catch (handlerErr) {
              debugPrint('[DIAG:Queue] $messageId identityChangeHandler '
                  'FAILED: $handlerErr');
            }
          } else {
            debugPrint('[DIAG:Queue] $messageId identity key changed for '
                '${idChange.peerSnowchatId} but no handler wired — '
                'ACK only');
          }
          _enqueueAck(messageId);
        } catch (e, st) {
          item.retryCount++;
          // Phase 8.7 Bug C: detect 1:1 ratchet corruption and trigger an
          // automatic session reset on the second retry. The error string
          // we look for ("could decrypt the message") is what
          // SignalProtocolService.decryptMessage emits when every stored
          // session entry has tried and failed — meaning local ratchet
          // state has diverged from the peer.
          final errStr = e.toString();
          final isRatchetCorruption =
              errStr.contains('could decrypt the message');
          if (isRatchetCorruption && item.retryCount == 2) {
            final senderSnow = (item.envelope['senderSnowchatId'] ??
                item.envelope['senderId']) as String?;
            if (senderSnow != null && senderSnow.isNotEmpty) {
              debugPrint('[DIAG:Queue] $messageId ratchet corruption '
                  'detected for $senderSnow → triggering session reset');
              // Fire-and-forget reset; the next retry attempt will hit a
              // freshly established X3DH session.
              unawaited(_sessionMgr.resetSession(senderSnow).catchError((err) {
                debugPrint('[DIAG:Queue] $messageId session reset FAILED: $err');
              }));
            }
          }
          if (item.retryCount >= _maxRetries) {
            debugPrint('[DIAG:Queue] $messageId DEAD LETTER after '
                '$_maxRetries retries: $e');
            _deadLetters.add(messageId);

            // Control messages (SKDM, GMK) are invisible to the user.
            // Do NOT create placeholder conversations or emit retry requests
            // for them — just ACK so the server stops re-delivering.
            final deadType = (item.envelope['type'] ?? '') as String;
            final isControlMsg = deadType == 'sender_key_distribution' ||
                deadType == 'group_metadata_key';
            // Session corruption ("forged or malformed", "shared secret")
            // is unrecoverable — retry request would trigger a pairwise
            // fallback that also fails, creating phantom conversations.
            final isSessionCorruption = errStr.contains('forged') ||
                errStr.contains('malformed') ||
                errStr.contains('shared secret');

            if (!isControlMsg) {
              // Phase 10 P0-B: Insert placeholder row BEFORE ACK.
              await _insertDecryptionFailedPlaceholder(
                item.envelope,
                messageId,
                errStr,
              );
              // Phase 10 P0-D: Emit retry request — but SKIP for session
              // corruption (unrecoverable; pairwise fallback would also fail).
              if (!isSessionCorruption) {
                await _emitRetryRequest(item.envelope, messageId, errStr);
              } else {
                debugPrint('[DIAG:Queue] $messageId session corruption '
                    '— skip retry request (pairwise would also fail)');
              }
            } else {
              debugPrint('[DIAG:Queue] $messageId control message ($deadType) '
                  '— skip placeholder/retry, ACK only');
            }
            // ACK so the server stops re-delivering it.
            _enqueueAck(messageId);
          } else {
            final delay = _retryBackoff[item.retryCount - 1];
            debugPrint('[DIAG:Queue] $messageId RETRY in '
                '${delay.inMilliseconds}ms (attempt ${item.retryCount}): $e');
            // Schedule a delayed re-enqueue. Use a Timer instead of awaiting
            // here so the worker can continue processing other items.
            Timer(delay, () {
              if (_deadLetters.contains(messageId)) return;
              _queue.add(item);
              _kickWorker();
            });
            // Suppress unused stack trace warning
            // ignore: unused_local_variable
            final _ = st;
          }
        }
      }
    } finally {
      _processing = false;
      // Phase 8.7 round 3: every drain → ack burst is forced through the
      // wire immediately. The 50ms debounce timer is only a safety net for
      // single-message bursts; the common case (fetchPending batch on
      // reconnect) flushes synchronously here so the server learns about
      // every committed drift row before any subsequent process kill can
      // strand them as 'delivered' on the server with no client copy.
      flushAcks();
      // Resolve any pending idle waiters now that the worker is done.
      final completer = _idleCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      _idleCompleter = null;
    }
  }

  /// Phase 8.7 Bug E: server told us the SKDM source is offline. Drain the
  /// parked queue for that (groupId, senderSnowchatId) pair into the dead-
  /// letter set so we stop looping forever, ack the envelopes back to the
  /// server, and surface a single user-visible system message per pair.
  Future<void> _handleSenderKeyRequestFailed(Map<String, dynamic> data) async {
    final groupId = data['groupId'] as String?;
    final senderSnow = data['senderSnowchatId'] as String?;
    if (groupId == null || senderSnow == null) return;
    final key = '$groupId:$senderSnow';
    final waiting = _pendingSKDM.remove(key);
    if (waiting == null || waiting.isEmpty) {
      debugPrint('[DIAG:Queue] sender_key_request_failed for $key '
          '(no parked envelopes)');
      return;
    }
    debugPrint('[DIAG:Queue] sender_key_request_failed: dropping '
        '${waiting.length} parked msg(s) for $key (sender offline)');
    for (final item in waiting) {
      final messageId =
          (item.envelope['id'] ?? item.envelope['messageId']) as String?;
      if (messageId == null) continue;
      _deadLetters.add(messageId);
      // Phase 10 P0-B: Insert placeholder row BEFORE ACK (same guarantee
      // as the main dead-letter path — ACK deletes the server copy).
      await _insertDecryptionFailedPlaceholder(
        item.envelope,
        messageId,
        'sender_offline',
      );
      // Phase 10 P0-D: Emit group retry request for offline sender messages.
      await _emitRetryRequest(item.envelope, messageId, 'sender_offline');
      // Ack to the server so it stops re-delivering on reconnect.
      if (_socketManager.isConnected) {
        _socketManager.sendMessageAck([messageId]);
      }
    }
    // Dedupe system message: one per (groupId, senderSnow) lifetime.
    if (_offlineSenderNotified.add(key)) {
      // TODO(Phase 8.7): inject a system message row into the conversation
      // so the user sees "N messages from <sender> could not be decrypted
      // (sender offline)". Hook into ConversationDao when the UI surface
      // for system messages is finalized.
      debugPrint('[DIAG:Queue] system message hint for $key '
          '(${waiting.length} undelivered)');
    }
  }

  /// Drain all messages waiting for an SKDM from this sender in this group.
  /// Called by [_processSKDM] after a fresh SKDM is installed.
  void _drainPendingSKDM(String groupId, String senderSnow) {
    final key = '$groupId:$senderSnow';
    final waiting = _pendingSKDM.remove(key);
    if (waiting == null || waiting.isEmpty) return;
    debugPrint('[DIAG:SKDM] DRAIN ${waiting.length} parked msgs for '
        '$senderSnow@$groupId');
    // Reset retry count since the blocker is now resolved.
    // Note: skdmRetryCount is NOT reset — it tracks the cumulative number of
    // park/drain cycles. If the fresh SKDM still can't decrypt, the counter
    // will hit _maxSkdmRetries and break the loop.
    for (final item in waiting) {
      item.retryCount = 0;
    }
    _queue.insertAll(0, waiting);
    _kickWorker();
  }

  // ---------------------------------------------------------------------------
  // Dispatch
  // ---------------------------------------------------------------------------

  Future<void> _processOne(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    final type = (envelope['type'] ?? 'e2ee_text') as String;
    final senderSnow = (envelope['senderSnowchatId'] ?? envelope['senderId'])
        as String?;

    // Skip own messages echoed back.
    final myId = _myIdResolver();
    if (senderSnow != null && senderSnow == myId) {
      debugPrint('[DIAG:Queue] $messageId SKIP (own echo from=$senderSnow myId=$myId)');
      return;
    }

    // Dedup BEFORE decryption — same message via socket + REST fetch must
    // not consume two ratchet steps.
    final existing = await _messageDao.getMessageById(messageId);
    if (existing != null) {
      debugPrint('[DIAG:Queue] $messageId DEDUP (already in drift)');
      return;
    }

    // Also dedup against pending SKDM holding queue (msg arrived twice
    // before its SKDM was installed).
    //
    // Phase 8.7 round 3: a plain `return` here used to short-circuit
    // _processOne and the caller (_drain) would then run the new
    // verify-after-commit check, which fails because the row is still
    // sitting in _pendingSKDM (never inserted into drift). The whole
    // message would then dead-letter even though it was simply waiting
    // on the SKDM. Drop the parked envelope silently and re-throw the
    // existing _AwaitingSKDMException so _drain re-parks it under the
    // same key (the existing entry is already there, so the new add is
    // either dedup-on-id or the existing copy stays — both are safe).
    for (final entry in _pendingSKDM.entries) {
      if (entry.value.any(
          (q) => (q.envelope['id'] ?? q.envelope['messageId']) == messageId)) {
        debugPrint('[DIAG:Queue] $messageId DEDUP (already pending SKDM)');
        final colon = entry.key.indexOf(':');
        throw _AwaitingSKDMException(
          entry.key.substring(0, colon),
          entry.key.substring(colon + 1),
        );
      }
    }

    debugPrint('[DIAG:Queue] $messageId dispatching to handler type=$type');
    switch (type) {
      case 'sender_key_distribution':
        await _processSKDM(envelope);
        break;
      case 'sender_key':
        await _processGroupMessage(envelope);
        break;
      case 'group_metadata_key':
        await _processGroupMetadataKey(envelope);
        break;
      case 'sealed':
        await _processSealedMessage(envelope);
        break;
      case 'system':
        await _processSystem(envelope);
        break;
      case 'session_reset':
      case 'e2ee_text':
      default:
        await _processPrivate1to1(envelope);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Type handlers
  // ---------------------------------------------------------------------------

  Future<void> _processPrivate1to1(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    final senderSnow = (envelope['senderSnowchatId'] ?? envelope['senderId'])
        as String;
    final convId = envelope['conversationId'] as String? ?? senderSnow;

    debugPrint('[DIAG:1to1] $messageId start: from=$senderSnow convId=$convId');
    final decrypted = await _e2eeHandler.decryptIncomingMessage(envelope);
    debugPrint('[DIAG:1to1] $messageId decrypted (type=${decrypted.type.name})');

    // Phase 10 P1-A: Silently consume session_reset notifications.
    // The peer sent this after archiveAndResetSession() to establish the new
    // session on our side. The prekey message processing already advanced our
    // ratchet — no drift insert needed.
    if (decrypted.metadata != null &&
        decrypted.metadata!['isSessionReset'] == true) {
      debugPrint('[DIAG:1to1] $messageId SESSION_RESET from $senderSnow — consumed silently');
      // ACK directly — no drift row, so verify check would fail.
      _enqueueAck(messageId);
      // Throw a sentinel so _drain skips the verify-after-commit block.
      // Using _AwaitingSKDMException is wrong here; instead just return
      // after ACK and mark the envelope type so the caller knows.
      // Simplest: set a flag on the envelope that _drain checks.
      envelope['_sessionResetConsumed'] = true;
      return;
    }

    // Wallet V2 Phase B (D2 P0-1 fix): skip transfer control messages.
    // EncryptedMessageHandler's transfer_* dispatcher already emitted to TransferEventBus.
    // No drift insert (avoids empty system bubble + last preview / unread badge noise).
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isTransferControl'] == true) {
      debugPrint('[DIAG:1to1] $messageId TRANSFER_CONTROL from $senderSnow — drift skip');
      _enqueueAck(messageId);
      envelope['_sessionResetConsumed'] = true;
      return;
    }

    // Phase 10 P0-F: Check if this is a retry response from the original sender.
    // If so, try to update the existing placeholder row instead of inserting
    // a new message. The originalMessageId matches the placeholder's row ID.
    if (decrypted.metadata != null &&
        decrypted.metadata!['isRetry'] == true) {
      final originalId =
          decrypted.metadata!['originalMessageId'] as String?;
      if (originalId != null) {
        final updated = await _messageDao.updatePlaceholder(
          originalId,
          decrypted.plaintext,
          decrypted.type.name,
        );
        if (updated) {
          debugPrint('[DIAG:1to1] $messageId RETRY resolved placeholder '
              '$originalId');
          return;
        }
        // Placeholder not found — fall through to normal insert path.
        debugPrint('[DIAG:1to1] $messageId RETRY no placeholder for '
            '$originalId, inserting as new');
      }
    }

    final tsStr = (envelope['serverTimestamp'] ?? envelope['createdAt']) as String?;
    final timestamp =
        tsStr != null ? DateTime.parse(tsStr) : DateTime.now();
    final ttl = decrypted.ttlSeconds;

    // Ensure the conversation row exists in drift before inserting the
    // message. Without this, offline-recovered messages for brand-new 1:1
    // conversations end up as orphan rows in localMessages and the
    // ConversationListNotifier never sees them — the user can't tell a
    // message even arrived. The live socket path
    // (conversation_list_provider._listenForIncomingMessages) handles this
    // for online deliveries, but REST fetchPending bypasses that listener.
    final myId = _myIdResolver();
    await _conversationDao.findOrCreate(
      id: convId,
      type: 'direct',
      participantIds: [myId, senderSnow],
      title: senderSnow,
    );
    debugPrint('[DIAG:1to1] $messageId conversation findOrCreate done convId=$convId myId=$myId');
    onNewConversation?.call(convId, senderSnow);

    final companion = LocalMessagesCompanion(
      id: Value(messageId),
      conversationId: Value(convId),
      senderSnowchatId: Value(senderSnow),
      plaintext: Value(decrypted.plaintext),
      dateSent: Value(timestamp.millisecondsSinceEpoch),
      dateReceived: Value(DateTime.now().millisecondsSinceEpoch),
      type: Value(decrypted.type.name),
      metadata:
          Value(decrypted.metadata != null ? jsonEncode(decrypted.metadata) : null),
      expiresIn: Value(ttl ?? 0),
      // Signal pattern: receiver starts the timer upon read (expireStarted=0 → waiting)
      expireStarted: const Value(0),
      read: const Value(false),
      outgoingStatus: const Value('delivered'),
      senderDisplayName: Value(envelope['senderDisplayName'] as String?),
      replyToId: Value(decrypted.replyToId),
      replyToPreview: Value(decrypted.replyToPreview),
      replyToSenderId: Value(decrypted.replyToSenderId),
    );

    // Check if the conversation is currently being viewed by the user
    final isViewing = MarkReadHelper.isConversationActive(convId);
    debugPrint('[DIAG:ReadReceipt] msgId=$messageId convId=$convId isViewing=$isViewing activeSet=${MarkReadHelper.debugActiveSet}');

    // If viewing → mark read + start expiry timer immediately
    final now = DateTime.now().millisecondsSinceEpoch;
    final insertCompanion = isViewing
        ? companion.copyWith(
            read: const Value(true),
            expireStarted: Value(ttl != null ? now : 0),
          )
        : companion;

    await _messageDao.insertIncomingMessage(
      message: insertCompanion,
      conversationId: convId,
      snippetText: decrypted.plaintext,
      receivedTimestamp: now,
      senderId: senderSnow,
      mentionsSelf: false,
      isCurrentlyViewing: isViewing,
    );
    debugPrint('[DIAG:1to1] $messageId INSERTED into drift convId=$convId viewing=$isViewing');
    _maybeShowMessageBanner(
      isViewing: isViewing,
      conversationId: convId,
      senderId: senderSnow,
      plaintext: decrypted.plaintext,
    );

    // Send read receipt immediately if user is viewing this conversation
    if (isViewing) {
      _socketManager.sendReadReceipt([messageId]);
    }

    // Disappearing-message TTL: schedule only if already read (viewing).
    // Otherwise, timer starts when markAsRead() is called (Signal pattern).
    if (ttl != null && ttl > 0 && isViewing) {
      _expiringManager.schedule(messageId, ttl);
    }

    // File / voice / image (carried as MessageType.file with image mime):
    // create attachment row + trigger encrypted-blob download. Without this,
    // the bubble has no attachment row and shows a non-tappable download icon
    // (or shimmer for images) — file body never lands locally.
    if (decrypted.metadata != null &&
        (decrypted.type == MessageType.file ||
            decrypted.type == MessageType.voice)) {
      _processIncomingAttachments(messageId, decrypted.metadata!);
    }

    // Show local notification with decrypted plaintext preview.
    // Triggered here (post-decryption) instead of PushService (pre-decryption)
    // so we get actual message content and correct active-conversation check.
    if (!isViewing) {
      final senderName = (envelope['senderDisplayName'] as String?)
          ?? _truncateSnowId(senderSnow);
      NotificationService().showMessageNotification(
        senderName: senderName,
        preview: _notificationPreview(decrypted),
        conversationId: convId,
      );
    }
  }

  /// Phase 10.1: Process a Sealed Sender message.
  ///
  /// Routes to EncryptedMessageHandler.decryptSealedMessage() which:
  /// 1. Unseals the envelope (learns sender identity)
  /// 2. Decrypts the inner DR ciphertext
  /// 3. Returns the same Message object as regular 1:1 decrypt
  Future<void> _processSealedMessage(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;

    // 2026-05-04 Signal-style VoIP signaling delivery — server enqueues
    // mid-call sealed envelopes with metadata.voip=true when recipient is
    // offline (callHandler.ts orphan branch). Route to CallSignaling
    // instead of the chat decrypt + drift insert path. The inner envelope
    // is the raw base64 Sealed Sender ciphertext; CallSignaling.injectEnvelope
    // runs the same unseal + DR decrypt + dispatch pipeline that the live
    // socket fast-path uses, so CallService sees the same events.
    final outerMeta = envelope['metadata'];
    final isVoip = outerMeta is Map && outerMeta['voip'] == true;
    if (isVoip) {
      final encContent = envelope['encryptedContent'];
      final voipEnvelope =
          encContent is Map ? encContent['envelope'] as String? : null;
      if (voipEnvelope != null && voipEnvelope.isNotEmpty &&
          injectVoipEnvelope != null) {
        debugPrint('[DIAG:Sealed] $messageId VOIP route to CallSignaling');
        try {
          await injectVoipEnvelope!(voipEnvelope);
        } catch (e) {
          debugPrint('[DIAG:Sealed] $messageId VOIP inject failed: '
              '${e.runtimeType}');
          // Fall through to ack — re-delivery would just retry the same
          // failure (retry receipt path inside CallSignaling handles
          // session-state errors separately).
        }
      } else {
        debugPrint('[DIAG:Sealed] $messageId VOIP marker but '
            'envelope/handler missing — skip + ack');
      }
      _enqueueAck(messageId);
      envelope['_sessionResetConsumed'] = true;
      return;
    }

    debugPrint('[DIAG:Sealed] $messageId start');
    final decrypted = await _e2eeHandler.decryptSealedMessage(envelope);
    final senderId = decrypted.senderSnowchatId;
    // Sealed Sender routing: the receiver MUST NOT route by the sender's
    // embedded conversationId. That field is the sender's own server-CUID
    // — every user has its own per-perspective row id for the same 1:1, so
    // the sender's id is a foreign value to the receiver. Storing a row
    // under that foreign id creates a phantom that loadFromServer later
    // can't reconcile against the canonical row it pulls from the server,
    // and both can coexist indefinitely (the source of the badge-stuck-
    // at-N bug where unread sits on a row the UI never surfaces).
    //
    // Resolve by peer instead. When a direct row already exists for this
    // sender — created either by loadFromServer (canonical CUID) or by a
    // prior sealed receive (snow-id fallback) — use that row's id.
    // Otherwise fall back to senderId (snow), which is deterministic per
    // peer and dedupe-able later when loadFromServer brings in the
    // canonical CUID.
    final existing = await _conversationDao.findDirectByParticipant(senderId);
    final String convId;
    if (existing != null) {
      convId = existing.id;
      if (decrypted.conversationId != convId) {
        debugPrint('[DIAG:Sealed] $messageId routed by peer: '
            '${decrypted.conversationId} -> $convId (existing direct row)');
      }
    } else {
      convId = senderId;
      debugPrint('[DIAG:Sealed] $messageId no direct row for $senderId — '
          'falling back to snow-id convId (dedupe will merge once '
          'loadFromServer brings the canonical CUID)');
    }
    debugPrint('[DIAG:Sealed] $messageId decrypted: from=$senderId convId=$convId');

    // Wallet V2 Phase B (D2 P0-1 fix): skip transfer control messages (Sealed path).
    // EncryptedMessageHandler's transfer_* dispatcher already emitted to TransferEventBus.
    // No drift insert (avoids empty system bubble + noise).
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isTransferControl'] == true) {
      debugPrint('[DIAG:Sealed] $messageId TRANSFER_CONTROL from $senderId — drift skip');
      _enqueueAck(messageId);
      envelope['_sessionResetConsumed'] = true;
      return;
    }

    // Phase 10 P0-F: Check if this is a retry response (same logic as 1:1).
    // Sealed Sender retry responses are sent as normal 1:1 E2EE (not sealed),
    // but handle defensively in case the path arrives here.
    if (decrypted.metadata != null &&
        decrypted.metadata!['isRetry'] == true) {
      final originalId =
          decrypted.metadata!['originalMessageId'] as String?;
      if (originalId != null) {
        final updated = await _messageDao.updatePlaceholder(
          originalId,
          decrypted.plaintext,
          decrypted.type.name,
        );
        if (updated) {
          debugPrint('[DIAG:Sealed] $messageId RETRY resolved placeholder '
              '$originalId');
          return;
        }
        debugPrint('[DIAG:Sealed] $messageId RETRY no placeholder for '
            '$originalId, inserting as new');
      }
    }

    final tsStr = (envelope['serverTimestamp'] ?? envelope['createdAt']) as String?;
    final timestamp =
        tsStr != null ? DateTime.parse(tsStr) : DateTime.now();
    final ttl = decrypted.ttlSeconds;

    // Ensure conversation row exists (same as _processPrivate1to1).
    // Note: in-memory state sync is handled exclusively by
    // onSealedMessageDecoded below — firing onNewConversation here as well
    // would double-count unread (the new-conv branch sets unreadCount=1,
    // then the message-arrived branch adds +1 on top).
    final myId = _myIdResolver();
    await _conversationDao.findOrCreate(
      id: convId,
      type: 'direct',
      participantIds: [myId, senderId],
      title: senderId,
    );

    final companion = LocalMessagesCompanion(
      id: Value(messageId),
      conversationId: Value(convId),
      senderSnowchatId: Value(senderId),
      plaintext: Value(decrypted.plaintext),
      dateSent: Value(timestamp.millisecondsSinceEpoch),
      dateReceived: Value(DateTime.now().millisecondsSinceEpoch),
      type: Value(decrypted.type.name),
      metadata:
          Value(decrypted.metadata != null ? jsonEncode(decrypted.metadata) : null),
      expiresIn: Value(ttl ?? 0),
      expireStarted: const Value(0),
      read: const Value(false),
      outgoingStatus: const Value('delivered'),
      replyToId: Value(decrypted.replyToId),
      replyToPreview: Value(decrypted.replyToPreview),
      replyToSenderId: Value(decrypted.replyToSenderId),
    );

    final isViewing = MarkReadHelper.isConversationActive(convId);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _messageDao.insertIncomingMessage(
      message: isViewing
          ? companion.copyWith(
              read: const Value(true),
              expireStarted: Value(ttl != null ? now : 0),
            )
          : companion,
      conversationId: convId,
      snippetText: decrypted.plaintext,
      receivedTimestamp: now,
      senderId: senderId,
      mentionsSelf: false,
      isCurrentlyViewing: isViewing,
    );
    debugPrint('[DIAG:Sealed] $messageId INSERTED into drift convId=$convId');

    // Sealed envelopes carry no senderDisplayName (zero-knowledge), so the
    // banner / notification would fall back to a truncated snow id and the
    // recipient sees a hex string instead of a nickname. After the convId
    // remap the canonical drift row already holds the resolved display name
    // (set by ConversationListNotifier's _resolveSenderDisplayName when the
    // peer was first surfaced) — reuse it. Treat title == senderId as
    // unresolved (the initial placeholder findOrCreate writes the snow id
    // as a title until the server lookup completes).
    final convRow = await _conversationDao.getConversation(convId);
    final convTitle = convRow?.title;
    final resolvedSenderName = (convTitle != null &&
            convTitle.isNotEmpty &&
            convTitle != senderId)
        ? convTitle
        : _truncateSnowId(senderId);

    _maybeShowMessageBanner(
      isViewing: isViewing,
      conversationId: convId,
      senderId: resolvedSenderName,
      plaintext: decrypted.plaintext,
    );

    if (isViewing) {
      _socketManager.sendReadReceipt([messageId]);
    }

    if (ttl != null && ttl > 0 && isViewing) {
      _expiringManager.schedule(messageId, ttl);
    }

    if (decrypted.metadata != null &&
        (decrypted.type == MessageType.file ||
            decrypted.type == MessageType.voice)) {
      _processIncomingAttachments(messageId, decrypted.metadata!);
    }

    // Drive ConversationListNotifier's unread + preview update. The socket
    // listener can't do this for sealed envelopes — sender is null at the
    // wire level — so the in-memory state would otherwise stay stale and
    // the unread badge never appears.
    onSealedMessageDecoded?.call(
      convId,
      senderId,
      decrypted.plaintext,
      timestamp,
    );

    // OS-level notification only when the app is NOT in the foreground.
    // The in-app banner above already covers the FG case; firing both
    // produces the duplicate "banner + toast" the user observed.
    if (!isViewing && !_isAppInForeground()) {
      NotificationService().showMessageNotification(
        senderName: resolvedSenderName,
        preview: _notificationPreview(decrypted),
        conversationId: convId,
      );
    }
  }

  /// True when the app's UI is active and the in-app banner can be shown.
  /// AppLifecycleState.resumed = visible & receiving input. inactive/paused/
  /// hidden/detached all mean the OS notification path should win.
  bool _isAppInForeground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == AppLifecycleState.resumed;
  }

  Future<void> _processSKDM(Envelope envelope) async {
    // SKDM is a control message — decrypt the 1:1 envelope, parse the
    // distribution bytes, install into the SenderKeyManager, persist.
    // No drift insert (SKDM is not user-visible).
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    final senderSnow = (envelope['senderSnowchatId'] ?? envelope['senderId'])
        as String;
    final encContent = envelope['encryptedContent'];
    final messageType = (envelope['messageType'] as int?) ?? 1;

    if (encContent == null) {
      throw StateError('SKDM envelope missing encryptedContent');
    }

    // The 1:1 wrapper has the SKDM bytes inside its plaintext payload.
    Uint8List ciphertext;
    if (encContent is String) {
      ciphertext = Uint8List.fromList(base64Decode(encContent));
    } else if (encContent is List<int>) {
      ciphertext = Uint8List.fromList(encContent);
    } else if (encContent is Map && encContent['ciphertext'] is String) {
      ciphertext = Uint8List.fromList(base64Decode(encContent['ciphertext'] as String));
    } else {
      throw StateError('SKDM envelope has unrecognized encryptedContent shape');
    }

    // Phase 8.7 Bug A: SKDM may be the very first inbound from this sender.
    // Adopt the envelope's senderDeviceId on cache miss instead of falling
    // back to the placeholder 'primary' (which used to silently mismatch).
    final incomingDeviceId =
        (envelope['senderDeviceId'] ?? envelope['deviceId']) as String?;
    final deviceId =
        _sessionMgr.learnDeviceIdFromIncoming(senderSnow, incomingDeviceId);
    final wrapperBytes = await _sessionMgr.decrypt(
      senderSnow,
      deviceId,
      ciphertext,
      messageType,
    );

    // Wrapper is JSON: { type: 'sender_key_distribution', text: base64(SKDM bytes) }
    Uint8List skdmBytes;
    try {
      final wrapper = jsonDecode(utf8.decode(wrapperBytes)) as Map<String, dynamic>;
      final textB64 = wrapper['text'] as String;
      skdmBytes = Uint8List.fromList(base64Decode(textB64));
    } catch (_) {
      // Raw SKDM bytes (defensive)
      skdmBytes = wrapperBytes;
    }

    final groupSessionMgr = _e2eeHandler.groupSessionManager;
    if (groupSessionMgr == null) {
      throw StateError('GroupSessionManager not available');
    }
    final dist = SenderKeyDistributionMessage.deserialize(skdmBytes);
    groupSessionMgr.handleSenderKeyMessage(dist.groupId, senderSnow, skdmBytes);
    await groupSessionMgr.persistState();
    debugPrint('[DIAG:SKDM] INSTALLED from=$senderSnow groupId=${dist.groupId}');

    // Drain any group messages from this sender that were waiting for this SKDM.
    _drainPendingSKDM(dist.groupId, senderSnow);

    // ACK the SKDM control message itself (the drain loop skipped it).
    _enqueueAck(messageId);
  }

  Future<void> _processGroupMessage(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    final senderSnow = (envelope['senderSnowchatId'] ?? envelope['senderId'])
        as String;
    final groupId = (envelope['groupChatId'] ?? envelope['groupId']) as String?;
    if (groupId == null) {
      throw StateError('Group message missing groupChatId');
    }

    // Suppress unused warning while we keep messageId for diagnostics.
    // ignore: unused_local_variable
    final _msgId = messageId;

    final groupSessionMgr = _e2eeHandler.groupSessionManager;
    if (groupSessionMgr == null) {
      throw StateError('GroupSessionManager not available');
    }

    debugPrint('[DIAG:Group] $messageId start: from=$senderSnow groupId=$groupId');

    // If we don't have an SKDM for this sender yet, request one and PARK
    // the message in _pendingSKDM until the SKDM arrives. We must NOT loop
    // on retry because SKDMs travel via a separate 1:1 message that may
    // take seconds to arrive (X3DH bundle fetch + double ratchet decrypt).
    if (!groupSessionMgr.hasSenderKey(groupId, senderSnow)) {
      debugPrint('[DIAG:Group] $messageId NO_SKDM from=$senderSnow groupId=$groupId, '
          'requesting via sender_key_request and parking');
      _socketManager.sendSenderKeyRequest(
        groupId: groupId,
        senderSnowchatId: senderSnow,
      );
      throw _AwaitingSKDMException(groupId, senderSnow);
    }

    debugPrint('[DIAG:Group] $messageId has SKDM, decrypting');

    // Phase 10 P1-C (Mechanism 6, revised): Distinguish decrypt failure modes.
    //
    // Case A — "iteration behind, no cached key": The sender's chain has
    //   ratcheted forward past this message's iteration. HMAC ratchet is
    //   one-way: no fresh SKDM can recover old message keys. Removing the
    //   SKDM and re-requesting creates an INFINITE LOOP because
    //   getExistingSKDM() returns the current (advanced) state, which will
    //   also fail on the same old message. The SKDM itself is NOT corrupt —
    //   it's still needed for FUTURE messages from this sender.
    //   → Do NOT remove the SKDM. Re-throw as a regular error so the normal
    //     retry/dead-letter path handles it (placeholder + ACK).
    //
    // Case B — Other decrypt failures (signature mismatch, corrupt state):
    //   The SKDM state is genuinely bad. Remove it, request a fresh one,
    //   and park the message. But cap at _maxSkdmRetries to prevent loops.
    final Message decrypted;
    try {
      decrypted = await _e2eeHandler.decryptGroupMessage(envelope);
    } catch (e) {
      final errStr = e.toString();
      debugPrint('[DIAG:Group] $messageId SKDM exists but decrypt FAILED: $errStr');

      // Case A: iteration mismatch — message is from an older chain position
      // that has already been ratcheted past. No SKDM recovery possible.
      // Let the normal retry path dead-letter this single message while
      // preserving the SKDM for future messages.
      if (errStr.contains('iteration') && errStr.contains('behind')) {
        debugPrint('[DIAG:Group] $messageId iteration-behind gap detected — '
            'SKDM NOT removed (one-way ratchet). Letting retry path handle.');
        rethrow;
      }

      // Case B: genuine SKDM corruption — remove and re-request.
      groupSessionMgr.senderKeyManager
          .removeSenderKeyForMember(groupId, senderSnow);
      await groupSessionMgr.persistState();
      _socketManager.sendSenderKeyRequest(
        groupId: groupId,
        senderSnowchatId: senderSnow,
      );
      debugPrint('[DIAG:Group] $messageId corrupt SKDM removed, '
          'fresh SKDM requested — parking message');
      throw _AwaitingSKDMException(groupId, senderSnow);
    }
    debugPrint('[DIAG:Group] $messageId decrypted (type=${decrypted.type.name})');

    // System messages (e.g., metadata.text generated by server) — not handled here
    // since type='sender_key' is the encrypted user-visible path.
    final tsStr = (envelope['serverTimestamp'] ?? envelope['createdAt']) as String?;
    final timestamp =
        tsStr != null ? DateTime.parse(tsStr) : DateTime.now();
    final ttl = (decrypted.expiresAt != null && decrypted.expiresAt!.millisecondsSinceEpoch > 0)
        ? decrypted.expiresAt!.difference(timestamp).inSeconds
        : null;

    final companion = LocalMessagesCompanion(
      id: Value(messageId),
      conversationId: Value(groupId),
      senderSnowchatId: Value(senderSnow),
      plaintext: Value(decrypted.plaintext),
      dateSent: Value(timestamp.millisecondsSinceEpoch),
      dateReceived: Value(DateTime.now().millisecondsSinceEpoch),
      type: Value(decrypted.type.name),
      metadata:
          Value(decrypted.metadata != null ? jsonEncode(decrypted.metadata) : null),
      expiresIn: Value(ttl ?? 0),
      expireStarted: const Value(0),
      read: const Value(false),
      outgoingStatus: const Value('delivered'),
      senderDisplayName: Value(envelope['senderDisplayName'] as String?),
      replyToId: Value(decrypted.replyToId),
      replyToPreview: Value(decrypted.replyToPreview),
      replyToSenderId: Value(decrypted.replyToSenderId),
    );

    final isViewingGroup = MarkReadHelper.isConversationActive(groupId);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _messageDao.insertIncomingMessage(
      message: isViewingGroup
          ? companion.copyWith(
              read: const Value(true),
              expireStarted: Value(ttl != null ? now : 0),
            )
          : companion,
      conversationId: groupId,
      snippetText: decrypted.plaintext,
      receivedTimestamp: now,
      senderId: senderSnow,
      mentionsSelf: false,
      isCurrentlyViewing: isViewingGroup,
    );
    debugPrint('[DIAG:Group] $messageId INSERTED into drift groupId=$groupId');
    _maybeShowMessageBanner(
      isViewing: isViewingGroup,
      conversationId: groupId,
      senderId: senderSnow,
      plaintext: decrypted.plaintext,
    );

    // Disappearing-message TTL: schedule only if already read (viewing).
    if (ttl != null && ttl > 0 && isViewingGroup) {
      _expiringManager.schedule(messageId, ttl);
    }

    // File / voice / image (carried as MessageType.file with image mime):
    // create attachment row + trigger encrypted-blob download. Same fix as
    // _processPrivate1to1 — without this, group file recipients only see
    // the metadata bubble with no body and no way to download.
    if (decrypted.metadata != null &&
        (decrypted.type == MessageType.file ||
            decrypted.type == MessageType.voice)) {
      _processIncomingAttachments(messageId, decrypted.metadata!);
    }

    // Show local notification with decrypted plaintext preview.
    if (!isViewingGroup) {
      final senderName = (envelope['senderDisplayName'] as String?)
          ?? _truncateSnowId(senderSnow);
      NotificationService().showGroupNotification(
        groupName: (envelope['groupName'] as String?) ?? 'Group Chat',
        senderName: senderName,
        preview: _notificationPreview(decrypted),
        conversationId: groupId,
      );
    }

    // Persist Sender Key state after successful decryption (in-memory ratchet
    // advanced; we must save to disk so app restart doesn't lose progress).
    await groupSessionMgr.persistState();
  }

  /// Phase 8.8: Process incoming Group Metadata Key (GMK).
  /// Decrypt the 1:1 E2EE envelope (raw, no JSON wrapper), extract GMK, store locally.
  Future<void> _processGroupMetadataKey(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    final senderSnow = (envelope['senderSnowchatId'] ?? envelope['senderId'])
        as String;

    debugPrint('[GMK] $messageId processing from $senderSnow');

    try {
      // Raw decrypt — GMK payload was encrypted via sessionManager.encrypt
      // (raw Uint8List, NOT via encryptMessage's JSON wrapper).
      final encryptedContent = envelope['encryptedContent'];
      final messageType = (envelope['messageType'] ?? 1) as int;
      final senderDeviceId = (envelope['senderDeviceId'] ?? envelope['deviceId'] ?? '') as String;

      Uint8List ciphertext;
      if (encryptedContent is String) {
        ciphertext = Uint8List.fromList(base64Decode(encryptedContent));
      } else if (encryptedContent is Map) {
        ciphertext = Uint8List.fromList(
          base64Decode((encryptedContent['ciphertext'] ?? encryptedContent['data']) as String));
      } else {
        debugPrint('[GMK] $messageId unknown encryptedContent format');
        return;
      }

      final plaintextBytes = await _e2eeHandler.sessionManager.decrypt(
        senderSnow, senderDeviceId, ciphertext, messageType,
      );
      final payload = jsonDecode(utf8.decode(plaintextBytes)) as Map<String, dynamic>;

      final groupId = payload['groupId'] as String?;
      final gmkBase64 = payload['gmk'] as String?;
      final epoch = payload['epoch'] as int? ?? 0;

      if (groupId == null || gmkBase64 == null) {
        debugPrint('[GMK] $messageId missing groupId or gmk — skipping');
        return;
      }

      final gmk = Uint8List.fromList(base64Decode(gmkBase64));

      // Verify coordinator signature if present
      final sigBase64 = payload['signature'] as String?;
      if (sigBase64 != null) {
        final coordinatorSnowId = payload['coordinatorSnowId'] as String?;
        debugPrint('[GMK] $messageId has signature from $coordinatorSnowId');
        // Signature verification requires coordinator's Ed25519 public key.
        // For now, trust the 1:1 E2EE channel (sender authenticated by Double Ratchet).
        // Full signature verification will be added when request_gmk flow is implemented.
      }

      // Store GMK in flutter_secure_storage
      await GroupMetadataCrypto.storeGMK(groupId, gmk, epoch);
      debugPrint('[GMK] $messageId stored GMK for group=$groupId epoch=$epoch');

      // Notify conversation list to refresh group name
      onGmkReceived?.call(groupId);
    } catch (e) {
      debugPrint('[GMK] $messageId processing failed: $e');
    }
  }

  Future<void> _processSystem(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    final groupId = (envelope['groupChatId'] ?? envelope['groupId']) as String?;
    final convId = groupId ?? envelope['conversationId'] as String?;
    if (convId == null) {
      throw StateError('System message missing conversation context');
    }

    // System messages: server-generated text in metadata.text (not E2EE).
    String text = '';
    final metadata = envelope['metadata'];
    if (metadata is Map && metadata['text'] is String) {
      text = metadata['text'] as String;
    } else if (envelope['text'] is String) {
      text = envelope['text'] as String;
    }

    final tsStr = (envelope['serverTimestamp'] ?? envelope['createdAt']) as String?;
    final timestamp =
        tsStr != null ? DateTime.parse(tsStr) : DateTime.now();

    final companion = LocalMessagesCompanion(
      id: Value(messageId),
      conversationId: Value(convId),
      senderSnowchatId: const Value(''),
      plaintext: Value(text),
      dateSent: Value(timestamp.millisecondsSinceEpoch),
      dateReceived: Value(DateTime.now().millisecondsSinceEpoch),
      type: const Value('system'),
      read: const Value(true),
      outgoingStatus: const Value('delivered'),
    );

    await _messageDao.insertIncomingMessage(
      message: companion,
      conversationId: convId,
      snippetText: text,
      receivedTimestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: '',
      mentionsSelf: false,
      isCurrentlyViewing: true, // system messages don't bump unread
    );
  }

  // ---------------------------------------------------------------------------
  // Attachment processing
  // ---------------------------------------------------------------------------

  /// Insert attachment row(s) for an incoming file message and trigger the
  /// encrypted-blob download in the background. Mirrors
  /// MessageRepository._processIncomingAttachments but runs at the queue
  /// level so attachments land regardless of whether any chat screen is open.
  ///
  /// Supports both single-attachment metadata (`fileId` at top level) and
  /// the multi-attachment `attachments: [...]` shape produced by the sender.
  void _processIncomingAttachments(
      String messageId, Map<String, dynamic> metadata) {
    // E2EE file decryption key (present when file was encrypted before upload)
    final fileKeyB64 = metadata['fileKey'] as String?;
    final contentHash = metadata['contentHash'] as String?;

    final attachments = metadata['attachments'];
    if (attachments is! List || attachments.isEmpty) {
      // Single attachment fallback
      final fileId = metadata['fileId'] as String?;
      if (fileId == null) return;
      final attId = 'att_${messageId}_0';
      _attachmentDao
          .insertAttachment(LocalAttachmentsCompanion(
            id: Value(attId),
            messageId: Value(messageId),
            displayOrder: const Value(0),
            contentType: Value(
                (metadata['mimeType'] ?? 'application/octet-stream') as String),
            fileName: Value(metadata['fileName'] as String?),
            fileSize: Value((metadata['size'] as int?) ?? 0),
            remoteFileId: Value(fileId),
            transferState: const Value(TransferState.pending),
          ))
          .then((_) {
        _downloadAttachment(
            attId, fileId, metadata['fileName'] as String? ?? fileId,
            fileKeyB64: fileKeyB64, contentHash: contentHash);
      });
      return;
    }

    // Multi-attachment shape
    for (var i = 0; i < attachments.length; i++) {
      final a = Map<String, dynamic>.from(attachments[i] as Map);
      final fileId = a['fileId'] as String?;
      if (fileId == null) continue;
      final attId = 'att_${messageId}_$i';
      final fileName = a['fileName'] as String? ?? fileId;
      _attachmentDao
          .insertAttachment(LocalAttachmentsCompanion(
            id: Value(attId),
            messageId: Value(messageId),
            displayOrder: Value(i),
            contentType: Value(
                (a['mimeType'] ?? 'application/octet-stream') as String),
            fileName: Value(fileName),
            fileSize: Value((a['size'] as int?) ?? 0),
            width: Value((a['width'] as int?) ?? 0),
            height: Value((a['height'] as int?) ?? 0),
            remoteFileId: Value(fileId),
            transferState: const Value(TransferState.pending),
          ))
          .then((_) {
        _downloadAttachment(attId, fileId, fileName,
            fileKeyB64: fileKeyB64, contentHash: contentHash);
      });
    }
  }

  /// Download an encrypted blob, decrypt with [fileKeyB64] (when present),
  /// save the plaintext under `snowchat_attachments/{fileId}.{ext}` and
  /// finalize the attachment row. Stores the RELATIVE path so iOS container
  /// UUID changes don't invalidate it.
  Future<void> _downloadAttachment(
      String attachmentId, String fileId, String fileName,
      {String? fileKeyB64, String? contentHash}) async {
    try {
      await _attachmentDao.markStarted(attachmentId);

      final encryptedBytes = await _fileService.downloadEncryptedFile(fileId);

      Uint8List plainBytes;
      if (fileKeyB64 != null) {
        final fileKey = Uint8List.fromList(base64Decode(fileKeyB64));
        plainBytes = await FileEncryptor.decryptFile(
            encryptedBytes, fileKey, expectedHash: contentHash);
        debugPrint('[MessageQueue] Decrypted file $fileId '
            '(${encryptedBytes.length}B → ${plainBytes.length}B)');
      } else {
        plainBytes = encryptedBytes;
      }

      final dir = await getApplicationDocumentsDirectory();
      final attachDir = Directory('${dir.path}/snowchat_attachments');
      if (!attachDir.existsSync()) {
        attachDir.createSync(recursive: true);
      }
      final ext = fileName.contains('.') ? fileName.split('.').last : 'bin';
      final relativePath = 'snowchat_attachments/$fileId.$ext';
      await File('${dir.path}/$relativePath').writeAsBytes(plainBytes);

      await _attachmentDao.finalizeDownload(attachmentId, relativePath);
      debugPrint('[MessageQueue] Downloaded attachment $fileId → $relativePath');
    } catch (e) {
      debugPrint('[MessageQueue] Download attachment $fileId failed: $e');
      await _attachmentDao.markFailed(attachmentId);
    }
  }

  // ---------------------------------------------------------------------------
  // Decryption failure placeholder (Phase 10 P0-B)
  // ---------------------------------------------------------------------------

  /// Insert a placeholder row into drift for a message that could not be
  /// decrypted after exhausting all retries. This MUST be called BEFORE
  /// the corresponding ACK is sent — once the server receives the ACK it
  /// deletes its copy of the ciphertext, making the message permanently
  /// unrecoverable without the placeholder.
  ///
  /// The placeholder carries:
  /// - type = 'system' (renders as a system bubble in the UI)
  /// - outgoingStatus = 'decryption_failed' (drives the placeholder UI)
  /// - metadata = { retryState, error } (for future retry/recovery logic)
  /// - plaintext = '' (no cleartext available)
  Future<void> _insertDecryptionFailedPlaceholder(
    Envelope envelope,
    String messageId,
    String errorCode,
  ) async {
    try {
      // Extract sender and conversation info from the envelope.
      final senderSnow = (envelope['senderSnowchatId'] ??
          envelope['senderId'] ??
          '') as String;
      final type = (envelope['type'] ?? 'e2ee_text') as String;

      // Determine conversationId based on message type:
      // - Group messages (sender_key): use groupChatId / groupId
      // - 1:1 messages (e2ee_text / sealed): use conversationId or senderId
      String conversationId;
      if (type == 'sender_key') {
        conversationId = (envelope['groupChatId'] ??
            envelope['groupId'] ??
            senderSnow) as String;
      } else {
        conversationId = (envelope['conversationId'] ?? senderSnow) as String;
      }

      final tsStr =
          (envelope['serverTimestamp'] ?? envelope['createdAt']) as String?;
      final timestamp =
          tsStr != null ? DateTime.tryParse(tsStr) : null;
      final dateSent = timestamp?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;

      // Skip placeholder if the conversation doesn't already exist in drift.
      // Phantom conversations from retry-request fallbacks, session resets,
      // or SKDM-related side effects should not create new 1:1 entries.
      // Only add placeholders to conversations the user has already interacted with.
      if (type != 'sender_key') {
        final existing = await _conversationDao.getConversation(conversationId);
        if (existing == null) {
          debugPrint('[DIAG:Queue] $messageId skip phantom placeholder '
              '(no existing conv $conversationId)');
          return;
        }
      }

      // Ensure conversation row exists (same as _processPrivate1to1 / _processGroupMessage).
      final myId = _myIdResolver();
      if (type == 'sender_key') {
        await _conversationDao.findOrCreate(
          id: conversationId,
          type: 'group',
          participantIds: [],
          title: conversationId,
        );
      } else if (senderSnow.isNotEmpty) {
        await _conversationDao.findOrCreate(
          id: conversationId,
          type: 'direct',
          participantIds: [myId, senderSnow],
          title: senderSnow,
        );
      }

      final companion = LocalMessagesCompanion(
        id: Value(messageId),
        conversationId: Value(conversationId),
        senderSnowchatId: Value(senderSnow),
        plaintext: const Value(''),
        dateSent: Value(dateSent),
        dateReceived: Value(DateTime.now().millisecondsSinceEpoch),
        type: const Value('system'),
        metadata: Value(jsonEncode({
          'retryState': 'pending',
          'error': errorCode,
        })),
        read: const Value(false),
        outgoingStatus: const Value('decryption_failed'),
      );

      // Use upsertMessage (insertOnConflictUpdate) so we don't crash if a
      // partial row already exists from a previous failed attempt.
      await _messageDao.upsertMessage(companion);
      debugPrint('[DIAG:Queue] $messageId placeholder INSERTED '
          'convId=$conversationId sender=$senderSnow');
    } catch (placeholderErr) {
      // Placeholder insertion failure is serious but must not block the ACK
      // path — otherwise the server keeps re-delivering the undecryptable
      // message in an infinite loop. Log and continue.
      debugPrint('[DIAG:Queue] $messageId placeholder INSERT FAILED: '
          '$placeholderErr');
    }
  }

  // ---------------------------------------------------------------------------
  // Retry request emit (Phase 10 P0-D)
  // ---------------------------------------------------------------------------

  /// Emit a retry request to the original sender after decryption failure.
  ///
  /// Dispatches by message type:
  /// - `e2ee_text` (1:1): archiveAndResetSession → sendMessageRetryRequest
  /// - `sealed` (Sealed Sender): sendMessageRetryRequest with null sender
  ///   (server resolves via blind retry)
  /// - `sender_key` (group): sendGroupMessageRetryRequest
  ///
  /// IMPORTANT: For 1:1 ratchet corruption, archiveAndResetSession() MUST
  /// complete before the retry emit to prevent the race where the sender
  /// re-encrypts against the old (now-archived) session.
  Future<void> _emitRetryRequest(
    Envelope envelope,
    String messageId,
    String errorCode,
  ) async {
    try {
      final type = (envelope['type'] ?? 'e2ee_text') as String;
      final senderSnow = (envelope['senderSnowchatId'] ??
          envelope['senderId']) as String?;

      switch (type) {
        case 'sender_key':
          // Group message: emit group retry request
          final groupId = (envelope['groupChatId'] ??
              envelope['groupId']) as String?;
          if (groupId != null &&
              senderSnow != null &&
              senderSnow.isNotEmpty) {
            _socketManager.sendGroupMessageRetryRequest(
              groupId,
              messageId,
              senderSnow,
            );
          }
          break;

        case 'sealed':
          // Sealed Sender: sender ID unknown → blind retry via server
          _socketManager.sendMessageRetryRequest(messageId, null);
          break;

        case 'e2ee_text':
        default:
          // 1:1 message: archive and reset session FIRST, then emit retry
          if (senderSnow != null && senderSnow.isNotEmpty) {
            await _sessionMgr.archiveAndResetSession(senderSnow);
            _socketManager.sendMessageRetryRequest(messageId, senderSnow);
          }
          break;
      }

      debugPrint('[DIAG:Queue] $messageId retry request emitted '
          '(type=$type sender=$senderSnow)');
    } catch (retryErr) {
      // Retry request failure must not block the ACK path.
      debugPrint('[DIAG:Queue] $messageId retry request FAILED: $retryErr');
    }
  }

  // ---------------------------------------------------------------------------
  // ACK batching
  // ---------------------------------------------------------------------------

  void _enqueueAck(String messageId) {
    _pendingAcks.add(messageId);
    _ackFlushTimer ??= Timer(_ackFlushDelay, _flushAcks);
  }

  void _flushAcks() {
    _ackFlushTimer = null;
    if (_pendingAcks.isEmpty) return;
    final batch = List<String>.from(_pendingAcks);
    _pendingAcks.clear();

    // Send via socket (preferred — lower latency).
    if (_socketManager.isConnected) {
      _socketManager.sendMessageAck(batch);
      return;
    }

    // Fallback: REST endpoint.
    _apiClient
        .post(ApiEndpoints.ackMessages, data: {'messageIds': batch})
        .then((_) {})
        .catchError((e) {
      debugPrint('[MessageQueue] REST ACK failed: $e');
      // Re-buffer for next attempt
      _pendingAcks.addAll(batch);
    });
  }

  /// Force flush pending ACKs (used on dispose / chat exit).
  void flushAcks() {
    _ackFlushTimer?.cancel();
    _ackFlushTimer = null;
    _flushAcks();
  }

  // ---------------------------------------------------------------------------
  // Notification helpers
  // ---------------------------------------------------------------------------

  /// Notification preview text based on decrypted message type.
  String _notificationPreview(Message msg) {
    switch (msg.type) {
      case MessageType.voice:
        return 'Voice message';
      case MessageType.file:
        final mime = msg.metadata?['mimeType'] as String? ?? '';
        if (mime.startsWith('image/')) return 'Photo';
        return 'File';
      case MessageType.text:
      case MessageType.system:
        return msg.plaintext;
    }
  }

  /// Truncate a SnowChat ID for display in notifications.
  String _truncateSnowId(String snowId) {
    if (snowId.length > 12) {
      return '${snowId.substring(0, 8)}...${snowId.substring(snowId.length - 4)}';
    }
    return snowId;
  }
}
