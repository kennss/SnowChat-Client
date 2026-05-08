/// @file        call_service.dart
/// @description WebRTC P2P PeerConnection management + CallSignaling integration (Phase 8.2 §3.3)
///              DTLS-SRTP voice call + Sealed Sender signaling + Always Relay option.
///              Zero-Trace §23: explicit wipe of all fields on termination.
///              Phase J (§26): caller-side ringback tone + busy tone playback management.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-05-06 (Fix B revised — _handleRemoteEnd no longer silently
///              returns when _callId == null. cold-start path: callee main
///              isolate decrypts call_end successfully (after long-idle ratchet
///              desync was self-healed by retry_receipt) but invite envelope
///              was already permanently lost (call_invite is excluded from
///              _sentCache to break the +233 retry storm), so _callId never
///              got populated by handleIncomingInvite. Instead of silent return
///              we populate _callId/_remoteSnowchatId from the event, mark the
///              callId in _recentlyEndedCallIds (60s anti-replay set consulted
///              by handleIncomingInvite + every callId-mismatch guard), and
///              run _cleanup with a new endedReason='cold_fallback' that
///              CallNotifier interprets to insert the missed-call message
///              bypassing the prevStatus==incoming gate. _emit accepts
///              override params so the terminal CallServiceEvent carries the
///              correct callId/remoteSnowchatId even though _cleanup wipes the
///              fields beforehand. Solves user-reported "Galaxy keeps ringing
///              after iPhone cancels + missed-call message 0건" matrix that
///              only reproduces on lock / swipe-dismiss). Earlier 2026-05-03 (v213: _startRingtone 에 audio_session 명시 setup
///              (Playback category + setActive(true)). v212 에서 누락된
///              부분 — audioplayers 가 default category (SoloAmbient) 로
///              silent 재생되던 회귀 (CLAUDE.md §2.7). 사용자 매트릭스
///              "v212 빌드 후 화면 OK 벨 0" log 분석 결과 ringing 페이즈
///              audio assertion 0건 확인. Earlier v212: re-add iOS FG-only
///              in-app ringtone fallback.
///              v207 strip-all-ringtone was correct for BG/Lock (cold-launch
///              audio priority race) but iOS FG 의 PushKit CallKit banner
///              는 system ringtone 을 안정적으로 안 들려줌 (사용자 매트릭스:
///              "FG 수신 화면 OK but 벨 안 울림"). lifecycle.resumed +
///              Platform.isIOS gate 로 BG/Lock race 회피. Earlier v207:
///              handleIncomingInvite removes our-side iOS
///              ringtone (_configureAudioSessionForRingtone + _startRingtone).
///              Phase E-2 v3.1 PushKit/CallKit owns the system ringtone now —
///              our Dart-side path was 임시 코드 and triggered OSStatus
///              560557684 (insufficient priority) when audio_session.setActive
///              fired before CallKit accept granted ownership in BG cold-launch
///              window. Throw cascaded to cleanup(ended) and the call died
///              before user could see CallKit UI (매트릭스 "BG 3초 후 안 뜸").
///              v206 server iOS-always-push made this race observable. v205:
///              pre-warm RTCAudioSession singleton before
///              CallKit fires didActivate by acquiring the local stream first
///              on iOS outbound. v204 wired CallKit correctly, but the fake
///              AVAudioSessionInterruptionNotification posted by
///              SwiftFlutterCallkitIncomingPlugin's didActivate handler had
///              no observer because flutter_webrtc lazy-initializes the
///              singleton inside getUserMedia → AURemoteIO never constructed
///              and both directions were silent. v205 reorders so getUserMedia
///              runs BEFORE startOutgoing. Earlier v204: startCall on iOS
///              goes through
///              CallKitManager.startOutgoing → CXStartCallAction →
///              provider:didActivate:audioSession:, mirroring the acceptCall
///              completer-await pattern. Pre-v204 outbound bypassed CallKit and
///              called _configureAudioSession+setActive(true) directly. iOS
///              granted the AVAudioSession technically, but without
///              ClientPriority=PhoneCall the AURemoteIO recording/output
///              routing failed silently — user heard nothing in either
///              direction even though WebRTC reported Connected. Caller side
///              now blocks on the same Completer<void> until CallKit fires
///              didActivate (or 2s timeout → v200 swallow fallback).
///              v203: handleIncomingInvite now uses
///              _configureAudioSessionForRingtone (Playback + defaultMode +
///              speaker) instead of _configureAudioSession (PlayAndRecord +
///              VoiceChat). VoiceChat routes ringtone to earpiece + applies
///              voice processing → user perceives ringtone as silent because
///              phone is on table/in pocket (matrix test 2 회귀 발견).
///              acceptCall continues with playAndRecord+voiceChat for WebRTC.
///              Trade-off: Playback honors iOS Silent Switch (intended OS
///              behavior). Earlier v202: _generateCallId switched from raw
///              32-hex to RFC 4122 v4 UUID(8-4-4-4-12) so caller-side callId
///              can flow through CallKit without the v201 UUID-format guard
///              rejecting it. Pairs with fork commit 81e5dfd (force-unwrap →
///              guard let) for defense in depth. Earlier v200:
///              _configureAudioSession swallows the iOS
///              "Insufficient priority" (-12983) thrown by setActive(true)
///              during the CallKit accept handoff window. Ringtone session
///              held by callservicesd hadn't fully released → our setActive
///              lost the priority contest → exception bubbled up to
///              acceptPendingVoipCallWithEnvelopes' catch → endCall(nonce) →
///              CallKit dismissed → user perceived the chronic
///              "수신 스와이프하고 꺼짐" pattern (~50% intermittent).
///              CallKit activates the session for us via
///              provider:didActivateAudioSession: once the Ringtone tears
///              down, so swallowing here is safe. Earlier v199:
///              _handleRemoteOffer buffers rtc_offer when _callId is null;
///              v197: sync broadcast streams; Phase E-2 §26.5/§28.3:
///              configure audio session before iOS receiver ringtone;
///              §28.5(a): clear signaling envelope dedup on cleanup.)
///
/// @functions
///  - CallService.startCall(): start outgoing call (call_invite + rtc_offer)
///  - CallService.handleIncomingInvite(): prepare to accept incoming invite
///  - CallService.acceptCall(): accept (call_answer) — rtc_answer is automatic after offer received
///  - CallService.endCall(): terminate + cleanup
///  - CallService.toggleMute() / toggleSpeaker()
///  - CallService.handleRemote*(): dispatch CallSignaling incoming events
///  - CallService._cleanup(): memory wipe (§23.4.5) + assert verification
///  - CallService._startRingback() / _stopRingback() / _playBusyTone() (Phase J §26)
///  - CallService._startRingtone() / _stopRingtone() (v212, iOS FG fallback)

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audio_session/audio_session.dart';
// audioplayers conflicts with audio_session on the `AVAudioSessionCategory` name,
// so import only the needed symbols via `show` (Phase J §26).
import 'package:audioplayers/audioplayers.dart'
    show AudioPlayer, AssetSource, ReleaseMode;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_signaling.dart';
import 'call_verification.dart';
import 'callkit_manager.dart';
import 'turn_credential_manager.dart';

/// CallService internal state transitions.
enum CallServiceStatus { idle, outgoing, incoming, connecting, active, ended }

/// Change events published from CallService → CallNotifier.
class CallServiceEvent {
  const CallServiceEvent({
    required this.status,
    this.callId,
    this.remoteSnowchatId,
    this.remoteDisplayName,
    this.endedReason,
    this.error,
  });

  final CallServiceStatus status;
  final String? callId;
  final String? remoteSnowchatId;

  /// The remote peer's displayName (nickname). Caller side sets it externally via
  /// startCall(remoteDisplayName). Callee side extracts it from senderDisplayName in the call_invite payload.
  final String? remoteDisplayName;

  /// End reason on `ended`: `ended` | `declined` | `busy` | `timeout` | `failed` | `permission_denied` | `offline`
  final String? endedReason;
  final String? error;
}

/// SAS (Short Authentication String) computation-complete event.
/// CallNotifier subscribes and injects into CallState.sas → displayed in ActiveCallScreen.
class CallSasEvent {
  const CallSasEvent({required this.sas});
  final String sas;
}

/// WebRTC P2P voice call manager.
///
/// Owned by CallNotifier; state transitions happen only in CallNotifier.
/// CallService wraps the WebRTC API and CallSignaling and only emits state events.
class CallService {
  CallService({
    required CallSignaling signaling,
    required TurnCredentialManager turnManager,
    CallKitManager? callKit,
  })  : _signaling = signaling,
        _turnManager = turnManager,
        _callKit = callKit {
    _signalingSub = _signaling.onSignalingEvent.listen(_dispatchRemoteEvent);
    // v2.5 (2026-05-03): _subscribeToAudioSessionEvents removed. The previous
    // design registered a setMethodCallHandler on `snowchat/voip_native`,
    // colliding with VoipNativeBridge's handler — whichever provider
    // initialized last won, silently dropping the other side. Audio session
    // events now arrive via `wireNativeBridge`, called from
    // callServiceProvider with the bridge's broadcast streams.
  }

  final CallSignaling _signaling;
  final TurnCredentialManager _turnManager;
  // v204 (2026-05-03): outbound CallKit registration. Null on Android (uses
  // ConnectionService Self-Managed via the same plugin internally) and in
  // tests. When non-null, startCall on iOS triggers CXStartCallAction so
  // CallKit owns the audio session activation — same path as acceptCall.
  final CallKitManager? _callKit;

  // Phase 8.2 v2.2 — Audio session CallKit delegation (iOS only).
  //
  // Apple WWDC 2018 pattern: we never call AVAudioSession.setActive(true)
  // ourselves. CallKit grants ClientPriority=PhoneCall, calls setActive(true)
  // internally, then fires provider:didActivate:. Only after that callback do
  // we start the WebRTC peer connection.
  //
  // Two arrival paths to keep the Completer robust:
  //   primary — CallKitManager broadcasts audioSessionActivated after the
  //             plugin emits ACTION_CALL_TOGGLE_AUDIO_SESSION. CallNotifier
  //             forwards via notifyAudioSessionActivatedFromCallKit.
  //   backup  — AppDelegate.didActivateAudioSession → VoipNativeBridge →
  //             MethodChannel 'snowchat/voip_native' (audioSessionActivated).
  // Idempotent via Completer.isCompleted; whichever lands first wins.
  Completer<void>? _audioSessionActivatedCompleter;
  // v2.5: replaces _audioSessionListenerRegistered. Subscriptions to the
  // VoipNativeBridge broadcast streams are wired via wireNativeBridge from
  // callServiceProvider. Null when not yet wired or after dispose.
  StreamSubscription<void>? _bridgeAudioActivatedSub;
  StreamSubscription<void>? _bridgeAudioDeactivatedSub;
  StreamSubscription<void>? _bridgeSystemResetSub;

  // Monitoring metrics (24h rolling counter, daily report).
  // 모두 < 1% of total call accepts 가 합격 기준 (§5 acceptance).
  int _diagAudioPriorityRaceCount = 0;        // v200 -12983 swallow trigger
  int _diagAudioSessionTimeoutCount = 0;      // 2s Completer timeout
  int _diagFailOpenAcceptCount = 0;           // Completer null (race A 잔존 진단)

  late final StreamSubscription<CallSignalingEvent> _signalingSub;
  // sync: true — see CallSignaling._eventController. Mirroring on this side so
  // CallNotifier._onServiceEvent runs synchronously inside _emit. Otherwise
  // state.status update lags one microtask behind _callService._status, and any
  // downstream code reading state.status after _emit can race.
  final _eventController = StreamController<CallServiceEvent>.broadcast(sync: true);
  final _sasController = StreamController<CallSasEvent>.broadcast(sync: true);

  Stream<CallServiceEvent> get events => _eventController.stream;

  /// Emitted when Safety Number computation finishes — right after both rtc_offer/answer SDPs are obtained.
  Stream<CallSasEvent> get sasEvents => _sasController.stream;

  /// Fingerprint parsed from local SDP (set after setLocalDescription).
  String? _localFingerprint;

  // Active call state — all fields MUST be nulled in _cleanup() (§23.4.5)
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  CallServiceStatus _status = CallServiceStatus.idle;
  String? _callId;
  String? _remoteSnowchatId;
  String? _remoteDisplayName;
  bool _alwaysRelay = false;
  bool _muted = false;
  bool _speakerOn = false;
  // [Trickle ICE off] Created in _createPeerConnection and awaited by _waitForIceGather().
  // Nulled in _cleanup(). Concurrent calls are blocked by policy (§9.3), so no race.
  Completer<void>? _iceGatheringCompleter;

  // [ICE restart retry — 2026-04-21]
  // International call testing observed disconnects from NAT rebinding (A7 ~3 min) /
  // TURN allocation expiry (S23 ~20 min). With no retry on a single restart failure, recovery failed.
  // Up to 3 attempts with 3/6/9-second backoff. Counter resets when Connected resumes.
  int _iceRestartAttempts = 0;
  Timer? _disconnectedTimer;

  /// 2026-05-04 fix: caller outgoing answer timeout (RFC 3261 Timer B = 32s).
  /// startCall 시 30s 타이머. 진짜 recipient answer (call_answer / rtc_answer)
  /// 도착 시 cancel. 만료 시 자동 _cleanup(reason='timeout') → caller 무한
  /// ring 차단.
  ///
  /// NOTE: 처음 v229 fix 는 startCall 의 offer 송신 직후 (line ~437) cancel
  /// 했는데 이건 잘못 — 그 시점은 recipient 답 받기 전 caller 가 자기
  /// SDP offer 보낸 직후 (optimistic connecting 전이) 라 timer 가 영영
  /// 안 fire. 사용자 보고 (Galaxy → 5554 decline 후 45s+ ring) 의 root
  /// cause. 진짜 answer 도착 시점 (`_handleRemoteAnswer`) 으로 옮김.
  Timer? _outgoingTimer;
  bool _answerReceived = false;

  // Fix B revised (2026-05-06) — cold-start anti-replay set.
  //
  // When the cold-fallback path of _handleRemoteEnd runs, we record the
  // event's inner callId here. handleIncomingInvite + every other
  // _handleRemote* callId-mismatch path consults this set up front: a hit
  // means the call was already torn down via fallback, so any late-arriving
  // invite/offer/answer/ICE for the same callId must be silently rejected
  // (not turned into a fresh CallKit raise / late state mutation).
  //
  // Necessary because the retry_receipt mechanism (call_signaling.dart catch
  // path) can, in principle, deliver an invite for the same call AFTER call_end
  // has already been processed if we ever loosen the call_invite cache
  // exclusion (defense-in-depth — Fix A is currently dropped, but the guard
  // costs nothing and protects against future architectural drift).
  //
  // 60s TTL — matches Redis voip:active_push:<userId> TTL on the server.
  // Beyond 60s the server has already let the active_push key expire, so any
  // re-fired invite is treated as a brand-new call (different nonce + callId).
  // 32 cap — call_id is a 36-char UUID; 32 entries ≈ 1.2KB. Set is keyed by
  // callId string. Cleared on dispose.
  final Set<String> _recentlyEndedCallIds = <String>{};
  static const Duration _recentlyEndedTtl = Duration(seconds: 60);
  Timer? _recentlyEndedSweepTimer;
  // Same-key TTL tracking — paired with _recentlyEndedCallIds; entry is
  // removed when the per-key Timer fires. We don't bother with a heap-based
  // structure because cap is 32; a per-entry Timer is fine.
  final Map<String, Timer> _recentlyEndedExpirers = <String, Timer>{};

  void _markRecentlyEnded(String callId) {
    if (callId.isEmpty) return;
    _recentlyEndedCallIds.add(callId);
    _recentlyEndedExpirers[callId]?.cancel();
    _recentlyEndedExpirers[callId] = Timer(_recentlyEndedTtl, () {
      _recentlyEndedCallIds.remove(callId);
      _recentlyEndedExpirers.remove(callId);
    });
  }

  bool _isRecentlyEnded(String? callId) {
    if (callId == null || callId.isEmpty) return false;
    return _recentlyEndedCallIds.contains(callId);
  }

  // [Pre-accept offer buffer — 2026-04-19]
  // The caller's startCall sends an rtc_offer right after the invite. On the receiver side _pc
  // isn't created until the user accepts (acceptCall → _createPeerConnection), so silently
  // dropping an offer that arrives in between means setRemoteDescription is never called and
  // ICE never starts. Buffer the offer and process it at the end of acceptCall.
  CallSignalingEvent? _pendingOffer;

  // Phase J (Phase 8.2 §26): caller-side ringback / busy tone playback management.
  // Ringback is caller side only — callee uses the CallKit system ring on Android.
  // Busy tone plays for 2s on end reason 'busy', then auto-dismisses.
  AudioPlayer? _ringbackPlayer;
  AudioPlayer? _busyPlayer;
  // v212 (2026-05-03): iOS FG-only in-app ringtone fallback. Constructed
  // only on handleIncomingInvite when lifecycle.resumed && Platform.isIOS;
  // disposed on acceptCall, ICE Connected, and _cleanup. BG/Lock leaves
  // ringtone responsibility to PushKit/CallKit (v207 unchanged).
  AudioPlayer? _ringtonePlayer;

  CallServiceStatus get status => _status;
  String? get callId => _callId;
  String? get remoteSnowchatId => _remoteSnowchatId;
  String? get remoteDisplayName => _remoteDisplayName;
  bool get isMuted => _muted;
  bool get isSpeakerOn => _speakerOn;

  // ---------------------------------------------------------------------------
  // Caller side
  // ---------------------------------------------------------------------------

  /// Start outgoing call. Sends `call_invite` then `rtc_offer` in sequence.
  ///
  /// [alwaysRelay]: user option. ORed with the recipient's preference for the final decision (§8.3).
  /// [remoteDisplayName]: peer name shown in the iOS CallKit window (§7.1
  ///   includesCallsInRecents=false → not exposed to system Phone app). Caller
  ///   already knows the callee, so passing the name is privacy-safe.
  Future<void> startCall({
    required String recipientSnowchatId,
    required bool alwaysRelay,
    String? senderDisplayName,
    String? remoteDisplayName,
  }) async {
    try {
      await _startCallImpl(
        recipientSnowchatId: recipientSnowchatId,
        alwaysRelay: alwaysRelay,
        senderDisplayName: senderDisplayName,
        remoteDisplayName: remoteDisplayName,
      );
    } on _CallCancelledException catch (e) {
      // 2026-05-04 fix: state race audit. _cleanup 가 setup 중간에 발화한
      // 케이스 — orphan resources (mic stream / PC) 는 이미 정리됨.
      // 호출자에게 silent 처리.
      debugPrint('[CallService] startCall cancelled mid-setup: ${e.reason}');
    }
  }

  Future<void> _startCallImpl({
    required String recipientSnowchatId,
    required bool alwaysRelay,
    String? senderDisplayName,
    String? remoteDisplayName,
  }) async {
    if (_status != CallServiceStatus.idle) {
      throw StateError('Call already in progress');
    }

    _callId = _generateCallId();
    _remoteSnowchatId = recipientSnowchatId;
    _remoteDisplayName = remoteDisplayName;
    _alwaysRelay = alwaysRelay;
    _emit(CallServiceStatus.outgoing);

    // 2026-05-04 — Pre-warm Signal Double Ratchet for long-idle peers.
    // 사용자 보고 (양 device 10min+ idle 후 첫 통화): recipient 의 stale
    // ratchet 으로 invite envelope decrypt fail → CallKit 미표시 +
    // caller 무한 ring (이전엔 30s timeout fix). 정공법: 1h+ idle 면
    // sender 측에서 archive_reset force → 다음 invite 가 prekey-message
    // (X3DH bootstrap) 형식으로 송신 → recipient 가 stale session 무시하고
    // fresh bootstrap → 첫 시도 부터 정상 decrypt.
    //
    // Cost: prekey bundle fetch + X3DH ~ 1-2s. 1h 미만 활동 시엔 영향 0
    // (lastEncryptTimestamp 가 최근). cooldown 5min 안엔 force 도 cooldown
    // skip 되지만 startCall 의 1h threshold 가 자동 제어.
    final lastSent =
        _signaling.sessionManager.lastEncryptTimestamp(recipientSnowchatId);
    final idleAge = lastSent == null
        ? const Duration(days: 365)
        : DateTime.now().difference(lastSent);
    if (idleAge > const Duration(hours: 1)) {
      debugPrint('[CallService] startCall — peer idle ${idleAge.inMinutes}min '
          '> 1h → pre-warm via archive_reset (force) for fresh X3DH');
      try {
        await _signaling.sessionManager
            .archiveAndResetSession(recipientSnowchatId, force: true);
      } catch (e) {
        debugPrint('[CallService] startCall pre-warm failed (non-fatal): '
            '${e.runtimeType}');
      }
    }

    // 2026-05-04 fix: outgoing answer timeout (RFC 3261 Timer B = 32s).
    // 사용자 보고 — recipient 가 decline/accept 했어도 sealed_call_signaling
    // 가 server 에 도달 못 하는 race (long-idle 후 첫 시도, socket
    // disconnect, encryption fail 등) 에서 caller 영원히 ring. Safety net
    // 으로 30s answer 안 오면 자동 ended. _emit(connecting/active) 시점에
    // timer cancel — 정상 path 영향 0.
    _scheduleOutgoingTimeout();

    // v205 (2026-05-03): pre-warm WebRTC + RTCAudioSession singleton BEFORE
    // CallKit fires didActivate. Acquiring the local stream first triggers
    // WebRTC.initialize → RTCPeerConnectionFactory → audioDeviceModule → which
    // creates [RTCAudioSession sharedInstance] and registers it as observer
    // for AVAudioSessionInterruptionNotification. After that, CallKit's
    // provider:didActivate posts the fake interruption notification (via
    // sendDefaultAudioInterruptionNotificationToStartAudioResource at
    // SwiftFlutterCallkitIncomingPlugin:952) and the singleton is in place
    // to react → AURemoteIO constructs → mic capture + output routing both
    // come up. Without this pre-warm the v204 outbound path consistently
    // ended with zero AURemoteIO traces in the system log even though
    // CallKit's didActivate fired and ClientPriority=PhoneCall was granted —
    // because the singleton wasn't created until _acquireLocalStream ran
    // ~100ms LATER, by which point the notification had already evaporated
    // with no observer.
    //
    // v204 (2026-05-03): outbound audio session via CallKit on iOS.
    // Pre-v204 path called _configureAudioSession() then setActive(true)
    // directly. AVAudioSession activated technically (no error), but iOS
    // didn't grant ClientPriority=PhoneCall to the session because CallKit
    // wasn't driving it. AURemoteIO ran in a degraded mode where mic capture
    // and output routing silently failed — caller and callee both heard zero
    // audio even though WebRTC reported Connected. Symptom matched the
    // user-reported "iPhone→Galaxy 화면 동기는 되는데 양방향 무음" pattern.
    //
    // Fix: CallKit.startOutgoing → CXStartCallAction →
    // provider:didActivate:audioSession: → ClientPriority=PhoneCall →
    // AURemoteIO gets full mic/output routing. Same Completer<void> pathway
    // as acceptCall (L398). On Android, _configureAudioSession is sufficient
    // (ConnectionService runs in Self-Managed mode and the plugin handles
    // the audio focus internally).
    if (Platform.isIOS && _callKit != null) {
      // v205: acquire mic FIRST so WebRTC's RTCAudioSession singleton exists
      // before CallKit's didActivate posts the fake interruption notification.
      // ensureAudioSession (called transitively from getUserMedia → getUserAudio)
      // sets the AVAudioSession category to playAndRecord but does NOT call
      // setActive — so the session is "ready, idle" until CallKit takes over.
      // Mic LED blips on briefly before the CallKit window appears, but the
      // user is the one initiating the call so the UX trade is acceptable.
      await _acquireLocalStream();
      prepareAudioSessionAwaiter();
      try {
        await _callKit.startOutgoing(
          callId: _callId!,
          calleeName: remoteDisplayName ?? 'SnowChat Call',
          handle: recipientSnowchatId,
        );
      } catch (e) {
        // CallKit start failure shouldn't block the call — fall back to
        // direct audio session config so the user still has a chance.
        debugPrint('[CallService] startOutgoing failed (${e.runtimeType}: $e) '
            '— falling back to manual audio session');
        await _configureAudioSession();
      }
      final completer = _audioSessionActivatedCompleter;
      if (completer != null && !completer.isCompleted) {
        try {
          await completer.future.timeout(const Duration(seconds: 2));
          debugPrint('[CallService] startCall audio session activated by CallKit');
        } on TimeoutException {
          _diagAudioSessionTimeoutCount++;
          debugPrint('[CallService] startCall audio session TIMEOUT — '
              'proceeding (v200 swallow protected)');
        }
      }
    } else {
      await _configureAudioSession();
      await _acquireLocalStream();
    }

    final iceServers = await _turnManager.getIceServers();
    await _createPeerConnection(iceServers: iceServers, relay: alwaysRelay);

    // Send call_invite (meta only — actual SDP follows as rtc_offer).
    // The receiver UI (IncomingCallScreen / CallKit toast) uses senderDisplayName as the
    // peer display name. Falls back to snow ID if absent.
    await _signaling.sendSealedSignaling(
      recipientSnowchatId: recipientSnowchatId,
      eventType: 'call_invite',
      innerPayload: {
        'callId': _callId,
        'alwaysRelay': alwaysRelay,
        'mediaType': 'audio',
        if (senderDisplayName != null && senderDisplayName.isNotEmpty)
          'senderDisplayName': senderDisplayName,
      },
    );

    // Create + send SDP offer
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _pc!.setLocalDescription(offer);

    // Phase G: Extract local DTLS fingerprint for SAS computation.
    // Envelope (Sealed Sender + DR) already authenticates SDP content end-to-end;
    // SAS provides a second user-audible layer of MITM defense.
    // The a=fingerprint line is identical even after ICE candidates are inlined, so it is
    // safe to extract from the SDP right after createOffer.
    _localFingerprint = _safeParseFingerprint(offer.sdp);

    // [Trickle ICE off] Wait until gather completes, then extract the candidate-inlined
    // SDP from _pc.localDescription.
    final finalSdp = await _waitForIceGatherAndGetLocalSdp(fallback: offer.sdp);

    await _signaling.sendSealedSignaling(
      recipientSnowchatId: recipientSnowchatId,
      eventType: 'rtc_offer',
      innerPayload: {
        'callId': _callId,
        'sdp': finalSdp,
      },
    );

    // _emit(connecting) 은 caller 측 optimistic transition (offer 보냈으니
    // 곧 answer 올 것이다). 실제 recipient answer 는 _handleRemoteAnswer
    // 에서 처리 — outgoing timeout cancel 도 거기로.
    _emit(CallServiceStatus.connecting);

    // Phase J (§26): ringback — caller hears the "ring" tone until callee answers / ICE completes.
    // For the callee, CallKit owns the system ring → no overlap.
    unawaited(_startRingback());
  }

  /// [Trickle ICE off] Wait for ICE gathering complete (up to 5s), then return the SDP from
  /// _pc.localDescription. On timeout, use [fallback] (the original SDP without inlined candidates) —
  /// relay-only calls gather ICE quickly so connectivity impact is minimal.
  Future<String?> _waitForIceGatherAndGetLocalSdp({String? fallback}) async {
    if (_pc == null) return fallback;
    if (_pc!.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return (await _pc!.getLocalDescription())?.sdp ?? fallback;
    }
    final c = _iceGatheringCompleter;
    if (c != null && !c.isCompleted) {
      try {
        await c.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        debugPrint('[CallService] ICE gather timeout — sending current SDP');
      }
    }
    return (await _pc?.getLocalDescription())?.sdp ?? fallback;
  }

  // ---------------------------------------------------------------------------
  // Callee side
  // ---------------------------------------------------------------------------

  /// On remote invite receipt, only transitions internal state outgoing→incoming.
  /// CallNotifier calls this method to display the incoming UI.
  void handleIncomingInvite({
    required String callId,
    required String callerSnowchatId,
    required bool remoteWantsRelay,
    String? callerDisplayName,
  }) {
    // Fix B revised (2026-05-06) — anti-replay guard.
    //
    // If we recently fell back to ended for this same callId, a late-arriving
    // invite (caller retry after we already gave up + cleaned up) MUST NOT
    // raise a fresh CallKit. Send call_end back so caller stops ringing too,
    // and abort. 60s window matches server-side voip:active_push TTL.
    if (_isRecentlyEnded(callId)) {
      debugPrint('[CallService] handleIncomingInvite REJECTED — '
          'callId=$callId in _recentlyEndedCallIds (replay after fallback). '
          'Replying call_end to caller.');
      unawaited(_signaling.sendSealedSignaling(
        recipientSnowchatId: callerSnowchatId,
        eventType: 'call_end',
        innerPayload: {'callId': callId, 'reason': 'ended'},
      ));
      return;
    }

    // Phase 8.2 §25 — Dual-delivery dedup (PushKit + socket).
    // The same call_invite envelope arrives twice for iOS recipients (push
    // path + socket relay). The second arrival must NOT fall through to the
    // `_status != idle` busy branch — that would teardown the in-flight call.
    if (_status == CallServiceStatus.incoming && _callId == callId) {
      debugPrint('[DIAG:CallService] handleIncomingInvite dedup callId=$callId');
      return;
    }
    if (_status != CallServiceStatus.idle) {
      // Busy — decline immediately (§9.3)
      unawaited(_signaling.sendSealedSignaling(
        recipientSnowchatId: callerSnowchatId,
        eventType: 'call_end',
        innerPayload: {'callId': callId, 'reason': 'busy'},
      ));
      return;
    }
    _callId = callId;
    _remoteSnowchatId = callerSnowchatId;
    _remoteDisplayName = callerDisplayName;
    _alwaysRelay = remoteWantsRelay;
    _emit(CallServiceStatus.incoming);
    // v207 (2026-05-03) — receiver-side ringtone deleted on both platforms.
    // CallKit (iOS, via PushKit Phase E-2 v3.1) and ConnectionService Self-
    // Managed (Android) own the system ringtone now. Our Dart-side ringtone
    // was Phase E-2 이전 임시 코드인데, v206 의 iOS-always-push 와 짝이 맞지
    // 않아 회귀 유발: PushKit 으로 cold-launch 된 BG process 에서
    // _configureAudioSessionForRingtone → audio_session.setActive(true) 가
    // CallKit accept 전에 ownership 없이 호출되어 OSStatus 560557684
    // (insufficient priority) throw → unhandled inside unawaited block →
    // Dart isolate 가 cleanup(ended) cascade → state=incoming → ended 직행 →
    // CallKit UI 사라짐 (사용자 매트릭스: "BG 3초 후 발신 → 안 뜸").
    //
    // 정공법: 우리 측 ringtone 호출 자체를 제거. Phase E-2 v3.1 검증 (2026-
    // 05-02 memory project_voip_pushkit_blocked.md) 후 모든 iOS 사용자가
    // PushKit token 등록 상태이므로 회귀 위험 0. acceptCall 의 audio session
    // 설정 흐름은 변경 없음 (CallKit accept → didActivate → completer await).
    //
    // v212 (2026-05-03): iOS FG 만 ringtone 부활. PushKit CallKit 의 FG
    // banner 는 system ringtone 안정적으로 안 들려줌 (사용자 매트릭스: "FG
    // 수신 화면 OK but 벨 안 울림"). lifecycle.resumed gate 로 BG cold-
    // launch 의 OSStatus 560557684 race 회피 (FG 라 audio session ownership
    // 가능). audio_session 명시 setup 안 함 — audioplayers default category
    // (SoloAmbient/Ambient) 가 silent switch 만 존중하면 speaker 출력 정상.
    if (!kIsWeb && Platform.isIOS) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.resumed) {
        unawaited(_startRingtone());
      }
    }
  }

  /// Invoked when the user taps accept. Prepares PeerConnection and sends rtc_answer.
  Future<void> acceptCall({required bool localAlwaysRelay}) async {
    try {
      await _acceptCallImpl(localAlwaysRelay: localAlwaysRelay);
    } on _CallCancelledException catch (e) {
      // 2026-05-04 fix: state race audit. cleanup 가 accept 중간 발화 →
      // orphan resources 정리됨 → silent return.
      debugPrint('[CallService] acceptCall cancelled mid-setup: ${e.reason}');
    }
  }

  Future<void> _acceptCallImpl({required bool localAlwaysRelay}) async {
    // [DIAG-VOIP-2026-04-19] For tracing acceptCall step timing. Remove after diagnosis.
    final sw = Stopwatch()..start();
    debugPrint('[DIAG:CallService] acceptCall ENTER');
    if (_status != CallServiceStatus.incoming) {
      throw StateError('No incoming call to accept');
    }
    // v212: stop in-app ringtone before audio session reconfig.
    unawaited(_stopRingtone());
    _alwaysRelay = _alwaysRelay || localAlwaysRelay;

    // Phase 8.2 v2.1 — Audio session CallKit delegation.
    //
    // 변경 전: await _configureAudioSession();
    //   → AVAudioSession.setActive(true) 직접 호출 → CallKit ActivationContext 가
    //     아직 PhoneCall priority 부여 전 → callservicesd Ringtone interrupt 거부 →
    //     -12983 → audio activate fail → 첫 accept 무시 ("두 번 탭" UX bug).
    //
    // 변경 후: AVAudioSession 카테고리/모드는 100% native (CXProviderDelegate.
    //   provider:performAnswerCallAction:) 에서 setup. 우리는 CallKit 의 didActivate
    //   콜백을 기다린 후 WebRTC peer connection 시작.
    //
    // FAIL-OPEN PATH (intentional contract):
    //   _audioSessionActivatedCompleter == null 인 경우는 두 가지:
    //   (a) Race A 잔존 (alias mismatch) — CallNotifier 의 stale guard 가
    //       prepareAudioSessionAwaiter() 호출 전에 차단됨. Dart state machine 의
    //       다른 경로 (예: in-app IncomingCallScreen 의 직접 acceptCall 호출) 로
    //       여기 도달.
    //   (b) Caller path 의 acceptCall 변형 (현재는 없지만 미래 호환).
    //   → 두 경우 모두 즉시 진행. flutter_webrtc 가 native 에서 RTCAudioSession
    //     activate 시 v200 swallow 가 -12983 catch 로 보호. 통화는 connect 됨.
    //   → 이 경로 발생 빈도를 _diagFailOpenAcceptCount metric 으로 monitor.
    if (Platform.isIOS) {
      final completer = _audioSessionActivatedCompleter;
      if (completer != null && !completer.isCompleted) {
        try {
          await completer.future.timeout(const Duration(seconds: 2));
          debugPrint('[CallService] audio session activated by CallKit '
              '(${sw.elapsedMilliseconds}ms)');
        } on TimeoutException {
          _diagAudioSessionTimeoutCount++;
          debugPrint('[CallService] audio session activate TIMEOUT — proceeding '
              '(v200 swallow protected)');
        }
      } else {
        _diagFailOpenAcceptCount++;
        debugPrint('[CallService] acceptCall fail-open (no completer) — '
            'relying on flutter_webrtc native + v200 swallow');
      }
    }
    debugPrint('[DIAG:CallService] acceptCall audioSession ${sw.elapsedMilliseconds}ms');
    await _acquireLocalStream();
    debugPrint('[DIAG:CallService] acceptCall localStream ${sw.elapsedMilliseconds}ms');

    final iceServers = await _turnManager.getIceServers();
    debugPrint('[DIAG:CallService] acceptCall iceServers ${sw.elapsedMilliseconds}ms');
    await _createPeerConnection(iceServers: iceServers, relay: _alwaysRelay);
    debugPrint('[DIAG:CallService] acceptCall peerConn ${sw.elapsedMilliseconds}ms');

    await _signaling.sendSealedSignaling(
      recipientSnowchatId: _remoteSnowchatId!,
      eventType: 'call_answer',
      innerPayload: {'callId': _callId},
    );
    debugPrint('[DIAG:CallService] acceptCall sentAnswer ${sw.elapsedMilliseconds}ms');

    _emit(CallServiceStatus.connecting);
    debugPrint('[DIAG:CallService] acceptCall EXIT ${sw.elapsedMilliseconds}ms');

    // [Pre-accept offer buffer] Process any rtc_offer that arrived before _pc was created.
    // Usually caller sends invite + offer together, so this is almost always populated.
    final pending = _pendingOffer;
    if (pending != null) {
      _pendingOffer = null;
      debugPrint('[DIAG:CallService] processing buffered rtc_offer');
      await _handleRemoteOffer(pending);
    }
  }

  /// User decline. [reason] default 'declined' — for the CallKit ringer timeout case it is
  /// called with 'timeout' to trigger the missed call system message (V1.0.1 §2.2).
  Future<void> declineCall({String reason = 'declined'}) async {
    if (_remoteSnowchatId == null || _callId == null) return;
    await _signaling.sendSealedSignaling(
      recipientSnowchatId: _remoteSnowchatId!,
      eventType: 'call_end',
      innerPayload: {'callId': _callId, 'reason': reason},
    );
    await _cleanup(endedReason: reason);
  }

  // ---------------------------------------------------------------------------
  // Mid-call controls
  // ---------------------------------------------------------------------------

  /// End call (user pressed the end button).
  Future<void> endCall() async {
    debugPrint('[DIAG:CallService] endCall ENTER status=$_status');
    // Fire-and-forget signaling — so _cleanup isn't tied to socket ack timeout.
    // If the peer is offline / socket asleep, ack may not arrive for up to 30s, forcing
    // the user to wait 30s for the 'ended → idle' transition. Ignore end-signal failures —
    // the peer self-terminates on ICE timeout.
    if (_callId != null && _remoteSnowchatId != null) {
      final cid = _callId!;
      final peer = _remoteSnowchatId!;
      unawaited(() async {
        try {
          await _signaling.sendSealedSignaling(
            recipientSnowchatId: peer,
            eventType: 'call_end',
            innerPayload: {'callId': cid, 'reason': 'ended'},
          );
        } catch (_) {
          // ignore
        }
      }());
    }
    final sw = Stopwatch()..start();
    await _cleanup(endedReason: 'ended');
    debugPrint('[DIAG:CallService] endCall cleanup ${sw.elapsedMilliseconds}ms');
  }

  void toggleMute() {
    final audioTrack = _localStream?.getAudioTracks().firstOrNull;
    debugPrint('[DIAG:CallService] toggleMute audioTrack=${audioTrack != null} '
        'currentMuted=$_muted');
    if (audioTrack == null) return;
    _muted = !_muted;
    audioTrack.enabled = !_muted;
    debugPrint('[DIAG:CallService] toggleMute applied newMuted=$_muted '
        'trackEnabled=${audioTrack.enabled}');
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    final track = _localStream?.getAudioTracks().firstOrNull;
    // flutter_webrtc 1.x: Helper.setSpeakerphoneOn is deprecated — route is decided via audio_session
    if (track != null) {
      await Helper.setSpeakerphoneOn(_speakerOn);
    }
  }

  // ---------------------------------------------------------------------------
  // Remote signaling event dispatch
  // ---------------------------------------------------------------------------

  Future<void> _dispatchRemoteEvent(CallSignalingEvent event) async {
    // [DIAG-VOIP-2026-04-19] For tracing remote signal dispatch. Remove after diagnosis.
    final sw = Stopwatch()..start();
    debugPrint('[DIAG:CallService] dispatchRemote ENTER type=${event.type}');
    try {
      switch (event.type) {
        case 'retry_receipt':
          // 2026-05-04 Signal Retry Receipt — recipient 가 우리가 보낸
          // envelope decrypt 실패해서 재전송 요청. CallSignaling 의 sent
          // cache 에서 hash 로 lookup → fresh session 으로 재암호화 + 재전송.
          final hash = event.data['envelopeHash'] as String?;
          if (hash == null || hash.isEmpty) return;
          await _signaling.handleRetryReceipt(hash, event.senderSnowchatId);
          return;

        case 'call_invite':
          final callId = event.data['callId'] as String?;
          final wantsRelay = event.data['alwaysRelay'] as bool? ?? false;
          final callerName = event.data['senderDisplayName'] as String?;
          if (callId == null) return;
          handleIncomingInvite(
            callId: callId,
            callerSnowchatId: event.senderSnowchatId,
            remoteWantsRelay: wantsRelay,
            callerDisplayName: callerName,
          );
          return;

        case 'call_answer':
          // Callee accepted — waiting for our offer to arrive at them (already sent in startCall).
          // Remote will now respond with rtc_answer.
          return;

        case 'rtc_offer':
          await _handleRemoteOffer(event);
          return;

        case 'rtc_answer':
          await _handleRemoteAnswer(event);
          return;

        case 'ice_candidate':
          await _handleRemoteIceCandidate(event);
          return;

        case 'call_end':
          await _handleRemoteEnd(event);
          return;
      }
    } catch (e) {
      debugPrint('[CallService] dispatch error: ${e.runtimeType}');
    } finally {
      debugPrint('[DIAG:CallService] dispatchRemote EXIT type=${event.type} ${sw.elapsedMilliseconds}ms');
    }
  }

  Future<void> _handleRemoteOffer(CallSignalingEvent event) async {
    // [callId guard — 2026-04-21] Even with the concurrent-call block policy, if a 3rd party
    // starts a call while one is already active, the rtc_offer following that invite was being
    // injected into the current peer connection, breaking the audio route. Reject only when
    // _callId is set AND mismatches — a null _callId means the call_invite hasn't arrived
    // yet (push cold-launch + socket reconnect race fires rtc_offer first), in which case
    // we still want to buffer it; the buffer replay in acceptCall re-runs this guard once
    // _callId is set, so a genuinely 3rd-party offer is dropped at replay time. Field-confirmed
    // via TestFlight v198: rtc_offer arrived 4s before user Accept, was discarded here, and
    // the call connected media-less because no remote SDP ever reached the peer connection.
    final eventCallId = event.data['callId'] as String?;
    // Fix B revised (2026-05-06) — anti-replay: late offer for an already-ended
    // call (e.g. caller-side retry after our cold fallback) must not pollute
    // _pendingOffer or hit the active peer connection.
    if (_isRecentlyEnded(eventCallId)) {
      debugPrint('[CallService] rtc_offer ignored — '
          'callId=$eventCallId in _recentlyEndedCallIds');
      return;
    }
    if (_callId != null && eventCallId != _callId) {
      debugPrint('[CallService] rtc_offer ignored — callId mismatch '
          '(current=$_callId, incoming=$eventCallId)');
      return;
    }
    if (_pc == null) {
      // _pc not yet exists = user hasn't pressed acceptCall yet, OR call_invite hasn't been
      // injected yet. Buffer and process at the end of acceptCall. Concurrent calls are
      // blocked (§9.3), so a single buffer slot is OK.
      debugPrint('[CallService] rtc_offer arrived before peer connection — buffering '
          '(currentCallId=$_callId, eventCallId=$eventCallId)');
      _pendingOffer = event;
      return;
    }
    final sdp = event.data['sdp'] as String?;
    if (sdp == null) return;

    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _pc!.setLocalDescription(answer);

    _localFingerprint = _safeParseFingerprint(answer.sdp);
    _maybeEmitSas(remoteSdp: sdp);

    // [Trickle ICE off] Send the final SDP after waiting for inline ICE candidates.
    final finalAnswer =
        await _waitForIceGatherAndGetLocalSdp(fallback: answer.sdp);

    await _signaling.sendSealedSignaling(
      recipientSnowchatId: event.senderSnowchatId,
      eventType: 'rtc_answer',
      innerPayload: {
        'callId': _callId,
        'sdp': finalAnswer,
      },
    );
  }

  Future<void> _handleRemoteAnswer(CallSignalingEvent event) async {
    // [callId guard — 2026-04-21] Prevent audio breakage from renegotiation when another
    // call's answer would be injected into the current pc.
    final eventCallId = event.data['callId'] as String?;
    if (_isRecentlyEnded(eventCallId)) {
      debugPrint('[CallService] rtc_answer ignored — '
          'callId=$eventCallId in _recentlyEndedCallIds');
      return;
    }
    if (_callId == null || eventCallId != _callId) {
      debugPrint('[CallService] rtc_answer ignored — callId mismatch '
          '(current=$_callId, incoming=$eventCallId)');
      return;
    }
    if (_pc == null) return;
    final sdp = event.data['sdp'] as String?;
    if (sdp == null) return;
    // 2026-05-04 fix: 진짜 recipient answer 도착 — outgoing timeout cancel.
    // 이 시점이 RFC 3261 의 200 OK + ACK 수신 의미. 이 후 ICE 협상 중
    // (connecting → active) — timeout 더 안 필요.
    _cancelOutgoingTimeout();
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _maybeEmitSas(remoteSdp: sdp);
  }

  /// Once both local/remote fingerprints are obtained, compute the 4-digit SAS and emit on stream.
  /// Computation failure is ignored (the call is already protected by Envelope-level E2EE).
  void _maybeEmitSas({required String remoteSdp}) {
    final local = _localFingerprint;
    if (local == null) return;
    try {
      final remote = CallVerification.parseFingerprint(remoteSdp);
      final sas = CallVerification.computeSas(
        localFingerprint: local,
        remoteFingerprint: remote,
      );
      _sasController.add(CallSasEvent(sas: sas));
    } catch (_) {
      // SDP parse failure is ignored — UI doesn't show SAS
    }
  }

  String? _safeParseFingerprint(String? sdp) {
    if (sdp == null) return null;
    try {
      return CallVerification.parseFingerprint(sdp);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleRemoteIceCandidate(CallSignalingEvent event) async {
    // [callId guard — 2026-04-21] Prevent another call's ICE candidate from polluting the
    // current pc's ICE state and confusing connectivity checks.
    final eventCallId = event.data['callId'] as String?;
    if (_isRecentlyEnded(eventCallId)) {
      debugPrint('[CallService] ice_candidate ignored — '
          'callId=$eventCallId in _recentlyEndedCallIds');
      return;
    }
    if (_callId == null || eventCallId != _callId) {
      debugPrint('[CallService] ice_candidate ignored — callId mismatch '
          '(current=$_callId, incoming=$eventCallId)');
      return;
    }
    if (_pc == null) return;
    final cand = event.data['candidate'] as String?;
    final sdpMid = event.data['sdpMid'] as String?;
    final sdpMLineIndex = event.data['sdpMLineIndex'] as int?;
    if (cand == null) return;
    await _pc!.addCandidate(RTCIceCandidate(cand, sdpMid, sdpMLineIndex));
  }

  Future<void> _handleRemoteEnd(CallSignalingEvent event) async {
    // [callId guard — 2026-04-21] Defend against another call's call_end mistakenly ending
    // the current active call. Separates from 3rd-caller paths like busy responses.
    final eventCallId = event.data['callId'] as String?;
    final reason = event.data['reason'] as String? ?? 'ended';

    // Fix B revised (2026-05-06) — cold-start fallback path.
    //
    // _callId == null means handleIncomingInvite never ran on this isolate.
    // Most common cause: long-idle ratchet desync caused the invite envelope
    // to fail decrypt; the catch block sent retry_receipt but call_invite is
    // excluded from _sentCache (call_signaling.dart:215, +233 regression
    // guard) so caller could not resend. The BG isolate (Android FCM) /
    // PushKit handler (iOS) raised CallKit independently, so the user is
    // staring at a ringing UI driven by a Telecom Connection that the main
    // isolate has zero state for.
    //
    // Without this fallback the call_end is silently dropped (the original
    // guard return), so the Telecom Connection lingers RINGING until the
    // plugin's 30s ringer timeout, AND the missed-call system message never
    // inserts (CallNotifier ended-branch gates on prevStatus == incoming
    // which only sets when _emit(incoming) runs — handleIncomingInvite
    // never reached _emit because decrypt failed upstream).
    //
    // Fallback contract:
    //   1. Populate _callId / _remoteSnowchatId from the event so _cleanup's
    //      pre-emit capture (override path below) sees them.
    //   2. Mark _recentlyEndedCallIds so any late-arriving invite/offer for
    //      the SAME callId (e.g. caller-side retry that landed after we
    //      gave up) is rejected at handleIncomingInvite.
    //   3. Run _cleanup with reason='cold_fallback'. CallNotifier branches
    //      on this reason to bypass the prevStatus gate when inserting the
    //      missed-call message + broadcasting endCall to candidate id set.
    if (_callId == null) {
      if (eventCallId == null || eventCallId.isEmpty) {
        debugPrint('[CallService] call_end fallback skipped — '
            'event.callId missing, no Connection id to dismiss');
        return;
      }
      debugPrint('[CallService] call_end COLD FALLBACK — '
          'populating _callId=$eventCallId from event '
          '(invite never decrypted on this isolate)');
      _callId = eventCallId;
      _remoteSnowchatId = event.senderSnowchatId;
      // _remoteDisplayName left null — we don't have it (would need a
      // separate user lookup; CallNotifier's missed-call insert path
      // tolerates null peerName and renders the snow ID prefix instead).
      _markRecentlyEnded(eventCallId);
      await _cleanup(endedReason: 'cold_fallback');
      return;
    }

    if (eventCallId != _callId) {
      debugPrint('[CallService] call_end ignored — callId mismatch '
          '(current=$_callId, incoming=$eventCallId)');
      return;
    }
    // Normal path — record callId before cleanup wipes it so the anti-replay
    // set covers a late retry-resend of the same call_end (or any other
    // signal carrying the same callId).
    if (_callId != null) _markRecentlyEnded(_callId!);
    await _cleanup(endedReason: reason);
  }

  // ---------------------------------------------------------------------------
  // WebRTC setup
  // ---------------------------------------------------------------------------

  Future<void> _createPeerConnection({
    required List<Map<String, dynamic>> iceServers,
    required bool relay,
  }) async {
    final config = <String, dynamic>{
      'iceServers': iceServers,
      if (relay) 'iceTransportPolicy': 'relay',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
    };
    final pc = await createPeerConnection(config, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });
    // 2026-05-04 fix: abort-check. _cleanup 가 await 도중 발화 했으면
    // 새로 만든 PC 는 orphan — close() 안 하면 ICE candidate 계속 수집 +
    // network/memory leak. fire-and-forget close (cleanup 패턴과 동일).
    if (_callId == null) {
      debugPrint('[CallService] _createPeerConnection — call cancelled mid-await, '
          'closing orphan PC');
      unawaited(() async {
        try {
          await pc.close().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }());
      throw const _CallCancelledException('peer connection created after cleanup');
    }
    _pc = pc;

    // [Trickle ICE disabled — 2026-04-19]
    // Default trickle emits each discovered candidate as a separate sealed_call_signaling,
    // and the receiver runs sealed unseal + Double Ratchet decrypt (~200ms) per candidate
    // serially on the main thread. iPhone offer ~14 + ICE ~14 → the batch hogs the main
    // thread for 5s → blocks the CallKit accept touch event → 60s ringer timeout.
    //
    // Fix: inline the candidates inside the SDP. After createOffer/createAnswer, wait for
    // ICE gathering complete, extract the final SDP from _pc.localDescription, and send a
    // single rtc_offer/rtc_answer. The separate ICE candidate type emission is dropped.
    //
    // No security impact: the candidates were already inside a sealed envelope before
    // (now they're inlined in the SDP instead). DTLS fingerprint / SAS / Sealed Sender all unchanged.
    // Trade-off: call setup gets ~1-2s slower (waiting for ICE gather complete).
    _pc!.onIceCandidate = (_) {};

    // [Trickle ICE off] Completer for waiting on ICE gathering complete.
    // Awaited by sendOfferAfterGathering() / sendAnswerAfterGathering().
    _iceGatheringCompleter = Completer<void>();
    _pc!.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        if (_iceGatheringCompleter != null &&
            !_iceGatheringCompleter!.isCompleted) {
          _iceGatheringCompleter!.complete();
        }
      }
    };

    _pc!.onIceConnectionState = (state) {
      debugPrint('[CallService] iceConnectionState=$state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        // Phase J (§26): WebRTC starts bidirectional voice streaming — stop ringback/ringtone immediately.
        unawaited(_stopRingback());
        unawaited(_stopRingtone());
        // [Android speaker default fix — 2026-04-21]
        unawaited(() async {
          if (!kIsWeb && Platform.isAndroid) {
            try {
              await Helper.setSpeakerphoneOn(false);
            } catch (_) {/* ignore fallback */}
          }
          _speakerOn = false;
        }());
        // ICE reconnection succeeded — reset restart counter / preemptive timer.
        _iceRestartAttempts = 0;
        _disconnectedTimer?.cancel();
        _disconnectedTimer = null;
        _emit(CallServiceStatus.active);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        // Immediate restart attempt (with retry logic).
        _disconnectedTimer?.cancel();
        _disconnectedTimer = null;
        unawaited(_attemptIceRestart());
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        // WebRTC native transitions to Failed after ~15s. Preemptively wait only 10s and,
        // if still Disconnected, kick off the ICE restart first. Goal is to shorten the
        // recovery time for international call NAT rebinding.
        _disconnectedTimer?.cancel();
        _disconnectedTimer = Timer(const Duration(seconds: 10), () {
          if (_pc == null) return;
          final now = _pc!.iceConnectionState;
          if (now ==
                  RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
              now == RTCIceConnectionState.RTCIceConnectionStateFailed) {
            unawaited(_attemptIceRestart());
          }
        });
      }
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[CallService] connectionState=$state');
    };

    // Remote track — WebRTC auto-plays audio
    _pc!.onTrack = (event) {
      debugPrint('[CallService] onTrack kind=${event.track.kind}');
    };

    // Add local audio track
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        await _pc!.addTrack(track, stream);
      }
    }
  }

  void _scheduleOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _answerReceived = false;
    _outgoingTimer = Timer(const Duration(seconds: 30), () {
      // 진짜 recipient answer 안 도착 + call 진행중 (ended/idle 아님) →
      // signaling 누수 시나리오. cleanup 으로 caller 측 종료.
      // _status == outgoing 체크 안 함 — caller 는 offer 보내자마자
      // optimistic connecting 으로 전이하지만 실제 answer 는 아직 못 받았
      // 을 수 있음. _answerReceived flag 로 판정.
      if (!_answerReceived &&
          _status != CallServiceStatus.idle &&
          _status != CallServiceStatus.ended) {
        debugPrint('[CallService] outgoing timeout 30s — no answer received '
            '(status=$_status) → auto-cleanup');
        unawaited(_cleanup(endedReason: 'timeout'));
      }
    });
  }

  void _cancelOutgoingTimeout() {
    _outgoingTimer?.cancel();
    _outgoingTimer = null;
    _answerReceived = true;
  }

  Future<void> _acquireLocalStream() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    // 2026-05-04 fix: abort-check. _cleanup 가 await 도중 발화 (`_callId =
    // null`) 했으면 새로 acquire 한 stream 은 orphan — 정리 안 하면 마이크
    // LED indicator 가 계속 hot 상태 (privacy + battery leak). 즉시 stop.
    if (_callId == null) {
      debugPrint('[CallService] _acquireLocalStream — call cancelled mid-await, '
          'stopping orphan stream');
      try {
        for (final t in stream.getTracks()) {
          try { t.stop(); } catch (_) {}
        }
      } catch (_) {}
      throw const _CallCancelledException('local stream acquired after cleanup');
    }
    _localStream = stream;
  }

  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth,
      avAudioSessionMode: AVAudioSessionMode.voiceChat,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType:
          AndroidAudioFocusGainType.gainTransientExclusive,
    ));
    // v200: setActive on iOS can throw "Insufficient priority" (-12983) during
    // the CallKit accept handoff window — callservicesd's Ringtone session
    // hasn't fully released and wins the priority contest. CallKit subsequently
    // activates the session for us via provider:didActivateAudioSession: once
    // the Ringtone tears down, so swallowing the throw is safe. Without this
    // guard the exception propagates: acceptCall → acceptPendingVoipCall*
    // catch → endCall(nonce) — dismissing the call the user just answered
    // (the chronic "수신 스와이프하고 꺼짐" pattern, intermittent ~50%).
    // Mirrors the existing tolerance pattern in _startRingback (≈line 944).
    try {
      await session.setActive(true);
    } catch (e) {
      // Phase 8.2 v2.1 — Conditional preservation. After CallKit delegation
      // the -12983 should drop to ~0% for incoming calls (acceptCall no longer
      // calls _configureAudioSession). Outgoing path (startCall L221) and
      // ringtone path (handleIncomingInvite L347) still call this. We monitor
      // the count; sustained > 1% means delegation is incomplete somewhere.
      _diagAudioPriorityRaceCount++;
      debugPrint('[CallService] _configureAudioSession setActive ignored '
          '(${e.runtimeType}) — CallKit owns activation via didActivateAudioSession '
          '(metric=$_diagAudioPriorityRaceCount)');
    }
  }

  /// ICE Restart (handles network switching, §18.3).
  Future<void> _restartIce() async {
    if (_pc == null || _remoteSnowchatId == null || _callId == null) return;
    try {
      final offer = await _pc!.createOffer({'iceRestart': true});
      await _pc!.setLocalDescription(offer);
      await _signaling.sendSealedSignaling(
        recipientSnowchatId: _remoteSnowchatId!,
        eventType: 'rtc_offer',
        innerPayload: {
          'callId': _callId,
          'sdp': offer.sdp,
          'restart': true,
        },
      );
    } catch (e) {
      debugPrint('[CallService] ICE restart failed: ${e.runtimeType}');
    }
  }

  /// ICE Restart retry with backoff (2026-04-21 international call disconnect fix).
  ///
  /// In an ICE FAILED state caused by NAT rebinding (3~5 min) or TURN allocation expiry
  /// (~10 min), don't give up after a single restart failure — retry up to 3 times.
  /// Backoff 3/6/9s: wait that long after each attempt, retry next if still failed.
  /// [_iceRestartAttempts] resets to 0 when Connected resumes.
  Future<void> _attemptIceRestart() async {
    const maxAttempts = 3;
    if (_iceRestartAttempts >= maxAttempts) {
      debugPrint('[CallService] ICE restart exhausted ($maxAttempts) — ending call');
      await _cleanup(endedReason: 'failed');
      return;
    }
    _iceRestartAttempts++;
    debugPrint('[CallService] ICE restart attempt $_iceRestartAttempts/$maxAttempts');
    await _restartIce();

    // Backoff — re-check status after 3/6/9s based on current attempt count.
    final delay = Duration(seconds: 3 * _iceRestartAttempts);
    Timer(delay, () {
      if (_pc == null) return; // call already ended
      final now = _pc!.iceConnectionState;
      if (now == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          now == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        // Recovery succeeded — onIceConnectionState's Connected branch resets the counter.
        return;
      }
      // Still failing — next attempt.
      unawaited(_attemptIceRestart());
    });
  }

  // ---------------------------------------------------------------------------
  // Cleanup + memory wipe (§23.4.5)
  // ---------------------------------------------------------------------------

  Future<void> _cleanup({String? endedReason}) async {
    debugPrint('[DIAG:CallService] _cleanup ENTER reason=$endedReason');
    final sw = Stopwatch()..start();

    // Fix B revised (2026-05-06) — capture for terminal _emit before wipe.
    // CallNotifier's ended branch needs callId / remoteSnowchatId to:
    //   - broadcast _callKitManager.endCall to the right Telecom Connection id
    //   - insert the missed-call message addressed to the right peer
    // The previous "wipe-then-emit" order silently zeroed these out for the
    // cold-fallback path (which has no prior _emit(incoming) to seed
    // state.callId / state.remoteSnowchatId on the CallNotifier side).
    // Captured for ALL ended emits — pre-existing flows already had the
    // values populated in `state.*` by prior emits, so passing them again
    // via override is a no-op for the FG/normal path; CallNotifier's
    // endingIds set deduplicates.
    final capturedCallId = _callId;
    final capturedRemoteSnow = _remoteSnowchatId;
    final capturedRemoteName = _remoteDisplayName;

    // Phase J (§26): stop ringback/ringtone immediately. If end reason is busy, play busy tone for 2s
    // then dispose via its own timer — _cleanup itself does not block.
    unawaited(_stopRingback());
    unawaited(_stopRingtone());
    if (endedReason == 'busy') {
      unawaited(_playBusyTone());
    }

    // Cleanup ICE restart retry timer + reset counter (2026-04-21).
    _disconnectedTimer?.cancel();
    _disconnectedTimer = null;
    _iceRestartAttempts = 0;
    // 2026-05-04 fix: cancel outgoing timeout (manual end before timeout).
    _cancelOutgoingTimeout();

    // [2026-04-19] track.stop() is a synchronous native call, but on iOS sync negotiation
    // with the audio engine can hold the main thread (observed: 30s freeze after pressing end).
    // Schedule on the next macrotask to free the main isolate immediately.
    final stream = _localStream;
    if (stream != null) {
      Future<void>(() {
        try {
          for (final t in stream.getTracks()) {
            try {
              t.stop();
            } catch (_) {}
          }
        } catch (_) {}
      });
    }
    debugPrint('[DIAG:CallService] _cleanup tracksScheduled ${sw.elapsedMilliseconds}ms');

    // [2026-04-19] _pc.close() sometimes hangs on iOS at the native layer — main isolate's
    // await never resolves during ICE / DTLS teardown → end button has no UI response.
    // fire-and-forget + timeout frees the main isolate immediately while native cleanup
    // runs in the background. Memory wipe is immediate.
    final pcRef = _pc;
    if (pcRef != null) {
      unawaited(() async {
        try {
          await pcRef.close().timeout(const Duration(seconds: 2));
        } catch (_) {
          // close hang or throw — discard, native GC will clean up.
        }
      }());
    }

    // Explicit null assignment — Zero-Trace memory wipe (§23.4.5)
    _pc = null;
    _localStream = null;
    _callId = null;
    _remoteSnowchatId = null;
    _remoteDisplayName = null;
    _alwaysRelay = false;
    _muted = false;
    _speakerOn = false;
    _localFingerprint = null;
    if (_iceGatheringCompleter != null &&
        !_iceGatheringCompleter!.isCompleted) {
      _iceGatheringCompleter!.complete();
    }
    _iceGatheringCompleter = null;
    _pendingOffer = null;
    _ringbackPlayer = null;
    debugPrint('[DIAG:CallService] _cleanup wiped ${sw.elapsedMilliseconds}ms');

    // audio session also fire-and-forget + timeout — on iOS setActive(false) sometimes drags
    // due to routing negotiation with other audio clients.
    unawaited(() async {
      try {
        final session = await AudioSession.instance;
        await session.setActive(false).timeout(const Duration(seconds: 2));
      } catch (_) {
        // ignore — next call will re-configure via _configureAudioSession.
      }
    }());

    // Phase 8.2 §28.5(a) — clear envelope dedup cache so the next call's first
    // envelope (theoretically same hash) is not silent-dropped.
    try {
      _signaling.clearProcessedEnvelopes();
    } catch (e) {
      debugPrint('[CallService] clearProcessedEnvelopes failed: ${e.runtimeType}');
    }

    _emit(
      CallServiceStatus.ended,
      endedReason: endedReason,
      overrideCallId: capturedCallId,
      overrideRemoteSnowchatId: capturedRemoteSnow,
      overrideRemoteDisplayName: capturedRemoteName,
    );

    // Assert wipe — debug only
    assert(_pc == null);
    assert(_callId == null);
    assert(_remoteSnowchatId == null);
    // Phase J: ringback must always be null. busy is allowed during 2s playback (UX SFX).
    assert(_ringbackPlayer == null);

    _status = CallServiceStatus.idle;
    debugPrint('[DIAG:CallService] _cleanup EXIT ${sw.elapsedMilliseconds}ms');
  }

  void _emit(
    CallServiceStatus status, {
    String? endedReason,
    String? overrideCallId,
    String? overrideRemoteSnowchatId,
    String? overrideRemoteDisplayName,
  }) {
    // Late-emit guard (2026-04-21 revision) — after _cleanup runs and `_callId=null`, a
    // late non-terminal emit (connecting/active) from startCall/acceptCall's async path
    // races and the UI flips from "call ended" back to "in call" — busy/offline-response
    // UX breaks.
    //
    // Criterion: `_callId == null` + non-terminal status → block.
    //   · startCall/handleIncomingInvite set _callId first, then call _emit
    //     → _callId != null, passes.
    //   · _cleanup wipes _callId=null then calls _emit(ended, ...) → status is terminal, passes.
    //   · Subsequent connecting/active emits with _callId=null are late emits → block.
    if (_callId == null &&
        status != CallServiceStatus.idle &&
        status != CallServiceStatus.ended) {
      debugPrint('[CallService] _emit $status suppressed — _callId null (late emit after cleanup)');
      return;
    }
    _status = status;
    _eventController.add(CallServiceEvent(
      status: status,
      // Fix B revised (2026-05-06) — terminal 'ended' emit must carry the
      // callId/remoteSnowchatId the call WAS using so CallNotifier's ended
      // branch can broadcast endCall to the right Telecom Connection id and
      // insert the missed-call message addressed to the right peer.
      // _cleanup wipes _callId / _remoteSnowchatId BEFORE calling _emit, so
      // without override params the ended event would always carry nulls
      // (existing behavior — CallNotifier currently relies on `state.callId`
      // / `state.remoteSnowchatId` from a prior incoming/connecting emit).
      // The cold-fallback path has no prior incoming emit, so it must be
      // able to carry the values directly via the override.
      callId: overrideCallId ?? _callId,
      remoteSnowchatId: overrideRemoteSnowchatId ?? _remoteSnowchatId,
      remoteDisplayName: overrideRemoteDisplayName ?? _remoteDisplayName,
      endedReason: endedReason,
    ));
  }

  /// RFC 4122 v4 UUID (8-4-4-4-12 hyphenated, 36 chars).
  ///
  /// v202 (2026-05-01): switched from raw 32-hex to UUID format so the same id
  /// can flow into the iOS CallKit / Android ConnectionService layers without
  /// hitting `UUID(uuidString:)` parse failures (the chronic
  /// "수신 스와이프하고 꺼짐" / "발신 endCall → process dies" class). Server
  /// + signaling envelopes treat the field as opaque, so on-the-wire compat is
  /// preserved across v201↔v202 in-flight calls (32-hex and UUID both pass as
  /// strings; only the CallKit layer cares about the format and only ever sees
  /// fresh ids generated by this function).
  ///
  /// Aligns with Phase 8.2 §27 nonce widening pattern (UUID-36 + base64url-43)
  /// and lets `CallKitManager.startOutgoing()` register caller-side calls via
  /// CallKit (currently no-op because the v201 UUID guard rejects 32-hex).
  String _generateCallId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    // RFC 4122 v4: top 4 bits of byte 6 = 0100 (version), top 2 bits of byte 8
    // = 10 (variant). Without this, the bytes form a valid UUID string but not
    // a v4 — some strict parsers reject. Apple's UUID(uuidString:) is lenient,
    // but staying spec-correct avoids future surprises.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  // ---------------------------------------------------------------------------
  // Phase J (Phase 8.2 §26): ringback / busy tone playback
  // ---------------------------------------------------------------------------

  /// Caller-side ringback tone loop playback. Caller only — for the callee CallKit owns the
  /// system ring. Plays throughout connecting/outgoing and is stopped by `_stopRingback`
  /// when entering `active`. Asset is a synthesized sine wave (425 Hz Korean standard,
  /// 1s on/2s off, royalty-free).
  ///
  /// Playback session: keeps the `voiceChat` category — WebRTC takes over the session
  /// automatically when entering `active`. We don't reconfigure audio focus here.
  Future<void> _startRingback() async {
    // Late-call guard (2026-04-21) — startCall's unawaited call may late-fire after cleanup,
    // causing ringback to keep playing even after busy tone ends. Prevents that bug.
    // _callId is set early in startCall and wiped to null in _cleanup, providing a stable
    // terminal check.
    if (_callId == null) {
      debugPrint('[CallService] _startRingback skipped — _callId null (late-fire after cleanup)');
      return;
    }
    if (_ringbackPlayer != null) return; // already playing
    try {
      final player = AudioPlayer();
      _ringbackPlayer = player;
      // Phase E-2 §26.5 dynamic-audit fix — defensive guard.
      // startCall already configures the audio session, but if that failed
      // silently, this ensures ringback still plays into an active session.
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {
        // Ignore — fall through to play; AudioPlayer may still work.
      }
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('audio/ringback.wav'));
    } catch (e, st) {
      // Playback failure is a UX degrade but the call itself continues — zero policy impact.
      debugPrint('[CallService] ringback start failed: ${e.runtimeType} — $e');
      debugPrint(st.toString());
      _ringbackPlayer = null;
    }
  }

  /// Stop the ringback loop + dispose AudioPlayer. Safe across multiple calls (idempotent).
  Future<void> _stopRingback() async {
    final player = _ringbackPlayer;
    _ringbackPlayer = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  /// v212 (2026-05-03): iOS FG-only in-app ringtone. Caller-gated by
  /// handleIncomingInvite (lifecycle.resumed && Platform.isIOS) so BG
  /// cold-launch never reaches here — that's where audio session priority
  /// race triggers OSStatus 560557684 (Phase E-2 hardening). FG path is
  /// safe because the app is active and owns the audio session by default.
  /// Reuses the ringback asset (425Hz tone, 1s on / 2s off) — distinct
  /// dedicated ringtone .wav is an optional future improvement.
  Future<void> _startRingtone() async {
    if (_callId == null) return; // late-fire guard (mirrors _startRingback)
    if (_ringtonePlayer != null) return;
    try {
      // v213 (2026-05-03): audio session 명시 setup. v212 에서 누락 →
      // audioplayers 가 default category (SoloAmbient) 로 silent 재생되던
      // 회귀 fix. CLAUDE.md §2.7 가 정확히 이걸 경고: "iOS 는 정의되지 않은
      // session category 에서 audioplayers silenced". Playback category +
      // setActive(true) 로 ringtone 정상 출력. silent switch 존중 (iOS
      // 표준 ringtone 동작). FG 라 priority race 없음 (BG cold-launch
      // OSStatus 560557684 회피는 handleIncomingInvite 의 lifecycle gate
      // 가 담당).
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
        ));
        await session.setActive(true);
      } catch (e) {
        debugPrint('[CallService] _startRingtone audio session setup failed: '
            '$e — continuing with AudioPlayer default');
      }

      final player = AudioPlayer();
      _ringtonePlayer = player;
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('audio/ringback.wav'));
    } catch (e) {
      debugPrint('[CallService] _startRingtone failed: $e');
      _ringtonePlayer = null;
    }
  }

  /// Stop the in-app ringtone loop + dispose. Idempotent.
  Future<void> _stopRingtone() async {
    final p = _ringtonePlayer;
    _ringtonePlayer = null;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
    try {
      await p.dispose();
    } catch (_) {}
  }

  /// On end reason 'busy', play for 3s then auto-dispose. fire-and-forget so it doesn't
  /// block `_cleanup`. Fits within CallNotifier's 3s `ended → idle` delay.
  Future<void> _playBusyTone() async {
    if (_busyPlayer != null) {
      debugPrint('[DIAG:CallService] _playBusyTone skipped (already playing)');
      return;
    }
    debugPrint('[DIAG:CallService] _playBusyTone ENTER');
    try {
      final player = AudioPlayer();
      _busyPlayer = player;
      await player.play(AssetSource('audio/busy.wav'));
      debugPrint('[DIAG:CallService] _playBusyTone play dispatched');
      // Stop after 3s — busy.wav is a 2s cushion loop. Generous timing for caller UX.
      Future<void>.delayed(const Duration(seconds: 3), () async {
        try {
          await player.stop();
        } catch (_) {}
        try {
          await player.dispose();
        } catch (_) {}
        if (identical(_busyPlayer, player)) {
          _busyPlayer = null;
        }
        debugPrint('[DIAG:CallService] _playBusyTone disposed');
      });
    } catch (e) {
      debugPrint('[CallService] _playBusyTone failed: ${e.runtimeType}: $e');
      _busyPlayer = null;
    }
  }

  // Phase 8.2 v2.2 — Audio session CallKit delegation event subscription.
  //
  // Single primary path: CallKitManager broadcasts `audioSessionActivated`
  // when the plugin emits ACTION_CALL_TOGGLE_AUDIO_SESSION (isActivate=true).
  // CallNotifier wires CallKitManager.audioSessionActivated → this service
  // via `notifyAudioSessionActivatedFromCallKit`.
  //
  // Backup path: AppDelegate's CallkitIncomingAppDelegate hooks call
  // VoipNativeBridge → broadcast streams (this method's subscriptions). Used
  // only if the plugin's sendEvent sink was nil at fire time (e.g. PushKit
  // cold launch before isolate ready). Both paths are idempotent via the
  // Completer.isCompleted guard.
  //
  // Why path A (direct EventChannel subscribe) was removed:
  // EventChannel.receiveBroadcastStream() invokes native onListen on every
  // call. EventCallbackHandler.onListen overwrites its eventSink each time, so
  // having two subscribers (CallKitManager + CallService) caused the second
  // listener to silently kill the first sink — first ACCEPT tap dropped → user
  // forced to tap twice. CallKitManager owns the EventChannel exclusively now.
  //
  // v2.5 (2026-05-03): the old `_subscribeToAudioSessionEvents` registered a
  // `setMethodCallHandler` directly on `snowchat/voip_native`, colliding with
  // VoipNativeBridge's handler — whichever ran last won, silently dropping
  // the other side's MethodCalls. Bridge now owns the channel exclusively
  // and exposes audio session events as broadcast streams; this method
  // subscribes from `callServiceProvider`. Idempotent — re-wiring re-uses
  // the existing subs (cancels first), so a hot-restart-style re-init is safe.
  void wireNativeBridge({
    required Stream<void> audioSessionActivated,
    required Stream<void> audioSessionDeactivated,
    required Stream<void> systemReset,
  }) {
    if (!Platform.isIOS) return;             // Android: no CallKit delegation
    _bridgeAudioActivatedSub?.cancel();
    _bridgeAudioDeactivatedSub?.cancel();
    _bridgeSystemResetSub?.cancel();
    _bridgeAudioActivatedSub = audioSessionActivated.listen((_) {
      _onAudioSessionActivated(source: 'native_bridge');
    });
    _bridgeAudioDeactivatedSub = audioSessionDeactivated.listen((_) {
      // Observation only — cleanup is driven by endCall/decline, not by
      // audio lifecycle. Used for telemetry.
      debugPrint('[CallService] didDeactivateAudioSession (observation)');
    });
    _bridgeSystemResetSub = systemReset.listen((_) async {
      debugPrint('[CallService] providerDidReset → cleanup');
      await _cleanup(endedReason: 'system_reset');
    });
    // Replay invocation moved to CallKitManager.replayPendingFromBackground;
    // CallNotifier triggers it once the ckm.events listener is attached.
  }

  /// Public entry from CallNotifier when CallKitManager broadcasts an audio
  /// session activation. Idempotent via the Completer.isCompleted guard, so
  /// it's safe even if the backup MethodChannel path fires the same event.
  void notifyAudioSessionActivatedFromCallKit() {
    _onAudioSessionActivated(source: 'callkit_manager');
  }

  /// Idempotent — multiple paths may fire within ~5ms; first one completes
  /// the Completer, subsequent calls are no-ops.
  void _onAudioSessionActivated({required String source}) {
    final completer = _audioSessionActivatedCompleter;
    if (completer != null && !completer.isCompleted) {
      debugPrint('[CallService] didActivateAudioSession received via $source → completing');
      completer.complete();
    }
  }

  /// Public API for CallNotifier — create the Completer at the moment
  /// `actionCallAccept` is received (BEFORE `acceptCall` is invoked). This
  /// avoids the race where CallKit fires `didActivate` between accept event
  /// and `acceptCall` entry — without the Completer being created yet.
  void prepareAudioSessionAwaiter() {
    if (!Platform.isIOS) return;
    _audioSessionActivatedCompleter = Completer<void>();
  }

  /// Diagnostic snapshot for daily backend report.
  Map<String, int> get diagMetrics => {
        'audio_priority_race': _diagAudioPriorityRaceCount,
        'audio_session_timeout': _diagAudioSessionTimeoutCount,
        'fail_open_accept': _diagFailOpenAcceptCount,
      };

  Future<void> dispose() async {
    await _signalingSub.cancel();
    // v2.5: cancel bridge subscriptions instead of detaching the channel
    // handler — the channel is owned by VoipNativeBridge and dies with it.
    await _bridgeAudioActivatedSub?.cancel();
    await _bridgeAudioDeactivatedSub?.cancel();
    await _bridgeSystemResetSub?.cancel();
    _bridgeAudioActivatedSub = null;
    _bridgeAudioDeactivatedSub = null;
    _bridgeSystemResetSub = null;
    // Fix B revised (2026-05-06) — release anti-replay timers.
    _recentlyEndedSweepTimer?.cancel();
    _recentlyEndedSweepTimer = null;
    for (final t in _recentlyEndedExpirers.values) {
      t.cancel();
    }
    _recentlyEndedExpirers.clear();
    _recentlyEndedCallIds.clear();
    await _eventController.close();
    await _sasController.close();
    await _cleanup();
    // Phase J: also fully clean up any pending busy tone player.
    final busy = _busyPlayer;
    _busyPlayer = null;
    if (busy != null) {
      try {
        await busy.stop();
      } catch (_) {}
      try {
        await busy.dispose();
      } catch (_) {}
    }
  }
}

/// 2026-05-04 fix: state race audit. startCall / acceptCall 의 async chain
/// (_acquireLocalStream / _createPeerConnection 등) 도중에 _cleanup 가
/// 다른 곳 (소켓 disconnect, decline, cleanup-by-end) 에서 fire 되어
/// `_callId = null` 로 만들면, 새로 생성한 mic stream / PeerConnection 이
/// orphan 으로 leak. 이 sentinel exception 을 던져서 caller 에서 silent
/// catch + 정리. 정리 자체는 throw 직전에 (track.stop / pc.close) 수행됨.
class _CallCancelledException implements Exception {
  const _CallCancelledException(this.reason);
  final String reason;
  @override
  String toString() => '_CallCancelledException($reason)';
}
