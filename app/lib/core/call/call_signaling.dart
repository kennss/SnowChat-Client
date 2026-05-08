/// @file        call_signaling.dart
/// @description VoIP signaling Sealed Sender envelope E2EE (Phase 8.2 §24.2)
///              Server has no knowledge of envelope content nor sender ID.
///              Reuses messaging's sendSealedMessage pattern for signaling.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-05-06 (Fix D + Fix E enabler — emit signalType='end' for call_end so server can selectively enqueue durable MessageQueue rows + fire sendVoipCancel FCM. Also emits envelope callId metadata for call_end (was invite-only) so server can thread the same Telecom Connection id into the cancel-wake FCM. Same plaintext class as recipientSnowchatId per §2.6.2). Earlier 2026-05-05 (Fix B: hoist envelopeBase64 + senderId out of try so catch never re-unseals — sealed envelope is one-shot and the previous catch died with "Sealed message rejected" before either archive_reset or retry_receipt could fire)
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

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';

import '../crypto/sealed_sender.dart';
import '../crypto/sender_certificate_manager.dart';
import '../crypto/signal_session_manager.dart';
import '../diagnostics/diag_log.dart';
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
    String? Function()? mySnowchatIdResolver,
  })  : _sessionManager = sessionManager,
        _sealedSenderService = sealedSenderService,
        _senderCertificateManager = senderCertificateManager,
        _socketManager = socketManager,
        _mySnowchatIdResolver = mySnowchatIdResolver {
    _subscription = _socketManager.onSealedCallSignaling.listen(_onIncoming);
  }

  final SignalSessionManager _sessionManager;
  final SealedSenderService _sealedSenderService;
  final SenderCertificateManager _senderCertificateManager;
  final SocketManager _socketManager;

  /// 2026-05-04 fix: own-sender envelope 차단 가드용 — 사용자 보고 "통화
  /// 실패 후 발신자에게 콜백" 의 client-side defense. 어떤 leak path 로든
  /// (서버 라우팅 버그, PushKit 재배달, /calls/pending nonce 노출 등) 자기
  /// 가 보낸 sealed envelope 가 자기한테 도달했을 때 unseal/decrypt/emit
  /// 의 모든 단계를 abort. providers.dart 에서 currentSnowIdProvider 를
  /// closure 로 wire.
  final String? Function()? _mySnowchatIdResolver;

  // sync: true — listener (_dispatchRemoteEvent) for `call_invite` runs
  // handleIncomingInvite synchronously, which sets CallService._status=incoming
  // before add() returns. Without sync broadcast, acceptPendingVoipCall's
  // post-inject `_callService.status != incoming` check races and fires its
  // own endCall(nonce), tearing down the call user just answered.
  // Field-confirmed via iPhone Console v196 (acceptCall ENTER never logged).
  final _eventController = StreamController<CallSignalingEvent>.broadcast(sync: true);

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  // Phase 8.2 §25 — Dual-delivery dedup (PushKit + socket).
  // For iOS recipients the server fires both a PushKit envelope (fetched via
  // /calls/pending/:nonce → injectEnvelope) and a sealed_call_signaling socket
  // relay carrying the same base64 envelope. Without this guard the same
  // envelope decrypts twice, fires handleIncomingInvite twice, and the second
  // call hits `_status != idle` → server gets a spurious `busy` decline that
  // tears down the in-flight call. Cleared on _cleanup() at call end.
  final Set<String> _processedEnvelopes = <String>{};
  static const int _processedEnvelopesCap = 64;

  /// 2026-05-04 — Signal Retry Receipt 패턴. Sender 가 보낸 sealed envelope
  /// 의 plaintext 입력 cache (60s TTL, 32 cap). Recipient 가 decrypt fail
  /// 시 retry_receipt envelope (envelope hash 포함) 보내면 sender 가 cache
  /// 조회 → archive_reset 으로 fresh session bootstrap → 같은 plaintext 재
  /// 암호화 + 재전송. 첫 시도 자체가 self-heal.
  ///
  /// Cache key = SHA-256 hex of envelope_base64. Recipient 가 동일 hash 로
  /// retry_receipt 보내므로 매칭 가능.
  ///
  /// 60s TTL — call signaling 은 짧은 lifecycle. App restart 시 cache 손실
  /// (in-memory only) — restart 직후 retry_receipt 받으면 recover 못 하나
  /// 통화 자체가 stale 상태라 큰 문제 없음.
  final Map<String, _SentEnvelopeEntry> _sentCache = {};
  static const int _sentCacheCap = 32;
  static const Duration _sentCacheTtl = Duration(seconds: 60);

  /// Inner event stream after unseal + Double Ratchet decryption.
  Stream<CallSignalingEvent> get onSignalingEvent => _eventController.stream;

  /// 2026-05-04 — sessionManager 노출 (CallService 의 pre-warm 결정용).
  SignalSessionManager get sessionManager => _sessionManager;

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
    // Phase 8.2 Path B v4 (C2) + Fix D/E (2026-05-06):
    // - signalType: server push gating tag.
    //   'invite' → triggers always-push (PushKit + FCM voip).
    //   'end'    → reuse-branch enqueue1to1 (durable) + sendVoipCancel FCM
    //              (Android BG isolate dismisses Telecom Connection without
    //              waiting for main engine boot). Same threat class as
    //              recipientSnowchatId per §2.6.2.
    //   'other'  → offer/answer/ICE — redis rpush only, legacy path.
    // - callIdMetadata: envelope callId echoed to server for both invite and
    //   call_end. Server uses it as Telecom Connection id (Z-fix unification
    //   for invite, cancel-wake target for call_end). Other signal types still
    //   ride the existing nonce → no callId emit.
    final String signalType;
    if (eventType == 'call_invite') {
      signalType = 'invite';
    } else if (eventType == 'call_end') {
      signalType = 'end';
    } else {
      signalType = 'other';
    }
    String? callIdMetadata;
    if (eventType == 'call_invite' || eventType == 'call_end') {
      final candidate = innerPayload['callId'];
      if (candidate is String && candidate.isNotEmpty) {
        callIdMetadata = candidate;
      }
    }

    // 2026-05-04 Signal Retry Receipt — cache plaintext + envelope hash
    // BEFORE emit. recipient 가 decrypt fail 시 retry_receipt 보내면
    // 이 cache 에서 조회해 재암호화.
    //
    // 제외 사유:
    //  - retry_receipt: recursion 방지
    //  - call_invite: 사용자 보고 "5554 에 수신 배너 또 뜸" 회귀 (+233).
    //    recipient 가 invite decrypt fail → retry_receipt → caller 가
    //    재암호화 후 재전송 → server 가 새 nonce + 새 push → recipient
    //    측 CallKit 재 raise → 무한 loop. invite 는 best-effort, 자동
    //    재전송 안 함. caller 측 30s outgoing timeout safety net 으로
    //    무한 ring 방지. 다음 통화는 양측 ratchet 자동 align (recipient
    //    가 archive_reset 한 결과로 prekey-message 가 사용됨).
    final envelopeBase64 = base64Encode(sealedEnvelope);
    if (eventType != 'retry_receipt' && eventType != 'call_invite') {
      final hash = sha256.convert(utf8.encode(envelopeBase64)).toString();
      _putSentCache(hash, _SentEnvelopeEntry(
        recipientSnowchatId: recipientSnowchatId,
        eventType: eventType,
        innerPayload: innerPayload,
        sentAt: DateTime.now(),
      ));
    }

    final completer = Completer<SendResult>();
    _socketManager.sendSealedCallSignaling(
      recipientSnowchatId: recipientSnowchatId,
      envelope: envelopeBase64,
      signalType: signalType,
      callId: callIdMetadata,
      onAck: (response) {
        // [DIAG 2026-05-05] 사용자 보고 "5554 declinePending sent call_end
        // but iPhone never received". emit ack 결과를 항상 로그해서
        // delivery gap (relayed vs offline vs error vs no-ack-timeout) 을
        // 명확히 식별. eventType 포함 — call_end / rtc_offer 등 종류별 추적.
        if (response is Map) {
          if (response['error'] != null) {
            final code = response['error']['code']?.toString() ?? 'UNKNOWN';
            final msg = response['error']['message']?.toString() ?? '';
            diagLog('SealedSig',
                'ack ERROR eventType=$eventType code=$code message=$msg');
            completer.complete(SendResult.error(code: code, message: msg));
          } else if (response['offline'] == true) {
            diagLog('SealedSig',
                'ack OFFLINE eventType=$eventType pushed=${response['pushed']}');
            completer.complete(const SendResult.offline());
          } else if (response['relayed'] == true) {
            diagLog('SealedSig',
                'ack RELAYED eventType=$eventType pushed=${response['pushed']}');
            completer.complete(const SendResult.relayed());
          } else {
            diagLog('SealedSig',
                'ack UNKNOWN eventType=$eventType response=$response');
            completer.complete(const SendResult.relayed());
          }
        } else {
          diagLog('SealedSig',
              'ack NON-MAP eventType=$eventType response=$response');
          completer.complete(const SendResult.relayed());
        }
      },
    );
    // 2026-05-04 fix: 사용자 보고 "장시간 휴면 후 첫 시도, recipient
    // decline/accept 했는데 caller 영원히 ring" 의 root cause —
    // socket disconnect 시점에 emit 했으면 onAck 영원히 안 옴 → completer
    // hang → 호출자도 hang → call_end 도 못 보냄 → caller infinite ring.
    // 5s timeout 으로 정상 ack 없으면 error result 로 fail-loud → 호출자
    // (CallNotifier) 가 retry 또는 self-end 결정.
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        diagLog('SealedSig',
            'ack TIMEOUT eventType=$eventType — likely socket disconnected');
        return const SendResult.error(
          code: 'ACK_TIMEOUT',
          message: 'Socket emit ack timeout (5s)',
        );
      },
    );
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

    // 2026-05-05 Fix B: hoist envelopeBase64 + senderId out of the try so the
    // catch block can drive recovery without re-running unseal. Sealed
    // envelopes are one-shot — calling unseal a second time on the same bytes
    // throws "Sealed message rejected" (the previous catch did exactly that
    // and silently abandoned both archive_reset and retry_receipt, leaving
    // the caller stuck on infinite ringback). After this hoist, recovery
    // only depends on values that were already extracted before decrypt.
    final String? envelopeBase64 = data['envelope'] as String?;
    String? senderId;
    try {
      if (envelopeBase64 == null) return;

      // Dedup gate — same envelope arriving via socket + PushKit injectEnvelope.
      if (!_processedEnvelopes.add(envelopeBase64)) {
        debugPrint('[CallSignaling] envelope dedup — already processed');
        return;
      }
      // Cap memory: drop oldest when exceeding the bound.
      if (_processedEnvelopes.length > _processedEnvelopesCap) {
        _processedEnvelopes.remove(_processedEnvelopes.first);
      }

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

      senderId = unsealed.senderSnowchatId;
      final senderDeviceId = unsealed.senderDeviceId;

      // 2026-05-04 fix: self-sender envelope 차단. 사용자 보고 "통화 실패
      // 후 발신자에게 콜백" 의 client-side defense — 자기가 보낸 sealed
      // envelope 가 leak path (서버 routing bug, PushKit replay, multi-
      // device 동일 userId, /calls/pending nonce 노출 등) 로 돌아오면
      // _eventController.add 가 발화 → CallNotifier 가 incoming 처리 →
      // CallKit 발화 = "콜백" 증상. 여기서 abort 하면 모든 leak path 일괄
      // 차단 (server fix 와 별개의 second-line defense).
      final mySnow = _mySnowchatIdResolver?.call();
      if (mySnow != null && senderId == mySnow) {
        debugPrint('[CallSignaling] SELF-SENDER envelope rejected — '
            '발신자가 자기 자신 (leak path defense)');
        return;
      }

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
      // 2026-05-04 root cause fix: long-idle Signal ratchet desync 시 decrypt
      // 가 silent fail → 이전엔 envelope drop + 무대응 → caller 무한 ring
      // (e.g. recipient decline 의 call_end 못 받음). message_queue 의
      // session_reset auto-recovery 와 동일 패턴 적용 — decrypt 실패 시
      // sender 와 archiveAndResetSession trigger. 5min cooldown 내장이라
      // session_reset loop 위험 없음. 이번 envelope 은 lost 지만 다음
      // envelope (next call signaling) 부터 fresh session 으로 정상.
      try {
        // 2026-05-05 Fix B: senderId 와 envelopeBase64 는 이미 outer scope
        // 에서 추출됨 — 두 번째 unseal 호출 제거. 이전엔 여기서 재 unseal
        // 하다가 sealed envelope one-shot 특성 때문에 "Sealed message
        // rejected" 던져서 archive_reset 도 retry_receipt 도 둘 다 발화 못
        // 함 → caller 영원히 ring. unseal 자체가 fail 한 경우만 senderId
        // null → 그땐 sender 모르므로 어차피 reset 불가능 → early return.
        if (envelopeBase64 == null || senderId == null) {
          debugPrint('[CallSignaling] recovery skipped — '
              'envelope or senderId unavailable (unseal itself failed)');
          return;
        }

        // 1) archive_reset → fresh session bootstrap on our side.
        // P1 (2026-05-05): force=true to bypass the 5min reset cooldown.
        // Cooldown skip is silent (early return at signal_session_manager
        // L727-731) — without force, a second decrypt failure inside the
        // cooldown window quietly retains the broken local session while
        // we still send retry_receipt → sender rebuilds against fresh state
        // we do not own → retry envelopes also dead-letter → user sees
        // "first call fails, second succeeds" UX. Decrypt failure here is
        // hard evidence the session is broken; deferring reset only extends
        // the outage. archive (vs delete) keeps in-flight envelopes for
        // any pending message_queue retry.
        debugPrint('[CallSignaling] dispatch error → archiveAndResetSession '
            'with $senderId (force=true, decrypt-fail trigger)');
        await _sessionManager.archiveAndResetSession(senderId, force: true);

        // 2) Signal Retry Receipt — 원본 envelope hash 를 sender 한테
        // 알려서 sender 가 cache 에서 plaintext 찾아 fresh session 으로
        // 재암호화 + 재전송. 첫 통화 시도 자체가 살아남게.
        // archive_reset 후 sendSealedSignaling 첫 호출은 prekey-message
        // (X3DH bootstrap) 형식 → sender 가 자동으로 fresh session 생성.
        final envelopeHash = sha256.convert(utf8.encode(envelopeBase64)).toString();
        debugPrint('[CallSignaling] sending retry_receipt for envelope hash '
            '${envelopeHash.substring(0, 12)}... to $senderId');
        unawaited(sendSealedSignaling(
          recipientSnowchatId: senderId,
          eventType: 'retry_receipt',
          innerPayload: {'envelopeHash': envelopeHash},
        ));
      } catch (recoveryError, recoveryStack) {
        // P2 (2026-05-05): surface full error + stack. Previous
        // `runtimeType`-only print masked the failure cause behind generic
        // names like "StateError" / "SignalProtocolException", forcing us
        // to add ad-hoc print statements every time long-idle decrypt
        // recovery silently broke. Logging here costs nothing — this catch
        // only fires when we are already in a broken-session error path.
        debugPrint('[CallSignaling] session reset / retry_receipt failed: '
            '$recoveryError');
        debugPrint('[CallSignaling] recovery stack:\n$recoveryStack');
      }
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

  /// Clear the envelope dedup cache. Called from CallService._cleanup() at
  /// call end (Phase 8.2 §28.5(a)). The Set has a 64-entry size cap that
  /// auto-trims, but never auto-clears — multi-call sessions can poison the
  /// next call if not reset between calls.
  void clearProcessedEnvelopes() {
    _processedEnvelopes.clear();
  }

  /// 2026-05-04 — envelope decrypt 만 수행하고 stream 으로 emit 안 함.
  /// declinePendingVoipCall 등 UI side-effect 없이 sender info / inner
  /// event 만 추출하고 싶을 때 사용. _onIncoming 의 dedup / self-sender
  /// 가드 / catch 의 retry_receipt trigger 도 모두 발화 X.
  ///
  /// 반환: inner CallSignalingEvent (decrypted) — 또는 decrypt fail 시 null.
  Future<CallSignalingEvent?> parseEnvelope(String envelopeBase64) async {
    try {
      final ownPriv = _sessionManager.signal.identityPrivateKey;
      final ownPub = _sessionManager.signal.identityPublicKey;
      if (ownPriv == null || ownPub == null) return null;
      final unsealed = _sealedSenderService.unseal(
        myIdentityPrivateKey: ownPriv,
        myIdentityPublicKey: ownPub,
        sealedEnvelope: Uint8List.fromList(base64Decode(envelopeBase64)),
      );
      final senderId = unsealed.senderSnowchatId;
      // self-sender check
      final mySnow = _mySnowchatIdResolver?.call();
      if (mySnow != null && senderId == mySnow) return null;
      _sessionManager.learnDeviceIdFromIncoming(senderId, unsealed.senderDeviceId);
      // messageType 결정 (raw envelope 안에 messageType 정보 없음 — default 1)
      final plaintextBytes = await _sessionManager.decrypt(
        senderId,
        unsealed.senderDeviceId,
        unsealed.drCiphertext,
        1,
      );
      final inner = jsonDecode(utf8.decode(plaintextBytes)) as Map<String, dynamic>;
      return CallSignalingEvent(
        type: inner['type'] as String? ?? '',
        senderSnowchatId: senderId,
        data: (inner['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        timestamp: inner['timestamp'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('[CallSignaling] parseEnvelope decrypt failed: ${e.runtimeType}');
      return null;
    }
  }

  /// 2026-05-04 Signal Retry Receipt — 외부 dispatcher 가 retry_receipt
  /// 이벤트를 받으면 호출. envelope hash 로 cache 조회 → fresh session
  /// 으로 재암호화 + 재전송.
  Future<void> handleRetryReceipt(String envelopeHash, String fromSnowId) async {
    final entry = _sentCache[envelopeHash];
    if (entry == null) {
      debugPrint('[CallSignaling] retry_receipt: unknown envelope hash '
          '(cache miss or TTL expired) — original send is permanently lost');
      return;
    }
    // peer 와 self-sender check 일치성 검증 — retry_receipt 가 다른 peer
    // 한테 와서 cache 의 recipient 와 mismatch 면 abort (보안 가드).
    if (entry.recipientSnowchatId != fromSnowId) {
      debugPrint('[CallSignaling] retry_receipt: peer mismatch '
          '(cache.recipient=${entry.recipientSnowchatId}, from=$fromSnowId) — abort');
      return;
    }
    debugPrint('[CallSignaling] retry_receipt: re-encrypting '
        'eventType=${entry.eventType} for $fromSnowId (Signal-style retry)');
    // archive_reset 으로 fresh session 강제 (recipient 가 이미 reset 했으니
    // 양측 fresh start). archive_reset 의 5min cooldown 안에서 호출되면
    // 즉시 ensureSession(prekey fetch) 만 fire — 어쨌든 fresh session.
    try {
      await _sessionManager.archiveAndResetSession(entry.recipientSnowchatId);
    } catch (e) {
      debugPrint('[CallSignaling] retry_receipt: session reset failed '
          '${e.runtimeType} — proceeding with current session');
    }
    // 재전송. 같은 plaintext 로. 새 envelope 은 cache 에 다시 들어감 (재
    // retry 가능 — 단 retry storm 은 5min cooldown + cache TTL 로 자연 차단).
    try {
      final result = await sendSealedSignaling(
        recipientSnowchatId: entry.recipientSnowchatId,
        eventType: entry.eventType,
        innerPayload: entry.innerPayload,
      );
      debugPrint('[CallSignaling] retry_receipt: resend result=$result');
    } catch (e) {
      debugPrint('[CallSignaling] retry_receipt: resend failed ${e.runtimeType}');
    }
    // cache 에서 원본 entry 제거 — 같은 envelope 의 또 다른 retry_receipt
    // 는 cache 에 새 entry 생긴 걸 사용.
    _sentCache.remove(envelopeHash);
  }

  void _putSentCache(String hash, _SentEnvelopeEntry entry) {
    // TTL 만료 entries 청소 + cap 적용.
    final now = DateTime.now();
    _sentCache.removeWhere((_, e) => now.difference(e.sentAt) > _sentCacheTtl);
    if (_sentCache.length >= _sentCacheCap) {
      // 가장 오래된 entry 제거
      String? oldestKey;
      DateTime? oldestAt;
      for (final entry in _sentCache.entries) {
        if (oldestAt == null || entry.value.sentAt.isBefore(oldestAt)) {
          oldestAt = entry.value.sentAt;
          oldestKey = entry.key;
        }
      }
      if (oldestKey != null) _sentCache.remove(oldestKey);
    }
    _sentCache[hash] = entry;
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _eventController.close();
  }
}

/// 2026-05-04 — Signal Retry Receipt cache entry. Sender 가 보낸 sealed
/// envelope 의 plaintext 입력 보존. recipient decrypt fail 시 hash 기반
/// lookup → fresh session 으로 재암호화 + 재전송.
class _SentEnvelopeEntry {
  const _SentEnvelopeEntry({
    required this.recipientSnowchatId,
    required this.eventType,
    required this.innerPayload,
    required this.sentAt,
  });

  final String recipientSnowchatId;
  final String eventType;
  final Map<String, dynamic> innerPayload;
  final DateTime sentAt;
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
