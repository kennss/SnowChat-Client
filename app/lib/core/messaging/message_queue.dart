/// @file        message_queue.dart
/// @description Phase 6 — Single serial processing queue for incoming 1:1 messages
///              (sealed, sealed control). Group messages are rows of the group
///              queue (core/group_v2); this queue hands them to it (onGv2Rows) and runs the
///              follow-ups of a stored v2 message. Eliminates race conditions by ensuring
///              every message goes through one worker, in order, with atomic state mutation.
///              ACKs the server only after successful processing.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-07
/// @lastUpdated 2026-11-27 (wallet removed: no transfer-control branch — an old build's transfer_*
///              notice reaches the queue as an unknown inner type and is consumed). Earlier
///              2026-11-22 (no account or conversation id in a log line — logRef). Earlier 2026-11-22 (review fixes: a contact notice is handed on with whether it answers one of
///              this user's (onContactNotice's isAnswer), and its row id is remembered for a while —
///              wasContactNotice() — so a tap on its "New message" push opens the Friends tab; a read
///              receipt flips only this user's messages in the room of its authenticated sender; a
///              message whose room has no name yet is shown under the name this device knows for the
///              sender (peerName — the contact list, name certificates) before the short snowId; no
///              account id in a log line). Earlier 2026-11-22 (friend graph off the server — design 2026-11-22 §5.2, §12.4: a sealed
///              contact_added / contact_removed goes to onContactNotice (the contact store) and is
///              consumed — no room, no bubble, no unread; a message's name certificate is handed to
///              onPeerNameCert before the message is stored, so the room and the notification carry
///              the verified name; an inner type this build does not know is consumed and never
///              shown; a wallet transfer notice on the control path is consumed. Part 3 E: the
///              non-sealed 1:1 path (`e2ee_text`, `session_reset`, _processPrivate1to1) is gone — an
///              envelope of any other wire type is acknowledged and dropped — and so are the retry
///              request and the retry answer's placeholder fill (the server relays no retry
///              requests)). Earlier 2026-11-22 (SC-05: a sealed message that fails to decrypt resets the session and
///              sends no message_retry_request — the server refused it and it only named the sender;
///              a sealed session_reset control is consumed). Earlier 2026-11-21 (a 1:1 message whose sender's own id (`cid`) is stored already — the
///              sender's outbox sent it again after a lost ack — is acked and not stored again;
///              peerClientId is stored with each received 1:1 message). Earlier 2026-11-21 (X1: what an account this user blocked sent — BlockedSenderException from the decrypt — is acknowledged and dropped for good, never retried or answered; P5.6: fetchPending during a fetch shares it and fetches once more after — it returned at once, and the rows it was called for waited for a later trigger; P5.6: a received attachment is written only under a checked file id and extension (AttachmentStorage.relativePathFor) — a sender-supplied `../` could write anywhere in the container). Earlier 2026-11-21 (P5.6: a v2 invite is kept in the group inbox's table (onGv2Invite, wired when the queue is made) before its message is acknowledged — it was lost while the group runtime was not up). Earlier 2026-11-21 (no identity re-verification hold — the legacy key change it waited for cannot happen with mandatory bindings; no unused identityChangeHandler field). Earlier 2026-11-21 (comment: the sealed delete_chat is the only deletion signal). Earlier 2026-11-20 (v1 groups removed: no SKDM / v1 group message / GMK / server system
///              line processing, no SKDM parking, no groupsSynced; a retry response that fills
///              its placeholder is a consumed envelope (it has no row of its own — the commit
///              verify used to fail on it, retry and dead-letter it); a 1:1 message is stored in the
///              room of its authenticated sender — never in a conversation the envelope names —
///              and a retry response fills only a placeholder of the same sender; an envelope of
///              type 'system' is acknowledged and nothing stored. Earlier: group protocol v2: every
///              envelope that names a v2 group id is refused on the
///              v1 paths — also system lines and name keys; gv2GroupChanged() tells the Chats
///              list that a group changed).
///              Earlier 2026-11-13 (group protocol v2: fetchPending hands the `gv2` rows of a fetch to
///              the local inbox (onGv2Rows) and repeats while the group queue has more; an
///              envelope whose id was acknowledged in this session is acknowledged again
///              instead of processed again; the v1 Sender Key and group paths refuse a v2
///              group id; gv2MessageStored() runs the follow-ups of a stored v2 group
///              message; a sealed 1:1 message that is a v2 invite goes to onGv2Invite and
///              is consumed without a chat row). Earlier 2026-11-12 (a received GMK is stored as an unverified candidate —
///              GroupMetadataCrypto.offerCandidate — instead of overwriting the active key;
///              any 1:1 peer could previously replace the GMK of any group id).
///              Earlier 2026-11-11 (at-rest level 1: received attachments are written via AttachmentStorage.ensureDirectory() (iOS backup-excluded, CompleteUnlessOpen)). Earlier 2026-11-10 (B-2 Identity Binding v1: the identity dead-letter is replaced by the Signal-style policy — an IdentityKeyChangedException (legacy peer the user had verified) is NOT ACKed and NOT retried in-process: the server keeps the envelope and redelivers it on the next fetchPending after the user re-verifies (M2: an in-memory held set skips redelivered ids without decrypting until releaseHeldForPeer()); an IdentityBindingInvalidException (forged / downgraded / replayed binding) is terminal: ACK, no retry request, no session reset. User-visible notices come from VerifiedIdentityStore events. SKDM/GMK decrypts pass the envelope deviceId and never cache it before a verified decrypt; GMK no longer swallows the two identity failures). Earlier 2026-09-04 (sealed delete-chat: _processSealedControl dispatches inner type 'delete_chat' to the new onPeerDeletedChat callback (wired by ConversationListNotifier), so a peer's room deletion applied while this device was offline is honoured on the next queue drain). Earlier 2026-08-12 (bug #34 residue: added `groupsSynced` (wired by ConversationListNotifier.loadFromServer) — the sealed 1:1 receive path now passes trustServerCuidRows: groupsSynced so a pre-302 mis-typed group row cannot capture a queued 1:1 during the cold-start window before the heal runs; _insertDecryptionFailedPlaceholder's sender_key branch now retypeToGroup()s on the proof (and sets groupId) instead of relying on findOrCreate, which returns an existing mis-typed row untouched). Earlier 2026-08-06 (conversation-preview sync: added onGroupMessageDecoded callback — fired in _processGroupMessage after decrypt so the in-memory Chats-list group preview gets the real plaintext (the live wire listener only had a null-text "[New message]" placeholder → "No messages yet" until restart). Added onConversationPreviewStale callback — fired from _applyUnsend per affected conversation so an unsent last message's preview is recomputed instead of lingering. Earlier 2026-07-15 (sealed unsend: _processSealedControl dispatches inner type 'delete' → _applyUnsend physically removes rows, guarded by senderSnowchatId match (can't delete others' messages) + 5-min window. Sealed read receipt: _processSealedControl() consumes wire type 'sealed_control' — applies outgoingStatus='read' via markOutgoingAsRead, ACKs, never inserts; defense-in-depth _isReadReceipt skip in _processSealedMessage before the drift insert; live-read receipts now sealed E2EE instead of plaintext message_read). Earlier 2026-05-14 (sealed routing 정공법: decrypted.conversationId is the sender's server-CUID — meaningless to the receiver and the source of phantom rows when both canonical + foreign-id rows coexist post-dedupe. Stop trusting it; always resolve by findDirectByParticipant, deterministic snow-id fallback when no row yet.)
///
/// @functions
///  - MessageQueue: Single-worker FIFO queue for incoming message envelopes
///  - enqueue(envelope): Add an envelope to the queue (called by GlobalMessageRouter)
///  - fetchPending(): Pull all pending+delivered messages from server queue and enqueue
///  - _processNext(): Worker loop — drains queue serially
///  - _processOne(envelope): Dispatch a single envelope by type
///  - _processSealedMessage(envelope): Sealed Sender unseal + DR decrypt → drift insert
///  - _processSealedControl(envelope): silent sealed controls (receipts, unsend, delete chat,
///    session reset, contact_removed)
///  - _applyContactNotice(): a contact notice to the contact store (onContactNotice)
///  - wasContactNotice(): whether a row id was a contact notice handled lately (push taps)
///  - _processIncomingAttachments(): Insert attachment rows + trigger encrypted-blob download
///  - _downloadAttachment(): Download + decrypt + persist a single file attachment
///  - _insertDecryptionFailedPlaceholder(): insert placeholder row on dead-letter (required before ACK)
///  - _resetAfterFailedDecrypt(): after dead-letter, reset the session with the authenticated sender
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

import '../blocking/block_list.dart' show BlockedSenderException;
import '../../features/chat/models/message.dart' show Message, MessageType;
import '../../features/chat/providers/expiring_message_manager.dart';
import '../../features/chat/providers/mark_read_helper.dart';
import '../crypto/encrypted_message_handler.dart';
import '../crypto/file_encryptor.dart';
import '../crypto/identity_binding_exception.dart';
import '../crypto/signal_session_manager.dart';
import '../group_v2/gv2_codec.dart' show gv2IsGroupId;
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/file_service.dart';
import '../network/socket_manager.dart';
import '../notifications/notification_service.dart';
import '../storage/daos/attachment_dao.dart';
import '../storage/local_file_protection.dart';
import '../storage/daos/conversation_dao.dart';
import '../storage/daos/message_dao.dart';
import '../storage/database.dart';
import '../storage/tables/attachments_table.dart';
import '../../shared/services/message_banner_service.dart';
import '../../shared/widgets/message_banner.dart';
import '../diagnostics/log_ref.dart';

/// Type alias for the message envelope JSON map.
typedef Envelope = Map<String, dynamic>;

class _QueuedItem {
  final Envelope envelope;
  final DateTime enqueuedAt;
  int retryCount;
  _QueuedItem(this.envelope, this.enqueuedAt) : retryCount = 0;
}

class MessageQueue {
  final SignalSessionManager _sessionMgr;
  final EncryptedMessageHandler _e2eeHandler;
  final MessageDao _messageDao;
  final ConversationDao _conversationDao;
  final AttachmentDao _attachmentDao;

  /// Called AFTER a peer's sealed delete-chat control has already wiped the
  /// drift room, so ConversationListNotifier can drop it from in-memory state.
  /// UI-only by design: the durable work happens in [_applyDeleteChat], which
  /// must not depend on this being wired (the queue drains on cold start before
  /// the notifier is constructed).
  Future<void> Function(String peerSnowchatId, String roomId)?
      onPeerDeletedChat;

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

  /// Called after a group message (group protocol v2) has been stored
  /// ([gv2MessageStored]). ConversationListNotifier wires this to refresh the
  /// in-memory group row's last-message preview with the actual plaintext
  /// (drift is already updated by the v2 message sink).
  void Function(
    String groupId,
    String senderSnowId,
    String preview,
    DateTime msgTime,
  )? onGroupMessageDecoded;

  /// Called after a message row is physically removed (sealed 1:1 unsend /
  /// delete-for-everyone) so the denormalized conversation preview can be
  /// recomputed from the durable store. The queue has no conversationList ref,
  /// so ConversationListNotifier wires this to refreshPreviewAfterDelete().
  void Function(String conversationId)? onConversationPreviewStale;

  /// Group protocol v2: the rows of the group queue in a REST fetch (the
  /// `gv2` list) are handed to the local inbox (wired by providers to
  /// Gv2Runtime.receive). Returns true when the rows are stored and
  /// acknowledged — only then does the next fetch bring the rows after them.
  /// Null while group protocol v2 is off: the rows stay on the server.
  Future<bool> Function(List<dynamic> rows)? onGv2Rows;

  /// Group protocol v2: a 1:1 invite message arrived from [senderSnowId]
  /// (the sender its sealed envelope certified) in the 1:1 message
  /// [messageId]. Wired by providers when the queue is made — not by the
  /// group runtime, which may not be up yet — to keep the invite in the
  /// group inbox's table; returns once it is on disk, and only then is the
  /// message acknowledged. Taking it in happens later, in the group runtime.
  Future<void> Function(String senderSnowId, Uint8List invite, String messageId)?
  onGv2Invite;

  /// Group protocol v2: an invite was kept (wired by the group runtime: it
  /// drains). Null while the runtime is not up: it drains when it starts.
  void Function()? onGv2InviteKept;

  /// Group protocol v2: a group changed on this device (wired by the
  /// conversation list to ConversationListNotifier.syncGv2Group).
  void Function(String groupId)? onGv2GroupChanged;

  /// A contact notice ([notice]: contact_added / contact_removed) from
  /// [senderSnowId] (the certified sender of its sealed envelope), with the
  /// name certificate it carried and whether it is the answer to one of this
  /// user's ([isAnswer]). Wired by providers when the queue is made (the
  /// contact store); awaited before the envelope is acknowledged.
  Future<void> Function(
    String senderSnowId,
    String notice,
    String? nameCert,
    bool isAnswer,
  )? onContactNotice;

  /// The name this device knows for an account (the contact list, its
  /// name certificates — NameCertService.nameOf), or null. Wired by
  /// providers; used when a message's room has no name yet.
  Future<String?> Function(String snowId)? peerName;

  /// Server row ids of the contact notices handled lately (newest last,
  /// at most [_noticeIdsKept]): a tap on the "New message" push of one finds
  /// no message row — it opens the Friends tab instead.
  final Set<String> _contactNoticeIds = {};
  static const int _noticeIdsKept = 64;

  /// Whether the server row [messageId] was a contact notice handled by
  /// this queue lately.
  bool wasContactNotice(String messageId) =>
      _contactNoticeIds.contains(messageId);

  /// A name certificate [cert] (base64) a message of [senderSnowId]
  /// carried: checked and applied (NameCertService.receive) before the
  /// message is stored and notified. Wired by providers.
  Future<void> Function(String senderSnowId, String cert)? onPeerNameCert;
  final FileService _fileService;
  final ExpiringMessageManager _expiringManager;
  final ApiClient _apiClient;
  final SocketManager _socketManager;
  final String Function() _myIdResolver;

  /// FIFO queue of pending envelopes.
  final List<_QueuedItem> _queue = [];

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
  static const int _maxRetries = 5;

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
        _myIdResolver = myIdResolver;

  /// Current queue depth (for diagnostics / backpressure).
  int get depth => _queue.length;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Ids acknowledged in this session, oldest first. An envelope that comes
  /// again under one of them (fetched again before the server applied the
  /// acknowledgement — fetchPending repeats while the group queue has more)
  /// is acknowledged again, not processed again: a control envelope (sealed
  /// control, session reset) leaves no row behind to de-duplicate on, and
  /// decrypting it twice would break its 1:1 session.
  final Set<String> _acked = <String>{}; // a set literal keeps insertion order
  static const int _ackedLimit = 4000;

  /// Fetches in a row while the group queue says it has more.
  static const int _maxFetchRounds = 20;


  /// Enqueue an envelope. Called by GlobalMessageRouter for socket events
  /// and by [fetchPending] for REST API results.
  void enqueue(Envelope envelope) {
    final messageId = (envelope['id'] ?? envelope['messageId']) as String?;
    if (messageId == null) {
      debugPrint('[DIAG:Queue] enqueue REJECTED: missing id, '
          'envelope keys=${envelope.keys.toList()}');
      return;
    }
    if (_acked.contains(messageId)) {
      debugPrint('[DIAG:Queue] enqueue SKIPPED: acknowledged before, '
          'acknowledging again $messageId');
      _enqueueAck(messageId);
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

  /// The fetch under way: a caller during it shares it, and makes it fetch
  /// once more when it is done — not a duplicate request at the same time
  /// (that returned the same un-ACK'd messages twice), and not nothing (a
  /// fetch that started before the group runtime was there left its group
  /// rows on the server, and the runtime's own fetch was then skipped).
  Future<void>? _fetching;
  bool _fetchAgain = false;

  /// Fetch all pending+delivered messages from the server queue and enqueue them.
  /// Called on app start, socket reconnect, and chat re-entry.
  Future<void> fetchPending() {
    _fetchAgain = true;
    return _fetching ??= _fetchLoop().whenComplete(() => _fetching = null);
  }

  Future<void> _fetchLoop() async {
    while (_fetchAgain) {
      _fetchAgain = false;
      try {
        // The group queue hands out a page at a time; rows this device has
        // stored and acknowledged are gone from it, so the same request
        // brings the next page. (No parameter of its own for that: the
        // access log must not tell a group fetch from any other.) 1:1 rows
        // that come again meanwhile are recognised by enqueue().
        for (var round = 0; round < _maxFetchRounds; round++) {
          if (!await _fetchOnce()) break;
        }
      } catch (e) {
        debugPrint('[DIAG:Queue] fetchPending FAILED: $e');
      }
    }
  }

  /// One REST fetch: the group queue's rows go to the local inbox, the 1:1
  /// rows into this queue (and are processed before this returns). Returns
  /// true when the group queue has more rows and the ones just fetched are
  /// acknowledged.
  Future<bool> _fetchOnce() async {
    debugPrint('[DIAG:Queue] fetchPending: starting REST fetch');
    final response = await _apiClient.get(ApiEndpoints.fetchMessages);
    final data = response.data;
    if (data is! Map || data['messages'] is! List) {
      debugPrint('[DIAG:Queue] fetchPending: empty/malformed response');
      return false;
    }

    // Group protocol v2. Nothing of a row is logged.
    var gv2Acknowledged = false;
    final gv2 = data['gv2'];
    final toInbox = onGv2Rows;
    if (toInbox != null && gv2 is List && gv2.isNotEmpty) {
      try {
        gv2Acknowledged = await toInbox(gv2);
      } catch (_) {
        // Not stored: the server hands the rows out again.
      }
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
      debugPrint('[DIAG:Queue] fetchPending: re-enqueuing $id type=$type');
      enqueue(env);
    }
    // Wait for the worker to finish processing the just-enqueued items
    // so that callers can read drift state immediately after.
    await waitForIdle();
    debugPrint('[DIAG:Queue] fetchPending: completed (worker idle)');
    return gv2Acknowledged && data['gv2More'] == true;
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
          // Consumed envelopes (session reset, sealed control, a
          // retry response that filled its placeholder) and refused ones
          // leave no row of their own in localMessages. Skip drift-verify
          // and ACK directly.
          final isControl = item.envelope['_consumed'] == true ||
              item.envelope['_refused'] == true;
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
        } on BlockedSenderException {
          // X1: from an account this user blocked — dropped for good:
          // acknowledged, never retried or answered, nothing stored.
          debugPrint('[DIAG:Queue] $messageId from a blocked account — ACK, dropped');
          _enqueueAck(messageId);
        } on IdentityBindingInvalidException catch (rejected) {
          // B-2 §5.7 hard failure: forged / downgraded / replayed identity
          // binding. Terminal — ACK so the server stops redelivering, never
          // retry, never request a resend, never reset the session (all of
          // which would just repeat the rejection or burn our prekeys). The
          // security notice was emitted by VerifiedIdentityStore.
          _deadLetters.add(messageId);
          debugPrint('[DIAG:Queue] $messageId identity binding rejected '
              '(${rejected.reason.name}) — ACK, no retry');
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
          // SPK self-heal (2026-08-05): a Sealed Sender message that unsealed to
          // a certificate-authenticated sender but failed inner Signal decrypt
          // carries that sender (SealedDecryptException). Recover it so the
          // dead-letter path can target the retry/placeholder and, when the
          // cause is our own missing signed prekey, re-arm before asking the
          // sender to resend.
          final String? authedSender =
              e is SealedDecryptException ? e.senderSnowchatId : null;
          final bool isMissingLocalSpk = e is SealedDecryptException &&
              e.cause.toString().contains('Signed prekey') &&
              e.cause.toString().contains('not found');
          final isRatchetCorruption =
              errStr.contains('could decrypt the message');
          if (isRatchetCorruption && item.retryCount == 2) {
            // The sender is known only from the unsealed certificate: an
            // envelope names none (every 1:1 row is sealed).
            final senderSnow = authedSender;
            if (senderSnow != null && senderSnow.isNotEmpty) {
              debugPrint('[DIAG:Queue] $messageId ratchet corruption '
                  'detected for ${logRef(senderSnow)} → triggering session reset');
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

            // Session corruption ("forged or malformed", "shared secret")
            // is unrecoverable — a reset would fail the same way.
            final isSessionCorruption = errStr.contains('forged') ||
                errStr.contains('malformed') ||
                errStr.contains('shared secret');

            {
              // SPK self-heal (2026-08-05): if we failed because our LOCAL
              // signed prekey is missing, re-arm our bundle in the BACKGROUND
              // (unawaited) so the queue worker isn't blocked by the ~15s
              // keygen. This heals the account for FUTURE receive-first messages
              // (server now advertises an SPK we hold); it does NOT recover this
              // specific stuck message — that's covered by the visible
              // placeholder below (INV-4): there is no retry channel.
              if (isMissingLocalSpk) {
                debugPrint('[DIAG:Queue] $messageId missing local signed prekey '
                    '→ SPK self-heal (background)');
                unawaited(_sessionMgr
                    .reconcileSignedPreKey()
                    .catchError((Object healErr) {
                  debugPrint('[DIAG:Queue] $messageId SPK self-heal failed: '
                      '$healErr');
                }));
              }
              // Phase 10 P0-B: Insert placeholder row BEFORE ACK.
              // authedSender (sealed unseal succeeded) makes this a real,
              // non-phantom placeholder for a first-contact conversation.
              await _insertDecryptionFailedPlaceholder(
                item.envelope,
                messageId,
                errStr,
                authedSender: authedSender,
              );
              // Reset the session with the sender — but not for session
              // corruption (unrecoverable; a reset would fail the same way).
              if (!isSessionCorruption) {
                await _resetAfterFailedDecrypt(messageId, authedSender);
              } else {
                debugPrint('[DIAG:Queue] $messageId session corruption '
                    '— no session reset');
              }
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

  // ---------------------------------------------------------------------------
  // Dispatch
  // ---------------------------------------------------------------------------

  Future<void> _processOne(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    final type = (envelope['type'] ?? '') as String;

    // A row names no sender (every 1:1 row is sealed; the server keeps
    // neither its sender nor its reply fields): who sent it is known only
    // after the unseal.

    // Dedup BEFORE decryption — same message via socket + REST fetch must
    // not consume two ratchet steps.
    final existing = await _messageDao.getMessageById(messageId);
    if (existing != null) {
      debugPrint('[DIAG:Queue] $messageId DEDUP (already in drift)');
      return;
    }

    // Group protocol v2: the messages and keys of a v2 group travel its own
    // queue and are judged by its own roster (core/group_v2). An envelope of
    // this queue that names a v2 group id in any field is the server's word
    // about that group: terminal, acknowledged, nothing stored. (A 1:1
    // message is stored in its authenticated sender's room whatever the
    // envelope names — see _processSealedMessage — so this is a second line.)
    if (gv2IsGroupId(envelope['groupChatId']) ||
        gv2IsGroupId(envelope['groupId']) ||
        gv2IsGroupId(envelope['conversationId'])) {
      debugPrint('[DIAG:Queue] $messageId REFUSED (names a v2 group)');
      envelope['_refused'] = true;
      return;
    }

    debugPrint('[DIAG:Queue] $messageId dispatching to handler type=$type');
    switch (type) {
      case 'sealed':
        await _processSealedMessage(envelope);
        break;
      case 'sealed_control':
        await _processSealedControl(envelope);
        break;
      default:
        // Every 1:1 envelope is sealed (Part 3 E — the non-sealed path is
        // gone on both sides). Anything else — a server system line, an old
        // `e2ee_text` row — is acknowledged and nothing is stored.
        debugPrint('[DIAG:Queue] $messageId REFUSED (wire type $type)');
        envelope['_refused'] = true;
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Type handlers
  // ---------------------------------------------------------------------------

  /// Whether [senderId]'s message with its own id [peerClientId] (`cid`) is
  /// stored already: the sender's 1:1 outbox sent it again after a lost ack.
  /// A payload without `cid` is never a repeat.
  Future<bool> _isRepeatFromPeer(String senderId, String? peerClientId) async {
    if (peerClientId == null || peerClientId.isEmpty) return false;
    return _messageDao.hasMessageFromPeer(senderId, peerClientId);
  }

  /// Sealed control (2026-07-15): process a silent E2EE control envelope
  /// (wire type 'sealed_control'): a read receipt, an unsend, a chat
  /// deletion, a session reset, a contact_removed. Controls never insert a
  /// drift message, bump unread, show a banner, or fire a notification.
  ///
  /// Decrypt failures are ACKed and dropped — a lost receipt only costs a
  /// blue check, and routing a status flip into the retry/session-reset
  /// machinery risks reset storms (2026-05-13 lesson).
  Future<void> _processSealedControl(Envelope envelope) async {
    final messageId =
        (envelope['id'] ?? envelope['messageId']) as String;
    try {
      final decrypted = await _e2eeHandler.decryptSealedMessage(envelope);
      if (decrypted.metadata?['_isReadReceipt'] == true) {
        await _applyReadReceipt(
            decrypted.metadata!, decrypted.senderSnowchatId, messageId);
      } else if (decrypted.metadata?['_isUnsend'] == true) {
        await _applyUnsend(
            decrypted.metadata!, decrypted.senderSnowchatId, messageId);
      } else if (decrypted.metadata?['_isGroupInviteV2'] == true) {
        await _applyGv2Invite(decrypted);
      } else if (decrypted.metadata?['_isSessionReset'] == true) {
        // The peer re-established the session (archiveAndResetSession): the
        // decrypt above — a prekey message — already built it here. Nothing
        // else to do.
        debugPrint('[DIAG:SealedControl] $messageId session_reset consumed');
      } else if (decrypted.metadata?['_isDeleteChat'] == true) {
        // The peer deleted this 1:1 on their side — the only signal of it
        // (the server sends none). Queued like a message, so this also fires
        // for a delete that happened while we were offline.
        debugPrint('[DIAG:SealedControl] $messageId delete_chat');
        await _applyDeleteChat(decrypted.senderSnowchatId);
      } else if (decrypted.metadata?['_isContactNotice'] == true) {
        await _applyContactNotice(decrypted, messageId);
      } else if (decrypted.metadata?['_isUnknownType'] == true) {
        // A type this build does not know: consumed, nothing shown.
        debugPrint('[DIAG:SealedControl] $messageId consumed (no row)');
      } else {
        debugPrint('[DIAG:SealedControl] $messageId unknown control type — dropped');
      }
    } on BlockedSenderException {
      // X1: a control of an account this user blocked (a read receipt, an
      // unsend, a group invite, a chat deletion) — dropped for good.
      debugPrint('[DIAG:SealedControl] $messageId from a blocked account — dropped');
    } catch (e) {
      debugPrint('[DIAG:SealedControl] $messageId decrypt failed — dropped '
          '(no retry by design): $e');
    }
    _enqueueAck(messageId);
    envelope['_consumed'] = true;
  }

  /// Apply a decrypted read receipt: batch-flip our own outgoing rows to
  /// 'read'. Zero matched rows is a benign no-op (already read, expired, or
  /// racing the local→server id swap) — never an error.
  Future<void> _applyReadReceipt(
      Map<String, dynamic> metadata, String sender, String messageId) async {
    final rawIds = metadata['readIds'];
    final readIds =
        rawIds is List ? rawIds.whereType<String>().toList() : <String>[];
    if (readIds.isEmpty) return;
    // A 1:1 room's id is the peer's snowId: only this user's messages to
    // the receipt's authenticated sender are flipped.
    final updated = await _messageDao.markOutgoingAsRead(
      readIds,
      myId: _myIdResolver(),
      conversationId: sender,
    );
    debugPrint('[DIAG:SealedControl] $messageId read receipt applied '
        '($updated/${readIds.length} rows -> read)');
  }

  /// Apply a decrypted unsend ("delete for everyone"): physically remove the
  /// referenced rows. Mirrors GlobalMessageRouter._handleMessageDeleted
  /// (attachment files + attachment rows + message row) so drift watchers
  /// update the UI.
  ///
  /// SECURITY guard: only delete a row actually sent BY the unsend's
  /// authenticated sender. The sealed envelope's sender certificate + TOFU
  /// session pinning make [unsendSender] trustworthy; without this check a peer
  /// could reference a row id of a message we received from someone else and
  /// force us to delete it. senderSnowchatId mismatch → skip.
  ///
  /// The 5-minute unsend window is enforced on the SENDER side only (best-
  /// effort UX convention, mirroring read receipts). The recipient cannot
  /// robustly re-enforce it: the only timestamp the sender controls is
  /// `deletedAt`, and deleting one's own older message is a UX-policy matter,
  /// not a security boundary. The senderSnowchatId guard above is the real
  /// protection.
  ///
  /// A missing / mismatched row is a benign no-op (already gone / id-swap race).
  /// Apply a peer's sealed delete-chat: wipe this device's copy of the 1:1
  /// room (messages + conversation row) and the peer's Signal session.
  ///
  /// The drift work happens HERE rather than in [onPeerDeletedChat] because the
  /// queue drains on cold start BEFORE ConversationListNotifier is constructed
  /// and wires its callbacks: the control was decrypted, dispatched and ACKed
  /// while the callback was still null, so the room survived and the delete was
  /// lost for good (the ACK means the server drops its copy). Measured on the
  /// rig 2026-09-04. Same rule as [_applyUnsend] — the queue owns durable state
  /// changes; callbacks only refresh in-memory UI.
  ///
  /// Wiping the session mirrors ConversationListNotifier.applyPeerChatDeletion:
  /// the peer deleting the chat means both sides want a fresh start, and a
  /// retained ratchet would spin session_reset on the next exchange.
  Future<void> _applyDeleteChat(String peerSnowchatId) async {
    // A 1:1 room's id is the peer's snowId.
    final roomId = peerSnowchatId;
    try {
      await _conversationDao.deleteConversation(roomId);
      debugPrint('[DIAG:SealedControl] delete_chat wiped the room');
    } catch (e) {
      debugPrint('[DIAG:SealedControl] delete_chat drift cleanup failed: $e');
    }
    try {
      await _sessionMgr.deleteSessionForPeer(peerSnowchatId);
    } catch (e) {
      debugPrint('[DIAG:SealedControl] delete_chat session wipe failed: '
          '${e.runtimeType}');
    }
    await onPeerDeletedChat?.call(peerSnowchatId, roomId);
  }

  /// Group protocol v2: keep a decrypted invite message (onGv2Invite)
  /// before the envelope is acknowledged. Nothing of it is logged (it
  /// carries a group's master key). Whatever becomes of it, the envelope is
  /// consumed: its 1:1 session counter is spent and it could not be
  /// decrypted again — only a failure of this device's database loses it.
  Future<void> _applyGv2Invite(Message decrypted) async {
    final keep = onGv2Invite;
    final encoded = decrypted.metadata?['invite'];
    if (keep == null || encoded is! String) return;
    final Uint8List invite;
    try {
      invite = base64Decode(encoded);
    } on FormatException {
      return;
    }
    try {
      await keep(decrypted.senderSnowchatId, invite, decrypted.id);
    } catch (e) {
      debugPrint('[Queue] gv2 invite not kept: ${e.runtimeType}');
    }
  }

  /// A contact notice: handed to the contact store (onContactNotice) with
  /// the name certificate it carried. Whatever becomes of it, the envelope
  /// is consumed — a lost notice only leaves a label behind (§5.3).
  Future<void> _applyContactNotice(Message decrypted, String messageId) async {
    _contactNoticeIds.add(messageId);
    if (_contactNoticeIds.length > _noticeIdsKept) {
      _contactNoticeIds.remove(_contactNoticeIds.first);
    }
    final notice = decrypted.metadata?['notice'];
    final apply = onContactNotice;
    if (apply == null || notice is! String) return;
    try {
      await apply(
        decrypted.senderSnowchatId,
        notice,
        decrypted.peerNameCert,
        decrypted.metadata?['answer'] == true,
      );
    } catch (e) {
      debugPrint('[Queue] contact notice not applied: ${e.runtimeType}');
    }
  }

  /// A message's name certificate: checked and applied (onPeerNameCert).
  /// Never throws — the message is stored either way.
  Future<void> _applyNameCert(String sender, String cert) async {
    final apply = onPeerNameCert;
    if (apply == null) return;
    try {
      await apply(sender, cert);
    } catch (e) {
      debugPrint('[Queue] name certificate not applied: ${e.runtimeType}');
    }
  }

  Future<void> _applyUnsend(Map<String, dynamic> metadata,
      String unsendSender, String messageId) async {
    final rawIds = metadata['deleteIds'];
    final deleteIds =
        rawIds is List ? rawIds.whereType<String>().toList() : <String>[];
    if (deleteIds.isEmpty) return;
    final docsDir = await getApplicationDocumentsDirectory();
    var removed = 0;
    // Conversations whose last-message preview may now be stale (the removed
    // row could have been their newest message). Captured before deletion.
    final affectedConvIds = <String>{};
    for (final id in deleteIds) {
      try {
        final row = await _messageDao.getMessageById(id);
        if (row == null) continue; // already gone / id-swap race
        if (row.senderSnowchatId != unsendSender) {
          debugPrint('[DIAG:SealedControl] unsend $id rejected — sender '
              'mismatch');
          continue;
        }
        // Delete decrypted attachment blobs. localPath is stored RELATIVE to
        // the app documents dir (snowchat_attachments/…), so resolve it or the
        // decrypted file orphans on disk — defeating the point of an unsend.
        final attachments = await _attachmentDao.getForMessage(id);
        for (final att in attachments) {
          final lp = att.localPath;
          if (lp != null && lp.isNotEmpty) {
            try {
              final f = File(lp.startsWith('/') ? lp : '${docsDir.path}/$lp');
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
          }
        }
        if (attachments.isNotEmpty) {
          await _attachmentDao.deleteForMessage(id);
        }
        affectedConvIds.add(row.conversationId);
        await _messageDao.deleteMessage(id);
        removed++;
      } catch (e) {
        debugPrint('[DIAG:SealedControl] unsend $id failed: $e');
      }
    }
    debugPrint('[DIAG:SealedControl] $messageId unsend applied '
        '($removed/${deleteIds.length} rows removed)');
    // Recompute the denormalized conversation preview for each affected room —
    // the unsent message may have been its newest, and the drift/in-memory
    // snippet would otherwise keep showing the now-deleted text.
    for (final convId in affectedConvIds) {
      onConversationPreviewStale?.call(convId);
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
      envelope['_consumed'] = true;
      return;
    }

    debugPrint('[DIAG:Sealed] $messageId start');
    final decrypted = await _e2eeHandler.decryptSealedMessage(envelope);
    final senderId = decrypted.senderSnowchatId;
    // Sealed Sender routing: the room of a 1:1 message is its sender's —
    // the certificate-authenticated sender of the unsealed envelope — whose
    // snowId is the room id (1:1 rooms are peer-keyed since 2026-08-07). The
    // conversation id the sender embedded is its own perspective and never
    // used.
    final convId = senderId;
    debugPrint('[DIAG:Sealed] $messageId decrypted');

    // Sealed read receipt (2026-07-15): normally arrives as wire type
    // 'sealed_control' (handled by _processSealedControl). This branch is
    // defense-in-depth — MUST run before the drift insert below so a
    // receipt can never render as a phantom empty bubble or bump unread.
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isReadReceipt'] == true) {
      debugPrint('[DIAG:Sealed] $messageId READ_RECEIPT via sealed path — drift skip');
      await _applyReadReceipt(
          decrypted.metadata!, decrypted.senderSnowchatId, messageId);
      _enqueueAck(messageId);
      envelope['_consumed'] = true;
      return;
    }

    // Same defense-in-depth for unsend: a control payload arriving on the
    // non-control (control:false) sealed path must NOT insert a phantom empty
    // system bubble. Apply (senderSnowchatId-guarded, so harmless) and skip.
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isUnsend'] == true) {
      debugPrint('[DIAG:Sealed] $messageId UNSEND via sealed path — drift skip');
      await _applyUnsend(
          decrypted.metadata!, decrypted.senderSnowchatId, messageId);
      _enqueueAck(messageId);
      envelope['_consumed'] = true;
      return;
    }

    // A session_reset control on the non-control sealed path: the decrypt
    // already built the session — consume it, never a phantom bubble.
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isSessionReset'] == true) {
      debugPrint('[DIAG:Sealed] $messageId SESSION_RESET via sealed path — drift skip');
      _enqueueAck(messageId);
      envelope['_consumed'] = true;
      return;
    }

    // Group protocol v2 invite: handed to the v2 group actions and consumed.
    // No conversation row, no message row, no banner, no notification — an
    // invite is not a 1:1 message, and must not open a 1:1 room with the
    // inviter.
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isGroupInviteV2'] == true) {
      await _applyGv2Invite(decrypted);
      _enqueueAck(messageId);
      envelope['_consumed'] = true;
      return;
    }

    // A contact notice (contact_added — pushed like a message): to the
    // contact store. No conversation row, no message row, no unread.
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isContactNotice'] == true) {
      await _applyContactNotice(decrypted, messageId);
      _enqueueAck(messageId);
      envelope['_consumed'] = true;
      return;
    }

    // An inner type this build does not know: consumed, never shown — no
    // room, no bubble, no notification (contract §12.4).
    if (decrypted.metadata != null &&
        decrypted.metadata!['_isUnknownType'] == true) {
      debugPrint('[DIAG:Sealed] $messageId unknown inner type — consumed');
      _enqueueAck(messageId);
      envelope['_consumed'] = true;
      return;
    }

    // The same message sent again by the sender's outbox (its ack was lost):
    // stored already under the first copy's id — this copy is only acked.
    if (await _isRepeatFromPeer(senderId, decrypted.peerClientId)) {
      debugPrint('[DIAG:Sealed] $messageId repeat of a stored message — ACK, not stored');
      envelope['_consumed'] = true;
      return;
    }

    final tsStr = (envelope['serverTimestamp'] ?? envelope['createdAt']) as String?;
    final timestamp =
        tsStr != null ? DateTime.parse(tsStr) : DateTime.now();
    final ttl = decrypted.ttlSeconds;

    // Ensure the conversation row exists.
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
    // The sender's name certificate (first message, or a renamed sender):
    // checked and applied before the room, the banner and the notification
    // read the name — never a lookup on the server.
    final cert = decrypted.peerNameCert;
    if (cert != null) await _applyNameCert(senderId, cert);

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
      peerClientId: Value(decrypted.peerClientId),
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
    debugPrint('[DIAG:Sealed] $messageId INSERTED into drift');

    // Sealed envelopes carry no senderDisplayName (zero-knowledge). The
    // room's title holds the name from the sender's verified name
    // certificate (NameCertService, applied above) — reuse it. A title equal
    // to the snowId is unresolved (findOrCreate writes the snowId until a
    // certificate names the sender).
    final convRow = await _conversationDao.getConversation(convId);
    final convTitle = convRow?.title;
    final resolvedSenderName = (convTitle != null &&
            convTitle.isNotEmpty &&
            convTitle != senderId)
        ? convTitle
        : (await _knownName(senderId) ?? _truncateSnowId(senderId));

    _maybeShowMessageBanner(
      isViewing: isViewing,
      conversationId: convId,
      senderId: resolvedSenderName,
      plaintext: decrypted.plaintext,
    );

    // Live-read receipt (sealed path) — same fire-and-forget as 1:1 above.
    if (isViewing) {
      unawaited(_e2eeHandler
          .sendSealedReadReceipt(recipientId: senderId, readIds: [messageId])
          .catchError((Object e) {
        debugPrint('[DIAG:Sealed] live read receipt failed (dropped): $e');
      }));
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

  /// The name this device knows for [snowId] (peerName), or null. Never
  /// throws.
  Future<String?> _knownName(String snowId) async {
    try {
      final name = await peerName?.call(snowId);
      return (name != null && name.isNotEmpty) ? name : null;
    } catch (_) {
      return null;
    }
  }

  /// True when the app's UI is active and the in-app banner can be shown.
  /// AppLifecycleState.resumed = visible & receiving input. inactive/paused/
  /// hidden/detached all mean the OS notification path should win.
  bool _isAppInForeground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == AppLifecycleState.resumed;
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
      // Creates the dir with its at-rest policy (iOS: backup-excluded,
      // CompleteUnlessOpen — writable while locked, unreadable once closed).
      await AttachmentStorage.ensureDirectory();
      final relativePath = AttachmentStorage.relativePathFor(fileId, fileName);
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
    String errorCode, {
    String? authedSender,
  }) async {
    try {
      // The sender is the certificate-authenticated one of a sealed unseal
      // (authedSender): the envelope names none.
      final senderSnow = authedSender ?? '';

      // The placeholder goes into the sender's 1:1 room — never into a
      // conversation the envelope names (see _processSealedMessage).
      final conversationId = senderSnow;

      final tsStr =
          (envelope['serverTimestamp'] ?? envelope['createdAt']) as String?;
      final timestamp =
          tsStr != null ? DateTime.tryParse(tsStr) : null;
      final dateSent = timestamp?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;

      // No authenticated sender (the envelope did not even unseal): there is
      // no room to put a placeholder in. A sealed message that unsealed to a
      // certificate-authenticated sender is a genuine first contact, so its
      // room and placeholder are made (INV-4: the loss must be visible).
      if (senderSnow.isEmpty) {
        debugPrint('[DIAG:Queue] $messageId no authenticated sender — no placeholder');
        return;
      }

      // Ensure the conversation row exists.
      final myId = _myIdResolver();
      await _conversationDao.findOrCreate(
        id: conversationId,
        type: 'direct',
        participantIds: [myId, senderSnow],
        title: senderSnow,
      );

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
          'convId=${logRef(conversationId)} sender=${logRef(senderSnow)}');
    } catch (placeholderErr) {
      // Placeholder insertion failure is serious but must not block the ACK
      // path — otherwise the server keeps re-delivering the undecryptable
      // message in an infinite loop. Log and continue.
      debugPrint('[DIAG:Queue] $messageId placeholder INSERT FAILED: '
          '$placeholderErr');
    }
  }

  // ---------------------------------------------------------------------------
  // Session reset after a failed decrypt
  // ---------------------------------------------------------------------------

  /// A sealed message from [authedSender] (certificate-authenticated at
  /// unseal) could not be decrypted: archive and reset the session so the
  /// sender's FUTURE messages decrypt — the peer learns of the new session
  /// from a sealed session_reset control. Nothing asks the sender to send it
  /// again: the server relays no retry requests (they named the sealed
  /// sender, SC-05); the stuck message is the visible placeholder (INV-4).
  Future<void> _resetAfterFailedDecrypt(
      String messageId, String? authedSender) async {
    if (authedSender == null || authedSender.isEmpty) return;
    try {
      await _sessionMgr.archiveAndResetSession(authedSender);
      debugPrint('[DIAG:Queue] $messageId session reset after a failed decrypt');
    } catch (e) {
      // Must not block the ACK path.
      debugPrint('[DIAG:Queue] $messageId session reset FAILED: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // ACK batching
  // ---------------------------------------------------------------------------

  void _enqueueAck(String messageId) {
    _acked.remove(messageId);
    _acked.add(messageId);
    if (_acked.length > _ackedLimit) _acked.remove(_acked.first);
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

  /// Group protocol v2: a message of a v2 group was stored by the local
  /// inbox (Gv2AppMessageSink, after its transaction committed). The same
  /// follow-ups as the v1 group path: the Chats-list preview, the in-app
  /// banner, the attachment rows and downloads, the expiry timer when the
  /// chat is open, and the local notification. [type] is a MessageType name.
  void gv2MessageStored({
    required String groupId,
    required String messageId,
    required String senderSnowId,
    required String plaintext,
    required String type,
    required Map<String, dynamic>? metadata,
    required int ttlSeconds,
    required bool viewing,
    required String? groupName,
    required String? senderName,
    required int receivedAtMs,
  }) {
    onGroupMessageDecoded?.call(
      groupId,
      senderSnowId,
      plaintext,
      DateTime.fromMillisecondsSinceEpoch(receivedAtMs),
    );
    // The preview callback above does not count unread messages (for a v1
    // room the socket listener does); the list's entry is read again from
    // the stored row, which has the count.
    onGv2GroupChanged?.call(groupId);
    _maybeShowMessageBanner(
      isViewing: viewing,
      conversationId: groupId,
      senderId: senderSnowId,
      plaintext: plaintext,
    );
    if (ttlSeconds > 0 && viewing) {
      _expiringManager.schedule(messageId, ttlSeconds);
    }
    final isFile = type == MessageType.file.name;
    final isVoice = type == MessageType.voice.name;
    if (metadata != null && (isFile || isVoice)) {
      _processIncomingAttachments(messageId, metadata);
    }
    if (!viewing) {
      final String preview;
      if (isVoice) {
        preview = 'Voice message';
      } else if (isFile) {
        final mime = metadata?['mimeType'] as String? ?? '';
        preview = mime.startsWith('image/') ? 'Photo' : 'File';
      } else {
        preview = plaintext;
      }
      NotificationService().showGroupNotification(
        groupName: groupName ?? 'Group Chat',
        senderName: senderName ?? _truncateSnowId(senderSnowId),
        preview: preview,
        conversationId: groupId,
      );
    }
  }

  /// Group protocol v2: messages of [groupId] were removed (an unsend, a
  /// cleared history): its Chats-list preview is recomputed.
  void gv2MessagesRemoved(String groupId) =>
      onConversationPreviewStale?.call(groupId);

  /// Group protocol v2: [groupId] changed on this device (its conversation
  /// row and system lines are written): the Chats list follows.
  void gv2GroupChanged(String groupId) => onGv2GroupChanged?.call(groupId);

  /// Truncate a SnowChat ID for display in notifications.
  String _truncateSnowId(String snowId) {
    if (snowId.length > 12) {
      return '${snowId.substring(0, 8)}...${snowId.substring(snowId.length - 4)}';
    }
    return snowId;
  }
}
