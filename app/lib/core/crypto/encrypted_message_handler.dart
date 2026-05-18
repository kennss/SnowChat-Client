/// @file        encrypted_message_handler.dart
/// @description E2EE chat flow integration. Encrypt outgoing messages, decrypt incoming messages, 1:1/group E2EE, file transfer handling
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-14 (decryptSealedMessage now accepts both 'sealedContent' (socket transport) and 'encryptedContent' (REST fetchPending) field names — swipe-killed cold-start sealed messages were silently lost because REST drain hit a StateError that placeholder + ACK swallowed)
///
/// @functions
///  - EncryptedMessageHandler: E2EE message encrypt/decrypt handler class
///  - EncryptedMessageHandler.sendEncryptedMessage(): Send 1:1 encrypted message (with reply)
///  - EncryptedMessageHandler.decryptIncomingMessage(): Decrypt 1:1 incoming message (in-flight Future dedup)
///  - EncryptedMessageHandler._doDecrypt(): Perform the actual Signal decryption (internal only)
///  - EncryptedMessageHandler.sendGroupMessage(): Send encrypted group message (Sender Key, with reply)
///  - EncryptedMessageHandler.decryptGroupMessage(): Decrypt incoming group message (reply restoration)
///  - EncryptedMessageHandler.sendFileMessage(): Send E2EE file attachment message
///  - EncryptedMessageHandler.sendGroupFileMessage(): Send group E2EE file attachment message
///  - EncryptedMessageHandler.sendVoiceMessage(): Send E2EE voice message (AAC encrypted)
///  - EncryptedMessageHandler.sendGroupVoiceMessage(): Send group E2EE voice message
///  - EncryptedMessageHandler.getDecryptedFileBytes(): Extract fileId/fileKey from message metadata, download and decrypt
///  - EncryptedMessageHandler.sendSealedMessage(): Send Sealed Sender 1:1 encrypted message (seal() wraps DR ciphertext)
///  - EncryptedMessageHandler.decryptSealedMessage(): Sealed Sender unseal + DR decrypt -> return Message
///  - EncryptedMessageHandler._tryDispatchTransfer(): wallet V2 Phase B — transfer_* type dispatch + EventBus emit
///  - EncryptedMessageHandler._validateTransferRequest(): Validate UUID v4 / amount / decimals / mint / sentAt
///  - EncryptedMessageHandler._validateTransferResponse(): Validate walletAddress / Sig / ataRentLamports
///  - EncryptedMessageHandler._validateTransferCompleted(): Validate txHash non-empty Base58
///  - EncryptedMessageHandler._validateTransferFailed(): Validate requestId UUID v4
///  - EncryptedMessageHandler._isValidUuidV4(): UUID v4 regex validation (replay window guard)
///  - EncryptedMessageHandler._isValidBase58Address(): Solana Base58 32-byte validation (Ed25519HDPublicKey.fromBase58)

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:solana/solana.dart' show Ed25519HDPublicKey;

import '../../features/chat/models/message.dart';
import '../../features/wallet/models/transfer_request.dart';
import '../../features/wallet/services/transfer_event_bus.dart';
import '../network/file_service.dart';
import '../network/socket_manager.dart';
import 'file_encryptor.dart';
import 'group_session_manager.dart';
import 'identity_change_handler.dart';
import 'identity_key_changed_exception.dart';
import 'sealed_sender.dart';
import 'sender_certificate.dart';
import 'sender_certificate_manager.dart';
import 'signal_session_manager.dart';

/// Integrates E2EE with the chat flow.
///
/// - Encrypts outgoing messages before sending via socket
/// - Decrypts incoming messages from socket events
/// - Handles both 1:1 and group E2EE
///
/// Socket send payload matches server's PrivateMessagePayload:
/// { recipientId, encryptedContent (base64), type ('e2ee_text'),
///   clientMessageId, expiresIn? }
///
/// IMPORTANT: This handler never logs plaintext message content.
class EncryptedMessageHandler {
  final SignalSessionManager _sessionManager;
  final SocketManager _socketManager;
  final GroupSessionManager? _groupSessionManager;
  final FileService? _fileService;
  // Sealed Sender service + certificate manager are lazy-wired.
  // `sealedSenderServiceProvider` is a StateProvider whose initial value
  // is null — the service activates only after `/auth/server-key` fetch,
  // which happens post-login. Constructing this handler reads the
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

  /// Optional Safety Number mismatch handler. When wired, send-path TOFU
  /// failures (IdentityKeyChangedException raised by createSession) are
  /// routed through here instead of bubbling as a generic ratchet error.
  IdentityChangeHandler? identityChangeHandler;

  /// In-flight decrypt futures: prevents double-decryption when multiple
  /// broadcast-stream listeners (ConversationListProvider + MessageRepository)
  /// call decryptIncomingMessage concurrently for the same socket event.
  ///
  /// The Signal Double Ratchet is stateful — decrypting the same ciphertext
  /// twice corrupts the session. Because both listeners start before either
  /// awaits, a simple result-cache misses the race. Instead, the first caller
  /// registers its Future synchronously (before await), so the second caller
  /// finds and reuses the same Future.
  final Map<String, Future<Message>> _inflightDecrypts = {};

  /// Public access for group session initialization from ChatNotifier.
  GroupSessionManager? get groupSessionManager => _groupSessionManager;

  /// Public access for direct encrypt/decrypt (SKDM inline, pairwise fallback).
  SignalSessionManager get sessionManager => _sessionManager;

  EncryptedMessageHandler({
    required SignalSessionManager sessionManager,
    required SocketManager socketManager,
    GroupSessionManager? groupSessionManager,
    FileService? fileService,
    SealedSenderService? sealedSenderService,
    SenderCertificateManager? senderCertificateManager,
    TransferEventBus? transferEventBus,
  })  : _sessionManager = sessionManager,
        _socketManager = socketManager,
        _groupSessionManager = groupSessionManager,
        _fileService = fileService,
        _sealedSenderService = sealedSenderService,
        _senderCertificateManager = senderCertificateManager,
        _transferEventBus = transferEventBus;

  // ---------------------------------------------------------------------------
  // 1:1 Messaging
  // ---------------------------------------------------------------------------

  /// Encrypt and send a text message to [recipientId].
  ///
  /// Flow:
  /// 1. Ensure session exists (X3DH if needed via ensureSession)
  /// 2. Build plaintext JSON payload: { text, type, timestamp, ttl?, fileKey?, metadata? }
  /// 3. Encrypt with Double Ratchet -> { ciphertext, messageType }
  /// 4. Send via socket matching server's PrivateMessagePayload:
  ///    { recipientId, encryptedContent(b64), type('e2ee_text'), clientMessageId }
  Future<void> sendEncryptedMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    required String clientMessageId,
    String? attachmentFileKey,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
    Function(dynamic)? onAck,
  }) async {
    debugPrint('[E2EE:Send] Step 1: ensureSession($recipientId)');
    // Step 1: Ensure we have a session with the recipient.
    //
    // P0-2 Stage B: catch IdentityKeyChangedException explicitly here so a
    // TOFU mismatch routes into IdentityChangeHandler (Safety Number recompute,
    // DAO mismatch latch, in-conversation system message). Without this catch
    // the message would loop forever in the outbox — every retry hits the
    // same pin store check and re-throws — leaving the user wondering why
    // their messages stopped sending without any visible warning.
    try {
      await _sessionManager.ensureSession(recipientId);
    } on IdentityKeyChangedException catch (idChange) {
      debugPrint('[E2EE:Send] Identity key changed for '
          '${idChange.peerSnowchatId} — routing to IdentityChangeHandler');
      final handler = identityChangeHandler;
      if (handler != null) {
        try {
          await handler.handleMismatch(
            peerSnowchatId: idChange.peerSnowchatId,
            conversationId: conversationId,
            oldKey: idChange.expectedKey,
            newKey: idChange.actualKey,
          );
        } catch (handlerErr) {
          debugPrint('[E2EE:Send] identityChangeHandler FAILED: '
              '$handlerErr');
        }
      }
      // Rethrow so the outbox treats the message as undeliverable. Caller
      // (chat provider / outbox) MUST drop the message rather than retry —
      // the verify-identity flow is the recovery path.
      rethrow;
    }
    debugPrint('[E2EE:Send] Step 1 OK');

    // Step 2: Build the plaintext payload (JSON-encoded, never logged)
    final payload = _buildPayload(
      text: text,
      type: type,
      attachmentFileKey: attachmentFileKey,
      metadata: metadata,
      ttlSeconds: ttlSeconds,
      replyToId: replyToId,
      replyToPreview: replyToPreview,
      replyToSenderId: replyToSenderId,
    );
    final plaintextBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    // Step 3: Encrypt for the recipient's device
    // Use actual device ID from session (not hardcoded 'primary')
    debugPrint('[E2EE:Send] Step 3: getDeviceId + encrypt');
    final deviceId = await _sessionManager.getDeviceIdForRecipient(recipientId);
    final encrypted = await _sessionManager.encrypt(
      recipientId,
      deviceId,
      plaintextBytes,
    );
    debugPrint('[E2EE:Send] Step 3 OK: deviceId=$deviceId '
        'msgType=${encrypted['messageType']}');

    // Step 4: Send via socket matching server's PrivateMessagePayload.
    // Wrap the caller's onAck so we can register the server-assigned
    // messageId as an alias in MessageSendLog — peers send retry requests
    // using the server id, not the client id, and without this alias
    // `lookup()` returns null and the entire retry pipeline silently SKIPs
    // (the 2026-04-24 Galaxy ↔ emulator-5554 deadlock was a direct symptom).
    void Function(dynamic)? wrappedAck = onAck;
    wrappedAck = (response) {
      try {
        if (response is Map) {
          final serverMsgId = response['messageId'];
          if (serverMsgId is String && serverMsgId.isNotEmpty) {
            _sessionManager.signal.messageSendLog
                .addAlias(clientMessageId, serverMsgId);
            debugPrint(
              '[E2EE:Send] messageSendLog alias registered: '
              '$clientMessageId → $serverMsgId',
            );
          }
        }
      } catch (e) {
        debugPrint('[E2EE:Send] ack alias registration failed: $e');
      }
      if (onAck != null) onAck(response);
    };

    debugPrint('[E2EE:Send] Step 4: sendPrivateMessage');
    _socketManager.sendPrivateMessage({
      'recipientId': recipientId,
      'encryptedContent':
          base64Encode(encrypted['ciphertext'] as Uint8List),
      'type': 'e2ee_text',
      'messageType': encrypted['messageType'] as int, // 1=normal, 2=prekey
      'clientMessageId': clientMessageId,
      if (ttlSeconds != null) 'expiresIn': ttlSeconds,
    }, onAck: wrappedAck);
    debugPrint('[E2EE:Send] Step 4 OK — message dispatched');

    // Phase 10 P0-A: Record plaintext in MessageSendLog for retry requests.
    // If the recipient fails to decrypt, they'll send a retry request and we
    // re-encrypt from this log entry under the new session.
    _sessionManager.signal.messageSendLog.record(
      clientMessageId,
      plaintextBytes,
      conversationId: conversationId,
      isGroup: false,
    );
  }

  /// Decrypt an incoming 1:1 message from a socket event.
  ///
  /// The socket event (from server's 'new_message') contains:
  /// - `senderId` / `senderSnowchatId`: SnowChat ID of the sender
  /// - `senderDeviceId` / `deviceId`: sender's device ID
  /// - `encryptedPayload`: base64-encoded ciphertext
  /// - `messageType`: Signal message type (1=cipher, 2=prekey_msg)
  /// - `conversationId`: conversation ID (may be absent for new conversations)
  /// - `messageId` / `id`: server-assigned message ID
  /// - `serverTimestamp` / `timestamp`: ISO 8601 timestamp
  ///
  /// For messageType 2 (pre-key message), the session is established
  /// automatically during decryption -- this is the first message from
  /// a new contact.
  Future<Message> decryptIncomingMessage(
    Map<String, dynamic> socketEvent,
  ) async {
    final messageId =
        (socketEvent['messageId'] ?? socketEvent['id']) as String;

    // If another listener already started decrypting this message, reuse
    // its Future. This is checked synchronously (before any await) so the
    // second broadcast-stream listener always finds the Future registered
    // by the first listener.
    final inflight = _inflightDecrypts[messageId];
    if (inflight != null) {
      debugPrint('[E2EE] Joining in-flight decrypt for $messageId');
      return inflight;
    }

    // Register the decrypt Future synchronously before the first await.
    // This guarantees the second listener will see it even though Dart's
    // event loop hasn't yielded yet.
    final future = _doDecrypt(socketEvent, messageId);
    _inflightDecrypts[messageId] = future;

    try {
      return await future;
    } finally {
      _inflightDecrypts.remove(messageId);
      // Evict stale entries (defensive — should be empty under normal flow)
      if (_inflightDecrypts.length > 50) {
        _inflightDecrypts.remove(_inflightDecrypts.keys.first);
      }
    }
  }

  /// Internal: performs actual Signal decryption for a single message.
  Future<Message> _doDecrypt(
    Map<String, dynamic> socketEvent,
    String messageId,
  ) async {
    final senderId = (socketEvent['senderSnowchatId'] ??
        socketEvent['senderId']) as String;
    // Phase 8.7 Bug A: cached/consistent deviceId is preferred. On the very
    // first interaction with a sender (cold start, no prior outbound), the
    // cache may be empty — in that case adopt the senderDeviceId carried
    // by the socket envelope so the (snowId, deviceId) session key matches
    // what the peer used. Subsequent lookups continue to hit the cache.
    final incomingDeviceId =
        (socketEvent['senderDeviceId'] ?? socketEvent['deviceId']) as String?;
    final deviceId = _sessionManager.learnDeviceIdFromIncoming(
      senderId,
      incomingDeviceId,
    );
    final encryptedPayload =
        socketEvent['encryptedContent'] ?? socketEvent['encryptedPayload'];
    final messageType = socketEvent['messageType'] as int? ?? 1;
    debugPrint('[E2EE] Decrypting: sender=$senderId device=$deviceId '
        'msgType=$messageType hasContent=${encryptedPayload != null}');
    // Phase 3: server CUID required. No conv_ fallback.
    final conversationId = socketEvent['conversationId'] as String? ?? senderId;
    final timestamp = socketEvent['serverTimestamp'] != null
        ? DateTime.parse(socketEvent['serverTimestamp'] as String)
        : (socketEvent['timestamp'] != null
            ? DateTime.parse(socketEvent['timestamp'] as String)
            : DateTime.now());

    // Decode the base64 ciphertext
    Uint8List ciphertext;
    if (encryptedPayload is String) {
      ciphertext = Uint8List.fromList(base64Decode(encryptedPayload));
    } else if (encryptedPayload is List<int>) {
      ciphertext = Uint8List.fromList(encryptedPayload);
    } else {
      return _failedMessage(
        messageId: messageId,
        conversationId: conversationId,
        senderId: senderId,
        timestamp: timestamp,
      );
    }

    try {
      // Decrypt: for messageType 2, the Signal layer establishes the
      // session from the pre-key message automatically
      final plaintextBytes = await _sessionManager.decrypt(
        senderId,
        deviceId,
        ciphertext,
        messageType,
      );

      // Parse the decrypted JSON payload
      final payload = jsonDecode(utf8.decode(plaintextBytes))
          as Map<String, dynamic>;

      // Wallet V2 Phase B (2026-04-20): transfer_* type dispatch.
      // If payload['type'] is one of the 4 kinds (transfer_request /
      // response / completed / failed), emit on TransferEventBus and return
      // a system Message marking. The caller (message_queue) inspects
      // metadata['_isTransferControl'] to branch drift insert / UI handling
      // (will be unified in Phase G).
      final transferMsg = _tryDispatchTransfer(
        payload: payload,
        senderSnowchatId: senderId,
        messageId: messageId,
        conversationId: conversationId,
        timestamp: timestamp,
      );
      if (transferMsg != null) return transferMsg;

      final text = payload['text'] as String? ?? '';
      final msgType = _parseMessageType(payload['type'] as String?);
      final msgMetadata = payload['metadata'] as Map<String, dynamic>?;
      final ttlSeconds = payload['ttl'] as int?;
      final replyToId = payload['replyToId'] as String?;
      final replyToPreview = payload['replyToPreview'] as String?;
      final replyToSenderId = payload['replyToSenderId'] as String?;

      return Message(
        id: messageId,
        conversationId: conversationId,
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
      );
    } catch (e, st) {
      debugPrint('[EncryptedMessageHandler] Decryption failed for '
          'message $messageId from $senderId: $e\n$st');
      // Phase 6: Rethrow so the MessageQueue can retry / hold the message.
      // Returning a failure placeholder caused the queue to ACK and lose
      // the message permanently when decryption was actually recoverable
      // (e.g. out-of-order ratchet, missing SKDM dependency).
      rethrow;
    }
  }

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
  Future<void> sendSealedMessage({
    required String conversationId,
    required String recipientId,
    required String text,
    required String clientMessageId,
    String? attachmentFileKey,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
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
    // throw-free; transport failures here are absorbed by the same retry
    // path as regular DR — recipient decrypt fails, retry_handler kicks
    // session_reset, peer rebuilds on next message).
    final certificate = await _senderCertificateManager!.getCertificate();
    final recipientIdentityPubKey =
        _sessionManager.signal.getRemoteIdentityKey(recipientId);
    if (recipientIdentityPubKey == null) {
      throw StateError(
        'Sealed Sender: no cached identity key for $recipientId. '
        'Cannot seal without recipient IK.',
      );
    }
    final deviceId = await _sessionManager.getDeviceIdForRecipient(recipientId);

    // Step 3: Build the plaintext payload (JSON-encoded, never logged)
    final payload = _buildPayload(
      text: text,
      type: type,
      attachmentFileKey: attachmentFileKey,
      metadata: metadata,
      ttlSeconds: ttlSeconds,
      replyToId: replyToId,
      replyToPreview: replyToPreview,
      replyToSenderId: replyToSenderId,
    );
    final plaintextBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

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

    // Step 6: Send via socket 'sealed_message' event.
    _socketManager.sendSealedMessage(
      recipientId: recipientId,
      sealedContent: base64Encode(sealedEnvelope),
      clientMessageId: clientMessageId,
      expiresIn: ttlSeconds,
      onAck: onAck,
    );

    // Step 7: Record plaintext in MessageSendLog so retry_handler can
    // respond to blind-retry requests by re-encrypting under a fresh
    // session. Mirrors the regular DR path's record() call at the end of
    // sendEncryptedMessage.
    _sessionManager.signal.messageSendLog.record(
      clientMessageId,
      plaintextBytes,
      conversationId: conversationId,
      isGroup: false,
    );
  }

  /// Decrypt an incoming Sealed Sender message.
  ///
  /// Flow:
  /// 1. Parse sealed envelope from socket event
  /// 2. Get our own identity key pair
  /// 3. Unseal with SealedSenderService.unseal() -> sender identity + DR ciphertext
  /// 4. Feed DR ciphertext into existing _sessionManager.decrypt() pipeline
  /// 5. Return the same Message object as decryptIncomingMessage()
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

    // In-flight dedup (same as decryptIncomingMessage)
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

    final conversationId =
        socketEvent['conversationId'] as String? ?? messageId;
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

    debugPrint('[E2EE:Sealed] Unsealed: sender=$senderId device=$senderDeviceId '
        'context=${unsealed.messageContext}');

    // Cache the sender's device ID (same as learnDeviceIdFromIncoming)
    _sessionManager.learnDeviceIdFromIncoming(senderId, senderDeviceId);

    // Step 4: Determine Signal message type from DR ciphertext header.
    // The DR ciphertext is a JSON-encoded string. We need the messageType
    // to route correctly through the Signal decrypt pipeline.
    // For sealed messages, default to normal cipher (1) — prekey messages
    // (2) will be handled by the Signal layer automatically.
    final messageType = socketEvent['messageType'] as int? ?? 1;

    try {
      // Step 5: Decrypt with Double Ratchet
      final plaintextBytes = await _sessionManager.decrypt(
        senderId,
        senderDeviceId,
        unsealed.drCiphertext,
        messageType,
      );

      // Step 6: Parse the decrypted JSON payload
      final payload = jsonDecode(utf8.decode(plaintextBytes))
          as Map<String, dynamic>;

      // Derive conversationId from sender if not provided by server
      final resolvedConversationId =
          socketEvent['conversationId'] as String? ?? senderId;

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

      final text = payload['text'] as String? ?? '';
      final msgType = _parseMessageType(payload['type'] as String?);
      final msgMetadata = payload['metadata'] as Map<String, dynamic>?;
      final ttlSeconds = payload['ttl'] as int?;
      final replyToId = payload['replyToId'] as String?;
      final replyToPreview = payload['replyToPreview'] as String?;
      final replyToSenderId = payload['replyToSenderId'] as String?;

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
      );
    } catch (e, st) {
      debugPrint('[EncryptedMessageHandler:Sealed] Decryption failed for '
          'message $messageId from $senderId: $e\n$st');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Group Messaging (Sender Keys)
  // ---------------------------------------------------------------------------

  /// Encrypt and send a message to a group using Sender Keys.
  ///
  /// Flow:
  /// 1. Build plaintext JSON payload
  /// 2. Encrypt with own Sender Key via GroupSessionManager (O(1))
  /// 3. Send via Socket.IO 'send_group_message' event
  /// 4. Server fans out the same ciphertext to all group members
  ///
  /// **Phase 6.9**: [myId] (current user's SnowChat ID) MUST be passed by the
  /// caller. GroupSessionManager no longer captures myId at construction time.
  Future<Message> sendGroupMessage({
    required String conversationId,
    required String groupId,
    required String myId,
    required String text,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
  }) async {
    if (_groupSessionManager == null) {
      throw StateError('GroupSessionManager not configured');
    }
    if (myId.isEmpty) {
      throw ArgumentError(
          'sendGroupMessage: myId must not be empty (group $groupId)');
    }

    final payload = _buildPayload(
      text: text,
      type: type,
      metadata: metadata,
      ttlSeconds: ttlSeconds,
      replyToId: replyToId,
      replyToPreview: replyToPreview,
      replyToSenderId: replyToSenderId,
    );
    final plaintextBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));

    final ciphertext = _groupSessionManager.sendGroupMessage(
      groupId,
      myId,
      plaintextBytes,
    );

    final messageId = _generateMessageId();
    final now = DateTime.now();

    // Send via Socket.IO matching server's SendGroupMessagePayload
    _socketManager.sendGroupMessage({
      'groupChatId': groupId,
      'encryptedPayload': base64Encode(ciphertext),
      if (ttlSeconds != null) 'expiresIn': ttlSeconds,
    });

    return Message(
      id: messageId,
      conversationId: conversationId,
      senderSnowchatId: '', // Caller fills in
      plaintext: text,
      timestamp: now,
      type: type,
      status: MessageStatus.sending,
      metadata: metadata,
      expiresAt: ttlSeconds != null
          ? now.add(Duration(seconds: ttlSeconds))
          : null,
    );
  }

  /// Decrypt an incoming group message (from 'new_group_message' socket event).
  ///
  /// Socket event fields (from server messageHandler):
  /// - `senderSnowchatId` / `senderId`: sender SnowChat ID
  /// - `groupChatId`: group ID
  /// - `encryptedPayload`: base64-encoded Sender Key ciphertext
  /// - `messageId` / `id`: server-assigned message ID
  /// - `serverTimestamp` / `timestamp`: ISO 8601 timestamp
  /// - `senderKeyEpoch`: sender key epoch (for key rotation tracking)
  Future<Message> decryptGroupMessage(
    Map<String, dynamic> socketEvent,
  ) async {
    if (_groupSessionManager == null) {
      throw StateError('GroupSessionManager not configured');
    }

    final senderId = (socketEvent['senderSnowchatId'] ??
        socketEvent['senderId']) as String;
    final groupId = (socketEvent['groupChatId'] ??
        socketEvent['groupId']) as String;
    final encryptedPayload =
        socketEvent['encryptedContent'] ?? socketEvent['encryptedPayload'];
    final conversationId =
        socketEvent['conversationId'] as String? ?? 'group_$groupId';
    final messageId =
        (socketEvent['messageId'] ?? socketEvent['id']) as String;
    final timestamp = socketEvent['serverTimestamp'] != null
        ? DateTime.parse(socketEvent['serverTimestamp'] as String)
        : (socketEvent['timestamp'] != null
            ? DateTime.parse(socketEvent['timestamp'] as String)
            : DateTime.now());

    // Decode the base64 ciphertext
    Uint8List ciphertext;
    if (encryptedPayload is String) {
      ciphertext = Uint8List.fromList(base64Decode(encryptedPayload));
    } else if (encryptedPayload is List<int>) {
      ciphertext = Uint8List.fromList(encryptedPayload);
    } else {
      return _failedMessage(
        messageId: messageId,
        conversationId: conversationId,
        senderId: senderId,
        timestamp: timestamp,
      );
    }

    try {
      final plaintextBytes = _groupSessionManager.decryptGroupMessage(
        groupId,
        senderId,
        ciphertext,
      );

      final payload = jsonDecode(utf8.decode(plaintextBytes))
          as Map<String, dynamic>;

      final text = payload['text'] as String? ?? '';
      final msgType = _parseMessageType(payload['type'] as String?);
      final msgMetadata = payload['metadata'] as Map<String, dynamic>?;
      final ttlSeconds = payload['ttl'] as int?;
      final replyToId = payload['replyToId'] as String?;
      final replyToPreview = payload['replyToPreview'] as String?;
      final replyToSenderId = payload['replyToSenderId'] as String?;

      return Message(
        id: messageId,
        conversationId: conversationId,
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
      );
    } catch (e) {
      debugPrint('[EncryptedMessageHandler] Group decryption failed for '
          'message $messageId in group $groupId from $senderId: $e');
      // Rethrow so the caller (_handleGroupMessage) can fall through
      // to pairwise fallback instead of getting a fake success.
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Encrypted File Transfer
  // ---------------------------------------------------------------------------

  /// Encrypt and send a file message to a 1:1 recipient.
  ///
  /// Flow:
  /// 1. Read file bytes from [filePath]
  /// 2. Encrypt file with random key via FileEncryptor
  /// 3. Upload encrypted blob to server → get fileId
  /// 4. Build E2EE message containing file metadata + fileKey
  /// 5. Send via Double Ratchet → recipient decrypts message → gets fileKey
  ///    → downloads blob → decrypts file
  ///
  /// The server never sees: file content, file name, file type, or file key.
  Future<void> sendFileMessage({
    required String conversationId,
    required String recipientId,
    required String clientMessageId,
    required String filePath,
    required String fileName,
    required String mimeType,
    int? ttlSeconds,
  }) async {
    if (_fileService == null) {
      throw StateError('FileService not configured');
    }

    // Step 1: Read file
    final fileData = await File(filePath).readAsBytes();

    // Step 2: Encrypt with random key
    final encResult = await FileEncryptor.encryptFile(
      Uint8List.fromList(fileData),
    );

    // Step 3: Upload encrypted blob
    final fileId = await _fileService.uploadEncryptedFile(
      encResult.encryptedData,
      encResult.contentHash,
    );

    // Step 4: Build E2EE message with file metadata
    final fileMetadata = {
      'type': 'file',
      'fileId': fileId,
      'fileKey': base64Encode(encResult.fileKey),
      'fileName': fileName,
      'mimeType': mimeType,
      'size': fileData.length,
      'contentHash': encResult.contentHash,
    };

    // Step 5: Send as encrypted message
    await sendEncryptedMessage(
      conversationId: conversationId,
      recipientId: recipientId,
      text: fileName,
      clientMessageId: clientMessageId,
      type: MessageType.file,
      metadata: fileMetadata,
      ttlSeconds: ttlSeconds,
    );
  }

  /// Encrypt and send a file message to a group.
  ///
  /// Same flow as 1:1 file messages but encrypts with Sender Key.
  Future<Message> sendGroupFileMessage({
    required String conversationId,
    required String groupId,
    required String myId,
    required String filePath,
    required String fileName,
    required String mimeType,
    int? ttlSeconds,
  }) async {
    if (_fileService == null) {
      throw StateError('FileService not configured');
    }

    final fileData = await File(filePath).readAsBytes();

    final encResult = await FileEncryptor.encryptFile(
      Uint8List.fromList(fileData),
    );

    final fileId = await _fileService.uploadEncryptedFile(
      encResult.encryptedData,
      encResult.contentHash,
    );

    final fileMetadata = {
      'type': 'file',
      'fileId': fileId,
      'fileKey': base64Encode(encResult.fileKey),
      'fileName': fileName,
      'mimeType': mimeType,
      'size': fileData.length,
      'contentHash': encResult.contentHash,
    };

    return sendGroupMessage(
      conversationId: conversationId,
      groupId: groupId,
      myId: myId,
      text: fileName,
      type: MessageType.file,
      metadata: fileMetadata,
      ttlSeconds: ttlSeconds,
    );
  }

  // ---------------------------------------------------------------------------
  // Encrypted Voice Message
  // ---------------------------------------------------------------------------

  /// Encrypt and send a voice message to a 1:1 recipient.
  ///
  /// Flow:
  /// 1. Read audio bytes from [audioPath]
  /// 2. Encrypt audio with random key via FileEncryptor
  /// 3. Upload encrypted blob to server -> get fileId
  /// 4. Build E2EE message: { type: "voice", fileId, fileKey, duration, mimeType }
  /// 5. Send via Double Ratchet
  ///
  /// Max duration: 5 minutes (300 seconds). Format: AAC/M4A.
  Future<void> sendVoiceMessage({
    required String conversationId,
    required String recipientId,
    required String clientMessageId,
    required String audioPath,
    required int durationSeconds,
    int? ttlSeconds,
  }) async {
    if (_fileService == null) {
      throw StateError('FileService not configured');
    }

    // Step 1: Read audio file
    final audioData = await File(audioPath).readAsBytes();

    // Step 2: Encrypt with random key
    final encResult = await FileEncryptor.encryptFile(
      Uint8List.fromList(audioData),
    );

    // Step 3: Upload encrypted blob
    final fileId = await _fileService.uploadEncryptedFile(
      encResult.encryptedData,
      encResult.contentHash,
    );

    // Step 4: Build E2EE message with voice metadata
    final voiceMetadata = {
      'type': 'voice',
      'fileId': fileId,
      'fileKey': base64Encode(encResult.fileKey),
      'duration': durationSeconds,
      'mimeType': 'audio/aac',
      'size': audioData.length,
      'contentHash': encResult.contentHash,
    };

    // Step 5: Send as encrypted message
    await sendEncryptedMessage(
      conversationId: conversationId,
      recipientId: recipientId,
      text: 'Voice message',
      clientMessageId: clientMessageId,
      type: MessageType.voice,
      metadata: voiceMetadata,
      ttlSeconds: ttlSeconds,
    );
  }

  /// Encrypt and send a voice message to a group.
  ///
  /// Same flow as 1:1 voice messages but encrypts with Sender Key.
  Future<Message> sendGroupVoiceMessage({
    required String conversationId,
    required String groupId,
    required String myId,
    required String audioPath,
    required int durationSeconds,
    int? ttlSeconds,
  }) async {
    if (_fileService == null) {
      throw StateError('FileService not configured');
    }

    final audioData = await File(audioPath).readAsBytes();

    final encResult = await FileEncryptor.encryptFile(
      Uint8List.fromList(audioData),
    );

    final fileId = await _fileService.uploadEncryptedFile(
      encResult.encryptedData,
      encResult.contentHash,
    );

    final voiceMetadata = {
      'type': 'voice',
      'fileId': fileId,
      'fileKey': base64Encode(encResult.fileKey),
      'duration': durationSeconds,
      'mimeType': 'audio/aac',
      'size': audioData.length,
      'contentHash': encResult.contentHash,
    };

    return sendGroupMessage(
      conversationId: conversationId,
      groupId: groupId,
      myId: myId,
      text: 'Voice message',
      type: MessageType.voice,
      metadata: voiceMetadata,
      ttlSeconds: ttlSeconds,
    );
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

  Map<String, dynamic> _buildPayload({
    required String text,
    required MessageType type,
    String? attachmentFileKey,
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
  }) {
    return {
      'text': text,
      'type': type.name,
      'timestamp': DateTime.now().toIso8601String(),
      if (attachmentFileKey != null) 'fileKey': attachmentFileKey,
      if (metadata != null) 'metadata': metadata,
      if (ttlSeconds != null) 'ttl': ttlSeconds,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToPreview != null) 'replyToPreview': replyToPreview,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
    };
  }

  /// Return a placeholder message indicating decryption failure.
  static Message _failedMessage({
    required String messageId,
    required String conversationId,
    required String senderId,
    required DateTime timestamp,
  }) {
    return Message(
      id: messageId,
      conversationId: conversationId,
      senderSnowchatId: senderId,
      plaintext: '[Unable to decrypt message]',
      timestamp: timestamp,
      type: MessageType.system,
      status: MessageStatus.failed,
    );
  }

  static MessageType _parseMessageType(String? type) {
    switch (type) {
      case 'text':
        return MessageType.text;
      case 'file':
        return MessageType.file;
      case 'voice':
        return MessageType.voice;
      case 'system':
        return MessageType.system;
      default:
        return MessageType.text;
    }
  }

  static String _generateMessageId() {
    return 'msg_${DateTime.now().millisecondsSinceEpoch}';
  }
}
