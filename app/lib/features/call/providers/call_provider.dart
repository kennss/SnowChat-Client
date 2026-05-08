/// @file        call_provider.dart
/// @description CallNotifier state machine + Riverpod provider (Phase 8.2 §2, §5).
///              Wraps CallService and emits CallState for the UI to subscribe to.
///              Terminated-call metadata is not retained in state (§23 Zero-Trace).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-05-06 (Fix B revised — _onServiceEvent ended branch now
///              recognizes endedReason=='cold_fallback' from CallService and
///              inserts the missed-call message using event.remoteSnowchatId
///              instead of state.remoteSnowchatId. Cold fallback fires when
///              CallService._handleRemoteEnd hits _callId == null (invite was
///              lost in long-idle ratchet desync + call_invite cache exclusion);
///              the standard prevStatus==incoming gate would block the missed-
///              call insert because no _emit(incoming) ever ran. The terminal
///              ended event carries callId/remoteSnowchatId via _emit override
///              params CallService added so the existing endingIds set
///              (alias + state.callId + event.callId + lastShownIncomingId)
///              still finds the right Telecom Connection id for endCall.
///              2026-05-06 (Tier 1 trap surfacing: WARNING log when 410 fires
///              on Android in acceptPendingVoipCall. Android has no native
///              envelope pre-fetcher, so 410 there is always a regression
///              signal — not a benign "parallel native path won" race like
///              iOS PushKit. Behavior unchanged (still yields) to keep risk
///              zero; future regressions will surface in logcat instantly
///              instead of being silent-swallowed like the 2026-05-06 server
///              dist stale incident). 2026-05-05 (Z-5 §2.6.2: _NonceAliasMap.allKnownIds() + endCall
///              broadcast to all alias UUIDs at ended-event handling. Galaxy
///              21:04:47 logcat surfaced TC@222 ON_HOLD zombie surviving 7m
///              after endCall — root cause: BG isolate registered Telecom
///              Connection with FCM nonce id while main isolate registered
///              another with envelope callId, and only one received the
///              dispatch when the call ended. Z-1~3 (server callId echo) +
///              Z-4 (voip_push_handler unifiedId) make both paths share id
///              up-front so fork's same-id dedup gate (line 116-119) silent-
///              skips the second showCallkitIncoming. Z-5 here is the layered
///              defense: when ended fires, fan endCall out to every id we
///              ever bound — alias map keys + state.callId + event.callId +
///              lastShownIncomingId — so any pre-Z-fix lingering Connection
///              still gets reaped (fork no-ops on unknown ids, so the spray
///              is safe). Earlier 2026-05-05 (+241: declinePending DIAG →
///              diagLog (release-mode logcat). senderHash/callId 첫 8자만
///              노출 — Zero-Trace §2.5 준수). 2026-05-03 (v214: ended case 에 _callKitManager?.
///              clearLastShownIncomingId() 추가. 1차 통화 종료 후
///              CallKitManager._lastShownIncomingId 가 60s TTL 안에
///              잔존 → 다음 통화의 alias auto-register 가 1차 nonce 로
///              잘못 매핑 → endCall 이 stale nonce 로 가고 incoming UI
///              dismiss 도 안 됨. 사용자 매트릭스 "2차 콜 무반응" log
///              에서 alias=8f169adb(1차)↔d6f32d1e(2차) 확인. Earlier
///              v210: outdated cert-era comments cleanup in the
///              CallServiceStatus.incoming branch. The Platform.isAndroid
///              guard is correct (iOS PushKit-native owns the CallKit
///              window) but surrounding notes still said "iOS uses Flutter
///              IncomingCallScreen" which is no longer true once router
///              v210 stops rendering it on iOS. Behavior unchanged. Earlier
///              Phase 8.2 v2.5: cold-launch-from-PushKit alias
///              recovery on accept event. v2.4's `incomingShown` stream listener
///              cannot fix the case where plugin's `actionCallIncoming` never
///              reaches Dart (cold-launch fires the event before FlutterEngine
///              isolate is wired; replay only covers ACCEPT/ACTIVATED, not
///              INCOMING). The alias map is stuck at `nonce → nonce` self-
///              mapping (registered when `acceptPendingVoipCallWithEnvelopes`
///              ran with state.callId=null), so the user's first ACCEPT tap
///              hits the stale guard. v2.5 (a) re-registers the alias inside
///              WithEnvelopes after envelope injection completes (state.callId
///              now holds the real hash), and (b) opportunistically binds the
///              alias inside `_onCallKitEvent` accept case before the stale
///              guard fires, when state.status==incoming AND event.callId is
///              a voip nonce pattern AND alias not bound. Earlier 2026-05-02
///              (v204 Phase 8.2 v2.1: bidirectional nonce alias —
///              _activeCallKitNonce single value → _NonceAliasMap with bidirectional
///              register + isAliasMatch + 60s TTL. Fixes race A residual where
///              slow-APNs scenario left the alias unregistered when socket
///              envelope arrived first; the new map self-registers on socket
///              path too. Also calls CallService.prepareAudioSessionAwaiter()
///              right after actionCallAccept to avoid Completer-creation race
///              with CallKit's didActivate firing. Earlier v198 (2026-05-01):
///              (a) Stale-event guard now treats _activeCallKitNonce as a
///              valid alias for state.callId — push-path CallKit UI is keyed
///              by the server nonce (UUID-36), but CallService's internal
///              callId is the hash from the decrypted call_invite envelope,
///              so local CallKit End fired event.callId == nonce and the
///              guard silently rejected it. Field-confirmed via TestFlight
///              v197: Android→iOS call connected, iOS End button dropped,
///              call only terminated when remote hung up.
///              (b) ended-case dismiss now runs on iOS too (was Android-only
///              under the pre-Apple-Dev-cert workaround) and uses
///              _activeCallKitNonce when set, so push-path CallKit windows
///              are dismissed on remote-end / in-app End. Cert obtained
///              2026-04-29 with PushKit activation, so the 2026-04-19
///              "endCall blocks UI thread 30s+" symptom is gone.
///              Earlier 2026-04-29 (v197): sync broadcast streams + post-inject
///              sentinel close iOS Accept race. Earlier (v196): read
///              _callService.status not state.status in accept guards. Earlier
///              (v195): race guard between native CallAcceptCoordinator and
///              Dart _onCallKitEvent — 410 → softCleanup, no endAllCalls.
///              Earlier 2026-04-30 (Phase E-2 v3.1):
///              acceptPendingVoipCallWithEnvelopes hot path + isAccepted
///              recovery + WidgetsBindingObserver resume re-run.)
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
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../app/providers.dart';
import '../../../core/call/call_service.dart';
import '../../../core/call/callkit_manager.dart';
import '../../../core/diagnostics/diag_log.dart';
import '../../../core/network/api_client.dart';
import '../../settings/settings_provider.dart';

/// Phase 8.2 v2.1 (v204) — Bidirectional nonce alias map.
///
/// Replaces the v198 single-value `_activeCallKitNonce`. The previous design
/// only mapped `pushKitNonce → state.callId`, so when socket envelope arrived
/// before PushKit (slow APNs scenario, ~5–10% of cases) the alias never got
/// registered, and the stale guard rejected CallKit's `actionCallAccept`
/// fired with the PushKit nonce. The bidirectional map covers both directions.
///
/// Lifecycle:
///   - `register(nonce, callId)` on PushKit envelope receipt OR on Dart
///     state.callId assignment (whichever happens first).
///   - `isAliasMatch(eventId, stateId)` checks all 4 directions:
///     identical / nonce→callId / callId→nonce / either→either via reverse map.
///   - 60s TTL Timer per entry — covers the ringing window. Calls > 60s drop
///     the alias but at that point the call is already accepted and `state.callId`
///     identifies the call; alias is no longer needed.
///   - `clear()` on cleanup paths (idle / ended) — wipes all entries.
class _NonceAliasMap {
  final Map<String, String> _nonceToCallId = {};
  final Map<String, String> _callIdToNonce = {};
  final Map<String, Timer> _ttlTimers = {};

  /// Register a bidirectional alias between [pushKitNonce] and [envelopeCallId].
  /// Idempotent — re-registration with the same pair refreshes the TTL.
  /// If [envelopeCallId] is null, registers a self-mapping (nonce → nonce);
  /// later when the real callId is known, register again.
  void register(String pushKitNonce, String? envelopeCallId) {
    final callId = envelopeCallId ?? pushKitNonce;
    _nonceToCallId[pushKitNonce] = callId;
    _callIdToNonce[callId] = pushKitNonce;

    _ttlTimers[pushKitNonce]?.cancel();
    _ttlTimers[pushKitNonce] = Timer(const Duration(seconds: 60), () {
      _nonceToCallId.remove(pushKitNonce);
      _callIdToNonce.remove(callId);
      _ttlTimers.remove(pushKitNonce);
    });
  }

  /// Check whether [eventId] and [stateId] refer to the same call via any
  /// alias direction. Used by the stale-event guard in `_onCallKitEvent`.
  bool isAliasMatch(String eventId, String? stateId) {
    if (stateId == null) return false;
    if (eventId == stateId) return true;
    if (_nonceToCallId[eventId] == stateId) return true;
    if (_callIdToNonce[eventId] == stateId) return true;
    if (_nonceToCallId[stateId] == eventId) return true;
    if (_callIdToNonce[stateId] == eventId) return true;
    return false;
  }

  /// Look up the PushKit nonce associated with the given internal callId.
  /// Used for `endCall(nonce)` to dismiss CallKit windows raised via push.
  String? nonceForCallId(String? callId) {
    if (callId == null) return null;
    return _callIdToNonce[callId];
  }

  /// Z-5 defense-in-depth (2026-05-05) — return every UUID that Telecom may
  /// have registered a Connection for via either side of an alias pair.
  /// Used by the endCall path to broadcast dismissal to all known ids so a
  /// pre-Z-fix server (still allocating distinct nonce vs envelope callId)
  /// or a cold-launch race (alias not yet bound when one path fired) can't
  /// leave a zombie Connection in Telecom (Galaxy 21:04:47 TC@222 case).
  Set<String> allKnownIds() {
    final ids = <String>{};
    ids.addAll(_nonceToCallId.keys);
    ids.addAll(_callIdToNonce.keys);
    return ids;
  }

  /// Wipe all entries. Called on cleanup paths.
  void clear() {
    _nonceToCallId.clear();
    _callIdToNonce.clear();
    for (final t in _ttlTimers.values) {
      t.cancel();
    }
    _ttlTimers.clear();
  }
}

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

class CallNotifier extends StateNotifier<CallState> with WidgetsBindingObserver {
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
      // Phase 8.2 v2.2 — bridge CallKit's audio session activation into
      // CallService. CallKitManager owns the plugin EventChannel exclusively;
      // we forward the broadcast so CallService's Completer fires.
      _audioActivatedSub = ckm.audioSessionActivated.listen((_) {
        _callService.notifyAudioSessionActivatedFromCallKit();
      });
      // Phase 8.2 v2.4 — register alias when actionCallIncoming arrives AFTER
      // _onServiceEvent(incoming). PushKit ordering: envelope decrypt path can
      // beat the plugin's UI dispatch, so the synchronous lookup at incoming-
      // state time misses it. This listener catches the late notification.
      // Idempotent vs the synchronous path in `_onServiceEvent(incoming)`.
      _incomingShownSub = ckm.incomingShown.listen((nonce) {
        final cid = state.callId;
        if (cid != null && cid != nonce && !_aliasMap.isAliasMatch(nonce, cid)) {
          _aliasMap.register(nonce, cid);
          debugPrint('[DIAG:CallNotifier] late-bound alias on incomingShown: '
              'nonce=$nonce ↔ callId=$cid');
        }
      });
      // Phase 8.2 v2.2 — recover any ACCEPT / ACTIVATED events that the plugin
      // tried to send while the FlutterEngine isolate was paused or before this
      // listener attached. Plugin caches them for 5s; idempotent if there was
      // nothing to replay. Fire-and-forget.
      unawaited(ckm.replayPendingFromBackground());
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
    diagLog(
      'callNotifierCtor',
      'enter ref=${ref != null} pendingNonce=${pending != null}',
    );
    if (pending != null && ref != null) {
      _pendingVoipNonce = null;
      diagLog('callNotifierCtor', 'consume pending → _scheduleVoipResume');
      _scheduleVoipResume(ref, pending);
    } else if (ref != null) {
      // Defer via micro-task — async activeCalls() lookup outside ctor.
      diagLog(
        'callNotifierCtor',
        'no pending → schedule _recoverAcceptedCallFromCallKit',
      );
      Future.microtask(() => _recoverAcceptedCallFromCallKit(ref));
    }

    // [2026-05-05] Cold-launch DECLINE recovery — Android only.
    //
    // The fork-patched flutter_callkit_incoming (CallkitIncomingBroadcastReceiver
    // ACTION_CALL_DECLINE branch) persists the declined nonce in
    // SharedPreferences and launches MainActivity when CallKit was raised
    // by a BG FCM handler. Without this consumer, the cold-launch DECLINE
    // path drops the event (no Dart onEvent listener on BG engine, MAIN
    // engine never started by the original plugin behavior). Caller stays
    // in outgoing 30s. With this consumer, declinePendingVoipCall fires
    // within ~1s of MainActivity boot → call_end reaches caller via
    // sealed_call_signaling.
    if (ref != null) {
      Future.microtask(() => _consumePendingVoipDecline());
    }

    // Phase E-2 #4 (2026-04-30): wake-from-suspended recovery.
    //
    // PushKit fires while app is suspended → CallKit shown on lock screen
    // → user accepts → plugin sends ACTION_CALL_ACCEPT to EventChannel.
    // Flutter engine is paused at that instant, so the broadcast event
    // never reaches our CallKitManager listener — even though both ends
    // exist. By the time the engine resumes, the event is gone.
    //
    // The plugin's persistent activeCalls() still contains the entry
    // with isAccepted=true. Re-run the same cold-start recovery on
    // every resume so the next /calls/pending fetch picks it up.
    //
    // Only registers when ref != null (real CallNotifier — _IdleCallNotifier
    // has no ref to drive acceptPendingVoipCall anyway).
    if (ref != null) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed) return;
    final ref = _ref;
    if (ref == null) return;
    // Phase 8.2 v2.2 — every BG→FG resume, ask the plugin to replay any
    // ACCEPT / ACTIVATED events whose sendEvent silently dropped because the
    // sink was nil at fire time. 5s window inside the plugin; older entries
    // are cleared. Idempotent if there's nothing to replay.
    final ckm = _callKitManager;
    if (ckm != null) {
      unawaited(ckm.replayPendingFromBackground());
    }
    // Skip when already in a call — we'd already have routed via the
    // socket / state path. Recovery is for the silent-event-loss case.
    if (state.status != CallStatus.idle) return;
    Future.microtask(() => _recoverAcceptedCallFromCallKit(ref));
  }

  /// Phase I (§25) cold-start recovery: query the active-calls list that
  /// flutter_callkit_incoming keeps in internal storage, find an entry
  /// with `accepted=true` matching the nonce pattern, and resume. Recovers
  /// the case where the Accept event was emitted before Flutter engine
  /// boot and never reached the in-memory listener.
  Future<void> _recoverAcceptedCallFromCallKit(Ref ref) async {
    diagLog('coldRecover', 'enter _recoverAcceptedCallFromCallKit');
    try {
      final result = await FlutterCallkitIncoming.activeCalls();
      if (result is! List || result.isEmpty) {
        diagLog(
          'coldRecover',
          'activeCalls empty (type=${result.runtimeType})',
        );
        return;
      }
      diagLog('coldRecover', 'activeCalls returned ${result.length} entries');

      // Per-entry inspection for cold-launch race diagnosis.
      for (final entry in result) {
        if (entry is! Map) continue;
        final entryId = entry['id'];
        final shortEntryId = (entryId is String && entryId.length >= 8)
            ? entryId.substring(0, 8)
            : '$entryId';
        diagLog(
          'coldRecover',
          'entry id=$shortEntryId accepted=${entry['accepted']} '
              'isAccepted=${entry['isAccepted']} '
              'noncePat=${entryId is String && _voipNoncePattern.hasMatch(entryId)}',
        );
      }

      final matches = <String>[];
      for (final entry in result) {
        if (entry is! Map) continue;
        final id = entry['id'];
        // Plugin reports two distinct accept-state flags:
        //   - `accepted`  = Call.hasConnected (only flips after we ourselves
        //                   call reportConnectedCall — so it's false for an
        //                   incoming call the user just answered via CallKit;
        //                   the very state we're trying to recover here).
        //   - `isAccepted` = Data.isAccepted, set to true inside the plugin's
        //                   CXAnswerCallAction handler the moment the user
        //                   slides accept on the lock-screen UI.
        // We need either: hasConnected fires for a hot-restart that already
        // wired the call through; isAccepted fires for the cold-launch path
        // where this whole recovery exists.
        final accepted = entry['accepted'] == true;
        final isAccepted = entry['isAccepted'] == true;
        if (id is String &&
            (accepted || isAccepted) &&
            _voipNoncePattern.hasMatch(id)) {
          matches.add(id);
        }
      }

      if (matches.isEmpty) {
        diagLog('coldRecover', 'no accepted voip nonce match — return');
        return;
      }
      diagLog('coldRecover', 'matched ${matches.length} accepted nonce(s)');

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

      final shortPrimary =
          primary.length >= 8 ? primary.substring(0, 8) : primary;
      diagLog(
        'coldRecover',
        'recovered primary=$shortPrimary → _scheduleVoipResume',
      );
      _scheduleVoipResume(ref, primary);
    } catch (e) {
      diagLog('coldRecover', 'activeCalls failed: ${e.runtimeType}');
    }
  }

  /// [2026-05-05] Cold-launch DECLINE consumer (Android-only).
  ///
  /// The fork-patched `flutter_callkit_incoming` writes the declined nonce
  /// into Android SharedPreferences and starts MainActivity when the BG
  /// FCM isolate raised CallKit and there is no MAIN engine listener for
  /// the broadcast `sendEventFlutter(ACTION_CALL_DECLINE)`. This consumer
  /// runs once on CallNotifier construction (cold launch path), reads the
  /// nonce via `snowchat/voip_decline_recovery::consumePending`, and fires
  /// `declinePendingVoipCall` so call_end reaches the caller via the
  /// sealed_call_signaling socket. iOS is no-op (PushKit cold-launch
  /// decline has its own architectural fix tracked separately).
  Future<void> _consumePendingVoipDecline() async {
    if (!Platform.isAndroid) return;
    const channel = MethodChannel('snowchat/voip_decline_recovery');
    try {
      final pendingNonce = await channel.invokeMethod<String?>('consumePending');
      if (pendingNonce == null || pendingNonce.isEmpty) {
        diagLog('declineRecovery', 'consumePending returned null — no pending');
        return;
      }
      if (!_voipNoncePattern.hasMatch(pendingNonce)) {
        diagLog('declineRecovery',
            'nonce malformed (len=${pendingNonce.length}) — skip');
        return;
      }
      diagLog('declineRecovery',
          'nonce=${pendingNonce.substring(0, 8)} → declinePendingVoipCall');
      await declinePendingVoipCall(
        nonce: pendingNonce,
        reason: 'declined',
      );
    } catch (e) {
      diagLog('declineRecovery', 'channel error: ${e.runtimeType}');
    }
  }

  /// Phase I (§25): schedule pending nonce resume — runs immediately or
  /// waits for PIN unlock, depending on the callRequirePin option.
  void _scheduleVoipResume(Ref ref, String nonce) {
    final requirePin = ref.read(settingsProvider).callRequirePin;
    final locked = ref.read(isLockedProvider);
    final shortNonce = nonce.length >= 8 ? nonce.substring(0, 8) : nonce;
    diagLog(
      'voipResume',
      'schedule nonce=$shortNonce requirePin=$requirePin locked=$locked',
    );

    if (requirePin && locked) {
      // PIN-require option ON + currently locked. Resume right after PIN unlock.
      diagLog('voipResume', 'wait for PIN unlock — register isLocked listen');
      ref.listen<bool>(isLockedProvider, (prev, next) {
        diagLog(
          'voipResume',
          'isLocked transition $prev→$next pendingNonce=${_pendingVoipNonce != null}',
        );
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
    final shortNonce = nonce.length >= 8 ? nonce.substring(0, 8) : nonce;
    diagLog('voipResume', 'enter _doVoipResume nonce=$shortNonce');
    try {
      final relay = ref.read(settingsProvider).callAlwaysRelay;
      diagLog('voipResume', 'calling acceptPendingVoipCall relay=$relay');
      await acceptPendingVoipCall(
        nonce: nonce,
        localAlwaysRelay: relay,
      );
      diagLog('voipResume', 'acceptPendingVoipCall returned OK');
    } catch (e, st) {
      diagLog(
        'voipResume',
        'acceptPendingVoipCall FAILED ${e.runtimeType}: $e',
      );
      diagLog('voipResume', 'stack: ${st.toString().split("\n").take(3).join(" | ")}');
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
  StreamSubscription<void>? _audioActivatedSub;
  StreamSubscription<String>? _incomingShownSub;
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

  /// CallKit's transient ID for the active push-path call (= server-issued
  /// nonce). Differs from `state.callId`, which is the internal hash from the
  /// decrypted call_invite envelope. CallKit raises events with the nonce as
  /// the id, so on local End the event arrives with `event.callId == nonce`,
  /// NOT `state.callId`. Tracking this lets the stale-event guard treat the
  /// Phase 8.2 v2.1 (v204) — Bidirectional nonce alias map.
  /// Replaces the v198 single `_activeCallKitNonce` field. See `_NonceAliasMap`
  /// docstring for the rationale (slow-APNs race A residual coverage).
  /// Outgoing / foreground-socket-path calls do not register entries (their
  /// CallKit id IS the internal callId, no aliasing needed).
  final _NonceAliasMap _aliasMap = _NonceAliasMap();

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
        // v204 (2026-05-03): forward callee name so CallService can register
        // the iOS CallKit outbound window with the right display name.
        remoteDisplayName: remoteDisplayName,
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
    // Read CallService.status (synchronous). state.status is stream-delivered
    // so when this is invoked immediately after injectEnvelope, the listener
    // microtask hasn't fired yet and state.status still reads idle even though
    // _callService._status is already incoming. (v195+ race fix.)
    if (_callService.status != CallServiceStatus.incoming) return;
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
        // Defense in depth: CallService currently never _emit(idle) — the
        // terminal emit is `ended`, after which `_status` is reassigned to
        // idle internally. If that ever changes, wipe the alias map here too.
        _aliasMap.clear();
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
        // Phase 8.2 v2.3 — auto-register alias when CallKit incoming UI was
        // already raised by the native PushKit path. PushKit shows CallKit
        // with id=nonce; the envelope-decrypted callId is different. Without
        // this mapping the stale-event guard rejects the user's first ACCEPT
        // tap (eventCallId=nonce, stateCallId=envelope_callId) → "two-tap"
        // bug. acceptPendingVoipCallWithEnvelopes already registers when the
        // native fetch path runs; this branch handles the BG-receive path
        // where envelope arrives via socket / push-then-Dart-decrypt.
        {
          final ckm = _callKitManager;
          final cid = event.callId;
          if (ckm != null && cid != null) {
            final nonce = ckm.lastShownIncomingId;
            if (nonce != null && nonce != cid) {
              _aliasMap.register(nonce, cid);
              debugPrint('[DIAG:CallNotifier] auto-registered alias on '
                  'incoming: nonce=$nonce ↔ callId=$cid');
            }
          }
        }
        // Show the system incoming UI on Android via CallKitManager
        // (which wraps ConnectionService Self-Managed). On iOS the native
        // PushKit path (SwiftFlutterCallkitIncomingPlugin) already raised
        // the CallKit window before this Dart event landed, so we skip
        // the Dart-side showIncoming entirely on iOS — calling it would
        // either duplicate the window or trip iOS 14.5+ "PushKit payload
        // not fulfilled" throttling (field-observed 2026-04-29 revert
        // attempt).
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
        // Phase E-1: dismiss system UI (if any). 2026-05-01 (v198): enabled
        // on iOS too. The 2026-04-19 comment about iOS endCall blocking the
        // UI thread for 30s+ was a pre-Apple-Dev-cert symptom. Cert obtained
        // 2026-04-29 alongside PushKit activation, so dismissing CallKit on
        // iOS is now safe — without this, remote-end leaves the iOS CallKit
        // window stuck on screen until the user taps it manually.
        //
        // Z-5 defense-in-depth (2026-05-05) — collect every UUID that Telecom
        // may have registered a Connection for, then broadcast endCall to all
        // unique ids. Galaxy logcat 2026-05-05 21:04:47 confirmed dual-
        // Connection registration (BG isolate FCM nonce + main isolate socket
        // envelope callId, two distinct UUIDs) → endCall on only one left
        // TC@222 ON_HOLD as a 7-min zombie. Z-fix server-side callId echo
        // (§2.6.2) collapses both ids to the envelope callId for new builds,
        // but this client-side broadcast still fires on:
        //   - rolling deploys (recipient on +251 client, server pre-Z-fix)
        //   - cold-launch races (alias unbound when one path raised CallKit)
        //   - any future regression that re-introduces distinct ids
        // _aliasMap.allKnownIds() returns the union of nonce + callId keys
        // from the bidirectional map. We also add state.callId / event.callId
        // / lastShownIncomingId in case the alias never registered them
        // (e.g. Telecom raised actionCallIncoming after the alias TTL fired).
        // Each unique id gets one endCall — the fork's same-id dedup tolerates
        // unknown ids silently (CallkitConnection.find returns null → return).
        final endingIds = <String>{};
        endingIds.addAll(_aliasMap.allKnownIds());
        if (state.callId != null && state.callId!.isNotEmpty) {
          endingIds.add(state.callId!);
        }
        if (event.callId != null && event.callId!.isNotEmpty) {
          endingIds.add(event.callId!);
        }
        final lastShown = _callKitManager?.lastShownIncomingId;
        if (lastShown != null && lastShown.isNotEmpty) {
          endingIds.add(lastShown);
        }
        // Wipe the alias map before the unawaited dismiss so a late CallKit
        // event after this point sees the stale guard correctly.
        _aliasMap.clear();
        // v214 (2026-05-03): clear CallKitManager._lastShownIncomingId too.
        // 1차 통화 종료 후 60s TTL 안에 잔존하면 다음 통화의 alias auto-
        // register (CallServiceStatus.incoming branch L619-624) 가 stale
        // nonce 를 매핑함. 사용자 매트릭스 "2차 콜 무반응" log 에서
        // alias=8f169adb(1차 nonce) ↔ d6f32d1e(2차 callId) 확인.
        _callKitManager?.clearLastShownIncomingId();
        if (endingIds.isNotEmpty) {
          debugPrint('[DIAG:CallNotifier] calling callKitManager.endCall on '
              '${endingIds.length} alias(es): $endingIds');
          unawaited(() async {
            for (final id in endingIds) {
              try {
                await _callKitManager?.endCall(id);
              } catch (_) {/* ignore — fork no-ops on unknown ids */}
            }
          }());
        }
        // V1.0.1: trigger missed-call system message.
        // Condition: callee was in incoming state and call ended for any
        // reason other than self-decline (declined) = a missed call.
        //  - timeout: ConnectionService 60s ringer auto-terminate
        //  - ended:   caller hung up within 60s (most common in practice)
        //  - busy/failed/offline: system reasons preventing pickup
        //  - declined: user pressed decline → already aware, no message
        //
        // Fix B revised (2026-05-06) — also fire on 'cold_fallback' reason.
        // Cold fallback path means CallService._handleRemoteEnd ran the
        // _callId == null branch — invite was lost (long-idle ratchet desync
        // + call_invite cache exclusion), so prevStatus stayed idle and the
        // standard gate above fails. The fallback path populates event.callId
        // / event.remoteSnowchatId via _emit override so we use those
        // directly here (state.* was never set on this isolate). Same
        // endedReason gate (declined excluded) applies in spirit, but the
        // fallback never carries 'declined' (only 'cold_fallback') so the
        // explicit check is omitted.
        final isColdFallback = event.endedReason == 'cold_fallback';
        if (prevStatus == CallStatus.incoming &&
            event.endedReason != 'declined' &&
            prevPeer != null) {
          _maybeInsertMissedCallMessage(prevPeer, prevPeerName);
        } else if (isColdFallback &&
            event.remoteSnowchatId != null &&
            event.remoteSnowchatId!.isNotEmpty) {
          debugPrint('[DIAG:CallNotifier] cold_fallback missed-call insert '
              'peer=${event.remoteSnowchatId}');
          _maybeInsertMissedCallMessage(
            event.remoteSnowchatId!,
            event.remoteDisplayName,
          );
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

  /// Phase I (§25) + Phase E-2 §28 widened: accept BOTH base64url(43) AND
  /// standard UUID(36 with hyphens). Server switched to `randomUUID()` because
  /// the iOS plugin's UUID(uuidString:) force-unwraps and crashes on base64url
  /// (Phase 8.2 §27 11차). Without widening, `_recoverAcceptedCallFromCallKit`
  /// fails to match CallKit's id (which IS the nonce) on iOS PushKit cold-launch
  /// → `acceptPendingVoipCall` never fires → caller sees endless ringing while
  /// callee's CallKit is "active" but unwired (Phase 8.2 §27 12차/13차).
  static final _voipNoncePattern = RegExp(
    r'^([A-Za-z0-9_-]{43}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$',
  );

  /// Phase E-1: handle user actions from system UI (lockscreen / notification panel).
  /// Routes accept/decline/timeout/callback raised by CallKit into the
  /// main state machine. By policy, localAlwaysRelay must be read from
  /// settings at the call site, so the default here is false — system
  /// UI accept is an emergency fast-path, which is acceptable. If the
  /// user has always-relay turned on in settings, the main acceptCall
  /// preserves it via OR.
  void _onCallKitEvent(CallKitEvent event) {
    // [DIAG-VOIP-2026-05-05 cold-launch trace] release-survive logging via
    // diagLog (MethodChannel → Log.d). Plain debugPrint stripped in release.
    final shortId = event.callId.length >= 8
        ? event.callId.substring(0, 8)
        : event.callId;
    diagLog(
      'callkitEvent',
      'enter action=${event.action} eventCallId=$shortId '
          'stateCallId=${state.callId} status=${state.status} '
          'hasRef=${_ref != null}',
    );

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
            diagLog(
              'callkitEvent',
              'accept stash nonce=$shortId (ref=${ref != null} signaling=${signaling != null})',
            );
            CallNotifier.rememberPendingNonce(event.callId);
            return;
          }
          diagLog('callkitEvent', 'accept hot-path nonce=$shortId');
          final relay = ref.read(settingsProvider).callAlwaysRelay;
          unawaited(acceptPendingVoipCall(
            nonce: event.callId,
            localAlwaysRelay: relay,
          ));
          return;
        case CallKitAction.decline:
        case CallKitAction.timeout:
          // 2026-05-04 정공법 fix — 이전엔 "Sealed Sender 라 발신자 모름,
          // CallKit dismiss 만 하고 caller 30s timeout 의지" 의 임기응변.
          // 사용자 보고 "Galaxy 벨 계속 울리며 대기" 의 root cause.
          // Decline 시에도 acceptPendingVoipCall 패턴 적용 — envelope
          // fetch + decrypt → sender info 추출 → call_end envelope 전송 →
          // caller 즉시 ended. decrypt fail 시 Retry Receipt (#232) 가
          // self-heal trigger.
          if (ref == null || signaling == null) {
            // _IdleCallNotifier or SealedSender not ready — fall back to
            // CallKit dismiss only.
            unawaited(_callKitManager?.endCall(event.callId));
            CallNotifier._pendingVoipNonce = null;
            return;
          }
          diagLog(
            'callkitEvent',
            'DECLINE/TIMEOUT received action=${event.action} '
                'callId=${event.callId.length >= 8 ? event.callId.substring(0, 8) : event.callId} '
                '→ declinePendingVoipCall',
          );
          unawaited(declinePendingVoipCall(
            nonce: event.callId,
            reason: event.action == CallKitAction.timeout
                ? 'timeout'
                : 'declined',
          ));
          return;
        case CallKitAction.callback:
          return; // app foreground only, no extra action
      }
    }

    // The push path issues a CallKit UI keyed by the server nonce, but
    // CallService's internal callId is the hash from the decrypted envelope.
    // Accept the nonce as a valid alias for state.callId so local CallKit End
    // (event.callId == nonce) reaches the action switch. Without this,
    // tapping End on iOS CallKit was silently dropped — call only ended when
    // the remote peer hung up.
    //
    // v2.1: bidirectional `_aliasMap.isAliasMatch` covers both directions,
    // closing the slow-APNs race A residual where socket envelope arrived
    // first and v198's single-direction alias was never registered.

    // Phase 8.2 v2.5 — cold-launch-from-PushKit alias recovery on accept.
    //
    // Scenario: app cold-launched by PushKit. Plugin's `actionCallIncoming`
    // fired BEFORE the FlutterEngine isolate wired its EventChannel listener,
    // so the broadcast was silently dropped. The replay logic in
    // `replayPendingFromBackground` only covers ACCEPT and ACTIVATED events,
    // not INCOMING — so v2.4's `incomingShown` stream listener has nothing
    // upstream to fire. Result: alias map is stuck at the initial self-
    // mapping (`nonce → nonce`, registered when `acceptPendingVoipCallWithEnvelopes`
    // ran with state.callId still null). Even with v2.5 (a)'s post-inject
    // re-register, a race exists where the user's accept arrives before
    // injection completes — the eventCallId=nonce vs stateCallId=envelope_hash
    // mismatch fires the stale guard.
    //
    // v2.5 (b) fix: bind the alias right here on the accept event itself.
    // The heuristic is tight enough that legitimate stale events from a
    // previous (terminated) call won't slip through — terminated calls
    // transition state to `ended` → `idle`, so state.status would not be
    // `incoming` here. The check requires:
    //   - action == accept (only the accept event needs alias binding)
    //   - state.status == incoming (a current call is mid-ringing)
    //   - state.callId set (envelope_hash from injection)
    //   - event.callId is voip nonce pattern (came from CallKit raised by push)
    //   - !isAliasMatch (alias not bound yet — actually a stuck self-mapping)
    if (event.action == CallKitAction.accept &&
        state.status == CallStatus.incoming &&
        state.callId != null &&
        event.callId != state.callId &&
        _voipNoncePattern.hasMatch(event.callId) &&
        !_aliasMap.isAliasMatch(event.callId, state.callId)) {
      _aliasMap.register(event.callId, state.callId);
      debugPrint('[DIAG:CallNotifier] cold-launch alias bind on accept: '
          'nonce=${event.callId} ↔ callId=${state.callId}');
    }

    if (!_aliasMap.isAliasMatch(event.callId, state.callId)) {
      debugPrint('[DIAG:CallNotifier] stale event guard fired — ignored');
      return;
    }
    switch (event.action) {
      case CallKitAction.accept:
        debugPrint('[DIAG:CallNotifier] accept → acceptCall()');
        if (state.status == CallStatus.incoming) {
          // Phase 8.2 v2.1 — Create the audio-session-activated Completer
          // BEFORE calling acceptCall, so CallService's await catches the
          // CallKit didActivate event that fires within ~150ms of fulfill().
          // If we waited until acceptCall enters, the event could arrive in
          // between and be lost (broadcast EventChannel has no buffering).
          _callService.prepareAudioSessionAwaiter();
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
  /// Phase E-2 v3.1 (hot path): iOS PushKit cold-launch + native fetch path.
  ///
  /// Same shape as [acceptPendingVoipCall] but skips the server fetch step —
  /// CallAcceptCoordinator (native) has already pulled `/calls/pending/<nonce>`
  /// in the BFU/cold-launch window and is now handing the envelopes to Dart.
  /// We only need to inject + acceptCall.
  ///
  /// [source] = 'native' (iOS PushKit) | 'socket' (foreground push redelivery,
  /// future). Logged for telemetry; behavior identical.
  Future<void> acceptPendingVoipCallWithEnvelopes({
    required String nonce,
    required List<String> envelopes,
    required bool localAlwaysRelay,
    required String source,
  }) async {
    final ref = _ref;
    if (ref == null) {
      // _IdleCallNotifier — stash for ctor-resume of the real CallNotifier.
      // Native path rarely hits this (auth was already used by the fetch),
      // but keep the safety net for symmetry with acceptPendingVoipCall.
      CallNotifier.rememberPendingNonce(nonce);
      unawaited(_callKitManager?.endCall(nonce));
      return;
    }
    if (envelopes.isEmpty) {
      unawaited(_callKitManager?.endCall(nonce));
      return;
    }

    // Race guard: parallel Dart-side acceptPendingVoipCall (triggered by the
    // plugin's Event.actionCallAccept) may have already injected. Read
    // CallService.status (sync) — state.status is async via stream so lags.
    if (_callService.status != CallServiceStatus.idle) {
      debugPrint('[CallNotifier] WithEnvelopes — Dart path already owns '
          'serviceStatus=${_callService.status}, yielding source=$source');
      return;
    }

    // v2.1: bidirectional alias map register (replaces single _activeCallKitNonce).
    // state.callId may not be set yet (envelope not yet decrypted) — register
    // self-mapping for now; envelope inject below sets state.callId, and the
    // map is re-registered then by handleIncomingInvite if needed. The 60s
    // TTL ensures stale entries don't leak.
    _aliasMap.register(nonce, state.callId);
    _voipResumeInProgress = true;
    try {
      final signaling = ref.read(callSignalingProvider);
      if (signaling == null) {
        // SealedSender not initialized — decrypt impossible → stash + dismiss.
        CallNotifier.rememberPendingNonce(nonce);
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }
      for (final envelope in envelopes) {
        await signaling.injectEnvelope(envelope);
      }

      // Phase 8.2 v2.5 — re-register alias now that state.callId is known.
      // Initial register at the top of this method used `state.callId=null`
      // because injection hadn't started yet, so the map only has a
      // self-mapping (`nonce → nonce`). Now envelope decryption set the
      // actual hash via `_onServiceEvent(incoming)`, bind the proper alias
      // so any subsequent CallKit accept event passes the stale guard.
      // The auto-register block in `_onServiceEvent(incoming)` cannot do this
      // alone — it relies on `lastShownIncomingId`, which is null on cold-
      // launch from PushKit (plugin's `actionCallIncoming` was dropped before
      // FlutterEngine wired its EventChannel listener).
      final cidAfterInject = state.callId;
      if (cidAfterInject != null && cidAfterInject != nonce) {
        _aliasMap.register(nonce, cidAfterInject);
        debugPrint('[DIAG:CallNotifier] post-inject alias re-register: '
            'nonce=$nonce ↔ callId=$cidAfterInject');
      }

      // v195+ fix: read _callService.status (sync), not state.status (stream-async).
      if (_callService.status != CallServiceStatus.incoming) {
        unawaited(_callKitManager?.endCall(nonce));
        if (state.status != CallStatus.idle) {
          state = const CallState.idle();
        }
        return;
      }

      await acceptCall(localAlwaysRelay: localAlwaysRelay);
      debugPrint('[CallNotifier] accepted via native source=$source '
          'envCount=${envelopes.length}');
    } catch (e) {
      debugPrint('[CallNotifier] accept-with-envelopes failed: ${e.runtimeType}');
      unawaited(_callKitManager?.endCall(nonce));
      if (state.status != CallStatus.idle) {
        state = const CallState.idle();
      }
    } finally {
      _voipResumeInProgress = false;
    }
  }

  Future<void> acceptPendingVoipCall({
    required String nonce,
    required bool localAlwaysRelay,
  }) async {
    final shortNonce = nonce.length >= 8 ? nonce.substring(0, 8) : nonce;
    diagLog(
      'acceptPending',
      'enter nonce=$shortNonce relay=$localAlwaysRelay hasRef=${_ref != null}',
    );
    final ref = _ref;
    if (ref == null) {
      // _IdleCallNotifier — unreachable on the normal path (provider not ready).
      diagLog('acceptPending', 'ref==null → endCall + return');
      unawaited(_callKitManager?.endCall(nonce));
      return;
    }

    // v2.1: bidirectional alias map register before any await so a local End
    // during the network fetch / injection window passes the stale-event guard.
    _aliasMap.register(nonce, state.callId);
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
      diagLog(
        'acceptPending',
        'fetch /calls/pending/$shortNonce envelopes=${envelopes.length}',
      );
      if (envelopes.isEmpty) {
        diagLog('acceptPending', 'envelopes empty → endCall');
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }

      // Step 2: inject in order — first = call_invite → state=incoming,
      // subsequent = rtc_offer → CallService._pendingOffer buffer, ICE, etc.
      final signaling = ref.read(callSignalingProvider);
      if (signaling == null) {
        diagLog('acceptPending', 'signaling==null (SealedSender not init) → endCall');
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }
      // Race guard: while we awaited the network fetch, native
      // CallAcceptCoordinator's parallel path may have delivered envelopes via
      // VoipNativeBridge → acceptPendingVoipCallWithEnvelopes, which already
      // injected. Read CallService.status (synchronous) — Riverpod state.status
      // is stream-delivered (async) so it lags one microtask behind.
      if (_callService.status != CallServiceStatus.idle) {
        diagLog(
          'acceptPending',
          'native path already advanced (status=${_callService.status}) → yield',
        );
        return;
      }
      diagLog('acceptPending', 'injecting ${envelopes.length} envelope(s)');
      for (final envelope in envelopes) {
        await signaling.injectEnvelope(envelope);
      }
      diagLog(
        'acceptPending',
        'inject done serviceStatus=${_callService.status} stateStatus=${state.status}',
      );

      // v197 sentinel — confirms binary is v197 (sync broadcast streams + this log).
      debugPrint('[V197-SENTINEL] post-inject check '
          'serviceStatus=${_callService.status} stateStatus=${state.status}');
      // Step 3: if call_invite was processed, CallService._status should be
      // incoming. v195+ fix: must check _callService.status (sync) instead of
      // state.status — _emit() pushes to a broadcast StreamController which
      // delivers to CallNotifier listener async (next microtask). v197 made
      // both controllers sync broadcast so this check sees the up-to-date status.
      if (_callService.status != CallServiceStatus.incoming) {
        diagLog(
          'acceptPending',
          'post-inject FAILED svcStatus=${_callService.status} → endCall',
        );
        unawaited(_callKitManager?.endCall(nonce));
        if (state.status != CallStatus.idle) {
          state = const CallState.idle();
        }
        return;
      }

      diagLog('acceptPending', 'post-inject PASSED → calling acceptCall');
      await acceptCall(localAlwaysRelay: localAlwaysRelay);
      diagLog(
        'acceptPending',
        'acceptCall returned serviceStatus=${_callService.status} stateStatus=${state.status}',
      );
    } on DioException catch (e) {
      // 410 GONE = the parallel iOS native path (CallAcceptCoordinator) already
      // consumed the envelope via /calls/pending/<nonce>. The native path will
      // deliver via VoipNativeBridge → acceptPendingVoipCallWithEnvelopes and
      // own the rest of the lifecycle. Tearing down CallKit here would kill
      // the call the user just answered. Silently yield. Field-confirmed via
      // iPhone Console (v194 → v195 fix).
      if (e.response?.statusCode == 410) {
        // Android has no native consumer that pre-fetches envelopes (no
        // analogue to iOS PushKit's CallAcceptCoordinator). A 410 on Android
        // therefore does not mean "parallel native path already consumed
        // the envelope" — it means the envelope is genuinely lost. No
        // normal Android code path should produce a 410 here, so its mere
        // appearance is a regression signal.
        //
        // The 2026-05-06 regression's root cause was "server dist stale,
        // alias resolver undeployed → fetch by callId returns 410 → client
        // silent-yields". Surfacing this with a WARNING on Android lets
        // the same regression be caught on the first reproduction in
        // future. Behavior (yield) is preserved — keeping fail-loud off
        // because some unknown normal path (e.g. concurrent recovery
        // call) may still legitimately race to the same envelope.
        if (Platform.isAndroid) {
          diagLog(
            'acceptPending',
            'WARNING Android 410 — no native pre-fetch consumer exists; '
                'likely server bug (alias undeployed) or concurrent fetch race',
          );
        }
        diagLog('acceptPending', 'GET /calls/pending 410 GONE → yield to native');
        return;
      }
      diagLog(
        'acceptPending',
        'DioException status=${e.response?.statusCode} type=${e.type} → endCall',
      );
      unawaited(_callKitManager?.endCall(nonce));
      if (state.status != CallStatus.idle) {
        state = const CallState.idle();
      }
    } catch (e) {
      diagLog('acceptPending', 'unexpected ${e.runtimeType} → endCall');
      // Silent on structural errors only — call metadata must not be logged (§23.4.3).
      unawaited(_callKitManager?.endCall(nonce));
      if (state.status != CallStatus.idle) {
        state = const CallState.idle();
      }
    } finally {
      _voipResumeInProgress = false;
      diagLog('acceptPending', 'finally — _voipResumeInProgress=false');
    }
  }

  /// 2026-05-04 정공법 — Push path 의 decline 시 envelope fetch + decrypt
  /// → sender info 셋업 → call_end envelope 전송. 이전엔 envelope 없이
  /// CallKit dismiss 만 하고 caller 30s timeout 의지 했던 임기응변. 이제
  /// 같은 acceptPendingVoipCall 패턴으로 envelope 처리한 후 declineCall.
  ///
  /// decrypt fail 시 _onIncoming 의 catch 가 Retry Receipt (#232) trigger
  /// → caller 가 cache lookup + 재암호화 + 재전송 → 최종 success.
  Future<void> declinePendingVoipCall({
    required String nonce,
    required String reason,
  }) async {
    diagLog('declinePending',
        'ENTER nonce=${nonce.length >= 8 ? nonce.substring(0, 8) : nonce} reason=$reason');
    final ref = _ref;
    if (ref == null) {
      diagLog('declinePending', 'ABORT — ref null');
      unawaited(_callKitManager?.endCall(nonce));
      return;
    }

    // Bidirectional alias map register before await.
    _aliasMap.register(nonce, state.callId);
    try {
      // Step 1: fetch pending envelope list.
      final ApiClient apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/calls/pending/$nonce',
      );
      final envelopesRaw = response.data?['envelopes'];
      final envelopes = envelopesRaw is List
          ? envelopesRaw.whereType<String>().where((e) => e.isNotEmpty).toList()
          : <String>[];
      if (envelopes.isEmpty) {
        // No envelope — can't send call_end without sender info. Fall back
        // to CallKit dismiss + caller 30s timeout.
        diagLog('declinePending',
            'envelopes EMPTY — CallKit dismiss only, caller will hit 30s timeout');
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }

      // Step 2: parse envelope (decrypt only, no UI emit) → 첫 번째 invite
      // event 에서 sender info + callId 추출. injectEnvelope 사용하면
      // CallService.handleIncomingInvite 호출 → CallKit 재 raise 회귀
      // (사용자 보고 +233 "수신 배너 또 뜸"). parseEnvelope 는 stream emit
      // 안 함 → UI side effect 0.
      final signaling = ref.read(callSignalingProvider);
      if (signaling == null) {
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }
      diagLog('declinePending', 'envelopes count=${envelopes.length} '
          'nonce=${nonce.substring(0, 8)}');
      String? callerSnow;
      String? callIdFromInvite;
      String? lastSenderFallback;
      // 2026-05-04 fallback: 어떤 inner type 이라도 sender info 만 추출되면
      // call_end 보낼 수 있음. 첫 매치된 sender 를 fallback 으로 보관해두고,
      // call_invite 못 찾으면 fallback + nonce-as-callId 로 call_end 시도.
      // (caller 측 _handleRemoteEvent 는 callId mismatch 면 무시하지만,
      // sender 측 callService 상태머신은 _remoteSnowchatId 매칭으로도 종료
      // 가능 — 결과적으로 ringback 멈춤.)
      for (var i = 0; i < envelopes.length; i++) {
        final envelope = envelopes[i];
        final parsed = await signaling.parseEnvelope(envelope);
        if (parsed == null) {
          diagLog('declinePending', 'envelope[$i] parse=null');
          continue;
        }
        diagLog(
          'declinePending',
          'envelope[$i] type=${parsed.type} '
              'senderHash=${parsed.senderSnowchatId.substring(0, 8)} '
              'dataKeys=${parsed.data.keys.toList()}',
        );
        lastSenderFallback ??= parsed.senderSnowchatId;
        if (parsed.type == 'call_invite') {
          callerSnow = parsed.senderSnowchatId;
          callIdFromInvite = parsed.data['callId'] as String?;
          if (callIdFromInvite == null) {
            diagLog('declinePending',
                'call_invite has NO callId in data!');
          }
          break; // only need invite
        }
      }
      if (callerSnow == null || callIdFromInvite == null) {
        // Fallback path: no clean call_invite parsed but we have sender info.
        // Send call_end with nonce as callId — caller will key on
        // remoteSnowchatId match if its own callId differs (best-effort).
        if (lastSenderFallback != null) {
          diagLog(
            'declinePending',
            'fallback call_end senderHash='
                '${lastSenderFallback.substring(0, 8)} '
                'callId=${nonce.substring(0, 8)} (no clean invite parsed)',
          );
          try {
            await signaling.sendSealedSignaling(
              recipientSnowchatId: lastSenderFallback,
              eventType: 'call_end',
              innerPayload: {
                'callId': nonce,
                'reason': reason,
              },
            );
          } catch (e) {
            diagLog('declinePending',
                'fallback send failed: ${e.runtimeType}');
          }
          unawaited(_callKitManager?.endCall(nonce));
          return;
        }
        diagLog('declinePending',
            'no invite envelope (decrypt fail or wrong type) → CallKit dismiss only');
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }

      // Step 3: send call_end directly via sealed signaling — bypassing
      // CallService state machine (no _emit(incoming), no CallKit re-raise).
      diagLog(
        'declinePending',
        'sending call_end reason=$reason senderHash='
            '${callerSnow.substring(0, 8)} callId='
            '${callIdFromInvite.substring(0, 8)}',
      );
      try {
        await signaling.sendSealedSignaling(
          recipientSnowchatId: callerSnow,
          eventType: 'call_end',
          innerPayload: {
            'callId': callIdFromInvite,
            'reason': reason,
          },
        );
      } catch (e) {
        diagLog('declinePending',
            'call_end send failed: ${e.runtimeType} — caller will hit 30s timeout');
      }

      // Step 4: dismiss CallKit.
      unawaited(_callKitManager?.endCall(nonce));
    } on DioException catch (e) {
      // 410 = native path already consumed envelope. Just dismiss.
      if (e.response?.statusCode == 410) {
        diagLog('declinePending', '/calls/pending 410 — yielding');
        unawaited(_callKitManager?.endCall(nonce));
        return;
      }
      diagLog('declinePending',
          '/calls/pending DioException status=${e.response?.statusCode}');
      unawaited(_callKitManager?.endCall(nonce));
      if (state.status != CallStatus.idle) {
        state = const CallState.idle();
      }
    } catch (e) {
      diagLog('declinePending', 'error ${e.runtimeType}');
      unawaited(_callKitManager?.endCall(nonce));
      if (state.status != CallStatus.idle) {
        state = const CallState.idle();
      }
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
    _audioActivatedSub?.cancel();
    _incomingShownSub?.cancel();
    if (_ref != null) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
