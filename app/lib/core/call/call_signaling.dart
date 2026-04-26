/// @file        call_signaling.dart
/// @description VoIP signaling Sealed Sender envelope E2EE (Phase 8.2 §24.2)
///              Server has no knowledge of envelope content nor sender ID.
///              Reuses messaging's sendSealedMessage pattern for signaling.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - CallSignaling.sendSealedSignaling(): wrap signaling event in Sealed envelope and send
///  - CallSignaling.onSignalingEvent: stream of unsealed inner events
///  - CallSignaling._dispatch(): decrypt incoming envelope + dispatch by type
///  - CallSignaling.injectEnvelope(): Phase I FCM Voice Push path — feed pending
///    envelope into same decrypt / dispatch logic as the socket path

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../crypto/sealed_sender.dart';
import '../crypto/sender_certificate_manager.dart';
import '../crypto/signal_session_manager.dart';
import '../network/socket_manager.dart';

/// Signaling event type (inside the envelope — server cannot see).
class CallSignalingEvent {
  const CallSignalingEvent({
    required this.type,
    required this.senderSnowchatId,
    required this.data,
    required this.timestamp,
  });

  /// `call_invite` | `call_answer` | `call_end` | `rtc_offer` | `rtc_answer`
  /// | `ice_candidate` | `call_busy` | `call_ringing`
  final String type;

  /// Sender ID confirmed after envelope decryption (inside the Sealed Sender certificate).
  final String senderSnowchatId;

  /// Per-event payload. Example: `{callId, sdp, fingerprint, fingerprintSignature}`.
  final Map<String, dynamic> data;

  /// Sender-side timestamp (ISO 8601).
  final String timestamp;
}

/// VoIP signaling Sealed Sender wrapper.
///
/// Design:
/// - All signaling events ride on a single socket event `sealed_call_signaling`
/// - Event type (invite/offer/answer/ICE/end) is inside the envelope
/// - Server only relays the envelope fully opaquely (§24.2)
/// - Receiver unseals and dispatches by type via `onSignalingEvent`
class CallSignaling {
  CallSignaling({
    required SignalSessionManager sessionManager,
    required SealedSenderService sealedSenderService,
    required SenderCertificateManager senderCertificateManager,
    required SocketManager socketManager,
  })  : _sessionManager = sessionManager,
        _sealedSenderService = sealedSenderService,
        _senderCertificateManager = senderCertificateManager,
        _socketManager = socketManager {
    _subscription = _socketManager.onSealedCallSignaling.listen(_onIncoming);
  }

  final SignalSessionManager _sessionManager;
  final SealedSenderService _sealedSenderService;
  final SenderCertificateManager _senderCertificateManager;
  final SocketManager _socketManager;

  final _eventController = StreamController<CallSignalingEvent>.broadcast();

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  /// Inner event stream after unseal + Double Ratchet decryption.
  Stream<CallSignalingEvent> get onSignalingEvent => _eventController.stream;

  /// Send a signaling event wrapped in a Sealed Sender envelope.
  ///
  /// Sender-side flow (§24.2.2):
  /// 1. ensureSession(recipientSnowchatId) — guarantee X3DH session
  /// 2. Serialize inner payload JSON `{type, data, timestamp}`
  /// 3. Double Ratchet encrypt → drCiphertext
  /// 4. Obtain SenderCertificate (cache or reissue)
  /// 5. Look up recipient IK, then Sealed Sender seal
  /// 6. Send `sealed_call_signaling` over the socket (recipient ID + envelope base64 only)
  ///
  /// Throws on failure. Caller handles via CallNotifier state transitions.
  Future<SendResult> sendSealedSignaling({
    required String recipientSnowchatId,
    required String eventType,
    required Map<String, dynamic> innerPayload,
  }) async {
    // Step 1: Ensure session
    await _sessionManager.ensureSession(recipientSnowchatId);

    // Step 2: Build inner JSON
    final innerJson = jsonEncode({
      'type': eventType,
      'data': innerPayload,
      'timestamp': DateTime.now().toIso8601String(),
    });
    final innerBytes = Uint8List.fromList(utf8.encode(innerJson));

    // Step 3: Double Ratchet encrypt
    final deviceId =
        await _sessionManager.getDeviceIdForRecipient(recipientSnowchatId);
    final drResult = await _sessionManager.encrypt(
      recipientSnowchatId,
      deviceId,
      innerBytes,
    );
    final drCiphertext = drResult['ciphertext'] as Uint8List;

    // Step 4: Sender certificate
    final certificate = await _senderCertificateManager.getCertificate();

    // Step 5: Recipient identity key + seal
    final recipientIk =
        _sessionManager.signal.getRemoteIdentityKey(recipientSnowchatId);
    if (recipientIk == null) {
      throw StateError(
        'CallSignaling: no cached identity key for $recipientSnowchatId',
      );
    }

    final sealedEnvelope = _sealedSenderService.seal(
      recipientIdentityPubKey: recipientIk,
      drCiphertext: drCiphertext,
      certificate: certificate,
      messageContext: sealedType1to1,
    );

    // Step 6: Transport
    final completer = Completer<SendResult>();
    _socketManager.sendSealedCallSignaling(
      recipientSnowchatId: recipientSnowchatId,
      envelope: base64Encode(sealedEnvelope),
      onAck: (response) {
        if (response is Map) {
          if (response['error'] != null) {
            completer.complete(SendResult.error(
              code: response['error']['code']?.toString() ?? 'UNKNOWN',
              message: response['error']['message']?.toString() ?? '',
            ));
          } else if (response['offline'] == true) {
            completer.complete(const SendResult.offline());
          } else if (response['relayed'] == true) {
            completer.complete(const SendResult.relayed());
          } else {
            completer.complete(const SendResult.relayed());
          }
        } else {
          completer.complete(const SendResult.relayed());
        }
      },
    );
    return completer.future;
  }

  /// Incoming: envelope unseal → DR decrypt → parse inner JSON → emit on stream.
  Future<void> _onIncoming(Map<String, dynamic> data) async {
    // [Main thread yield — 2026-04-19]
    // If SocketManager calls this function immediately from the socket.on('sealed_call_signaling', ...)
    // callback, an envelope batch (e.g. ICE flood) holds the main thread serially →
    // platform events like CallKit accept get blocked. Insert one macrotask boundary so
    // IME / touch / OS events have a chance to dispatch in between.
    // (With Trickle ICE off the batch itself nearly disappears, but kept as a safety belt.)
    await Future<void>.delayed(Duration.zero);
    // [DIAG-VOIP-2026-04-19] For tracing sealed envelope decryption time. Remove after diagnosis.
    final sw = Stopwatch()..start();
    debugPrint('[DIAG:CallSignal] onIncoming ENTER bytes=${(data['envelope'] as String?)?.length ?? 0}');
    try {
      final envelopeBase64 = data['envelope'] as String?;
      if (envelopeBase64 == null) return;

      final sealedEnvelope = base64Decode(envelopeBase64);

      final ownPriv = _sessionManager.signal.identityPrivateKey;
      final ownPub = _sessionManager.signal.identityPublicKey;
      if (ownPriv == null || ownPub == null) {
        debugPrint('[CallSignaling] local identity keys unavailable');
        return;
      }

      final unsealed = _sealedSenderService.unseal(
        myIdentityPrivateKey: ownPriv,
        myIdentityPublicKey: ownPub,
        sealedEnvelope: Uint8List.fromList(sealedEnvelope),
      );
      debugPrint('[DIAG:CallSignal] unseal ${sw.elapsedMilliseconds}ms');

      final senderId = unsealed.senderSnowchatId;
      final senderDeviceId = unsealed.senderDeviceId;
      _sessionManager.learnDeviceIdFromIncoming(senderId, senderDeviceId);

      // DR cipher type — inside sealed defaults to 1 (normal); 2 is handled by the signal layer
      final messageType = (data['messageType'] as int?) ?? 1;

      final plaintextBytes = await _sessionManager.decrypt(
        senderId,
        senderDeviceId,
        unsealed.drCiphertext,
        messageType,
      );
      debugPrint('[DIAG:CallSignal] drDecrypt ${sw.elapsedMilliseconds}ms');

      final inner = jsonDecode(utf8.decode(plaintextBytes))
          as Map<String, dynamic>;
      final type = inner['type'] as String? ?? '';
      final innerData =
          (inner['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final timestamp = inner['timestamp'] as String? ?? '';

      _eventController.add(CallSignalingEvent(
        type: type,
        senderSnowchatId: senderId,
        data: innerData,
        timestamp: timestamp,
      ));
      debugPrint('[DIAG:CallSignal] onIncoming EXIT type=$type ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      // Don't log event type/content — Zero-Trace §23
      debugPrint('[CallSignaling] dispatch error: ${e.runtimeType} after ${sw.elapsedMilliseconds}ms');
    }
  }

  /// Phase I (Phase 8.2 §25): FCM Voice Push path.
  ///
  /// Background isolate shows CallKit → user Accept → MainActivity wakes → main isolate
  /// fetches base64 sealed envelope from `/api/v2/calls/pending/:nonce` and feeds it here.
  /// Reuses the same unseal + DR decrypt + dispatch logic as the existing socket path
  /// (`_onIncoming`) — no separate decryption path (keeps CI lint patterns consistent).
  ///
  /// Returns void. Decrypt results emit on the [onSignalingEvent] stream, so the caller
  /// can expect [CallService] state transition (incoming) after this Future completes.
  Future<void> injectEnvelope(String envelopeBase64) async {
    await _onIncoming({'envelope': envelopeBase64});
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _eventController.close();
  }
}

/// Result status for sendSealedSignaling.
class SendResult {
  const SendResult.relayed()
      : isRelayed = true,
        isOffline = false,
        errorCode = null,
        errorMessage = null;

  const SendResult.offline()
      : isRelayed = false,
        isOffline = true,
        errorCode = null,
        errorMessage = null;

  const SendResult.error({
    required String code,
    required String message,
  })  : isRelayed = false,
        isOffline = false,
        errorCode = code,
        errorMessage = message;

  final bool isRelayed;
  final bool isOffline;
  final String? errorCode;
  final String? errorMessage;

  bool get isError => errorCode != null;
}
