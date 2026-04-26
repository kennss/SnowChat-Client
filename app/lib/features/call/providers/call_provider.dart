/// @file        call_provider.dart
/// @description CallNotifier state machine + Riverpod provider (Phase 8.2 §2, §5).
///              Wraps CallService and emits CallState for the UI to subscribe to.
///              Terminated-call metadata is not retained in state (§23 Zero-Trace).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation; Phase I §25: FCM Voice Push — acceptPendingVoipCall + _onCallKitEvent nonce branch)
///
/// @functions
///  - CallNotifier.startCall(): start outgoing call
///  - CallNotifier.acceptCall() / declineCall(): accept/decline incoming call
///  - CallNotifier.endCall(): end call
///  - CallNotifier.toggleMute() / toggleSpeaker()
///  - CallNotifier._onCallKitEvent(): Phase E-1 system UI action routing
///  - CallNotifier._maybeInsertMissedCallMessage(): V1.0.1 missed-call system message
///  - CallNotifier.acceptPendingVoipCall(): Phase I FCM Voice Push — nonce path accept

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../app/providers.dart';
import '../../../core/call/call_service.dart';
import '../../../core/call/callkit_manager.dart';
import '../../../core/network/api_client.dart';
import '../../settings/settings_provider.dart';

/// Call status that the UI will display.
enum CallStatus {
  idle,
  outgoing,
  incoming,
  connecting,
  active,
  ended, // returns to idle within 2-3s after UI display (§3.5)
}

/// Call state snapshot. Fields are only filled during an active call.
/// All null on termination — terminated-call metadata must not be retained
/// (§23.4.5).
///
/// **elapsed field removed (2026-04-19)** — per-second state changes fired
/// every callProvider listener every second, putting load on the Riverpod
/// scheduler and accumulating ActiveCallScreen widget rebuilds every
/// second. Elapsed time is now computed from [callStartedAt] by a local
/// Timer + setState inside ActiveCallScreen.
class CallState {
  const CallState({
    this.status = CallStatus.idle,
    this.callId,
    this.remoteSnowchatId,
    this.remoteDisplayName,
    this.callStartedAt,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.alwaysRelay = false,
    this.sas,
    this.endedReason,
  });

  const CallState.idle() : this();

  final CallStatus status;
  final String? callId;
  final String? remoteSnowchatId;
  final String? remoteDisplayName;

  /// Time of `active` entry (set only once). UI computes elapsed via its
  /// own Timer. Null on termination. Doesn't change every second so does
  /// not trigger callProvider firings.
  final DateTime? callStartedAt;

  final bool isMuted;
  final bool isSpeakerOn;
  final bool alwaysRelay;

  /// 4-digit Safety Number (computed and injected in Phase G).
  final String? sas;

  /// Set only in `ended` state: `ended` | `declined` | `busy` | `timeout` | `failed` | `permission_denied` | `offline`.
  final String? endedReason;

  CallState copyWith({
    CallStatus? status,
    String? callId,
    String? remoteSnowchatId,
    String? remoteDisplayName,
    DateTime? callStartedAt,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? alwaysRelay,
    String? sas,
    String? endedReason,
  }) {
    return CallState(
      status: status ?? this.status,
      callId: callId ?? this.callId,
      remoteSnowchatId: remoteSnowchatId ?? this.remoteSnowchatId,
      remoteDisplayName: remoteDisplayName ?? this.remoteDisplayName,
      callStartedAt: callStartedAt ?? this.callStartedAt,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      alwaysRelay: alwaysRelay ?? this.alwaysRelay,
      sas: sas ?? this.sas,
      endedReason: endedReason ?? this.endedReason,
    );
  }
}

class CallNotifier extends StateNotifier<CallState> {
  /// Phase I (§25): in the app-killed → FCM Voice Push → CallKit Accept →
  /// MainActivity wake flow, when an Accept event arrives before
  /// SealedSender is initialized (PIN not unlocked, _IdleCallNotifier is
  /// active), stash the nonce here. After user unlocks PIN → SealedSender
  /// init → callProvider rebuild, the real CallNotifier constructor reads
  /// this value and auto-resumes. At most 1 entry per app lifetime. The
  /// 60s TTL is enforced by server Redis (on expiry /calls/pending/:nonce
  /// returns 410).
  static String? _pendingVoipNonce;

  /// Called from `_IdleCallNotifier._onCallKitEvent`. The CallKit UI is
  /// kept (not dismissed) — once the rebuilt CallNotifier resumes after
  /// PIN unlock, the call transitions normally, and CallKit is cleaned up
  /// when the user later declines/ends.
  static void rememberPendingNonce(String nonce) {
    _pendingVoipNonce = nonce;
  }

  CallNotifier({
    required CallService callService,
    CallKitManager? callKitManager,
    Ref? ref,
  })  : _callService = callService,
        _callKitManager = callKitManager,
        _ref = ref,
        super(const CallState.idle()) {
    _serviceSub = _callService.events.listen(_onServiceEvent);
    _sasSub = _callService.sasEvents.listen(_onSasEvent);
    // Phase E-1: bind system call UI events (CallKit / ConnectionService).
    final ckm = _callKitManager;
    if (ckm != null) {
      _callKitSub = ckm.events.listen(_onCallKitEvent);
    }

    // Phase I (§25): pending nonce resume — two paths.
    //
    // (A) in-memory pending: CallKit Accept event arrived at the
    //     _IdleCallNotifier stage and was stashed via `rememberPendingNonce`.
    //     Main isolate already alive — short window between Accept and
    //     provider rebuild.
    //
    // (B) CallKit's own storage lookup (cold-start recovery): if the app
    //     was killed → CallKit Accept → MainActivity launch → and the
    //     event was emitted before Flutter engine boot completed, it never
    //     reached the in-memory store. In that case flutter_callkit_incoming
    //     keeps `accepted: true` in its internal persistent storage, so we
    //     recover via `activeCalls()`.
    //
    // Only the first one found is processed. Duplicate resume is guarded
    // by the server's one-shot semantics (410).
    final pending = _pendingVoipNonce;
    if (pending != null && ref != null) {
      _pendingVoipNonce = null;
      _scheduleVoipResume(ref, pending);
    } else if (ref != null) {
      // Defer via micro-task — async activeCalls() lookup outside ctor.
      Future.microtask(() => _recoverAcceptedCallFromCallKit(ref));
    }
  }

  /// Phase I (§25) cold-start recovery: query the active-calls list that
  /// flutter_callkit_incoming keeps in internal storage, find an entry
  /// with `accepted=true` matching the nonce pattern, and resume. Recovers
  /// the case where the Accept event was emitted before Flutter engine
  /// boot and never reached the in-memory listener.
  Future<void> _recoverAcceptedCallFromCallKit(Ref ref) async {
    try {
      final result = await FlutterCallkitIncoming.activeCalls();
      if (result is! List || result.isEmpty) return;

      final matches = <String>[];
      for (final entry in result) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final accepted = entry['accepted'];
        if (id is String &&
            accepted == true &&
            _voipNoncePattern.hasMatch(id)) {
          matches.add(id);
        }
      }

      if (matches.isEmpty) return;

      // Only resume the most recently Accepted nonce — activeCalls()
      // ordering depends on the package internal impl, but if it fails
      // the server returns 410 and we'll endCall. The leftover stale
      // entries (accepted entries piled up from previous tests) are
      // cleaned up immediately.
      final primary = matches.last;
      for (final id in matches) {
        if (id == primary) continue;
        unawaited(_callKitManager?.endCall(id));
      }

      debugPrint('[CallNotifier] recovered accepted voip nonce from CallKit '
          '(total matches=${matches.length})');
      _scheduleVoipResume(ref, primary);
    } catch (e) {
      debugPrint('[CallNotifier] activeCalls() check failed: ${e.runtimeType}');
    }
  }

  /// Phase I (§25): schedule pending nonce resume — runs immediately or
  /// waits for PIN unlock, depending on the callRequirePin option.
  void _scheduleVoipResume(Ref ref, String nonce) {
    final requirePin = ref.read(settingsProvider).callRequirePin;
    final locked = ref.read(isLockedProvider);

    if (requirePin && locked) {
      // PIN-require option ON + currently locked. Resume right after PIN unlock.
      ref.listen<bool>(isLockedProvider, (prev, next) {
        if (!next && _pendingVoipNonce == null) {
          // isLocked true→false transition + no other resume already pending
          Future.microtask(() => _doVoipResume(ref, nonce));
        }
      });
      return;
    }

    // Default: resume immediately. Defer via micro-task — async runs
    // outside the ctor and ensures providers like callSignalingProvider
    // are ready.
    Future.microtask(() => _doVoipResume(ref, nonce));
  }

  Future<void> _doVoipResume(Ref ref, String nonce) async {
    try {
      final relay = ref.read(settingsProvider).callAlwaysRelay;
      await acceptPendingVoipCall(
        nonce: nonce,
        localAlwaysRelay: relay,
      );
    } catch (e) {
      debugPrint('[CallNotifier] pending nonce resume failed: ${e.runtimeType}');
    }
  }

  final CallService _callService;
  final CallKitManager? _callKitManager;
  /// V1.0.1: Riverpod ref for dao access (missed call system message insert).
  /// nullable — for _IdleCallNotifier compatibility (idle dummy is created
  /// without a ref).
  final Ref? _ref;
  late final StreamSubscription<CallServiceEvent> _serviceSub;
  late final StreamSubscription<CallSasEvent> _sasSub;
  StreamSubscription<CallKitEvent>? _callKitSub;
  // _elapsedTimer / _activeSince removed (2026-04-19) — replaced by callStartedAt.

  /// V1.0.1: per-peer 60s rate limit on missed-call system messages
  /// (in-memory only, no persistence — per call/CLAUDE.md §2.2 policy).
  final Map<String, DateTime> _lastMissedByPeer = <String, DateTime>{};

  /// Phase I (§25): flag set while FCM Voice Push pending resume is in progress.
  ///
  /// When `acceptPendingVoipCall` injects the envelope, CallService emits
  /// `handleRemote(call_invite)` → `_emit(incoming)`. At that point the
  /// `_onServiceEvent(incoming)` branch tries to raise **another CallKit
  /// (socket-path one, real caller name)**, but the FCM-path "SnowChat
  /// Call" CallKit is already alive (user Accepted), so we'd see duplicate
  /// UI. While this flag is true, the socket-path CallKit display is
  /// suppressed. Cleared after acceptCall completes.
  bool _voipResumeInProgress = false;

  void _onSasEvent(CallSasEvent event) {
    state = state.copyWith(sas: event.sas);
  }

  /// Start a new call. Only allowed in `idle` state.
  ///
  /// [remoteDisplayName]: peer nickname — for caller UI display
  /// [senderDisplayName]: own nickname — attached to call_invite payload, used for callee UI display
  Future<void> startCall({
    required String recipientSnowchatId,
    required bool alwaysRelay,
    String? remoteDisplayName,
    String? senderDisplayName,
  }) async {
    if (state.status != CallStatus.idle) {
      throw StateError('Already in a call');
    }
    // Optimistic UI — status transitions immediately; callId is created by CallService
    state = CallState(
      status: CallStatus.outgoing,
      remoteSnowchatId: recipientSnowchatId,
      remoteDisplayName: remoteDisplayName,
      alwaysRelay: alwaysRelay,
    );
    try {
      await _callService.startCall(
        recipientSnowchatId: recipientSnowchatId,
        alwaysRelay: alwaysRelay,
        senderDisplayName: senderDisplayName,
      );
    } catch (_) {
      // Rollback state on failure — so next attempt isn't stuck on
      // 'Bad state: already in a call'. If CallService later emits idle
      // via event, that path takes precedence (race-safe).
      if (state.status == CallStatus.outgoing) {
        state = const CallState.idle();
      }
      rethrow;
    }
  }

  /// Accept incoming call. `localAlwaysRelay` is the user setting.
  Future<void> acceptCall({required bool localAlwaysRelay}) async {
    if (state.status != CallStatus.incoming) return;
    try {
      await _callService.acceptCall(localAlwaysRelay: localAlwaysRelay);
    } catch (_) {
      // Rollback to idle on accept failure (prevents getting stuck in incoming).
      if (state.status == CallStatus.incoming) {
        state = const CallState.idle();
      }
      rethrow;
    }
  }

  Future<void> declineCall({String reason = 'declined'}) async {
    if (state.status != CallStatus.incoming) return;
    await _callService.declineCall(reason: reason);
  }

  Future<void> endCall() async {
    debugPrint('[DIAG:CallNotifier] endCall ENTER status=${state.status}');
    if (state.status == CallStatus.idle) {
      debugPrint('[DIAG:CallNotifier] endCall — already idle, ignored');
      return;
    }
    final sw = Stopwatch()..start();
    await _callService.endCall();
    debugPrint('[DIAG:CallNotifier] endCall EXIT ${sw.elapsedMilliseconds}ms');
  }

  void toggleMute() {
    debugPrint('[DIAG:CallNotifier] toggleMute ENTER currentMuted=${state.isMuted}');
    _callService.toggleMute();
    state = state.copyWith(isMuted: _callService.isMuted);
    debugPrint('[DIAG:CallNotifier] toggleMute EXIT newMuted=${state.isMuted}');
  }

  Future<void> toggleSpeaker() async {
    debugPrint('[DIAG:CallNotifier] toggleSpeaker ENTER currentSpeaker=${state.isSpeakerOn}');
    await _callService.toggleSpeaker();
    state = state.copyWith(isSpeakerOn: _callService.isSpeakerOn);
    debugPrint('[DIAG:CallNotifier] toggleSpeaker EXIT newSpeaker=${state.isSpeakerOn}');
  }

  // ---------------------------------------------------------------------------
  // Service event → state reflection
  // ---------------------------------------------------------------------------

  void _onServiceEvent(CallServiceEvent event) {
    // [DIAG-VOIP-2026-04-19] tracks CallService → CallNotifier transitions. Remove after diagnosis.
    debugPrint('[DIAG:CallNotifier] _onServiceEvent serviceStatus=${event.status} '
        'callId=${event.callId} prevState=${state.status}');
    switch (event.status) {
      case CallServiceStatus.idle:
        state = const CallState.idle();
        break;

      case CallServiceStatus.outgoing:
        state = state.copyWith(
          status: CallStatus.outgoing,
          callId: event.callId,
          remoteSnowchatId: event.remoteSnowchatId,
        );
        break;

      case CallServiceStatus.incoming:
        state = CallState(
          status: CallStatus.incoming,
          callId: event.callId,
          remoteSnowchatId: event.remoteSnowchatId,
          // displayName is extracted from call_invite payload's senderDisplayName,
          // stored in CallService._remoteDisplayName, then passed via event.remoteDisplayName.
          remoteDisplayName: event.remoteDisplayName,
        );
        // Phase E-1: show system incoming UI (visible even in
        // background / locked state).
        // [2026-04-19] iOS CallKit native impl hangs the main UI thread
        // in environments without an Apple Developer cert (confirmed —
        // same root cause as endCall).
        // On iOS, only in-app IncomingCallScreen is used — router
        // auto-nav pushes /call on status=incoming.
        //
        // Phase I (§25): if FCM pending resume is in progress, the
        // "SnowChat Call" CallKit (nonce id) is already alive in the
        // user-Accepted state. If the socket path raises a new CallKit
        // simultaneously we get duplicate UI and OS re-launch, causing
        // the "back to lockscreen" symptom (Image 8/9). Skip socket-path
        // CallKit while resume is in progress.
        final cm = _callKitManager;
        final cid = event.callId;
        final snowId = event.remoteSnowchatId;
        if (!_voipResumeInProgress &&
            cm != null &&
            cid != null &&
            snowId != null &&
            Platform.isAndroid) {
          // Prefer displayName — used by system Toast (Galaxy).
          // Fallback to first 12 chars of snow ID if missing.
          final caller = event.remoteDisplayName ??
              (snowId.length > 12 ? snowId.substring(0, 12) : snowId);
          unawaited(cm.showIncoming(
            callId: cid,
            callerName: caller,
            handle: caller,
          ));
        }
        break;

      case CallServiceStatus.connecting:
        state = state.copyWith(
          status: CallStatus.connecting,
          callId: event.callId,
          remoteSnowchatId: event.remoteSnowchatId,
        );
        break;

      case CallServiceStatus.active:
        state = state.copyWith(
          status: CallStatus.active,
          callStartedAt: DateTime.now(),
        );
        break;

      case CallServiceStatus.ended:
        debugPrint('[DIAG:CallNotifier] ended case ENTER');
        // V1.0.1: missed-call system message (callee side only, timeout limited).
        // Capture prev before state is .copyWith'd to .ended.
        final prevStatus = state.status;
        final prevPeer = state.remoteSnowchatId;
        final prevPeerName = state.remoteDisplayName;
        // Phase E-1: dismiss system UI (if any).
        // [2026-04-19] iOS CallKit endCall blocks the native UI thread
        // for 30s+ in environments without an Apple Developer cert — the
        // actual root cause of the whole-app freeze after pressing the
        // end button (confirmed via iPhone Console diagnosis).
        // Same context as PushKit (Phase E-2) — iOS-side CallKit system
        // integration is permanently deferred. Only Android (ConnectionService
        // Self-Managed) calls dismiss.
        final endingCallId = state.callId ?? event.callId;
        if (endingCallId != null && Platform.isAndroid) {
          debugPrint('[DIAG:CallNotifier] calling callKitManager.endCall callId=$endingCallId');
          unawaited(() async {
            try {
              await _callKitManager?.endCall(endingCallId);
            } catch (_) {/* ignore */}
          }());
        }
        // V1.0.1: trigger missed-call system message.
        // Condition: callee was in incoming state and call ended for any
        // reason other than self-decline (declined) = a missed call.
        //  - timeout: ConnectionService 60s ringer auto-terminate
        //  - ended:   caller hung up within 60s (most common in practice)
        //  - busy/failed/offline: system reasons preventing pickup
        //  - declined: user pressed decline → already aware, no message
        if (prevStatus == CallStatus.incoming &&
            event.endedReason != 'declined' &&
            prevPeer != null) {
          _maybeInsertMissedCallMessage(prevPeer, prevPeerName);
        }
        // Phase I follow-up (2026-04-21) — caller-side busy/offline system message.
        // UX observation: users hold the phone to their ear during outgoing
        // calls and can't see the screen. Record busy/offline results in
        // the chat so they can be checked later.
        // (other reasons — ended/declined/timeout/failed — are excluded
        // to avoid chat clutter. busy/offline carry the highest info value.)
        if ((prevStatus == CallStatus.outgoing ||
                prevStatus == CallStatus.connecting) &&
            (event.endedReason == 'busy' ||
                event.endedReason == 'offline') &&
            prevPeer != null) {
          _maybeInsertOutgoingCallResultMessage(
            prevPeer,
            prevPeerName,
            event.endedReason!,
          );
        }
        // Briefly publish ended state (2-3s for UI toast)
        state = state.copyWith(
          status: CallStatus.ended,
          endedReason: event.endedReason,
        );
        debugPrint('[DIAG:CallNotifier] ended state set');
        // Return to idle — terminated-call metadata must not be persisted (§23.4.5)
        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          if (state.status == CallStatus.ended) {
            state = const CallState.idle();
          }
        });
        break;
    }
  }

  /// Phase I (§25): FCM Voice Push nonce regex — 32-byte random base64url = 43 chars.
  /// Mirrors server `routes/calls.ts` / `PushNotificationService.sendVoipIncomingCall`.
  static final _voipNoncePattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  /// Phase E-1: handle user actions from system UI (lockscreen / notification panel).
  /// Routes accept/decline/timeout/callback raised by CallKit into the
  /// main state machine. By policy, localAlwaysRelay must be read from
  /// settings at the call site, so the default here is false — system
  /// UI accept is an emergency fast-path, which is acceptable. If the
  /// user has always-relay turned on in settings, the main acceptCall
  /// preserves it via OR.
  void _onCallKitEvent(CallKitEvent event) {
    // [DIAG-VOIP-2026-04-19] tracks CallKit event routing. Remove after diagnosis.
    debugPrint('[DIAG:CallNotifier] _onCallKitEvent action=${event.action} '
        'eventCallId=${event.callId} stateCallId=${state.callId} '
        'status=${state.status}');

    // Phase I (§25): FCM pending path — state is idle and callId matches
    // the nonce pattern.
    // Background isolate → CallKit shown → user Accept → MainActivity
    // wake → Flutter main isolate resume → `FlutterCallkitIncoming.onEvent`
    // emit → CallKitManager → this handler. App state is idle here (just
    // restarted).
    if (state.status == CallStatus.idle &&
        _voipNoncePattern.hasMatch(event.callId)) {
      final ref = _ref;
      // Check whether SealedSender/CallSignaling is initialized — in PIN
      // locked state callSignalingProvider is null so decrypt fails.
      final signaling = ref?.read(callSignalingProvider);

      switch (event.action) {
        case CallKitAction.accept:
          if (ref == null || signaling == null) {
            // _IdleCallNotifier or SealedSender not initialized (PIN locked).
            // Stash nonce in static + keep CallKit UI (no dismiss).
            // User unlocks PIN → SealedSender init → callProvider rebuild →
            // real CallNotifier ctor resumes the pending nonce (see ctor).
            debugPrint('[CallNotifier] CallKit accept during idle notifier — '
                'deferring nonce until SealedSender init');
            CallNotifier.rememberPendingNonce(event.callId);
            return;
          }
          final relay = ref.read(settingsProvider).callAlwaysRelay;
          unawaited(acceptPendingVoipCall(
            nonce: event.callId,
            localAlwaysRelay: relay,
          ));
          return;
        case CallKitAction.decline:
        case CallKitAction.timeout:
          // Cannot send call_end without an envelope — caller is not
          // identifiable (Sealed Sender). Just dismiss CallKit. Caller
          // auto-ends via its own 30s outgoing timeout.
          unawaited(_callKitManager?.endCall(event.callId));
          // Clear any pending nonce (user explicitly declined).
          CallNotifier._pendingVoipNonce = null;
          return;
        case CallKitAction.callback:
          return; // app foreground only, no extra action
      }
    }

    if (state.callId != event.callId) {
      debugPrint('[DIAG:CallNotifier] stale event guard fired — ignored');
      return;
    }
    switch (event.action) {
      case CallKitAction.accept:
        debugPrint('[DIAG:CallNotifier] accept → acceptCall()');
        if (state.status == CallStatus.incoming) {
          unawaited(acceptCall(localAlwaysRelay: state.alwaysRelay));
        }
        break;
      case CallKitAction.decline:
        if (state.status == CallStatus.incoming) {
          unawaited(declineCall());
        } else if (state.status != CallStatus.idle) {
          unawaited(endCall());
        }
        break;
      case CallKitAction.timeout:
        if (state.status == CallStatus.incoming) {
          // V1.0.1: declineCall with reason='timeout' → CallNotifier's
          // ended case triggers missed-call system message insert
          // (callee side, 5min TTL).
          unawaited(declineCall(reason: 'timeout'));
        }
        break;
      case CallKitAction.callback:
        // User came back to app via system notification tap — UI auto-
        // navigates to /call route, no extra action needed.
        break;
    }
  }

  /// Phase I (Phase 8.2 §25): accept the FCM Voice Push pending path.
  ///
  /// Background isolate shows CallKit incoming UI → user Accept →
  /// MainActivity wake → this method is called. If the app was killed,
  /// this is right after Riverpod / auth session restore finished.
  ///
  /// Order:
  ///  1. `/api/v2/calls/pending/:nonce` GET — one-shot fetch of sealed
  ///     envelope (atomic via server Redis MULTI GET+DEL → duplicate
  ///     fetch returns 410).
  ///  2. `CallSignaling.injectEnvelope(envelope)` — same unseal + DR
  ///     decrypt + dispatch as the existing socket path. CallService
  ///     handles the inner `call_invite`, emitting `CallServiceStatus.incoming`,
  ///     which moves this Notifier to `CallStatus.incoming`.
  ///  3. `acceptCall(localAlwaysRelay)` call — reuses the existing accept path.
  ///
  /// On failure (410 expired / network / decrypt / CallService not init):
  ///  - dismiss CallKit + return to idle.
  ///  - error metadata is not logged (§23 Zero-Trace).
  Future<void> acceptPendingVoipCall({
    required String nonce,
    required bool localAlwaysRelay,
  }) async {
    final ref = _ref;
    if (ref == null) {
      // _IdleCallNotifier — unreachable on the normal path (provider not ready).
      unawaited(_callKitManager?.endCall(nonce));
      return;
    }

    _voipResumeInProgress = true;
    try {
      // Step 1: fetch pending envelope list (one-shot, atomic Redis
      // LRANGE+DEL). One call consists of consecutive signaling events
      // (call_invite → rtc_offer → ICE...), all accumulated under the
      // same nonce by the server. Client processes them in order.
      final ApiClient apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/calls/pending/$nonce',
      );
      final envelopesRaw = response.data?['envelopes'];
      final envelopes = envelopesRaw is List
          ? envelopesRaw.whereType<String>().where((e) => e.isNotEmpty).toList()
          : <String>[];
      if (envelopes.isEmpty) {
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }

      // Step 2: inject in order — first = call_invite → state=incoming,
      // subsequent = rtc_offer → CallService._pendingOffer buffer, ICE, etc.
      final signaling = ref.read(callSignalingProvider);
      if (signaling == null) {
        // SealedSender not initialized — decrypt impossible → dismiss.
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }
      for (final envelope in envelopes) {
        await signaling.injectEnvelope(envelope);
      }

      // Step 3: if call_invite was processed, state should be incoming.
      if (state.status != CallStatus.incoming) {
        unawaited(_callKitManager?.endCall(nonce));
        if (state.status != CallStatus.idle) {
          state = const CallState.idle();
        }
        return;
      }

      await acceptCall(localAlwaysRelay: localAlwaysRelay);
    } catch (_) {
      // Silent on structural errors only — call metadata must not be logged (§23.4.3).
      unawaited(_callKitManager?.endCall(nonce));
      if (state.status != CallStatus.idle) {
        state = const CallState.idle();
      }
    } finally {
      _voipResumeInProgress = false;
    }
  }

  /// V1.0.1: callee-side missed-call system message insert.
  ///
  /// call/CLAUDE.md §2.2 limited-notification policy:
  ///  - 5min forced TTL (ignores conversation disappearing setting)
  ///  - 60s per-peer rate limit (in-memory map, no persistence)
  ///  - skip if no existing 1:1 conversation (V1.x may add auto-create)
  ///  - reuses the existing system_message_bubble infrastructure
  void _maybeInsertMissedCallMessage(String peerSnowId, String? peerName) {
    final ref = _ref;
    if (ref == null) return; // _IdleCallNotifier — no dao access
    final now = DateTime.now();
    final last = _lastMissedByPeer[peerSnowId];
    if (last != null &&
        now.difference(last) < const Duration(seconds: 60)) {
      debugPrint('[CallNotifier] missed call dedupe — peer=$peerSnowId within 60s');
      return;
    }
    _lastMissedByPeer[peerSnowId] = now;

    unawaited(() async {
      try {
        final convDao = ref.read(conversationDaoProvider);
        final conv = await convDao.findDirectByParticipant(peerSnowId);
        if (conv == null) {
          debugPrint('[CallNotifier] no 1:1 conversation with $peerSnowId — skip missed call message (V1.0.1)');
          return;
        }
        final caller = (peerName != null && peerName.isNotEmpty)
            ? peerName
            : (peerSnowId.length > 12
                ? peerSnowId.substring(0, 12)
                : peerSnowId);
        final time =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        final text = 'Missed voice call from $caller · $time';

        await ref.read(messageDaoProvider).insertLocalSystemMessage(
              conversationId: conv.id,
              text: text,
              eventType: 'missed_voice_call',
              metadata: {
                'callerSnowchatId': peerSnowId,
                // Store insert time for UI countdown (Auto-deletes in mm:ss).
                // 5min from now = insertedAtMs + 300_000.
                'insertedAtMs': now.millisecondsSinceEpoch,
              },
              expiresInSeconds: 300, // 5min forced TTL
            );
        debugPrint('[CallNotifier] inserted missed call system message convId=${conv.id}');
      } catch (e) {
        debugPrint('[CallNotifier] missed call insert failed: $e');
      }
    }());
  }

  /// Phase I follow-up (2026-04-21): caller-side busy/offline result system message.
  ///
  /// Users often hold the phone to their ear during outgoing calls and
  /// can't see the screen — augment with audio feedback (busy tone) +
  /// chat record. Mirror structure of `_maybeInsertMissedCallMessage` —
  /// reuses the existing missed-call infra / dedup map / bubble widget.
  ///
  /// Policy:
  ///  - 5min forced TTL (same)
  ///  - 60s per-peer dedup (same map, distinguished by `"outgoing_"` prefix key)
  ///  - skip if no 1:1 conversation
  ///  - reason is only 'busy' or 'offline' — caller pre-filters
  void _maybeInsertOutgoingCallResultMessage(
    String peerSnowId,
    String? peerName,
    String reason,
  ) {
    final ref = _ref;
    if (ref == null) return;
    final now = DateTime.now();
    final dedupKey = 'outgoing_$peerSnowId';
    final last = _lastMissedByPeer[dedupKey];
    if (last != null &&
        now.difference(last) < const Duration(seconds: 60)) {
      debugPrint(
          '[CallNotifier] outgoing call result dedupe — peer=$peerSnowId within 60s');
      return;
    }
    _lastMissedByPeer[dedupKey] = now;

    unawaited(() async {
      try {
        final convDao = ref.read(conversationDaoProvider);
        final conv = await convDao.findDirectByParticipant(peerSnowId);
        if (conv == null) return;
        final peer = (peerName != null && peerName.isNotEmpty)
            ? peerName
            : (peerSnowId.length > 12
                ? peerSnowId.substring(0, 12)
                : peerSnowId);
        final time =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        final text = switch (reason) {
          'busy' =>
            'Voice call to $peer — they were on another call · $time',
          'offline' => 'Voice call to $peer — they are offline · $time',
          _ => 'Voice call to $peer · $time',
        };

        await ref.read(messageDaoProvider).insertLocalSystemMessage(
              conversationId: conv.id,
              text: text,
              eventType: 'outgoing_voice_call_$reason',
              metadata: {
                'peerSnowchatId': peerSnowId,
                'reason': reason,
                // Reuse system_message_bubble's countdown ("Auto-deletes
                // in mm:ss") — same metadata key as existing _MissedCallBubble.
                'insertedAtMs': now.millisecondsSinceEpoch,
              },
              expiresInSeconds: 300,
            );
        debugPrint(
            '[CallNotifier] inserted outgoing call $reason message convId=${conv.id}');
      } catch (e) {
        debugPrint('[CallNotifier] outgoing call result insert failed: $e');
      }
    }());
  }

  @override
  void dispose() {
    _serviceSub.cancel();
    _sasSub.cancel();
    _callKitSub?.cancel();
    super.dispose();
  }
}
