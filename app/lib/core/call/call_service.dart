/// @file        call_service.dart
/// @description WebRTC P2P PeerConnection management + CallSignaling integration (Phase 8.2 §3.3)
///              DTLS-SRTP voice call + Sealed Sender signaling + Always Relay option.
///              Zero-Trace §23: explicit wipe of all fields on termination.
///              Phase J (§26): caller-side ringback tone + busy tone playback management.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation; Phase J §26: ringback / busy tone)
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

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audio_session/audio_session.dart';
// audioplayers conflicts with audio_session on the `AVAudioSessionCategory` name,
// so import only the needed symbols via `show` (Phase J §26).
import 'package:audioplayers/audioplayers.dart'
    show AudioPlayer, AssetSource, ReleaseMode;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_signaling.dart';
import 'call_verification.dart';
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
  })  : _signaling = signaling,
        _turnManager = turnManager {
    _signalingSub = _signaling.onSignalingEvent.listen(_dispatchRemoteEvent);
  }

  final CallSignaling _signaling;
  final TurnCredentialManager _turnManager;

  late final StreamSubscription<CallSignalingEvent> _signalingSub;
  final _eventController = StreamController<CallServiceEvent>.broadcast();
  final _sasController = StreamController<CallSasEvent>.broadcast();

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

  // [Pre-accept offer buffer — 2026-04-19]
  // The caller's startCall sends an rtc_offer right after the invite. On the receiver side _pc
  // isn't created until the user accepts (acceptCall → _createPeerConnection), so silently
  // dropping an offer that arrives in between means setRemoteDescription is never called and
  // ICE never starts. Buffer the offer and process it at the end of acceptCall.
  CallSignalingEvent? _pendingOffer;

  // Phase J (Phase 8.2 §26): caller-side ringback / busy tone playback management.
  // Ringback is caller side only — callee uses the CallKit system ring.
  // Busy tone plays for 2s on end reason 'busy', then auto-dismisses.
  AudioPlayer? _ringbackPlayer;
  AudioPlayer? _busyPlayer;

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
  Future<void> startCall({
    required String recipientSnowchatId,
    required bool alwaysRelay,
    String? senderDisplayName,
  }) async {
    if (_status != CallServiceStatus.idle) {
      throw StateError('Call already in progress');
    }

    _callId = _generateCallId();
    _remoteSnowchatId = recipientSnowchatId;
    _alwaysRelay = alwaysRelay;
    _emit(CallServiceStatus.outgoing);

    await _configureAudioSession();
    await _acquireLocalStream();

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
  }

  /// Invoked when the user taps accept. Prepares PeerConnection and sends rtc_answer.
  Future<void> acceptCall({required bool localAlwaysRelay}) async {
    // [DIAG-VOIP-2026-04-19] For tracing acceptCall step timing. Remove after diagnosis.
    final sw = Stopwatch()..start();
    debugPrint('[DIAG:CallService] acceptCall ENTER');
    if (_status != CallServiceStatus.incoming) {
      throw StateError('No incoming call to accept');
    }
    _alwaysRelay = _alwaysRelay || localAlwaysRelay;

    await _configureAudioSession();
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
    // injected into the current peer connection, breaking the audio route. Ignore all remote
    // events with a different callId to protect the existing call.
    final eventCallId = event.data['callId'] as String?;
    if (_callId == null || eventCallId != _callId) {
      debugPrint('[CallService] rtc_offer ignored — callId mismatch '
          '(current=$_callId, incoming=$eventCallId)');
      return;
    }
    if (_pc == null) {
      // _pc not yet exists = user hasn't pressed acceptCall yet. Buffer and process at the
      // end of acceptCall. Concurrent calls are blocked (§9.3), so a single buffer slot is OK.
      debugPrint('[CallService] rtc_offer arrived before peer connection — buffering');
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
    if (_callId == null || eventCallId != _callId) {
      debugPrint('[CallService] rtc_answer ignored — callId mismatch '
          '(current=$_callId, incoming=$eventCallId)');
      return;
    }
    if (_pc == null) return;
    final sdp = event.data['sdp'] as String?;
    if (sdp == null) return;
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
    if (_callId == null || eventCallId != _callId) {
      debugPrint('[CallService] call_end ignored — callId mismatch '
          '(current=$_callId, incoming=$eventCallId)');
      return;
    }
    final reason = event.data['reason'] as String? ?? 'ended';
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
    _pc = await createPeerConnection(config, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

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
        // Phase J (§26): WebRTC starts bidirectional voice streaming — stop ringback immediately.
        unawaited(_stopRingback());
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

  Future<void> _acquireLocalStream() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
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
    await session.setActive(true);
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

    // Phase J (§26): stop ringback immediately. If end reason is busy, play busy tone for 2s
    // then dispose via its own timer — _cleanup itself does not block.
    unawaited(_stopRingback());
    if (endedReason == 'busy') {
      unawaited(_playBusyTone());
    }

    // Cleanup ICE restart retry timer + reset counter (2026-04-21).
    _disconnectedTimer?.cancel();
    _disconnectedTimer = null;
    _iceRestartAttempts = 0;

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

    _emit(CallServiceStatus.ended, endedReason: endedReason);

    // Assert wipe — debug only
    assert(_pc == null);
    assert(_callId == null);
    assert(_remoteSnowchatId == null);
    // Phase J: ringback must always be null. busy is allowed during 2s playback (UX SFX).
    assert(_ringbackPlayer == null);

    _status = CallServiceStatus.idle;
    debugPrint('[DIAG:CallService] _cleanup EXIT ${sw.elapsedMilliseconds}ms');
  }

  void _emit(CallServiceStatus status, {String? endedReason}) {
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
      callId: _callId,
      remoteSnowchatId: _remoteSnowchatId,
      remoteDisplayName: _remoteDisplayName,
      endedReason: endedReason,
    ));
  }

  String _generateCallId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
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
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(AssetSource('audio/ringback.wav'));
    } catch (e) {
      // Playback failure is a UX degrade but the call itself continues — zero policy impact.
      debugPrint('[CallService] ringback start failed: ${e.runtimeType}');
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

  Future<void> dispose() async {
    await _signalingSub.cancel();
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
