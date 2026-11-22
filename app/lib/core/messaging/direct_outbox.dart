/// @file        direct_outbox.dart
/// @description The 1:1 outbox. An outgoing 1:1 message (text, file, voice) is shown and stored
///              at once as `sending`; a job here sends it — whenever the socket is connected,
///              oldest first per peer, one at a time — and keeps it until the server acks it.
///              The job outlives the chat screen and the app process (it is a drift row), so a
///              message written while offline goes out on the next connection instead of
///              vanishing, and a send whose ack never came is tried again (the receiver stores a
///              message once per (sender, cid), so a repeat is harmless). An attachment that
///              could not be uploaded yet is uploaded by the job first, from the kept local copy.
///              Design: Documentation/TO-DO/2026-11-21-direct-outbox-design.md.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-22 (review fixes: the outbox owns the sent / delivered marks of its messages —
///              every send has a wire id of its own (newWireMessageId), and the server's status events,
///              which echo it, are mapped back to the message: a "delivered" that comes before the ack
///              is written with the settle, one after it to the server's row; a contact_added waits
///              for this account's name certificate only noticeCertAttempts attempts, then goes without
///              one (the peer shows its chat name until the next message carries the certificate),
///              so the peer's lane is never held for days; dropPeer() — a blocked account's jobs go
///              (its messages read failed); a contact_removed takes the place of a contact_added to
///              the same peer that was not sent yet). Earlier 2026-11-22 (onRecipientChecked: the server's word on a job's recipient — it took
///              the send, or refused it with USER_NOT_FOUND — goes to the contact list, which shows
///              an account refused again and again as unavailable). Earlier 2026-11-22 (contact notices — design 2026-11-22-friend-graph-off-server §5.3: a
///              `control` job kind that is not tied to a local_messages row and carries its own
///              inner payload (contact_added / contact_removed); sent sealed after the peer's
///              identity is refreshed, kept until the server's ack, given up after
///              controlMaxAge (7 days), in order with the peer's messages. A message carries this
///              account's name certificate when the peer was not sent the current one yet
///              (NameCertService); the wire clientMessageId is a random UUID — the local id travels
///              only inside the E2EE payload). Earlier 2026-11-22 (SC-05: sealed only — with Sealed
///              Sender not active the message waits (later); the non-sealed fallback is gone).
///              Earlier 2026-11-21
///
/// @functions
///  - DirectOutbox.start() / stop(): follow the socket (drain on connect) / stop
///  - DirectOutbox.enqueueText(): queue a text message
///  - DirectOutbox.enqueueAttachment(): queue a file or voice message (upload, then send)
///  - DirectOutbox.enqueueNotice(): queue a contact notice (a control job, no message row); a
///    contact_removed drops a contact_added to the same peer not sent yet
///  - DirectOutbox.dropPeer(): every job of a peer goes (the account was blocked)
///  - DirectOutbox.retry(): send a failed message again (the bubble's "tap to retry")
///  - DirectOutbox.drain(): send what may go now
///  - DirectOutbox.backoff(): the wait after a number of failed attempts
///  - DirectSendOutcome: what one attempt came to
///  - RecipientChecked: the server took a send to a peer, or said the peer does not exist
///
/// Notes:
///  - The message's status lives on its local_messages row (`outgoingStatus`), which every open
///    chat screen watches: `sending` while a job exists, `sent` (with the local id swapped for the
///    server's) on the ack, `failed` after a refusal or DirectOutbox.maxAge.
///  - A control job (kind DirectOutbox.controlKind) has no row: its id is a random UUID, it ends
///    on the ack, and a refusal or DirectOutbox.controlMaxAge just drops it (a lost contact
///    notice only leaves a label behind — §5.3).
///  - Encryption happens at the moment of sending, never at enqueue: the Double Ratchet must see
///    the messages in the order they leave, and a session reset must not leave stale ciphertext.
///  - Status marks: the server's message_status events name a send by its wire id (the
///    clientMessageId it echoes — a random UUID per attempt, never the local id). The outbox keeps
///    wire id → message id in memory while the message waits for its settle; a mark for a message
///    sent before the app restarted is lost (a read receipt still comes).
///  - Nothing is logged but message ids and outcome kinds — never text, keys or metadata.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../features/chat/models/message.dart' show MessageType;
import '../../features/chat/providers/expiring_message_manager.dart';
import '../contacts/contact_notice.dart';
import '../contacts/name_cert_service.dart';
import '../contacts/name_certificate.dart';
import '../crypto/encrypted_message_handler.dart';
import '../crypto/file_encryptor.dart';
import '../crypto/identity_binding.dart';
import '../crypto/identity_binding_exception.dart';
import '../crypto/signal_protocol_service.dart' show SignalProtocolException;
import '../storage/daos/attachment_dao.dart';
import '../storage/daos/direct_outbox_dao.dart';
import '../storage/daos/message_dao.dart';
import '../storage/database.dart';
import '../storage/tables/direct_outbox_table.dart';

/// What one attempt of a job came to.
enum DirectSendOutcome {
  /// The server took it (or the job's message is gone): the job is over.
  done,

  /// Not now — no socket, no ack in time, a server hiccup: tried again later.
  later,

  /// Refused for good (the recipient does not exist, the request is invalid,
  /// the peer's identity binding is forged, the kept file is gone): failed.
  refused,
}

/// The server took a send to [peer] ([notFound] false), or refused it
/// because no such account exists ([notFound] true — USER_NOT_FOUND).
typedef RecipientChecked = Future<void> Function(String peer, bool notFound);

/// Uploads an encrypted attachment; returns the server's file id.
typedef DirectUpload = Future<String> Function(
    Uint8List encryptedData, String contentHash);

class DirectOutbox {
  DirectOutbox({
    required DirectOutboxDao jobs,
    required MessageDao messages,
    required AttachmentDao attachments,
    required EncryptedMessageHandler Function() handler,
    required bool Function() isConnected,
    required Stream<bool> connectionChanges,
    Stream<Map<String, dynamic>>? statusEvents,
    required DirectUpload upload,
    required Future<String> Function() documentsPath,
    ExpiringMessageManager? expiring,
    NameCertService? nameCerts,
    RecipientChecked? onRecipientChecked,
    DateTime Function()? now,
    this.ackTimeout = const Duration(seconds: 20),
  })  : _nameCerts = nameCerts,
        _onRecipientChecked = onRecipientChecked,
        _jobs = jobs,
        _messages = messages,
        _attachments = attachments,
        _handler = handler,
        _isConnected = isConnected,
        _connectionChanges = connectionChanges,
        _statusEvents = statusEvents,
        _upload = upload,
        _documentsPath = documentsPath,
        _expiring = expiring,
        _now = now ?? DateTime.now;

  /// A message not taken by the server this long after it was written fails
  /// (the user can send it again from the bubble).
  static const Duration maxAge = Duration(hours: 24);

  /// A control job (a contact notice) not taken by the server this long
  /// after it was queued is dropped.
  static const Duration controlMaxAge = Duration(days: 7);

  /// The job kind of a control (a contact notice): no local_messages row.
  static const String controlKind = 'control';

  /// Attempts a contact_added waits for this account's name certificate
  /// (the server could not give one: offline, rate-limited) before it goes
  /// without one. With [backoff] that is a few seconds while connected — the
  /// peer's lane (its messages after the notice) is never held longer.
  static const int noticeCertAttempts = 3;

  /// The first wait after a failed attempt; doubled per attempt up to
  /// [maxBackoff]. A reconnect lets every job go at once anyway.
  static const Duration baseBackoff = Duration(seconds: 2);
  static const Duration maxBackoff = Duration(minutes: 5);

  /// Server ack codes that will not change by trying again.
  static const Set<String> refusedCodes = {
    'INVALID_REQUEST',
    'USER_NOT_FOUND',
    'UNSUPPORTED_TYPE',
    'FORBIDDEN',
    'NOT_FOUND',
    'SEALED_RETRY_UNSUPPORTED',
  };

  /// How long a send waits for the server's ack before it counts as not
  /// delivered (an ack that comes later still settles the message).
  final Duration ackTimeout;

  final DirectOutboxDao _jobs;
  final MessageDao _messages;
  final AttachmentDao _attachments;
  final EncryptedMessageHandler Function() _handler;
  final bool Function() _isConnected;
  final Stream<bool> _connectionChanges;
  final Stream<Map<String, dynamic>>? _statusEvents;
  final DirectUpload _upload;
  final Future<String> Function() _documentsPath;
  final ExpiringMessageManager? _expiring;
  final NameCertService? _nameCerts;
  final RecipientChecked? _onRecipientChecked;
  final DateTime Function() _now;

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _statusSub;

  /// Wire id of a send → the local id of its message (every attempt has its
  /// own wire id). Kept past the settle — the newest [_wireIdsKept] — so a
  /// mark that comes after the ack still finds its message.
  final Map<String, String> _wireToLocal = {};
  static const int _wireIdsKept = 256;

  /// Messages the server said were delivered before their ack settled them.
  final Set<String> _deliveredEarly = {};
  Timer? _timer;
  bool _started = false;
  bool _stopped = false;
  bool _draining = false;
  bool _drainAgain = false;
  Future<void>? _drainDone;

  /// The wait after [attempts] failed attempts.
  static Duration backoff(int attempts) {
    if (attempts <= 0) return Duration.zero;
    final shift = attempts - 1 > 16 ? 16 : attempts - 1;
    final ms = baseBackoff.inMilliseconds * (1 << shift);
    return ms > maxBackoff.inMilliseconds ? maxBackoff : Duration(milliseconds: ms);
  }

  int get _nowMs => _now().millisecondsSinceEpoch;

  /// Follow the socket: every (re)connect lets all jobs go at once. Drains
  /// what is queued from before (an earlier run of the app).
  void start() {
    if (_started) return;
    _started = true;
    _stopped = false;
    _connectionSub = _connectionChanges.listen((connected) {
      if (!connected) return;
      unawaited(() async {
        await _jobs.retryAllNow();
        await drain();
      }());
    });
    _statusSub = _statusEvents?.listen(_onStatus);
    unawaited(drain());
  }

  /// A message_status event of the server: a send of this outbox (by its
  /// wire id) was delivered to the peer's device. Before the ack settled the
  /// message the mark waits for the settle; after it, it goes to the row
  /// under the server's id (written either way — it only moves a `sent`
  /// row). ("sent" is the ack's; "read" comes as a sealed receipt.)
  void _onStatus(Map<String, dynamic> event) {
    final wire = event['clientMessageId'];
    if (wire is! String || event['status'] != 'delivered') return;
    final local = _wireToLocal[wire];
    if (local == null) return;
    _deliveredEarly.add(local);
    final serverId = event['messageId'];
    if (serverId is String && serverId.isNotEmpty) {
      unawaited(_markDelivered(serverId, local));
    }
  }

  Future<void> _markDelivered(String serverId, String local) async {
    try {
      // Settled already: the mark is on the row now, nothing waits for it.
      if (await _messages.markOutgoingDelivered(serverId) > 0) {
        _deliveredEarly.remove(local);
      }
    } catch (e) {
      debugPrint('[DirectOutbox] delivered mark not written: ${e.runtimeType}');
    }
  }

  void _forgetWireIds(String messageId) {
    _wireToLocal.removeWhere((_, local) => local == messageId);
    _deliveredEarly.remove(messageId);
  }

  Future<void> stop() async {
    _stopped = true;
    _started = false;
    _timer?.cancel();
    _timer = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    await _drainDone;
  }

  /// Queue the text message [messageId] (already stored and shown as
  /// `sending`) for [peer].
  Future<void> enqueueText({
    required String messageId,
    required String peer,
    required String text,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
  }) async {
    await _put(
      messageId: messageId,
      peer: peer,
      kind: MessageType.text,
      phase: DirectOutboxPhase.send,
      payload: {
        'text': text,
        'ttl': ?ttlSeconds,
        'replyToId': ?replyToId,
        'replyToPreview': ?replyToPreview,
        'replyToSenderId': ?replyToSenderId,
      },
    );
  }

  /// Queue the file or voice message [messageId] (already stored and shown
  /// as `sending`, its plaintext kept at [relativePath] under the app
  /// documents directory) for [peer]: the job uploads it, then sends.
  Future<void> enqueueAttachment({
    required String messageId,
    required String peer,
    required MessageType kind,
    required String text,
    required String relativePath,
    required String fileName,
    required String mimeType,
    required int size,
    int? durationSeconds,
    int? ttlSeconds,
  }) async {
    assert(kind == MessageType.file || kind == MessageType.voice);
    await _put(
      messageId: messageId,
      peer: peer,
      kind: kind,
      phase: DirectOutboxPhase.upload,
      payload: {
        'text': text,
        'ttl': ?ttlSeconds,
        'relativePath': relativePath,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': size,
        'duration': ?durationSeconds,
      },
    );
  }

  /// Queue the contact notice [notice] for [peer]: a control job with no
  /// message row, sent in order with the peer's messages. A contact_added
  /// takes this account's name certificate when it is sent.
  Future<void> enqueueNotice({
    required String peer,
    required ContactNotice notice,
  }) async {
    if (!IdentityBindingV1.isValidSnowId(peer)) {
      throw ArgumentError('outbox: not an account');
    }
    if (!notice.isAdded) {
      // "I removed you" after an "I added you" that did not leave yet (the
      // user requested and cancelled while offline): the peer never needs to
      // see the request. (One already on its way is followed by this.)
      for (final job in await _jobs.forPeer(peer)) {
        if (job.kind == controlKind && _isAddedNotice(job)) {
          await _jobs.remove(job.messageId);
        }
      }
    }
    await _jobs.put(DirectOutboxJobsCompanion.insert(
      messageId: newWireMessageId(),
      peer: peer,
      kind: controlKind,
      phase: DirectOutboxPhase.send,
      payload: jsonEncode({
        'inner': notice.inner,
        'control': notice.isControl,
        'nameCert': notice.carriesNameCert,
      }),
      createdAtMs: _nowMs,
      attempts: const Value(0),
      nextAttemptAtMs: const Value(0),
    ));
    unawaited(drain());
  }

  static bool _isAddedNotice(DirectOutboxRow job) {
    try {
      final payload = jsonDecode(job.payload);
      final inner = payload is Map ? payload['inner'] : null;
      return inner is Map && inner['type'] == contactAddedType;
    } catch (_) {
      return false;
    }
  }

  /// [peer] was blocked: every job of it goes — nothing more is sent to it.
  /// A message among them reads `failed` (the user can send it again after
  /// an unblock). Never throws.
  Future<void> dropPeer(String peer) async {
    try {
      for (final job in await _jobs.forPeer(peer)) {
        if (job.kind != controlKind) {
          await _messages.updateOutgoingStatus(job.messageId, 'failed');
        }
        _forgetWireIds(job.messageId);
      }
      await _jobs.removeForPeer(peer);
    } catch (e) {
      debugPrint('[DirectOutbox] jobs of a blocked account not dropped: '
          '${e.runtimeType}');
    }
  }

  /// Send the failed message [messageId] again: a new job built from its
  /// stored row (and, for an attachment never uploaded, its kept copy). False
  /// when it is not a failed 1:1 message of this device or there is nothing
  /// to send it from.
  Future<bool> retry(String messageId) async {
    final row = await _messages.getMessageById(messageId);
    if (row == null || row.outgoingStatus != 'failed') return false;
    final peer = row.conversationId;
    if (!IdentityBindingV1.isValidSnowId(peer)) return false;
    final ttl = row.expiresIn > 0 ? row.expiresIn : null;
    final kind = MessageType.values.asNameMap()[row.type];
    if (kind == null || kind == MessageType.system) return false;

    final String phase;
    final Map<String, Object?> payload;
    if (kind == MessageType.text) {
      phase = DirectOutboxPhase.send;
      payload = {
        'text': row.plaintext,
        'ttl': ?ttl,
        'replyToId': ?row.replyToId,
        'replyToPreview': ?row.replyToPreview,
        'replyToSenderId': ?row.replyToSenderId,
      };
    } else {
      Map<String, dynamic>? meta;
      try {
        final raw = row.metadata;
        if (raw != null) meta = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        meta = null;
      }
      if (meta != null && meta['fileId'] is String && meta['fileKey'] is String) {
        phase = DirectOutboxPhase.send;
        payload = {'text': row.plaintext, 'ttl': ?ttl, 'metadata': meta};
      } else {
        final atts = await _attachments.getForMessage(messageId);
        final kept = atts.where((a) => a.localPath != null).firstOrNull;
        if (kept == null) return false;
        phase = DirectOutboxPhase.upload;
        payload = {
          'text': row.plaintext,
          'ttl': ?ttl,
          'relativePath': kept.localPath,
          'fileName': (meta?['fileName'] as String?) ?? kept.fileName ?? 'file',
          'mimeType': kept.contentType,
          'size': kept.fileSize,
          'duration': ?(meta?['duration'] as int?),
        };
      }
    }
    await _messages.updateOutgoingStatus(messageId, 'sending');
    await _put(
      messageId: messageId,
      peer: peer,
      kind: kind,
      phase: phase,
      payload: payload,
    );
    return true;
  }

  Future<void> _put({
    required String messageId,
    required String peer,
    required MessageType kind,
    required String phase,
    required Map<String, Object?> payload,
  }) async {
    await _jobs.put(DirectOutboxJobsCompanion.insert(
      messageId: messageId,
      peer: peer,
      kind: kind.name,
      phase: phase,
      payload: jsonEncode(payload),
      createdAtMs: _nowMs,
      attempts: const Value(0),
      nextAttemptAtMs: const Value(0),
    ));
    unawaited(drain());
  }

  /// Send what may go now. Concurrent calls fold into the running one (it
  /// passes over the jobs again before it ends).
  Future<void> drain() {
    if (_stopped) return Future.value();
    if (_draining) {
      _drainAgain = true;
      return _drainDone ?? Future.value();
    }
    _draining = true;
    final done = _drainLoop();
    _drainDone = done;
    return done;
  }

  Future<void> _drainLoop() async {
    try {
      while (!_stopped) {
        _drainAgain = false;
        final progressed = await _pass();
        if (!progressed && !_drainAgain) break;
      }
    } catch (e) {
      debugPrint('[DirectOutbox] drain failed: ${e.runtimeType}');
    } finally {
      _draining = false;
      await _armTimer();
    }
  }

  /// One pass: fail what is too old, then try the oldest job of each peer
  /// that is due. True when a job ended (so the next of its peer may go).
  Future<bool> _pass() async {
    final now = _nowMs;
    var progressed = false;
    final peersSeen = <String>{};
    for (final job in await _jobs.allJobs()) {
      if (_stopped) return progressed;
      if (now - job.createdAtMs > _maxAgeOf(job).inMilliseconds) {
        debugPrint('[DirectOutbox] ${job.messageId} too old — failed');
        await _fail(job);
        progressed = true;
        continue;
      }
      // Only the oldest job of a peer may go: its messages keep their order.
      if (!peersSeen.add(job.peer)) continue;
      if (job.nextAttemptAtMs > now) continue;
      if (!_isConnected()) continue;
      final outcome = await _attempt(job);
      switch (outcome) {
        case DirectSendOutcome.done:
          progressed = true;
        case DirectSendOutcome.refused:
          await _fail(job);
          progressed = true;
        case DirectSendOutcome.later:
          final attempts = job.attempts + 1;
          await _jobs.postpone(
            job.messageId,
            attempts: attempts,
            nextAttemptAtMs: _nowMs + backoff(attempts).inMilliseconds,
          );
      }
    }
    return progressed;
  }

  static Duration _maxAgeOf(DirectOutboxRow job) =>
      job.kind == controlKind ? controlMaxAge : maxAge;

  Future<DirectSendOutcome> _attempt(DirectOutboxRow job) async {
    if (job.kind == controlKind) return _sendControl(job);
    // The message went away (deleted, expired) or was settled under the
    // server's id already (a status event swapped it): nothing to send.
    if (await _messages.getMessageById(job.messageId) == null) {
      await _jobs.remove(job.messageId);
      return DirectSendOutcome.done;
    }
    final kind = MessageType.values.asNameMap()[job.kind];
    if (kind == null) return DirectSendOutcome.refused;
    var payload = (jsonDecode(job.payload) as Map).cast<String, dynamic>();
    if (job.phase == DirectOutboxPhase.upload) {
      final (uploaded, outcome) = await _uploadAttachment(job, payload);
      if (uploaded == null) return outcome;
      payload = uploaded;
    }
    return _send(job, kind, payload);
  }

  /// Upload the kept copy of [job]'s attachment. Returns the payload with
  /// the E2EE metadata, or null with why not (`later`: no network / server;
  /// `refused`: the kept copy is gone).
  Future<(Map<String, dynamic>?, DirectSendOutcome)> _uploadAttachment(
    DirectOutboxRow job,
    Map<String, dynamic> payload,
  ) async {
    final relativePath = payload['relativePath'] as String?;
    final fileName = payload['fileName'] as String? ?? 'file';
    final mimeType = payload['mimeType'] as String? ?? 'application/octet-stream';
    if (relativePath == null) return (null, DirectSendOutcome.refused);
    final Uint8List bytes;
    try {
      final file = File('${await _documentsPath()}/$relativePath');
      if (!await file.exists()) {
        debugPrint('[DirectOutbox] ${job.messageId} kept copy is gone — failed');
        return (null, DirectSendOutcome.refused);
      }
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return (null, DirectSendOutcome.refused);
    }
    final String fileId;
    final EncryptedFileResult enc;
    try {
      // XSalsa20-Poly1305 with a fresh key per upload: the server stores
      // only ciphertext; the key travels inside the E2EE payload.
      enc = await FileEncryptor.encryptFile(bytes);
      fileId = await _upload(enc.encryptedData, enc.contentHash);
    } catch (e) {
      debugPrint('[DirectOutbox] ${job.messageId} upload not done '
          '(${e.runtimeType}) — later');
      return (null, DirectSendOutcome.later);
    }
    final size = (payload['size'] as int?) ?? bytes.length;
    final duration = payload['duration'] as int?;
    final metadata = <String, dynamic>{
      'fileId': fileId,
      'fileName': fileName,
      'mimeType': mimeType,
      'size': size,
      'duration': ?duration,
      'fileKey': base64Encode(enc.fileKey),
      'contentHash': enc.contentHash,
      // The multi-attachment shape the receiver's queue consumes.
      'attachments': [
        {'fileId': fileId, 'fileName': fileName, 'mimeType': mimeType, 'size': size},
      ],
    };
    final next = {...payload, 'metadata': metadata};
    await _messages.updateMetadata(job.messageId, jsonEncode(metadata));
    await _attachments.markUploaded('att_${job.messageId}_0', fileId);
    await _jobs.toSend(job.messageId, jsonEncode(next));
    return (next, DirectSendOutcome.done);
  }

  Future<DirectSendOutcome> _send(
    DirectOutboxRow job,
    MessageType kind,
    Map<String, dynamic> payload,
  ) async {
    final text = payload['text'] as String? ?? '';
    final ttl = payload['ttl'] as int?;
    final metadata = (payload['metadata'] as Map?)?.cast<String, dynamic>();
    final ack = Completer<Object?>();
    var waiting = true;
    void onAck(dynamic response) {
      if (waiting) {
        if (!ack.isCompleted) ack.complete(response);
      } else {
        // An ack after the wait gave up still settles the message.
        unawaited(_settle(job.messageId, response));
      }
    }

    final handler = _handler();
    if (!handler.isSealedSenderAvailable) {
      // Sealed only (SC-05, 2026-11-10 report): never a non-sealed send that
      // names the sender to the server. Sealed Sender is active as soon as
      // an account is signed in (the server keys are pinned in the build) —
      // until then the message waits.
      debugPrint('[DirectOutbox] ${job.messageId} sealed sender not active — later');
      return DirectSendOutcome.later;
    }
    // This account's name goes with the first message to a peer and with
    // the next one after it changed (NameCertService) — never asked for.
    final cert = await _nameCertFor(job.peer);
    // The server's status events for this send name its wire id.
    final wireId = newWireMessageId();
    _wireToLocal[wireId] = job.messageId;
    if (_wireToLocal.length > _wireIdsKept) {
      _wireToLocal.remove(_wireToLocal.keys.first);
    }
    try {
      await handler.sendSealedMessage(
        conversationId: job.peer,
        recipientId: job.peer,
        text: text,
        clientMessageId: job.messageId,
        wireMessageId: wireId,
        type: kind,
        metadata: metadata,
        ttlSeconds: ttl,
        replyToId: payload['replyToId'] as String?,
        replyToPreview: payload['replyToPreview'] as String?,
        replyToSenderId: payload['replyToSenderId'] as String?,
        nameCert: cert?.base64,
        onAck: onAck,
      );
    } on IdentityBindingInvalidException {
      // B-2: the peer's identity binding is forged / downgraded / replayed —
      // terminal for this message (the security notice was emitted).
      waiting = false;
      return DirectSendOutcome.refused;
    } catch (e) {
      // No session yet (prekeys not reachable), no certificate: later.
      waiting = false;
      debugPrint('[DirectOutbox] ${job.messageId} not sent (${e.runtimeType}) — later');
      return DirectSendOutcome.later;
    }

    final response = await ack.future.timeout(ackTimeout, onTimeout: () => null);
    waiting = false;
    if (response == null) {
      debugPrint('[DirectOutbox] ${job.messageId} no ack in time — later');
      return DirectSendOutcome.later;
    }
    final error = response is Map ? response['error'] : null;
    if (error != null) {
      final code = error is Map ? error['code'] as String? : null;
      debugPrint('[DirectOutbox] ${job.messageId} refused by the server ($code)');
      if (code == 'USER_NOT_FOUND') await _recipientChecked(job.peer, notFound: true);
      return refusedCodes.contains(code)
          ? DirectSendOutcome.refused
          : DirectSendOutcome.later;
    }
    await _settle(job.messageId, response);
    if (cert != null) await _announced(job.peer, cert);
    await _recipientChecked(job.peer, notFound: false);
    return DirectSendOutcome.done;
  }

  /// This account's certificate when [peer] should get it with the next
  /// envelope, or null. Never throws.
  Future<NameCertificate?> _nameCertFor(String peer, {bool always = false}) async {
    try {
      return await _nameCerts?.certToAttach(peer, always: always);
    } catch (_) {
      return null;
    }
  }

  Future<void> _announced(String peer, NameCertificate cert) async {
    try {
      await _nameCerts?.markAnnounced(peer, cert.issuedAtMs);
    } catch (_) {
      // Sent again with the next message: harmless.
    }
  }

  /// One attempt of a control job: seal its inner payload (with this
  /// account's name certificate when it carries one) after the peer's
  /// identity was refreshed, and wait for the server's ack.
  Future<DirectSendOutcome> _sendControl(DirectOutboxRow job) async {
    final Map<String, dynamic> payload;
    try {
      payload = (jsonDecode(job.payload) as Map).cast<String, dynamic>();
    } catch (_) {
      return DirectSendOutcome.refused;
    }
    final inner = payload['inner'];
    if (inner is! Map) return DirectSendOutcome.refused;
    final body = inner.cast<String, dynamic>();
    final handler = _handler();
    if (!handler.isSealedSenderAvailable) return DirectSendOutcome.later;
    NameCertificate? cert;
    if (payload['nameCert'] == true) {
      cert = await _nameCertFor(job.peer, always: true);
      if (cert != null) {
        body['nameCert'] = cert.base64;
      } else if (job.attempts < noticeCertAttempts) {
        // A contact notice names its sender by the certificate: it waits a
        // little for one (the server may be back in a moment)...
        debugPrint('[DirectOutbox] ${job.messageId} no name certificate — later');
        return DirectSendOutcome.later;
      }
      // ...but never holds the peer's lane for long: without one the peer
      // shows this account by its chat name, and the next message to it
      // carries the certificate (nothing was announced).
    }

    final ack = Completer<Object?>();
    var waiting = true;
    void onAck(dynamic response) {
      if (waiting && !ack.isCompleted) ack.complete(response);
    }

    try {
      await handler.sendSealedPayload(
        recipientId: job.peer,
        payload: body,
        control: payload['control'] == true,
        onAck: onAck,
      );
    } on IdentityBindingInvalidException {
      waiting = false;
      return DirectSendOutcome.refused;
    } on SignalProtocolException {
      waiting = false; // the identity directory cannot be reached
      return DirectSendOutcome.later;
    } catch (e) {
      waiting = false;
      debugPrint('[DirectOutbox] ${job.messageId} control not sent '
          '(${e.runtimeType}) — later');
      return DirectSendOutcome.later;
    }
    final response = await ack.future.timeout(ackTimeout, onTimeout: () => null);
    waiting = false;
    if (response is! Map) {
      debugPrint('[DirectOutbox] ${job.messageId} control: no ack in time — later');
      return DirectSendOutcome.later;
    }
    final error = response['error'];
    if (error != null) {
      final code = error is Map ? error['code'] as String? : null;
      debugPrint('[DirectOutbox] ${job.messageId} control refused ($code)');
      if (code == 'USER_NOT_FOUND') await _recipientChecked(job.peer, notFound: true);
      return refusedCodes.contains(code)
          ? DirectSendOutcome.refused
          : DirectSendOutcome.later;
    }
    if (response['messageId'] is! String) return DirectSendOutcome.later;
    await _jobs.remove(job.messageId);
    if (cert != null) await _announced(job.peer, cert);
    await _recipientChecked(job.peer, notFound: false);
    return DirectSendOutcome.done;
  }

  /// Tell the contact list what the server said about [peer]. Never throws
  /// (the send's outcome does not depend on it).
  Future<void> _recipientChecked(String peer, {required bool notFound}) async {
    try {
      await _onRecipientChecked?.call(peer, notFound);
    } catch (e) {
      debugPrint('[DirectOutbox] recipient check not noted: ${e.runtimeType}');
    }
  }

  /// The server took [messageId] ([response] is its ack): the row takes the
  /// server's id (with its attachment and expiry timer) and `sent`, and the
  /// job ends. Idempotent — a status event may have swapped the id first.
  Future<void> _settle(String messageId, Object? response) async {
    if (response is! Map || response['error'] != null) return;
    final serverId = response['messageId'];
    try {
      if (serverId is String && serverId.isNotEmpty) {
        // A "delivered" that came before this ack is written with it.
        final status =
            _deliveredEarly.contains(messageId) ? 'delivered' : 'sent';
        await _attachments.updateMessageId(messageId, serverId);
        await _messages.updateOutgoingStatus(messageId, status,
            serverMessageId: serverId);
        _expiring?.rekey(messageId, serverId);
      } else {
        // Taken without a row (a recipient that cannot receive this kind).
        await _messages.updateOutgoingStatus(messageId, 'sent');
      }
    } finally {
      _deliveredEarly.remove(messageId);
      await _jobs.remove(messageId);
    }
  }

  /// [job] ends without the server having taken it: a message row reads
  /// `failed`; a control job is dropped.
  Future<void> _fail(DirectOutboxRow job) async {
    if (job.kind != controlKind) {
      await _messages.updateOutgoingStatus(job.messageId, 'failed');
    }
    _forgetWireIds(job.messageId);
    await _jobs.remove(job.messageId);
  }

  /// Wake up for what is due next: a postponed peer head (only while
  /// connected — a reconnect drains by itself) or the age limit of the
  /// oldest job. Never sooner than [_minWake], so a job that cannot go now
  /// is never spun on.
  Future<void> _armTimer() async {
    _timer?.cancel();
    _timer = null;
    if (_stopped) return;
    final jobs = await _jobs.allJobs();
    if (jobs.isEmpty) return;
    final now = _nowMs;
    // The age limit of every job is a deadline in any case.
    var next = jobs
        .map((j) => j.createdAtMs + _maxAgeOf(j).inMilliseconds + 1)
        .reduce((a, b) => a < b ? a : b);
    if (_isConnected()) {
      final heads = <String>{};
      for (final j in jobs) {
        if (!heads.add(j.peer)) continue;
        if (j.nextAttemptAtMs > now && j.nextAttemptAtMs < next) {
          next = j.nextAttemptAtMs;
        }
      }
    }
    var delay = Duration(milliseconds: next - now);
    if (delay < _minWake) delay = _minWake;
    _timer = Timer(delay, () => unawaited(drain()));
  }

  static const Duration _minWake = Duration(seconds: 1);
}
