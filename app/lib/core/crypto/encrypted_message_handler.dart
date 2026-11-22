/// @file        encrypted_message_handler.dart
/// @description E2EE chat flow integration. Encrypt outgoing messages, decrypt incoming messages, 1:1 E2EE, file transfer handling. (Group messages are group protocol v2 — core/group_v2; only its invite travels here, as a sealed 1:1 message.)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (review fixes: every sealed 1:1 plaintext is padded with spaces to a multiple
///              of sealedPlaintextBlock (512 bytes — encodeSealedPlaintext), so a contact notice, a
///              short message with a name certificate and one without travel in envelopes of the same
///              size; sendSealedMessage takes the wire id from its caller (wireMessageId — the 1:1
///              outbox maps the server's status events back to its message); a contact_added marked
///              as an answer surfaces as metadata `answer`; a peer's metadata never carries a key of
///              this device's own (`_…`) and a peer's inner type is never `system`; onNewInboundSession
///              — a prekey message from a peer (a new session it started); no account id in a log
///              line). Earlier 2026-11-22 (friend graph off the server — design 2026-11-22 §5.2, §12.2, §12.4: every
///              sealed send carries a random UUID as its wire clientMessageId (no receipt_ / unsend_ /
///              delchat_ / reset_ / retry_ / gv2inv_ prefixes, SC-25); sendSealedPayload() seals a
///              raw inner payload after refreshing the peer's identity (the 1:1 outbox's control jobs
///              — contact_added / contact_removed — and the wallet's transfer notices); a message
///              may carry this account's name certificate (`nameCert`, top level) and the decrypt
///              returns a peer's as Message.peerNameCert; contact_added / contact_removed surface as
///              metadata `_isContactNotice`; an inner `type` this build does not know is consumed and
///              never shown (`_isUnknownType`). Part 3 E: the non-sealed 1:1 receive path
///              (decryptIncomingMessage) and the retry answer (sendSealedRetry — the server relays no
///              retry requests any more) are gone, and so is the send log record they read).
///              Earlier 2026-11-22 (SC-05: no non-sealed 1:1 send — sendEncryptedMessage and the unused
///              sendFileMessage / sendVoiceMessage are gone; session_reset and the retry answer are
///              sealed — sendSealedSessionReset / sendSealedRetry, and an inner `session_reset`
///              surfaces as metadata `_isSessionReset`; providers.dart sets sendSealedSessionReset as
///              the session manager's reset notifier). Earlier 2026-11-21 (1:1 payload carries `cid` — the sender's own message id — and decrypt
///              returns it as Message.peerClientId: the receiver stores a message the 1:1 outbox
///              sent again once). Earlier 2026-11-21 (X1: what an account this user blocked sent is decrypted — the session stays in step — and refused with BlockedSenderException before anything of it is acted on; isBlocked). Earlier 2026-11-21 (no IdentityKeyChangedException: the identity failure of a send or a sealed decrypt is IdentityBindingInvalidException alone). Earlier 2026-11-21 (comment: sendSealedDeleteChat is the only deletion signal — no server chat_deleted). Earlier 2026-11-20 (a decrypted 1:1 message's conversationId is its authenticated sender, never the envelope's. v1 groups removed: sendGroupMessage / decryptGroupMessage / sendGroupFileMessage / sendGroupVoiceMessage and the GroupSessionManager are gone. sendSealedGroupInvite() asks the identity directory first, so that an invite is never sealed to an identity the peer no longer has). Earlier 2026-11-13 (group protocol v2: sendSealedGroupInvite() — the 1:1 invite message, acknowledged by the server — and the sealed decrypt surfaces an incoming invite as metadata `_isGroupInviteV2` instead of a chat message). Earlier 2026-11-10 (B-2 Identity Binding v1: the send path no longer drops on an identity change — the Signal-style policy lives in IdentityAdmission (unverified legacy change → continue with notice; verified → IdentityKeyChangedException until re-verify; forged binding → IdentityBindingInvalidException) and both typed failures are rethrown untouched so callers mark the message failed without retry; user-visible notices come from VerifiedIdentityStore events. Receive paths pass the envelope / sealed-certificate deviceId to decrypt() for binding.deviceId matching and no longer cache an unverified incoming deviceId). Earlier 2026-09-04 (sealed delete-chat: sendSealedDeleteChat() sends inner type 'delete_chat' over the shared _sendSealedControl helper, and _doDecryptSealed surfaces it via metadata._isDeleteChat before the generic Message build so it never renders. Gives Delete-chat an offline-durable propagation path — the REST delete's chat_deleted socket event only reaches a peer connected at that instant). Earlier 2026-08-03 (F3: _doDecryptSealed now derives the Signal messageType from the unsealed DR ciphertext itself via resolveSealedMessageType() instead of the transport field socketEvent['messageType'] (which Sealed Sender never carries → always 1/0 → prekey first-contact messages misrouted as normal → X3DH responder session never built → first message to a brand-new contact lost). Also enforces Sealed Sender Step 9 identity cross-check on prekey messages). Earlier 2026-07-15 (sealed unsend: sendSealedUnsend() + inner type 'delete' over the shared _sendSealedControl helper (read-receipt path refactored onto it); _doDecryptSealed surfaces it via metadata._isUnsend. Sealed read receipt: sendSealedReadReceipt() sends a silent sealed_control envelope with inner type 'read_receipt'; surfaced via metadata._isReadReceipt before the generic Message build so it never renders). Earlier 2026-05-14 (decryptSealedMessage now accepts both 'sealedContent' (socket transport) and 'encryptedContent' (REST fetchPending) field names — swipe-killed cold-start sealed messages were silently lost because REST drain hit a StateError that placeholder + ACK swallowed)
///
/// @functions
///  - EncryptedMessageHandler: E2EE message encrypt/decrypt handler class (sealed 1:1 only)
///  - EncryptedMessageHandler.getDecryptedFileBytes(): Extract fileId/fileKey from message metadata, download and decrypt
///  - EncryptedMessageHandler.sendSealedMessage(): Send Sealed Sender 1:1 encrypted message (seal() wraps DR ciphertext)
///  - EncryptedMessageHandler.sendSealedPayload(): Seal a raw inner payload (contact notices, wallet notices) after refreshing the peer's identity
///  - EncryptedMessageHandler.sendSealedSessionReset(): Sealed control telling the peer this device re-established the session
///  - EncryptedMessageHandler.sendSealedReadReceipt() / sendSealedUnsend() / sendSealedDeleteChat(): silent sealed controls
///  - EncryptedMessageHandler.sendSealedGroupInvite(): the group protocol v2 invite over the sealed 1:1 path
///  - EncryptedMessageHandler.decryptSealedMessage(): Sealed Sender unseal + DR decrypt -> return Message
///  - newWireMessageId(): a random UUID for a sealed send's wire clientMessageId
///  - encodeSealedPlaintext(): the inner JSON as UTF-8, padded with spaces to a multiple of
///    sealedPlaintextBlock
///  - EncryptedMessageHandler._tryDispatchTransfer(): wallet V2 Phase B — transfer_* type dispatch + EventBus emit
///  - EncryptedMessageHandler._validateTransferRequest(): Validate UUID v4 / amount / decimals / mint / sentAt
///  - EncryptedMessageHandler._validateTransferResponse(): Validate walletAddress / Sig / ataRentLamports
///  - EncryptedMessageHandler._validateTransferCompleted(): Validate txHash non-empty Base58
///  - EncryptedMessageHandler._validateTransferFailed(): Validate requestId UUID v4
///  - EncryptedMessageHandler._isValidUuidV4(): UUID v4 regex validation (replay window guard)
///  - EncryptedMessageHandler._isValidBase58Address(): Solana Base58 32-byte validation (Ed25519HDPublicKey.fromBase58)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:solana/solana.dart' show Ed25519HDPublicKey;
import 'package:uuid/uuid.dart';

import '../blocking/block_list.dart' show BlockedSenderException;
import '../contacts/contact_notice.dart';
import '../../features/chat/models/message.dart';
import '../../features/wallet/models/transfer_request.dart';
import '../../features/wallet/services/transfer_event_bus.dart';
import '../network/file_service.dart';
import '../group_v2/gv2_invite.dart' show gv2InviteInnerType;
import '../network/socket_manager.dart';
import 'file_encryptor.dart';
import 'identity_binding_exception.dart';
import 'sealed_sender.dart';
import 'sender_certificate_manager.dart';
import 'signal_protocol_service.dart' show SignalProtocolException;
import 'signal_session_manager.dart';

/// Thrown when a Sealed Sender message unsealed successfully (so the sender is
/// certificate-authenticated) but the inner Signal (X3DH/Double Ratchet)
/// decryption then failed. Carries the authenticated sender so the message
/// queue can issue a TARGETED retry request + a real (non-phantom) placeholder
/// and, when the cause is our own missing signed prekey, trigger SPK self-heal —
/// instead of the blind sender=null retry the server rejects (which left
/// first-contact sealed messages silently lost).
///
/// [cause] preserves the original decryption error (e.g. "Signed prekey N not
/// found") so the queue's existing corruption/recoverable classification still
/// applies via toString().
class SealedDecryptException implements Exception {
  final String senderSnowchatId;
  final String senderDeviceId;
  final Object cause;
  const SealedDecryptException(
      this.senderSnowchatId, this.senderDeviceId, this.cause);

  // The sender is not in the text: it ends up in log lines.
  @override
  String toString() => 'SealedDecryptException: $cause';
}

/// A random UUID for the wire `clientMessageId` of a sealed send. The
/// server echoes it back and stores it with the row; it must say nothing —
/// not the kind of envelope, not the time, not the local message id
/// (contract §12.2, SC-25).
String newWireMessageId() => const Uuid().v4();

/// Every sealed 1:1 plaintext is padded to a multiple of this many bytes
/// (contract §12.4 "padding"). Measured (sealed_padding_test.dart): a contact
/// notice with this account's name certificate, a short message with the
/// certificate and a short message without it all fit one block, so their
/// envelopes are the same size — first contact (a prekey message) and later
/// alike.
const int sealedPlaintextBlock = 512;

/// [payload] as the plaintext of a sealed 1:1 envelope: its UTF-8 JSON
/// followed by spaces (0x20) up to the next multiple of
/// [sealedPlaintextBlock]. A JSON reader skips the spaces (they are JSON
/// whitespace), so a receiver decodes it like an unpadded one.
Uint8List encodeSealedPlaintext(Map<String, dynamic> payload) {
  final json = utf8.encode(jsonEncode(payload));
  final blocks = (json.length + sealedPlaintextBlock - 1) ~/ sealedPlaintextBlock;
  final out = Uint8List((blocks == 0 ? 1 : blocks) * sealedPlaintextBlock)
    ..setAll(0, json);
  out.fillRange(json.length, out.length, 0x20);
  return out;
}

/// Integrates E2EE with the chat flow — sealed 1:1 only (Part 3 E: the
/// non-sealed 1:1 path is gone on both sides).
///
/// - Encrypts and seals outgoing messages and controls before the socket
/// - Unseals and decrypts incoming sealed envelopes
/// - Carries the sealed invite of group protocol v2 and the contact notices
///
/// Socket send payload: { recipientId, sealedContent (base64),
///   clientMessageId (random UUID), expiresIn?, control? }
///
/// IMPORTANT: This handler never logs plaintext message content.
class EncryptedMessageHandler {
  final SignalSessionManager _sessionManager;
  final SocketManager _socketManager;
  final FileService? _fileService;
  // Sealed Sender service + certificate manager are lazy-wired.
  // `sealedSenderServiceProvider` is a StateProvider whose initial value
  // is null — the service activates once an account is signed in (from
  // the server keys pinned in the build). Constructing this handler reads the
  // current (often still-null) snapshot; the wireSealedSender() setter
  // lets providers.dart push the activated instance in later without
  // rebuilding the handler (and every consumer depending on it).
  // Without the setter, _sealedSenderService stayed null forever and
  // isSealedSenderAvailable returned false — production +286/+287
  // landed 0 sealed messages even though the code path was wired.
  SealedSenderService? _sealedSenderService;
  SenderCertificateManager? _senderCertificateManager;

  /// Set or replace the sealed sender service + certificate manager.
  /// Called by providers.dart's ref.listen when the lazy-init completes.
  void wireSealedSender({
    required SealedSenderService? service,
    required SenderCertificateManager? manager,
  }) {
    _sealedSenderService = service;
    _senderCertificateManager = manager;
  }

  /// Wallet V2 Phase B (2026-04-20): emit target after transfer_request /
  /// response / completed / failed payload dispatch. When null, transfer_*
  /// payloads are silent dropped (defensive against wallet module disabled
  /// environments). In production providers.dart always injects this.
  final TransferEventBus? _transferEventBus;

  /// In-flight decrypt futures: prevents double-decryption when two callers
  /// ask decryptSealedMessage for the same envelope at the same time.
  ///
  /// The Signal Double Ratchet is stateful — decrypting the same ciphertext
  /// twice corrupts the session. Because both listeners start before either
  /// awaits, a simple result-cache misses the race. Instead, the first caller
  /// registers its Future synchronously (before await), so the second caller
  /// finds and reuses the same Future.
  final Map<String, Future<Message>> _inflightDecrypts = {};

  /// Public access for direct 1:1 encrypt/decrypt.
  SignalSessionManager get sessionManager => _sessionManager;

  EncryptedMessageHandler({
    required SignalSessionManager sessionManager,
    required SocketManager socketManager,
    FileService? fileService,
    SealedSenderService? sealedSenderService,
    SenderCertificateManager? senderCertificateManager,
    TransferEventBus? transferEventBus,
    required Future<bool> Function(String snowId) isBlocked,
    this.onNewInboundSession,
  })  : _sessionManager = sessionManager,
        _socketManager = socketManager,
        _fileService = fileService,
        _sealedSenderService = sealedSenderService,
        _senderCertificateManager = senderCertificateManager,
        _transferEventBus = transferEventBus,
        _isBlocked = isBlocked;

  /// Whether an account is blocked (BlockList.isBlocked): what it sent is
  /// decrypted (the session stays in step) and then refused with
  /// [BlockedSenderException] — before anything of it is acted on.
  final Future<bool> Function(String snowId) _isBlocked;

  /// A peer started a new session with this device: what it sent was a
  /// prekey message (its first contact, a reinstall, a session reset). The
  /// peer may have lost what this device told it before — e.g. this
  /// account's name (NameCertService.forgetAnnounced). Awaited after the
  /// decrypt; its failure does not fail the message.
  final Future<void> Function(String peer)? onNewInboundSession;

  // ---------------------------------------------------------------------------
  // Sealed Sender (Phase 10.1)
  // ---------------------------------------------------------------------------

  /// Whether Sealed Sender is available (service + certificate manager configured).
  bool get isSealedSenderAvailable =>
      _sealedSenderService != null && _senderCertificateManager != null;

  /// Encrypt and send a 1:1 text message via Sealed Sender.
  ///
  /// Flow:
  /// 1. Ensure session exists (X3DH if needed)
  /// 2. Build plaintext JSON payload
  /// 3. Encrypt with Double Ratchet -> DR ciphertext
  /// 4. Fetch/cache SenderCertificate
  /// 5. Get recipient's X25519 identity public key from session store
  /// 6. Wrap DR ciphertext with SealedSenderService.seal()
  /// 7. Send via socket 'sealed_message' event
  ///
  /// The server never learns the sender identity — only the recipient can
  /// unseal and discover who sent the message.
  ///
  /// [wireMessageId] is the wire `clientMessageId` — a new
  /// [newWireMessageId] for every send, chosen by the caller so that it can
  /// match the server's status events (which echo it) to its message.
  Future<void> sendSealedMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    required String clientMessageId,
    required String wireMessageId,
    String? attachmentFileKey,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
    String? nameCert,
    Function(dynamic)? onAck,
  }) async {
    if (_sealedSenderService == null || _senderCertificateManager == null) {
      throw StateError('SealedSenderService or SenderCertificateManager not configured');
    }

    // Step 1: Ensure we have a session with the recipient
    await _sessionManager.ensureSession(recipientId);

    // Step 2: Pre-fetch every throw-capable dependency BEFORE encrypt.
    //
    // Original ordering put encrypt() at Step 3 and certificate fetch +
    // identity-key lookup at Step 4/5. That meant any HTTP failure on
    // getCertificate() or a missing cached IK left the Double Ratchet
    // advanced (counter N → N+1) with no message on the wire — the next
    // send would re-advance to N+2 and recipient's counter N+1 stayed
    // empty forever. The disable-comment in chat_provider documented
    // exactly that hazard. The architectural fix is to front-load every
    // operation that can throw so once encrypt() runs the only remaining
    // steps are in-memory crypto + socket emit (both effectively
    // throw-free; a message lost after that shows on the receiver as a
    // placeholder and the session is reset from there).
    final certificate = await _senderCertificateManager!.getCertificate();
    final recipientIdentityPubKey =
        _sessionManager.signal.getRemoteIdentityKey(recipientId);
    if (recipientIdentityPubKey == null) {
      throw StateError(
        'Sealed Sender: no cached identity key for the peer. '
        'Cannot seal without recipient IK.',
      );
    }
    final deviceId = await _sessionManager.getDeviceIdForRecipient(recipientId);

    // Step 3: Build the plaintext payload (JSON-encoded, never logged)
    final payload = _buildPayload(
      clientMessageId: clientMessageId,
      text: text,
      type: type,
      attachmentFileKey: attachmentFileKey,
      metadata: metadata,
      ttlSeconds: ttlSeconds,
      replyToId: replyToId,
      replyToPreview: replyToPreview,
      replyToSenderId: replyToSenderId,
      nameCert: nameCert,
    );
    final plaintextBytes = encodeSealedPlaintext(payload);

    // Step 4: Encrypt with Double Ratchet (ratchet advances here).
    final encrypted = await _sessionManager.encrypt(
      recipientId,
      deviceId,
      plaintextBytes,
    );
    final drCiphertext = encrypted['ciphertext'] as Uint8List;

    // Step 5: Seal the DR ciphertext (in-memory crypto).
    final sealedEnvelope = _sealedSenderService!.seal(
      recipientIdentityPubKey: recipientIdentityPubKey,
      drCiphertext: drCiphertext,
      certificate: certificate,
      messageContext: sealedType1to1,
    );

    // Step 6: Send via socket 'sealed_message' event. The wire id is a
    // random UUID; [clientMessageId] travels only inside the E2EE payload
    // (`cid`, the receiver's duplicate guard).
    _socketManager.sendSealedMessage(
      recipientId: recipientId,
      sealedContent: base64Encode(sealedEnvelope),
      clientMessageId: wireMessageId,
      expiresIn: ttlSeconds,
      onAck: onAck,
    );
  }

  /// Seal [payload] — a whole inner JSON object with its own `type` (a
  /// contact notice, a wallet transfer notice) — to [recipientId] and hand
  /// it to the socket; [onAck] gets the server's answer. [control] sends it
  /// as a silent `sealed_control` row (no push); otherwise as an ordinary
  /// sealed row, pushed like a message.
  ///
  /// The peer's identity is looked up in the directory first
  /// (SignalSessionManager.refreshPeerIdentity), like for a group invite: a
  /// notice is often the first envelope in a long while, and one sealed to an
  /// identity the peer no longer has (it reinstalled) could never be opened.
  ///
  /// Throws StateError when Sealed Sender is not active, the socket is down
  /// or the peer has no usable identity — nothing is encrypted then;
  /// SignalProtocolException when the directory cannot be reached;
  /// IdentityBindingInvalidException for a forged binding. The caller (the
  /// 1:1 outbox) decides what to try again.
  Future<void> sendSealedPayload({
    required String recipientId,
    required Map<String, dynamic> payload,
    required bool control,
    Function(dynamic)? onAck,
  }) async {
    if (_sealedSenderService == null || _senderCertificateManager == null) {
      throw StateError('Sealed Sender not active');
    }
    if (!_socketManager.isReadyToSend) {
      throw StateError('Socket not connected');
    }
    await _sessionManager.refreshPeerIdentity(recipientId);
    await _sessionManager.ensureSession(recipientId);
    final certificate = await _senderCertificateManager!.getCertificate();
    final recipientIdentityPubKey =
        _sessionManager.signal.getRemoteIdentityKey(recipientId);
    if (recipientIdentityPubKey == null) {
      throw StateError('Sealed Sender: no identity key for the peer');
    }
    final deviceId = await _sessionManager.getDeviceIdForRecipient(recipientId);
    final encrypted = await _sessionManager.encrypt(
      recipientId,
      deviceId,
      encodeSealedPlaintext(payload),
    );
    final sealedEnvelope = _sealedSenderService!.seal(
      recipientIdentityPubKey: recipientIdentityPubKey,
      drCiphertext: encrypted['ciphertext'] as Uint8List,
      certificate: certificate,
      messageContext: sealedType1to1,
    );
    _socketManager.sendSealedMessage(
      recipientId: recipientId,
      sealedContent: base64Encode(sealedEnvelope),
      clientMessageId: newWireMessageId(),
      control: control,
      onAck: onAck,
    );
  }

  /// Send a sealed E2EE read receipt to [recipientId] (1:1 only).
  ///
  /// Travels as a silent sealed_control envelope: the server cannot see that
  /// it is a read receipt (only an opaque control), never pushes or
  /// badge-counts it, and prunes it with the 7-day control cleanup. The
  /// peer's MessageQueue consumes it silently and flips outgoingStatus to
  /// 'read' on the referenced rows (blue double-check) — no chat bubble, no
  /// unread bump, no notification.
  ///
  /// [readIds] are server row ids — the drift PK both peers share for the
  /// same logical sealed message. Best-effort by design: a lost receipt only
  /// costs a blue check (the peer drops undecryptable controls without
  /// firing session-reset storms), and we bail before advancing the
  /// Double Ratchet when the socket is down instead of burning a counter on
  /// an envelope that can never leave the device.
  Future<void> sendSealedReadReceipt({
    required String recipientId,
    required List<String> readIds,
  }) async {
    if (readIds.isEmpty) return;
    await _sendSealedControl(
      recipientId: recipientId,
      payload: {
        'type': 'read_receipt',
        'readIds': readIds,
        'readAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Send a sealed E2EE unsend ("delete for everyone") to [recipientId] (1:1
  /// only). Travels as the same silent sealed_control envelope as read
  /// receipts — the server cannot see it is a delete. The peer's MessageQueue
  /// physically removes the referenced drift rows (no tombstone).
  ///
  /// [deleteIds] are server row ids — the drift PK both peers share for the
  /// same logical sealed message (so the recipient self-locates its copy). The
  /// 5-minute unsend window is enforced client-side by the caller before this
  /// runs; there is no server row left to enforce it against. Best-effort like
  /// read receipts: if the recipient is on a pre-support build the server drops
  /// the control and the delete does not propagate until they upgrade. Group
  /// unsend stays on the server path — there is no shared row id per member.
  /// Returns `true` iff the sealed unsend control was actually dispatched to the
  /// socket. `false` means it could not be sent (socket down, or no sealed
  /// channel to this peer yet) — the caller must NOT then claim the peer's copy
  /// was removed.
  Future<bool> sendSealedUnsend({
    required String recipientId,
    required List<String> deleteIds,
  }) async {
    if (deleteIds.isEmpty) return false;
    return _sendSealedControl(
      recipientId: recipientId,
      payload: {
        'type': 'delete',
        'deleteIds': deleteIds,
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Tell the peer that this 1:1 conversation was deleted so their client
  /// removes its own copy — the "the other person will also lose this
  /// conversation" promise in the Delete-chat dialog.
  ///
  /// Travels over the same silent sealed_control channel as unsend / read
  /// receipts, which means it is QUEUED like any other message: an offline peer
  /// applies it on their next connect. It is the only signal a peer gets: the
  /// server says nothing about a deleted 1:1 (its old `chat_deleted` socket
  /// event reached only a connected peer, and was the server's word).
  ///
  /// Server-opaque: this is an ordinary sealed_control row (senderId=NULL +
  /// senderHash), so it adds no new metadata class — in particular it does NOT
  /// reintroduce the (user1,user2) pair row that metadata-min Batch 2 dropped.
  ///
  /// Best-effort like the other controls: false when the socket is down or no
  /// sealed channel to this peer exists yet, and the server drops it for a
  /// recipient on a build older than SEALED_CONTROL_MIN_BUILD.
  Future<bool> sendSealedDeleteChat({required String recipientId}) {
    return _sendSealedControl(
      recipientId: recipientId,
      payload: {
        'type': 'delete_chat',
        'deletedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Tell [recipientId] that this device re-established the 1:1 session
  /// (SignalSessionManager.archiveAndResetSession): the control is the first
  /// message of the new session — a prekey message — so decrypting it builds
  /// the session on the peer's side. Sealed (SC-05): the server learns
  /// neither sender nor that it is a reset. Returns false when it could not
  /// be sent (Sealed Sender not active, socket down, no cached identity key):
  /// then nothing is sent at all — the next real message is a prekey message
  /// and does the same.
  Future<bool> sendSealedSessionReset(String recipientId) async {
    if (!isSealedSenderAvailable) return false;
    return _sendSealedControl(
      recipientId: recipientId,
      payload: {
        'type': 'session_reset',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  /// Seal an inner control payload to [recipientId] over the sealed_control
  /// channel (server-opaque, no push, no badge, 7d cleanup). Shared by read
  /// receipts and unsend. Best-effort: bails before advancing the Double
  /// Ratchet when the socket is down or no session identity key is cached, so
  /// no counter is burned on an envelope that can never leave the device.
  /// Returns `true` iff the control envelope was dispatched to the socket;
  /// `false` on a best-effort bail (socket down / no cached identity key).
  Future<bool> _sendSealedControl({
    required String recipientId,
    required Map<String, dynamic> payload,
  }) async {
    if (_sealedSenderService == null || _senderCertificateManager == null) {
      throw StateError(
          'SealedSenderService or SenderCertificateManager not configured');
    }
    if (!_socketManager.isConnected) return false;

    await _sessionManager.ensureSession(recipientId);

    final certificate = await _senderCertificateManager!.getCertificate();
    final recipientIdentityPubKey =
        _sessionManager.signal.getRemoteIdentityKey(recipientId);
    if (recipientIdentityPubKey == null) {
      // No cached IK means no sealed channel to this peer yet — controls are
      // an optimization on top of an existing conversation, so drop.
      return false;
    }
    final deviceId = await _sessionManager.getDeviceIdForRecipient(recipientId);

    final plaintextBytes = encodeSealedPlaintext(payload);

    final encrypted = await _sessionManager.encrypt(
      recipientId,
      deviceId,
      plaintextBytes,
    );
    final drCiphertext = encrypted['ciphertext'] as Uint8List;

    final sealedEnvelope = _sealedSenderService!.seal(
      recipientIdentityPubKey: recipientIdentityPubKey,
      drCiphertext: drCiphertext,
      certificate: certificate,
      messageContext: sealedType1to1,
    );

    _socketManager.sendSealedMessage(
      recipientId: recipientId,
      sealedContent: base64Encode(sealedEnvelope),
      clientMessageId: newWireMessageId(),
      control: true,
    );
    return true;
  }

  /// Group protocol v2: send an invite message ([invite] — the bytes of a
  /// Gv2InviteMessage) to [recipientId] over the sealed 1:1 path. Not a
  /// control envelope: the recipient is pushed, like for a chat message, so
  /// that its app comes up and takes the invite in. The inner payload is
  /// `{type: 'group_invite_v2', invite: base64}`; the receiver intercepts
  /// it before any chat row is made.
  ///
  /// The peer's identity is looked up in the directory first
  /// (SignalSessionManager.refreshPeerIdentity): a session with an identity
  /// it no longer has is put aside, so the invite is sealed to the one it
  /// has now.
  ///
  /// Returns true only when the server acknowledged the envelope; false
  /// when the socket is down, the directory cannot be reached, the peer has
  /// no usable session identity, the
  /// server refused it or did not answer within [timeout] (the caller — the
  /// v2 outbox — sends it again later). Nothing is encrypted when the
  /// socket is down. An identity failure (IdentityBindingInvalidException)
  /// propagates.
  Future<bool> sendSealedGroupInvite({
    required String recipientId,
    required Uint8List invite,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_sealedSenderService == null || _senderCertificateManager == null) {
      return false;
    }
    if (!_socketManager.isConnected) return false;

    // An invite is often the first message to someone in a long while: the
    // session this device holds may be with an identity the peer no longer
    // has (it reinstalled, or registered again). Sealed to that, the invite
    // could not be opened and nobody would know. The directory is asked
    // first; a stale session is put aside and a new one set up.
    try {
      await _sessionManager.refreshPeerIdentity(recipientId);
    } on SignalProtocolException {
      return false; // the directory is not reachable: tried again later
    }
    await _sessionManager.ensureSession(recipientId);
    final certificate = await _senderCertificateManager!.getCertificate();
    final recipientIdentityPubKey =
        _sessionManager.signal.getRemoteIdentityKey(recipientId);
    if (recipientIdentityPubKey == null) return false;
    final deviceId = await _sessionManager.getDeviceIdForRecipient(recipientId);

    final plaintextBytes = encodeSealedPlaintext({
      'type': gv2InviteInnerType,
      'invite': base64Encode(invite),
    });
    final encrypted = await _sessionManager.encrypt(
      recipientId,
      deviceId,
      plaintextBytes,
    );
    final sealedEnvelope = _sealedSenderService!.seal(
      recipientIdentityPubKey: recipientIdentityPubKey,
      drCiphertext: encrypted['ciphertext'] as Uint8List,
      certificate: certificate,
      messageContext: sealedType1to1,
    );

    final accepted = Completer<bool>();
    _socketManager.sendSealedMessage(
      recipientId: recipientId,
      sealedContent: base64Encode(sealedEnvelope),
      clientMessageId: newWireMessageId(),
      onAck: (response) {
        if (accepted.isCompleted) return;
        accepted.complete(response is Map && response['messageId'] is String);
      },
    );
    return accepted.future.timeout(timeout, onTimeout: () => false);
  }

  /// Decrypt an incoming Sealed Sender message.
  ///
  /// Flow:
  /// 1. Parse sealed envelope from socket event
  /// 2. Get our own identity key pair
  /// 3. Unseal with SealedSenderService.unseal() -> sender identity + DR ciphertext
  /// 4. Feed DR ciphertext into existing _sessionManager.decrypt() pipeline
  /// 5. Return the Message (or a control / notice marked in its metadata)
  ///
  /// The sender identity is extracted from the verified SenderCertificate
  /// embedded inside the sealed envelope.
  Future<Message> decryptSealedMessage(
    Map<String, dynamic> socketEvent,
  ) async {
    if (_sealedSenderService == null) {
      throw StateError('SealedSenderService not configured');
    }

    final messageId =
        (socketEvent['messageId'] ?? socketEvent['id']) as String;

    // In-flight dedup: a second caller for the same envelope shares the
    // first decrypt (decrypting twice would break the session).
    final inflight = _inflightDecrypts[messageId];
    if (inflight != null) {
      debugPrint('[E2EE:Sealed] Joining in-flight decrypt for $messageId');
      return inflight;
    }

    final future = _doDecryptSealed(socketEvent, messageId);
    _inflightDecrypts[messageId] = future;

    try {
      return await future;
    } finally {
      _inflightDecrypts.remove(messageId);
      if (_inflightDecrypts.length > 50) {
        _inflightDecrypts.remove(_inflightDecrypts.keys.first);
      }
    }
  }

  /// Internal: performs Sealed Sender unseal + Signal decryption.
  Future<Message> _doDecryptSealed(
    Map<String, dynamic> socketEvent,
    String messageId,
  ) async {
    // Sealed payload arrives under two different field names depending on
    // transport: 'sealedContent' from the live socket relay (messageHandler
    // rebuilds the envelope explicitly) and 'encryptedContent' from the REST
    // fetchPending response (routes/messages.ts passes the raw DB column
    // through). Without this fallback, every swipe-killed cold-start sealed
    // message dead-letters on REST drain: the StateError fires, retries
    // exhaust, _insertDecryptionFailedPlaceholder is skipped (senderId+convId
    // both null on the wire — phantom guard returns early), and the ACK
    // still fires — server deletes the ciphertext, message permanently lost
    // while the push-driven badge sits at N with nothing in drift to clear
    // it with.
    final sealedContent = (socketEvent['sealedContent'] ??
        socketEvent['encryptedContent']) as String?;
    if (sealedContent == null || sealedContent.isEmpty) {
      throw StateError('Sealed message missing sealedContent/encryptedContent');
    }

    final timestamp = socketEvent['serverTimestamp'] != null
        ? DateTime.parse(socketEvent['serverTimestamp'] as String)
        : (socketEvent['timestamp'] != null
            ? DateTime.parse(socketEvent['timestamp'] as String)
            : DateTime.now());

    // Step 1: Decode the sealed envelope
    final sealedEnvelope = Uint8List.fromList(base64Decode(sealedContent));

    // Step 2: Get our own identity keys
    final myIdentityPublicKey = _sessionManager.signal.identityPublicKey;
    final myIdentityPrivateKey = _sessionManager.signal.identityPrivateKey;
    if (myIdentityPublicKey == null || myIdentityPrivateKey == null) {
      throw StateError('Sealed Sender: local identity keys not available');
    }

    // Step 3: Unseal — reveals sender identity + DR ciphertext
    final unsealed = _sealedSenderService!.unseal(
      myIdentityPrivateKey: myIdentityPrivateKey,
      myIdentityPublicKey: myIdentityPublicKey,
      sealedEnvelope: sealedEnvelope,
    );

    final senderId = unsealed.senderSnowchatId;
    final senderDeviceId = unsealed.senderDeviceId;

    debugPrint('[E2EE:Sealed] Unsealed: context=${unsealed.messageContext}');

    // B-2: the certificate's deviceId is cached by decrypt() only after the
    // DR decrypt (and binding verification) succeeded.

    try {
      // Step 4: Recover the Signal message type from the unsealed DR ciphertext
      // itself — NEVER from socketEvent. Sealed Sender hides the inner message
      // type from the wire (the server relays no messageType and stores 0 for
      // sealed rows), so the old `socketEvent['messageType'] ?? 1` always
      // resolved to 1/0 and a prekey first-contact message was misrouted as a
      // normal message: the X3DH `if (messageType == 2)` branch never ran, the
      // responder session was never built, and the message dead-lettered (lost).
      // resolveSealedMessageType() reads prekey-ness from the ciphertext's own
      // self-describing header and also runs Sealed Sender Step 9 (binds the
      // X3DH identity to the certificate identity, rejecting a mismatch). Kept
      // INSIDE the try so a Step-9 rejection (or a malformed prekey header) is
      // logged + rethrown on the same handled path as any decrypt failure; a
      // non-JSON ciphertext instead degrades to messageType 1 inside the helper.
      final messageType = _sessionManager.signal.resolveSealedMessageType(
        unsealed.drCiphertext,
        unsealed.senderIdentityKey,
      );

      // Step 5: Decrypt with Double Ratchet
      final plaintextBytes = await _sessionManager.decrypt(
        senderId,
        senderDeviceId,
        unsealed.drCiphertext,
        messageType,
        envelopeDeviceId: senderDeviceId,
      );

      // X1: the certificate-authenticated sender is an account this user
      // blocked — refused before anything of it is acted on (a transfer
      // control, a read receipt, an unsend, a group invite, a message).
      if (await _isBlocked(senderId)) throw const BlockedSenderException();

      // A prekey message: the peer started a new session (first contact, a
      // reinstall, a reset) and may have lost what it knew of this account.
      if (messageType == 2) {
        try {
          await onNewInboundSession?.call(senderId);
        } catch (e) {
          debugPrint('[E2EE:Sealed] new session not noted: ${e.runtimeType}');
        }
      }

      // Step 6: Parse the decrypted JSON payload
      final payload = jsonDecode(utf8.decode(plaintextBytes))
          as Map<String, dynamic>;

      // The room is the certificate-authenticated sender's — never a
      // conversation id the envelope names.
      final resolvedConversationId = senderId;

      // Wallet V2 Phase B (2026-04-20): transfer_* type dispatch (Sealed path).
      // Goes through the same dispatcher as the normal 1:1 path — the sender
      // identity from the unsealed Sealed Sender envelope is used as
      // fromSnowchatId (authenticity guaranteed).
      final transferMsg = _tryDispatchTransfer(
        payload: payload,
        senderSnowchatId: senderId,
        messageId: messageId,
        conversationId: resolvedConversationId,
        timestamp: timestamp,
      );
      if (transferMsg != null) return transferMsg;

      // Sealed read receipt (2026-07-15): silent E2EE control — the peer
      // read our messages. Surfaced via metadata so MessageQueue's control
      // branch can flip outgoingStatus='read' and ACK. Detected BEFORE the
      // generic Message build so it can never render as a phantom bubble.
      if (payload['type'] == 'read_receipt') {
        final rawIds = payload['readIds'];
        final readIds =
            rawIds is List ? rawIds.whereType<String>().toList() : <String>[];
        return Message(
          id: messageId,
          conversationId: resolvedConversationId,
          senderSnowchatId: senderId,
          plaintext: '',
          timestamp: timestamp,
          type: MessageType.system,
          status: MessageStatus.delivered,
          metadata: {
            '_isReadReceipt': true,
            'readIds': readIds,
          },
        );
      }

      // Sealed unsend (2026-07-15): the sender is deleting-for-everyone. Silent
      // E2EE control — surfaced via metadata so MessageQueue's control branch
      // physically removes the referenced rows. Detected BEFORE the generic
      // Message build so it can never render as a phantom bubble.
      if (payload['type'] == 'delete') {
        final rawIds = payload['deleteIds'];
        final deleteIds =
            rawIds is List ? rawIds.whereType<String>().toList() : <String>[];
        return Message(
          id: messageId,
          conversationId: resolvedConversationId,
          senderSnowchatId: senderId,
          plaintext: '',
          timestamp: timestamp,
          type: MessageType.system,
          status: MessageStatus.delivered,
          metadata: {
            '_isUnsend': true,
            'deleteIds': deleteIds,
          },
        );
      }

      // Sealed session reset (2026-11-22): the peer re-established the
      // session; decrypting this prekey message built it here. Surfaced via
      // metadata so MessageQueue consumes it silently — never a bubble.
      if (payload['type'] == 'session_reset') {
        return Message(
          id: messageId,
          conversationId: resolvedConversationId,
          senderSnowchatId: senderId,
          plaintext: '',
          timestamp: timestamp,
          type: MessageType.system,
          status: MessageStatus.delivered,
          metadata: const {'_isSessionReset': true},
        );
      }

      // Sealed delete-chat (2026-09-04): the peer deleted the whole 1:1 room.
      // Silent E2EE control — surfaced via metadata so MessageQueue's control
      // branch wipes the room + Signal session. Detected BEFORE the generic
      // Message build so it can never render as a phantom bubble.
      if (payload['type'] == 'delete_chat') {
        return Message(
          id: messageId,
          conversationId: resolvedConversationId,
          senderSnowchatId: senderId,
          plaintext: '',
          timestamp: timestamp,
          type: MessageType.system,
          status: MessageStatus.delivered,
          metadata: const {'_isDeleteChat': true},
        );
      }

      // Group protocol v2 invite: not a chat message. Surfaced via metadata
      // so MessageQueue hands it to the v2 group actions and consumes it —
      // detected BEFORE the generic Message build so it can never render as
      // a bubble or create a 1:1 room.
      if (payload['type'] == gv2InviteInnerType) {
        final invite = payload['invite'];
        return Message(
          id: messageId,
          conversationId: resolvedConversationId,
          senderSnowchatId: senderId,
          plaintext: '',
          timestamp: timestamp,
          type: MessageType.system,
          status: MessageStatus.delivered,
          metadata: {
            '_isGroupInviteV2': true,
            'invite': ?(invite is String ? invite : null),
          },
        );
      }

      // Contact notices (design 2026-11-22 §5.2): the peer added this user
      // (a request, or the acceptance of this user's request) or removed
      // them. Never a chat message: surfaced via metadata so MessageQueue
      // hands it to the contact store and consumes it — no room, no bubble,
      // no unread. The name certificate rides along (§12.4).
      final innerType = payload['type'];
      if (innerType == contactAddedType || innerType == contactRemovedType) {
        final cert = payload['nameCert'];
        return Message(
          id: messageId,
          conversationId: resolvedConversationId,
          senderSnowchatId: senderId,
          plaintext: '',
          timestamp: timestamp,
          type: MessageType.system,
          status: MessageStatus.delivered,
          metadata: {
            '_isContactNotice': true,
            'notice': innerType,
            'answer': contactNoticeIsAnswer(payload),
          },
          peerNameCert: cert is String ? cert : null,
        );
      }

      // A message. An inner `type` this build does not know (a later build's
      // structured payload) is consumed and never shown — no room, no
      // bubble, no notification (§12.4).
      final msgType =
          innerType == null ? MessageType.text : _parseMessageType(innerType);
      if (msgType == null) {
        return Message(
          id: messageId,
          conversationId: resolvedConversationId,
          senderSnowchatId: senderId,
          plaintext: '',
          timestamp: timestamp,
          type: MessageType.system,
          status: MessageStatus.delivered,
          metadata: const {'_isUnknownType': true},
        );
      }
      final text = payload['text'] as String? ?? '';
      final msgMetadata = _peerMetadata(payload['metadata']);
      final ttlSeconds = payload['ttl'] as int?;
      final replyToId = payload['replyToId'] as String?;
      final replyToPreview = payload['replyToPreview'] as String?;
      final replyToSenderId = payload['replyToSenderId'] as String?;
      final peerClientId = payload['cid'] as String?;
      final cert = payload['nameCert'];

      return Message(
        id: messageId,
        conversationId: resolvedConversationId,
        senderSnowchatId: senderId,
        plaintext: text,
        timestamp: timestamp,
        type: msgType,
        status: MessageStatus.delivered,
        metadata: msgMetadata,
        expiresAt: ttlSeconds != null
            ? timestamp.add(Duration(seconds: ttlSeconds))
            : null,
        ttlSeconds: ttlSeconds,
        replyToId: replyToId,
        replyToPreview: replyToPreview,
        replyToSenderId: replyToSenderId,
        peerClientId: peerClientId,
        peerNameCert: cert is String ? cert : null,
      );
    } on IdentityBindingInvalidException {
      // B-2 hard failure — must reach the queue unwrapped so it is ACKed as a
      // terminal rejection (no retry request, no session reset).
      rethrow;
    } on BlockedSenderException {
      // X1 — terminal as well: unwrapped, acknowledged, never answered.
      rethrow;
    } catch (e, st) {
      debugPrint('[EncryptedMessageHandler:Sealed] Decryption failed for '
          'message $messageId: $e\n$st');
      // Preserve the certificate-authenticated sender (bound at unseal, before
      // this try) so the queue can target the retry + placeholder + SPK
      // self-heal, instead of a blind sender=null retry the server rejects.
      throw SealedDecryptException(senderId, senderDeviceId, e);
    }
  }

  // ---------------------------------------------------------------------------
  // File Download & Decryption
  // ---------------------------------------------------------------------------

  /// Download and decrypt a file attachment from a received message.
  ///
  /// [metadata] should contain: fileId, fileKey (base64), contentHash.
  Future<Uint8List> downloadAndDecryptFile(
    Map<String, dynamic> metadata,
  ) async {
    if (_fileService == null) {
      throw StateError('FileService not configured');
    }

    final fileId = metadata['fileId'] as String;
    final fileKeyB64 = metadata['fileKey'] as String;
    final contentHash = metadata['contentHash'] as String?;

    final fileKey = Uint8List.fromList(base64Decode(fileKeyB64));

    // Download encrypted blob
    final encryptedData = await _fileService.downloadEncryptedFile(fileId);

    // Decrypt with fileKey (verifies contentHash if provided)
    return FileEncryptor.decryptFile(
      encryptedData,
      fileKey,
      expectedHash: contentHash,
    );
  }

  // ---------------------------------------------------------------------------
  // Convenience: Decrypt file from Message
  // ---------------------------------------------------------------------------

  /// Extract fileId/fileKey from a message's metadata, download, and decrypt.
  ///
  /// This is a convenience wrapper around [downloadAndDecryptFile] that
  /// takes a [Message] directly. Useful for UI components that need to
  /// display decrypted file content (e.g., image previews).
  ///
  /// Throws if the message has no metadata or is missing required fields.
  Future<Uint8List> getDecryptedFileBytes(Message message) async {
    final metadata = message.metadata;
    if (metadata == null) {
      throw ArgumentError('Message has no metadata');
    }
    if (metadata['fileId'] == null || metadata['fileKey'] == null) {
      throw ArgumentError('Message metadata missing fileId or fileKey');
    }
    return downloadAndDecryptFile(metadata);
  }

  // ---------------------------------------------------------------------------
  // Wallet V2 Phase B — transfer_* dispatcher
  // ---------------------------------------------------------------------------

  /// UUID v4 regex (lowercase hex, version=4, variant=89ab).
  /// Spec §5.15: replay window guard — strict format validation for `requestId`.
  /// e.g. `1f4e2c0a-1234-4abc-89ab-0123456789ab`
  static final RegExp _uuidV4Re = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Transfer payload replay window — reject if `sentAt` falls outside
  /// now ± 24h. Blocks malicious peers attaching very old or future
  /// timestamps to attempt redelivery / fingerprinting.
  static const Duration _transferReplayWindow = Duration(hours: 24);

  /// Wallet V2 Phase B (Spec §5.15): if payload['type'] is transfer_*,
  /// emit on TransferEventBus and return a system Message marking to caller.
  ///
  /// **Return value**:
  /// - `null` → not a transfer payload (caller handles as normal message)
  /// - `Message` (system type, plaintext='', metadata includes wireType) →
  ///   transfer handled. The caller identifies via
  ///   metadata['_isTransferControl'] and branches drift insert / UI
  ///   (Phase G unification planned).
  ///
  /// **Validation failure is silent drop** (spec §5.15): no TransferFailed
  /// is sent — no response to malicious peers (auto-response could be
  /// abused as an amplification attack).
  ///
  /// **try/catch wrapper**: unguarded casts in model-level fromJson would,
  /// on field missing / type mismatch, raise an unhandled `TypeError` →
  /// killing the E2EE handler isolate. The dispatcher catches all to
  /// protect the isolate.
  Message? _tryDispatchTransfer({
    required Map<String, dynamic> payload,
    required String senderSnowchatId,
    required String messageId,
    required String conversationId,
    required DateTime timestamp,
  }) {
    final wireType = payload['type'];
    if (wireType is! String) return null;

    switch (wireType) {
      case TransferMessageType.request:
        try {
          final req = TransferRequest.fromJson(payload);
          if (!_validateTransferRequest(req)) {
            debugPrint('[Transfer] invalid transfer_request fields, drop');
            return _transferControlMessage(
              messageId: messageId,
              conversationId: conversationId,
              senderSnowchatId: senderSnowchatId,
              timestamp: timestamp,
              wireType: wireType,
            );
          }
          debugPrint('[Transfer] dispatch request requestId=${req.requestId} '
              'bus=${_transferEventBus == null ? "NULL" : _transferEventBus.hashCode}');
          _transferEventBus?.addRequest(senderSnowchatId, req);
        } catch (e) {
          debugPrint('[Transfer] malformed transfer_request: $e');
        }
        return _transferControlMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderSnowchatId: senderSnowchatId,
          timestamp: timestamp,
          wireType: wireType,
        );

      case TransferMessageType.response:
        try {
          final resp = TransferResponse.fromJson(payload);
          if (!_validateTransferResponse(resp)) {
            debugPrint('[Transfer] invalid transfer_response fields, drop');
            return _transferControlMessage(
              messageId: messageId,
              conversationId: conversationId,
              senderSnowchatId: senderSnowchatId,
              timestamp: timestamp,
              wireType: wireType,
            );
          }
          debugPrint('[Transfer] dispatch response requestId=${resp.requestId} '
              'accepted=${resp.accepted} bus=${_transferEventBus == null ? "NULL" : _transferEventBus.hashCode}');
          _transferEventBus?.addResponse(senderSnowchatId, resp);
        } catch (e) {
          debugPrint('[Transfer] malformed transfer_response: $e');
        }
        return _transferControlMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderSnowchatId: senderSnowchatId,
          timestamp: timestamp,
          wireType: wireType,
        );

      case TransferMessageType.completed:
        try {
          final c = TransferCompleted.fromJson(payload);
          if (!_validateTransferCompleted(c)) {
            debugPrint('[Transfer] invalid transfer_completed fields, drop');
            return _transferControlMessage(
              messageId: messageId,
              conversationId: conversationId,
              senderSnowchatId: senderSnowchatId,
              timestamp: timestamp,
              wireType: wireType,
            );
          }
          debugPrint('[Transfer] dispatch completed requestId=${c.requestId} '
              'bus=${_transferEventBus == null ? "NULL" : _transferEventBus.hashCode}');
          _transferEventBus?.addCompleted(senderSnowchatId, c);
        } catch (e) {
          debugPrint('[Transfer] malformed transfer_completed: $e');
        }
        return _transferControlMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderSnowchatId: senderSnowchatId,
          timestamp: timestamp,
          wireType: wireType,
        );

      case TransferMessageType.failed:
        try {
          final f = TransferFailed.fromJson(payload);
          if (!_validateTransferFailed(f)) {
            debugPrint('[Transfer] invalid transfer_failed fields, drop');
            return _transferControlMessage(
              messageId: messageId,
              conversationId: conversationId,
              senderSnowchatId: senderSnowchatId,
              timestamp: timestamp,
              wireType: wireType,
            );
          }
          debugPrint('[Transfer] dispatch failed requestId=${f.requestId} '
              'reason=${f.reason.toJson()} bus=${_transferEventBus == null ? "NULL" : _transferEventBus.hashCode}');
          _transferEventBus?.addFailed(senderSnowchatId, f);
        } catch (e) {
          debugPrint('[Transfer] malformed transfer_failed: $e');
        }
        return _transferControlMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderSnowchatId: senderSnowchatId,
          timestamp: timestamp,
          wireType: wireType,
        );

      default:
        return null; // normal message
    }
  }

  /// Marking Message returned to the caller by the transfer_* dispatcher.
  /// In Phase G, message_queue will inspect metadata['_isTransferControl']
  /// and branch drift insert policy (request/response/failed are skipped;
  /// completed is converted into a permanent system message after RPC
  /// verification).
  static Message _transferControlMessage({
    required String messageId,
    required String conversationId,
    required String senderSnowchatId,
    required DateTime timestamp,
    required String wireType,
  }) {
    return Message(
      id: messageId,
      conversationId: conversationId,
      senderSnowchatId: senderSnowchatId,
      plaintext: '',
      timestamp: timestamp,
      type: MessageType.system,
      status: MessageStatus.delivered,
      metadata: <String, dynamic>{
        '_isTransferControl': true,
        'wireType': wireType,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Wallet V2 Phase B — field validation helpers (spec §5.15)
  // ---------------------------------------------------------------------------

  /// Validate transfer_request — UUID v4 / amount > 0 / decimals 0~18 / mint
  /// (SOL→null, SPL/NFT→Base58) / sentAt now ± 24h.
  bool _validateTransferRequest(TransferRequest req) {
    if (!_isValidUuidV4(req.requestId)) return false;

    // amount BigInt-safe + positive
    final amount = BigInt.tryParse(req.amount);
    if (amount == null || amount <= BigInt.zero) return false;

    // decimals range
    if (req.decimals < 0 || req.decimals > 18) return false;

    // mint vs token consistency
    switch (req.token) {
      case TokenType.sol:
        if (req.mint != null) return false; // SOL must have no mint
        break;
      case TokenType.spl:
      case TokenType.nft:
        final mint = req.mint;
        if (mint == null || !_isValidBase58Address(mint)) return false;
        break;
    }

    // sentAt now ± 24h (replay window)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final windowMs = _transferReplayWindow.inMilliseconds;
    if ((req.sentAt - nowMs).abs() > windowMs) return false;

    return true;
  }

  /// Validate transfer_response — UUID v4 + when accepted=true, walletAddress
  /// / walletAddressSig non-null + Base58 + ataRentLamports >= 0.
  bool _validateTransferResponse(TransferResponse resp) {
    if (!_isValidUuidV4(resp.requestId)) return false;

    if (resp.accepted) {
      // accepted=true branch: walletAddress + sig required (P1-5)
      final addr = resp.walletAddress;
      final sig = resp.walletAddressSig;
      if (addr == null || addr.isEmpty) return false;
      if (sig == null || sig.isEmpty) return false;
      if (!_isValidBase58Address(addr)) return false;
    }

    // ataRentLamports >= 0 when non-null
    final rent = resp.ataRentLamports;
    if (rent != null && rent < 0) return false;

    return true;
  }

  /// Validate transfer_completed — UUID v4 + txHash non-empty Base58 (~64 chars).
  bool _validateTransferCompleted(TransferCompleted c) {
    if (!_isValidUuidV4(c.requestId)) return false;
    if (c.txHash.isEmpty) return false;
    // txHash is a Solana signature (Base58-encoded 64-byte) — typically
    // 87~88 chars. Ed25519HDPublicKey.fromBase58 is for 32-byte public keys
    // only, so it's unfit for signature validation → only validate Base58
    // alphabet + length range.
    if (!_isBase58SignatureLike(c.txHash)) return false;
    return true;
  }

  /// Validate transfer_failed — UUID v4 (reason is enum, fromJson throws).
  bool _validateTransferFailed(TransferFailed f) {
    return _isValidUuidV4(f.requestId);
  }

  /// Whether [s] is in UUID v4 format (lowercase hex).
  bool _isValidUuidV4(String s) => _uuidV4Re.hasMatch(s);

  /// Solana address = Ed25519 32-byte public key Base58. `solana` package's
  /// `Ed25519HDPublicKey.fromBase58` is a strict parse — validates
  /// length / alphabet / decoded byte length. Returns false on throw.
  bool _isValidBase58Address(String addr) {
    try {
      Ed25519HDPublicKey.fromBase58(addr);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Validate Solana transaction signature Base58 format. Ed25519 signatures
  /// are 64 bytes → 86~88 chars when Base58-encoded (varies). Unlike public
  /// keys, the package has no 32-byte enforcing tool, so we fall back to
  /// regex.
  static final RegExp _base58SigRe =
      RegExp(r'^[1-9A-HJ-NP-Za-km-z]{43,90}$');
  bool _isBase58SignatureLike(String s) => _base58SigRe.hasMatch(s);

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// [clientMessageId] travels as `cid`: this device's own id for the
  /// message. The 1:1 outbox sends a message again when the server's ack did
  /// not come back; the receiver stores it once per (sender, cid). Inside the
  /// E2EE payload only — the server never sees it. [nameCert] (base64) is
  /// this account's name certificate, at the top level (§12.4).
  Map<String, dynamic> _buildPayload({
    required String clientMessageId,
    required String text,
    required MessageType type,
    String? attachmentFileKey,
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
    String? nameCert,
  }) {
    return {
      'cid': clientMessageId,
      'text': text,
      'type': type.name,
      'timestamp': DateTime.now().toIso8601String(),
      if (attachmentFileKey != null) 'fileKey': attachmentFileKey,
      if (metadata != null) 'metadata': metadata,
      if (ttlSeconds != null) 'ttl': ttlSeconds,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToPreview != null) 'replyToPreview': replyToPreview,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      if (nameCert != null) 'nameCert': nameCert,
    };
  }

  /// The message type an inner `type` names, or null for one this build
  /// does not know (consumed, never shown). `system` is never a peer's: it
  /// is this device's own kind (its controls, its notices) — a peer naming it
  /// gets nothing shown.
  static MessageType? _parseMessageType(Object? type) {
    switch (type) {
      case 'text':
        return MessageType.text;
      case 'file':
        return MessageType.file;
      case 'voice':
        return MessageType.voice;
      default:
        return null;
    }
  }

  /// A message's metadata as the peer sent it, without the keys that start
  /// with `_` — this device's own flags (`_isReadReceipt`, `_isUnsend`, …)
  /// that only the decrypt sets. A peer that put one there would otherwise
  /// make an ordinary message act as a control. Null when it is not a map.
  static Map<String, dynamic>? _peerMetadata(Object? raw) {
    if (raw is! Map) return null;
    return {
      for (final e in raw.entries)
        if (e.key is String && !(e.key as String).startsWith('_'))
          e.key as String: e.value,
    };
  }
}
