/// @file        socket_manager.dart
/// @description Socket.IO-based realtime messaging connection management. Handles connection lifecycle, reconnect, and event routing.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-03 (Phase 11 fix — connect() async + pre-flight
///              `await ensureFreshToken!()` + library auto-reconnect disabled
///              (`setReconnectionAttempts(0)`) + `_connecting` single-flight
///              guard. Original Phase 11 cut over only wired the reactive
///              onConnectError branch — connect() entry kept reading the
///              cached snapshot synchronously, so a stale access JWT (idle
///              65min past 1h TTL) launched the handshake, got rejected,
///              and relied on reactive recovery. Server log evidence
///              2026-05-03 16:08~16:16 UTC: 13 jwt-expired Socket auth
///              failures vs only 3 actual /auth/refresh hits in 8 minutes —
///              gap was Socket.IO library's enableReconnection retrying in
///              the background with stale auth captured at io.io
///              construction. Earlier same day: token field + updateToken +
///              _refreshing + onJwtExpired/onAuthFailed callbacks all
///              removed. SocketManager receives `tokenProvider` (sync read)
///              + `ensureFreshToken` (async refresh) callbacks from
///              providers.dart. Earlier v206: didChangeAppLifecycleState
///              emits app_state=background on inactive too. Earlier
///              2026-04-26: header English translation; Layer 7 send-time
///              actual socket state check + stale _isConnected self-heal.)
///  - onUserRegistered: new user registration notification stream
///  - added user_registered/online_users socket event listeners
///  - SocketManager.sendPrivateMessage(): T0-pattern 1:1 message send (ack callback support)
///  - SocketManager.sendGroupMessage(): group message event send
///  - SocketManager.onGroupMessage: group message receive stream
///  - SocketManager.onMessageDeleted: message-deleted notification receive stream
///  - SocketManager.onGroupMemberAdded: group member added event stream
///  - SocketManager.onGroupMemberRemoved: group member removed event stream
///  - SocketManager.onGroupUpdated: group info changed event stream
///  - SocketManager.onGroupOwnerChanged: group owner changed event stream
///  - SocketManager.onGroupInvite: group invite receive stream
///  - SocketManager.emit(): general-purpose socket event send
///  - Fix: added enableForceNewConnection() — resolves socket_io_client URL caching issue
///
/// @functions
///  - SocketManager: WebSocket connection management class
///  - SocketManager.connect(): connect to WebSocket server
///  - SocketManager.disconnect(): disconnect from server
///  - SocketManager.sendMessage(): send message event (legacy)
///  - SocketManager.sendPrivateMessage(): T0-pattern 1:1 message send
///  - SocketManager.sendTyping(): send typing indicator
///  - SocketManager.stopTyping(): send typing stop
///  - SocketManager.ackMessage(): message receive acknowledgement
///  - SocketManager.sendReadReceipt(): send read receipt
///  - SocketManager.emit(): general-purpose socket event send
///  - SocketManager.sendSealedMessage(): Sealed Sender 1:1 message send (sealed_message event)
///  - SocketManager.sendSealedGroupMessage(): Sealed Sender group message send (sealed_group_message event)
///  - SocketManager.sendMessageRetryRequest(): 1:1 decryption failure retry request (Sealed Sender included)
///  - SocketManager.sendGroupMessageRetryRequest(): group decryption failure retry request
///  - SocketManager.dispose(): resource cleanup

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_endpoints.dart';

/// Socket.IO connection manager for real-time messaging.
/// Handles connection lifecycle, reconnection, and event routing.
class SocketManager with WidgetsBindingObserver {
  /// Phase 11: sync read of the current access JWT. Returns null if the user
  /// is unauthenticated. The wiring (providers.dart) points this at
  /// `tokenManager.snapshot?.access`.
  String? Function()? tokenProvider;

  /// Phase 11: async refresh entry. On JWT expiry detected via
  /// `onConnectError`, this is invoked to obtain a fresh access JWT before
  /// reconnecting. Routes through `tokenManager.ensureFresh()` so the
  /// 100-concurrent caller mutex covers HTTP + Socket simultaneously.
  /// Returns null if refresh failed (caller falls through to disconnected).
  Future<String?> Function()? ensureFreshToken;

  io.Socket? _socket;
  bool _isConnected = false;
  bool _disposed = false;
  bool get isConnected => _isConnected;

  // Event stream controllers
  // Phase 6: Single envelope stream — both 1:1 and group messages flow through
  // _incomingEnvelopeController. The MessageQueue is the only consumer.
  // Legacy onMessage / onGroupMessage are retained for non-message UI events
  // (typing, presence, etc.) and code that hasn't migrated yet.
  final _incomingEnvelopeController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _messageStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _prekeysLowController = StreamController<void>.broadcast();
  // Vuln 2 Stage B: server-side fetch noticed our device is missing
  // identityKeyEd25519 → asks us to re-run uploadPreKeys with the verify key.
  final _forcePrekeyUploadController = StreamController<Map<String, dynamic>>.broadcast();
  final _messageDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _chatDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Vuln 3 (Stage 3): fan-out when a group admin clears messages for all members
  final _groupMessagesClearedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _userRegisteredController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupMemberAddedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupMemberRemovedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupOwnerChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupInviteController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupInviteRejectedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _senderKeyRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Phase 8.7 Bug E: server tells us the SKDM source is offline so we can
  // drain the parked queue instead of looping forever.
  final _senderKeyRequestFailedController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Phase 8.2 VoIP — Sealed Sender opaque signaling relay (§24.2)
  // Server has no idea about the envelope contents. Client unseals and dispatches by inner event type.
  final _sealedCallSignalingController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Phase 3: AI Desktop Task relay
  final _aiTaskResponseController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _aiTaskStatusController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Phase 10 P0-E: Retry requests from recipients who failed to decrypt.
  // When THIS device is the original sender, these events arrive so we can
  // re-encrypt from MessageSendLog and re-send.
  final _messageRetryRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _groupMessageRetryRequestController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Phase 6: Single source of truth for all incoming message envelopes.
  /// Subscribed to by GlobalMessageRouter → MessageQueue.
  Stream<Map<String, dynamic>> get onIncomingEnvelope =>
      _incomingEnvelopeController.stream;

  /// @deprecated Phase 6 — kept for backward compat. Filters envelopes for 1:1 messages
  /// (no groupChatId). Consumers should migrate to drift watch or onIncomingEnvelope.
  Stream<Map<String, dynamic>> get onMessage => _incomingEnvelopeController.stream
      .where((e) => e['groupChatId'] == null);

  /// @deprecated Phase 6 — kept for backward compat. Filters envelopes for group messages.
  Stream<Map<String, dynamic>> get onGroupMessage => _incomingEnvelopeController.stream
      .where((e) => e['groupChatId'] != null);

  /// Phase 6: SKDM request from a recipient (we are the sender).
  Stream<Map<String, dynamic>> get onSenderKeyRequest =>
      _senderKeyRequestController.stream;

  /// Phase 8.2 VoIP: Sealed Sender signaling receive stream (§24.2).
  /// Each event has the form `{envelope: base64}`. Subscriber (CallSignaling) unseals.
  Stream<Map<String, dynamic>> get onSealedCallSignaling =>
      _sealedCallSignalingController.stream;

  /// Phase 8.7 Bug E: server-side notification that a previously emitted
  /// `sender_key_request` cannot be relayed because the target sender has
  /// no live sockets. Consumed by MessageQueue to drain parked SKDMs.
  Stream<Map<String, dynamic>> get onSenderKeyRequestFailed =>
      _senderKeyRequestFailedController.stream;

  /// Phase 10 P0-E: Incoming 1:1 retry request (we are the original sender).
  Stream<Map<String, dynamic>> get onMessageRetryRequest =>
      _messageRetryRequestController.stream;

  /// Phase 10 P0-E: Incoming group retry request (we are the original sender).
  Stream<Map<String, dynamic>> get onGroupMessageRetryRequest =>
      _groupMessageRetryRequestController.stream;

  Stream<Map<String, dynamic>> get onMessageDeleted =>
      _messageDeletedController.stream;
  Stream<Map<String, dynamic>> get onChatDeleted =>
      _chatDeletedController.stream;
  /// Vuln 3 (Stage 3): stream that signals an admin cleared group messages.
  /// payload: { groupChatId, clearedBy (snowchatId), clearedAt (ISO) }
  Stream<Map<String, dynamic>> get groupMessagesClearedStream =>
      _groupMessagesClearedController.stream;
  Stream<Map<String, dynamic>> get onUserRegistered =>
      _userRegisteredController.stream;
  Stream<Map<String, dynamic>> get onMessageStatus =>
      _messageStatusController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  Stream<Map<String, dynamic>> get onPresence => _presenceController.stream;
  Stream<Map<String, dynamic>> get onGroupMemberAdded =>
      _groupMemberAddedController.stream;
  Stream<Map<String, dynamic>> get onGroupMemberRemoved =>
      _groupMemberRemovedController.stream;
  Stream<Map<String, dynamic>> get onGroupUpdated =>
      _groupUpdatedController.stream;
  Stream<Map<String, dynamic>> get onGroupOwnerChanged =>
      _groupOwnerChangedController.stream;
  Stream<Map<String, dynamic>> get onGroupInvite =>
      _groupInviteController.stream;
  Stream<Map<String, dynamic>> get onGroupInviteRejected =>
      _groupInviteRejectedController.stream;

  // Phase 3: AI Desktop Task
  Stream<Map<String, dynamic>> get onAiTaskResponse =>
      _aiTaskResponseController.stream;
  Stream<Map<String, dynamic>> get onAiTaskStatus =>
      _aiTaskStatusController.stream;

  final _profileUpdatedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onProfileUpdated =>
      _profileUpdatedController.stream;

  // Phase 8.8: GMK request/response
  final _gmkRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onGmkRequest =>
      _gmkRequestController.stream;
  final _gmkResponseController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onGmkResponse =>
      _gmkResponseController.stream;

  final _channelMemberJoinedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onChannelMemberJoined =>
      _channelMemberJoinedController.stream;

  final _channelMemberLeftController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onChannelMemberLeft =>
      _channelMemberLeftController.stream;

  final _channelMemberRoleChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onChannelMemberRoleChanged =>
      _channelMemberRoleChangedController.stream;

  final _unauthorizedLoginController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onUnauthorizedLoginAttempt =>
      _unauthorizedLoginController.stream;

  final _channelApplicationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onChannelApplicationReceived =>
      _channelApplicationController.stream;

  final _channelOwnerChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onChannelOwnerChanged =>
      _channelOwnerChangedController.stream;

  final _channelDeletedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onChannelDeleted =>
      _channelDeletedController.stream;

  // Phase 9.1: friend request received (PERSONAL channel invite)
  final _friendRequestReceivedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onFriendRequestReceived =>
      _friendRequestReceivedController.stream;

  /// Last received online_users bulk data, buffered for late subscribers.
  Map<String, dynamic>? _lastOnlineUsersData;
  Stream<bool> get onConnectionChange => _connectionController.stream;
  Stream<void> get onPrekeysLow => _prekeysLowController.stream;

  /// Vuln 2 Stage B: server asks us to re-upload our prekeys because the
  /// device row is missing identityKeyEd25519 (legacy registration before
  /// Phase 5). Payload: { reason: 'missing_ed25519' }.
  Stream<Map<String, dynamic>> get onForcePrekeyUpload =>
      _forcePrekeyUploadController.stream;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SocketManager({this.tokenProvider, this.ensureFreshToken}) {
    // App lifecycle observer — recover dead socket when returning background → foreground.
    // If the OS killed the socket in background, Socket.IO may not detect it immediately →
    // trigger explicit reconnect on resume (falls back to onConnectError → JWT refresh path if needed).
    WidgetsBinding.instance.addObserver(this);

    // Network connectivity observer — reconnect socket immediately on none → wifi/mobile transition.
    // Don't rely on Socket.IO's internal exponential backoff (5~60s); fire on the first OS connectivity
    // event. Recovers within 1s for airplane mode toggle / WiFi switch / signal recovery.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (_disposed) return;
      if (tokenProvider?.call() == null) return;
      final online = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn);
      if (online && !_isConnected && !_jwtRefreshInFlight && !_connecting) {
        debugPrint('[SocketManager] Connectivity restored ($results) — reconnecting');
        unawaited(connect());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    final token = tokenProvider?.call();

    // [Phase 8.2 §8-B fix — app_state presence emit]
    // iPhone 의 fg→bg 30s 내 incoming 수신 불가 (매트릭스 #4) 의 정공법.
    // server `wantPush = isOffline` 이 socket presence 기반인데, iOS 가
    // background 진입해도 socket 즉시 안 죽음 (~10-30s grace) → server 가
    // "online" 으로 판단 → push 안 보냄 → socket emit 가도 background app
    // deliver 못 함 → invite 사라짐.
    //
    // 해법: client 가 background 진입 시 server 에 명시 알림. server 는
    // userAppState 에 'background' 기록 → wantPush 조건에 포함. iOS 의 ~5s
    // grace window 안에 emit 가 deliver 되어 server 가 정확한 state 인식.
    //
    // foreground 복귀 시도 emit — server 가 reset 해서 next call 정상.
    //
    // AppLifecycleState.paused = iOS applicationDidEnterBackground / Android onStop
    // AppLifecycleState.inactive = iOS willResignActive (전화 / 알림 등 transient)
    // AppLifecycleState.resumed = foreground 복귀
    //
    // v206 (2026-05-03): iOS 의 paused emit 가 BG transition window 에서 socket
    // I/O freeze 로 손실되는 race 를 좁히기 위해 inactive 에서도 background
    // emit. inactive 는 transient (control center / notification banner) 에서도
    // 발화하지만 server 의 userAppState 는 idempotent map 이고, 이후 paused
    // 안 오고 resumed 가 오면 정상 복귀 emit 가 덮어쓰므로 부작용 없음.
    // server 측 v206 의 iOS-always-push 와 짝 — 서버가 이미 iOS 는 항상
    // PushKit 발사하므로 이 emit 는 Android 의 BG-aware push 정확도 + iOS 의
    // 보조 신호 역할.
    if (_isConnected && _socket != null && token != null) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        debugPrint('[SocketManager] App ${state.name} — emit app_state=background');
        try {
          _socket!.emit('app_state', {'state': 'background'});
        } catch (e) {
          debugPrint('[SocketManager] app_state background emit failed: ${e.runtimeType}');
        }
      } else if (state == AppLifecycleState.resumed) {
        debugPrint('[SocketManager] App resumed — emit app_state=foreground');
        try {
          _socket!.emit('app_state', {'state': 'foreground'});
        } catch (e) {
          debugPrint('[SocketManager] app_state foreground emit failed: ${e.runtimeType}');
        }
      }
    }

    if (state == AppLifecycleState.resumed && token != null) {
      if (!_isConnected && !_jwtRefreshInFlight && !_connecting) {
        debugPrint('[SocketManager] App resumed — reconnecting (was disconnected)');
        unawaited(connect());
      } else {
        debugPrint('[SocketManager] App resumed — already connected or refreshing, skip');
      }
    }
  }

  /// Local guard for socket-driven JWT refresh — prevents the onConnectError
  /// branch from firing two ensureFreshToken calls in parallel for the same
  /// expired token. The TokenManager mutex would coalesce them anyway, but
  /// keeping this avoids a noisy log + double socket recreate.
  bool _jwtRefreshInFlight = false;

  /// Phase 11 fix (2026-05-03): single-flight guard for connect() itself.
  /// connect() is now async + awaits ensureFresh — without this guard, a
  /// rapid burst (lifecycle resume + connectivity restored + onDisconnect
  /// 5s timer) could race two parallel handshakes against the server.
  bool _connecting = false;

  /// Connect to the Socket.IO server with JWT authentication.
  ///
  /// Phase 11 spec (`Documentation/Dev-plan2/Phase11-JWT-Token-Permanent-Solution.md` §4.3):
  /// "connect() 전 await tokenManager.ensureFresh()". The original cut over
  /// only wired the reactive onConnectError branch — connect() entry kept
  /// reading the cached snapshot synchronously, so a stale access JWT (idle
  /// 65min past 1h TTL) would launch the handshake, get rejected, and rely
  /// on the reactive path to recover. Server log evidence (2026-05-03
  /// 16:08~16:16): 13 jwt-expired Socket auth failures vs only 3 actual
  /// /auth/refresh hits in 8 minutes — the gap was the Socket.IO library's
  /// `enableReconnection()` retrying in the background with the stale auth
  /// captured at io.io construction time, while our onConnectError branch
  /// could not see those retries (they fire on the disposed socket's
  /// listeners).
  ///
  /// Fix:
  ///   1. async + pre-flight `await ensureFreshToken!()` so every handshake
  ///      starts with a guaranteed fresh access JWT (5min near-expiry
  ///      threshold inside TokenManager.ensureFresh).
  ///   2. `setReconnectionAttempts(0)` + drop `enableReconnection()` —
  ///      this client owns ALL reconnect logic. The library's silent
  ///      stale-auth retry loop is permanently disabled.
  ///   3. `_connecting` single-flight guard so concurrent lifecycle events
  ///      (resume + connectivity + 5s disconnect timer) coalesce into one
  ///      handshake instead of racing.
  Future<void> connect() async {
    if (_disposed) return;
    if (_connecting) {
      debugPrint('[SocketManager] connect() already in flight — skip');
      return;
    }
    _connecting = true;
    try {
      // Pre-flight: ensure access JWT is fresh BEFORE the handshake.
      // ensureFreshToken returns null when refresh fails 3x — TokenManager
      // already emitted `expiredHard` so providers.dart listener handles
      // logout. We just stay disconnected.
      String? freshToken;
      if (ensureFreshToken != null) {
        freshToken = await ensureFreshToken!();
      } else {
        // Defensive fallback for tests / pre-Phase 11 wiring.
        freshToken = tokenProvider?.call();
      }
      if (_disposed) return;
      if (freshToken == null) {
        debugPrint('[SocketManager] connect() — no valid token, staying disconnected');
        return;
      }

      // Already connected — nothing to do (idempotent). Re-check after the
      // await so a parallel onConnect that fired during ensureFresh wins.
      if (_isConnected && _socket != null) {
        debugPrint('[SocketManager] Already connected, skipping reconnect');
        return;
      }

      // Clean up existing socket before reconnect.
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
      _isConnected = false;

      final socketUrl = ApiEndpoints.getSocketUrl();
      debugPrint('[SocketManager] Connecting to $socketUrl (token prefix=${freshToken.length > 8 ? freshToken.substring(0, 8) : freshToken})');

      _socket = io.io(
        socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': freshToken})
            .disableAutoConnect()
            .enableForceNewConnection() // Prevent stale cached socket after reconnect
            // Phase 11 fix: disable library auto-reconnect. We own ALL retry
            // via onDisconnect (5s timer) + onConnectError (ensureFresh +
            // reconnect) + lifecycle / connectivity observers. Otherwise the
            // library captures auth at io.io construction and silently
            // retries with stale token on its own backoff schedule — server
            // sees ghost handshakes the client cannot observe.
            .setReconnectionAttempts(0)
            .build(),
      );

      _setupEventListeners();
      _socket!.connect();
    } finally {
      _connecting = false;
    }
  }

  /// Set up all Socket.IO event listeners.
  void _setupEventListeners() {
    final socket = _socket;
    if (socket == null) return;

    socket.onConnect((_) {
      debugPrint('[SocketManager] Connected (id: ${socket.id})');
      _isConnected = true;
      _connectionController.add(true);
    });

    socket.onDisconnect((reason) {
      debugPrint('[SocketManager] Disconnected (reason: $reason)');
      _isConnected = false;
      _connectionController.add(false);
      // Phase 11 fix: library reconnection is disabled (setReconnectionAttempts(0)),
      // so this manual 5s timer is the ONLY auto-reconnect path on a clean
      // disconnect. connect() now does its own pre-flight ensureFresh, so we
      // do not need to gate on _jwtRefreshInFlight — the TokenManager mutex
      // and our _connecting flag coalesce.
      if (!_disposed && tokenProvider?.call() != null) {
        Future.delayed(const Duration(seconds: 5), () {
          if (!_disposed && !_isConnected && !_connecting) {
            debugPrint('[SocketManager] Scheduled reconnect after disconnect (5s)');
            unawaited(connect());
          }
        });
      }
    });

    socket.onConnectError((error) {
      debugPrint('[SocketManager] Connection error: $error');
      _isConnected = false;
      _connectionController.add(false);

      // Detect JWT expiry → ensureFresh via TokenManager, then reconnect.
      // Server (auth.ts:91) sends "jwt expired: INVALID_TOKEN" / "jwt invalid: INVALID_TOKEN" /
      // "jwt missing: AUTH_REQUIRED". Also include 'token' / 'invalid' for backward compat
      // with the old format ("INVALID_TOKEN"/"AUTH_REQUIRED").
      final msg = error?.toString().toLowerCase() ?? '';
      final looksExpired = msg.contains('jwt') ||
          msg.contains('expired') ||
          msg.contains('auth') ||
          msg.contains('token') ||
          msg.contains('invalid');
      if (looksExpired && ensureFreshToken != null && !_jwtRefreshInFlight && !_disposed) {
        _jwtRefreshInFlight = true;
        debugPrint('[SocketManager] JWT expired suspected — triggering ensureFresh');
        // Stop the old socket's internal auto-reconnect first to avoid stale-token retry race.
        try { _socket?.disconnect(); } catch (_) {}
        () async {
          try {
            final newToken = await ensureFreshToken!();
            if (_disposed) return;
            if (newToken == null) {
              // TokenManager already emitted expiredHard event so the
              // providers.dart listener fires logout + UI navigate. We just
              // stay disconnected — no need to call out.
              debugPrint('[SocketManager] ensureFresh returned null — staying disconnected');
              return;
            }
            debugPrint('[SocketManager] Token refreshed — reconnecting');
            unawaited(connect());
          } catch (e) {
            debugPrint('[SocketManager] ensureFresh failed: $e — staying disconnected');
          } finally {
            _jwtRefreshInFlight = false;
          }
        }();
      }
    });

    socket.onReconnect((_) {
      debugPrint('[SocketManager] Reconnected');
      _isConnected = true;
      _connectionController.add(true);
    });

    // --- Application events ---

    // Incoming 1:1 message (T0 pattern: private_message event)
    // Phase 6: Single 'new_message' event for all incoming messages
    // (1:1, group, SKDM, system). The MessageQueue handles dispatch.
    socket.on('new_message', (data) {
      if (data is Map) {
        // [DIAG] Bug 1/2 diagnostic: trace whether the socket layer received the envelope
        final id = data['id'] ?? data['messageId'];
        final type = data['type'] ?? 'unknown';
        final groupChatId = data['groupChatId'];
        final convId = data['conversationId'];
        final from = data['senderSnowchatId'] ?? data['senderId'];
        debugPrint('[DIAG:Socket] new_message RECEIVED id=$id type=$type '
            'groupChatId=$groupChatId convId=$convId from=$from');
        _incomingEnvelopeController.add(Map<String, dynamic>.from(data));
      } else {
        debugPrint('[DIAG:Socket] new_message DROPPED: data is not Map (type=${data.runtimeType})');
      }
    });

    // Phase 10.1: Sealed Sender message — server relays opaque blob
    // with type='sealed'. Feeds into same envelope stream so MessageQueue
    // can dispatch to EncryptedMessageHandler.decryptSealedMessage().
    socket.on('sealed_message', (data) {
      if (data is Map) {
        final envelope = Map<String, dynamic>.from(data);
        // Inject type='sealed' so MessageQueue can discriminate
        envelope['type'] = 'sealed';
        final id = envelope['id'] ?? envelope['messageId'];
        debugPrint('[DIAG:Socket] sealed_message RECEIVED id=$id');
        _incomingEnvelopeController.add(envelope);
      }
    });

    // Phase 8.2 VoIP — Sealed Sender signaling opaque receive (§24.2)
    // Don't log envelope content/size (Zero-Trace §23)
    socket.on('sealed_call_signaling', (data) {
      if (data is Map) {
        _sealedCallSignalingController.add(
          Map<String, dynamic>.from(data),
        );
      }
    });

    // Phase 6: SKDM request — recipient asks us to re-send sender key
    socket.on('sender_key_request', (data) {
      debugPrint('[SocketManager] sender_key_request received');
      if (data is Map) {
        _senderKeyRequestController.add(Map<String, dynamic>.from(data));
      }
    });

    // Phase 8.7 Bug E: server tells us our sender_key_request cannot be
    // relayed (target sender offline) → drop parked queue, surface system msg.
    socket.on('sender_key_request_failed', (data) {
      debugPrint('[SocketManager] sender_key_request_failed received');
      if (data is Map) {
        _senderKeyRequestFailedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Phase 10 P0-E: Retry request from a recipient (we are the original sender).
    // The server relays this after verifying the requester is the true recipient.
    socket.on('message_retry_request', (data) {
      debugPrint('[SocketManager] message_retry_request received');
      if (data is Map) {
        _messageRetryRequestController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('group_message_retry_request', (data) {
      debugPrint('[SocketManager] group_message_retry_request received');
      if (data is Map) {
        _groupMessageRetryRequestController
            .add(Map<String, dynamic>.from(data));
      }
    });

    // Message status update (delivered, read)
    socket.on('message_status', (data) {
      if (data is Map) {
        _messageStatusController.add(Map<String, dynamic>.from(data));
      }
    });

    // Typing indicators
    socket.on('user_typing', (data) {
      if (data is Map) {
        _typingController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('user_stopped_typing', (data) {
      if (data is Map) {
        _typingController.add({
          ...Map<String, dynamic>.from(data),
          'stopped': true,
        });
      }
    });

    // Presence events
    socket.on('user_online', (data) {
      if (data is Map) {
        _presenceController.add({
          ...Map<String, dynamic>.from(data),
          'online': true,
        });
      }
    });

    socket.on('user_offline', (data) {
      if (data is Map) {
        _presenceController.add({
          ...Map<String, dynamic>.from(data),
          'online': false,
        });
      }
    });

    // PreKeys low warning
    socket.on('prekeys_low', (_) {
      debugPrint('[SocketManager] prekeys_low warning received');
      _prekeysLowController.add(null);
    });

    // Vuln 2 Stage B: server requests immediate prekey re-upload because
    // identityKeyEd25519 is NULL on at least one of our devices. Listener
    // (in app startup wiring) calls SignalSessionManager.uploadPreKeys();
    // the in-flight guard there merges duplicate triggers.
    socket.on('force_prekey_upload', (data) {
      debugPrint('[SocketManager] force_prekey_upload received: $data');
      if (data is Map) {
        _forcePrekeyUploadController.add(Map<String, dynamic>.from(data));
      } else {
        _forcePrekeyUploadController.add(const {'reason': 'unknown'});
      }
    });

    // New user registered notification (real-time contact update)
    socket.on('user_registered', (data) {
      debugPrint('[SocketManager] user_registered received');
      if (data is Map) {
        _userRegisteredController.add(Map<String, dynamic>.from(data));
      }
    });

    // Profile updated (displayName change) — real-time contact refresh
    socket.on('profile_updated', (data) {
      debugPrint('[SocketManager] profile_updated received');
      if (data is Map) {
        _profileUpdatedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Channel member joined — refresh channel member list
    socket.on('channel_member_joined', (data) {
      debugPrint('[SocketManager] channel_member_joined received');
      if (data is Map) {
        _channelMemberJoinedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Channel member left/kicked — refresh channel member list
    socket.on('channel_member_left', (data) {
      debugPrint('[SocketManager] channel_member_left received');
      if (data is Map) {
        _channelMemberLeftController.add(Map<String, dynamic>.from(data));
      }
    });

    // Channel member role changed — refresh channel list for updated role
    socket.on('channel_member_role_changed', (data) {
      debugPrint('[SocketManager] channel_member_role_changed received');
      if (data is Map) {
        _channelMemberRoleChangedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Channel ownership transferred — refresh admin screen
    socket.on('channel_owner_changed', (data) {
      debugPrint('[SocketManager] channel_owner_changed received');
      if (data is Map) {
        _channelOwnerChangedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Channel deleted — remove from list, pop screens
    socket.on('channel_deleted', (data) {
      debugPrint('[SocketManager] channel_deleted received');
      if (data is Map) {
        _channelDeletedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Channel application received — admin should refresh pending list
    socket.on('channel_application_received', (data) {
      debugPrint('[SocketManager] channel_application_received');
      if (data is Map) {
        _channelApplicationController.add(Map<String, dynamic>.from(data));
      }
    });

    // Phase 9.1: friend request received (PERSONAL channel invite)
    socket.on('friend_request_received', (data) {
      debugPrint('[SocketManager] friend_request_received');
      if (data is Map) {
        _friendRequestReceivedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Security: unauthorized login attempt from another device
    socket.on('unauthorized_login_attempt', (data) {
      debugPrint('[SocketManager] ⚠️ unauthorized_login_attempt received');
      if (data is Map) {
        _unauthorizedLoginController.add(Map<String, dynamic>.from(data));
      }
    });

    // Bulk online users list (received on connection)
    socket.on('online_users', (data) {
      debugPrint('[SocketManager] online_users received');
      if (data is Map && data['users'] is List) {
        final payload = {'bulk': true, 'users': data['users']};
        _lastOnlineUsersData = payload;
        _presenceController.add(payload);
      }
    });

    // Message deleted notification (delete for everyone)
    socket.on('message_deleted', (data) {
      debugPrint('[SocketManager] message_deleted received');
      if (data is Map) {
        _messageDeletedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Phase 11: Chat/Group deleted (room blown up)
    socket.on('chat_deleted', (data) {
      debugPrint('[SocketManager] chat_deleted received: $data');
      if (data is Map) {
        _chatDeletedController.add(Map<String, dynamic>.from(data));
      }
    });
    socket.on('group_deleted', (data) {
      debugPrint('[SocketManager] group_deleted received: $data');
      if (data is Map) {
        _chatDeletedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Vuln 3 (Stage 3): admin-triggered group clear chat
    socket.on('group_messages_cleared', (data) {
      debugPrint('[SocketManager] group_messages_cleared received');
      if (data is Map) {
        _groupMessagesClearedController.add(Map<String, dynamic>.from(data));
      }
    });

    // Group management events
    socket.on('group_member_added', (data) {
      debugPrint('[SocketManager] group_member_added received');
      if (data is Map) {
        _groupMemberAddedController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('group_member_removed', (data) {
      debugPrint('[SocketManager] group_member_removed received');
      if (data is Map) {
        _groupMemberRemovedController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('group_updated', (data) {
      debugPrint('[SocketManager] group_updated received');
      if (data is Map) {
        _groupUpdatedController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('group_owner_changed', (data) {
      debugPrint('[SocketManager] group_owner_changed received');
      if (data is Map) {
        _groupOwnerChangedController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('request_gmk', (data) {
      debugPrint('[SocketManager] request_gmk received');
      if (data is Map) {
        _gmkRequestController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('gmk_response', (data) {
      debugPrint('[SocketManager] gmk_response received');
      if (data is Map) {
        _gmkResponseController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('group_invite', (data) {
      debugPrint('[SocketManager] group_invite received');
      if (data is Map) {
        _groupInviteController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('group_invite_rejected', (data) {
      debugPrint('[SocketManager] group_invite_rejected received');
      if (data is Map) {
        _groupInviteRejectedController
            .add(Map<String, dynamic>.from(data));
      }
    });

    // Phase 3: AI Desktop Task relay
    socket.on('ai_task_response', (data) {
      debugPrint('[SocketManager] ai_task_response received');
      if (data is Map) {
        _aiTaskResponseController.add(Map<String, dynamic>.from(data));
      }
    });

    socket.on('ai_task_status', (data) {
      debugPrint('[SocketManager] ai_task_status received');
      if (data is Map) {
        _aiTaskStatusController.add(Map<String, dynamic>.from(data));
      }
    });
  }

  /// Disconnect from the server.
  void disconnect() {
    _socket?.disconnect();
    _isConnected = false;
    _connectionController.add(false);
  }

  /// Send a group message via Socket.IO (Phase 6: pure Sender Key payload).
  /// The [data] map should match [SendGroupMessagePayload] on the server:
  /// { groupChatId, encryptedPayload, type: 'sender_key', clientMessageId, expiresIn? }
  void sendGroupMessage(Map<String, dynamic> data, {Function(dynamic)? onAck}) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send group message: not connected');
      onAck?.call({'error': {'code': 'NOT_CONNECTED', 'message': 'Socket not connected'}});
      return;
    }
    if (onAck != null) {
      _socket!.emitWithAck('send_group_message', data, ack: onAck);
    } else {
      _socket!.emit('send_group_message', data);
    }
  }

  /// Phase 6: Send a batch ACK for processed messages.
  void sendMessageAck(List<String> messageIds) {
    if (!_isReadyToSend()) return;
    if (messageIds.isEmpty) return;
    _socket!.emit('message_ack', {'messageIds': messageIds});
  }

  /// Phase 6: Request SKDM from a sender we don't have a sender key for.
  void sendSenderKeyRequest({
    required String groupId,
    required String senderSnowchatId,
  }) {
    if (!_isReadyToSend()) return;
    _socket!.emit('sender_key_request', {
      'groupId': groupId,
      'senderSnowchatId': senderSnowchatId,
    });
    debugPrint('[SocketManager] Requested SKDM from $senderSnowchatId for $groupId');
  }

  /// Phase 10 P0-D: Emit a 1:1 retry request to the server.
  ///
  /// Called by MessageQueue when a 1:1 or Sealed Sender message fails to decrypt
  /// after exhausting retries. The server validates the requester, checks nonce
  /// uniqueness, and relays to the original sender.
  ///
  /// [messageId]: The server-assigned message ID that failed to decrypt.
  /// [senderSnowchatId]: Original sender's SnowChat ID, or null for Sealed Sender
  ///   messages (server resolves sender via messageId lookup — blind retry).
  void sendMessageRetryRequest(String messageId, String? senderSnowchatId) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send message_retry_request: not connected');
      return;
    }
    _socket!.emit('message_retry_request', {
      'messageId': messageId,
      'senderSnowchatId': senderSnowchatId,
      'requestNonce': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    debugPrint('[SocketManager] Sent message_retry_request for $messageId');
  }

  /// Phase 10 P0-D: Emit a group retry request to the server.
  ///
  /// Called by MessageQueue when a group message fails to decrypt after SKDM
  /// recovery has also failed. The server verifies group membership, checks
  /// nonce uniqueness, and relays to the original sender. The sender will
  /// re-encrypt as 1:1 pairwise fallback.
  void sendGroupMessageRetryRequest(
    String groupId,
    String messageId,
    String senderSnowchatId,
  ) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send group_message_retry_request: not connected');
      return;
    }
    _socket!.emit('group_message_retry_request', {
      'groupId': groupId,
      'messageId': messageId,
      'senderSnowchatId': senderSnowchatId,
      'requestNonce': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    debugPrint('[SocketManager] Sent group_message_retry_request for $messageId '
        'in group $groupId');
  }

  /// Send a 1:1 message via Socket.IO (T0 pattern: simple JSON passthrough).
  /// The [data] map should contain: { recipientId, text, type, replyToId?, expiresIn? }
  /// Optional [onAck] callback receives the server's ack response
  /// ({ messageId, serverTimestamp } on success, { error: {...} } on failure).
  void sendPrivateMessage(Map<String, dynamic> data, {Function(dynamic)? onAck}) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send private_message: not connected (isConnected=$_isConnected, actual=${_socket?.connected}, socket=${_socket != null})');
      onAck?.call({'error': {'code': 'NOT_CONNECTED', 'message': 'Socket not connected'}});
      return;
    }
    debugPrint('[SocketManager] Sending private_message to ${data['recipientId']}');
    _socket!.emitWithAck('private_message', data, ack: (response) {
      debugPrint('[SocketManager] private_message ack: $response');
      onAck?.call(response);
    });
  }

  /// Whether send is possible — prevents mismatch between `_isConnected` flag and actual socket state.
  ///
  /// On background → foreground transition there are cases where Socket.IO's internal reconnect
  /// fires but the onConnect callback doesn't (especially iOS), leaving `_isConnected` stuck
  /// stale at false so only sends are blocked (receive works fine — socket is alive). If the
  /// actual `_socket.connected` is true, sync the flag and proceed with send.
  bool _isReadyToSend() {
    if (_socket == null) return false;
    final actualConnected = _socket!.connected;
    if (actualConnected && !_isConnected) {
      // Missing onConnect — flag self-heal.
      debugPrint('[SocketManager] Stale _isConnected=false but socket.connected=true — syncing');
      _isConnected = true;
      _connectionController.add(true);
    }
    return actualConnected;
  }

  /// Phase 10.1: Send a Sealed Sender 1:1 message.
  ///
  /// The server receives an opaque sealed envelope — it does NOT know the
  /// sender identity. Only the recipient can unseal and discover the sender.
  ///
  /// [recipientId]: Recipient's SnowChat ID (for server routing)
  /// [sealedContent]: Base64-encoded sealed envelope bytes
  /// [clientMessageId]: Client-generated local ID for round-trip matching
  /// [expiresIn]: Optional TTL in seconds
  void sendSealedMessage({
    required String recipientId,
    required String sealedContent,
    required String clientMessageId,
    int? expiresIn,
    Function(dynamic)? onAck,
  }) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send sealed_message: not connected (isConnected=$_isConnected, actual=${_socket?.connected})');
      onAck?.call({'error': {'code': 'NOT_CONNECTED', 'message': 'Socket not connected'}});
      return;
    }
    debugPrint('[SocketManager] Sending sealed_message to $recipientId');
    _socket!.emitWithAck('sealed_message', {
      'recipientId': recipientId,
      'sealedContent': sealedContent,
      'clientMessageId': clientMessageId,
      if (expiresIn != null) 'expiresIn': expiresIn,
    }, ack: (response) {
      debugPrint('[SocketManager] sealed_message ack: $response');
      onAck?.call(response);
    });
  }

  /// Phase 10.1: Send Sealed Sender group messages.
  ///
  /// Each group member receives their own sealed envelope (per-recipient sealing).
  /// The server fans out each blob to the corresponding recipient.
  ///
  /// [groupChatId]: Group ID
  /// [recipientSealedContents]: Map of recipientSnowchatId -> base64 sealed envelope
  /// [clientMessageId]: Client-generated local ID
  /// [expiresIn]: Optional TTL in seconds
  void sendSealedGroupMessage({
    required String groupChatId,
    required Map<String, String> recipientSealedContents,
    required String clientMessageId,
    int? expiresIn,
    Function(dynamic)? onAck,
  }) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send sealed_group_message: not connected');
      onAck?.call({'error': {'code': 'NOT_CONNECTED', 'message': 'Socket not connected'}});
      return;
    }
    debugPrint('[SocketManager] Sending sealed_group_message to group $groupChatId '
        '(${recipientSealedContents.length} recipients)');
    _socket!.emitWithAck('sealed_group_message', {
      'groupChatId': groupChatId,
      'recipientSealedContents': recipientSealedContents,
      'clientMessageId': clientMessageId,
      if (expiresIn != null) 'expiresIn': expiresIn,
    }, ack: (response) {
      debugPrint('[SocketManager] sealed_group_message ack: $response');
      onAck?.call(response);
    });
  }

  /// Phase 8.8: Request GMK from online group members.
  void requestGmk(String groupId) {
    if (!_isReadyToSend()) return;
    _socket!.emit('request_gmk', {'groupId': groupId});
  }

  /// Send a 1:1 message via Socket.IO (legacy E2EE path).
  /// Kept for backward compatibility. New code should use [sendPrivateMessage].
  void sendMessage(Map<String, dynamic> data, {Function(dynamic)? onAck}) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send: not connected');
      onAck?.call({'error': {'code': 'NOT_CONNECTED', 'message': 'Socket not connected'}});
      return;
    }
    debugPrint('[SocketManager] Emitting send_message to ${data['recipientId']}');
    _socket!.emit('send_message', data);
    if (onAck != null) {
      debugPrint('[SocketManager] onAck provided but not invoked — '
          'plain emit does not support ack callbacks');
    }
  }

  /// Send typing start indicator.
  void sendTyping(String conversationId) {
    if (!_isReadyToSend()) return;
    _socket!.emit('typing_start', {'conversationId': conversationId});
  }

  /// Send typing stop indicator.
  void stopTyping(String conversationId) {
    if (!_isReadyToSend()) return;
    _socket!.emit('typing_stop', {'conversationId': conversationId});
  }

  /// Send read receipts for a list of message IDs.
  void sendReadReceipt(List<String> messageIds) {
    if (!_isReadyToSend()) return;
    _socket!.emit('message_read', {'messageIds': messageIds});
  }

  /// Acknowledge message receipt (legacy, use sendReadReceipt instead).
  void ackMessage(String messageId) {
    sendReadReceipt([messageId]);
  }

  /// Get the last buffered online_users data (for late subscribers).
  Map<String, dynamic>? get lastOnlineUsersData => _lastOnlineUsersData;

  /// Emit a generic Socket.IO event with data.
  void emit(String event, Map<String, dynamic> data) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot emit $event: not connected');
      return;
    }
    _socket!.emit(event, data);
  }

  // ── Phase 3: AI Desktop Task ──

  /// Send an AI task request to desktop via server relay.
  void sendAiTaskRequest({
    required String taskId,
    required String targetDeviceId,
    required String ciphertext,
    Function(dynamic)? onAck,
  }) {
    if (!_isReadyToSend()) {
      debugPrint('[SocketManager] Cannot send AI task: not connected');
      return;
    }
    final data = {
      'taskId': taskId,
      'targetDeviceId': targetDeviceId,
      'ciphertext': ciphertext,
    };
    _socket!.emit('ai_task_request', data);
  }

  /// Acknowledge receipt of AI task response.
  void ackAiTask(String taskId) {
    emit('ai_task_ack', {'taskId': taskId});
  }

  /// Cancel an AI task.
  void cancelAiTask(String taskId) {
    emit('ai_task_cancel', {'taskId': taskId});
  }

  /// Clean up resources.
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _connectivitySub = null;
    disconnect();
    _socket?.dispose();
    _socket = null;
    _incomingEnvelopeController.close();
    _messageStatusController.close();
    _typingController.close();
    _presenceController.close();
    _connectionController.close();
    _prekeysLowController.close();
    _forcePrekeyUploadController.close();
    _messageDeletedController.close();
    _chatDeletedController.close();
    _groupMessagesClearedController.close();
    _userRegisteredController.close();
    _groupMemberAddedController.close();
    _groupMemberRemovedController.close();
    _groupUpdatedController.close();
    _groupOwnerChangedController.close();
    _groupInviteController.close();
    _groupInviteRejectedController.close();
    _senderKeyRequestController.close();
    _senderKeyRequestFailedController.close();
    _messageRetryRequestController.close();
    _groupMessageRetryRequestController.close();
    _friendRequestReceivedController.close();
    _channelOwnerChangedController.close();
    _channelDeletedController.close();
    _aiTaskResponseController.close();
    _aiTaskStatusController.close();
    _sealedCallSignalingController.close();
  }

  /// Phase 8.2 VoIP: Sealed Sender signaling send (§24.2).
  /// Server does not know envelope contents and only performs memory-only relay.
  /// onAck callback receives `{relayed: true}`, `{offline: true}`, or an error response.
  ///
  /// Path B v4 (C2) + Fix D/E (2026-05-06):
  /// - [signalType]: coarse type tag for server push gating.
  ///   'invite' → triggers always-push when callee on PATHB_MIN_CLIENT_VERSION.
  ///   'end'    → reuse-branch enqueue1to1 + sendVoipCancel FCM (Android BG isolate
  ///              dismisses Telecom Connection without main engine boot).
  ///   'other'  → legacy isOffline-only path for offer/answer/ICE.
  ///   Plan §2.5 / §2.7 / §10.16, §2.6.2 callId class.
  /// - [callId]: caller-allocated RFC4122 v4 UUID for end-to-end nonce alignment
  ///   (F1, Plan §2.10, Z-fix §2.6.2). Server uses this as PushKit nonce on invite
  ///   so callee's Telecom Connection id == envelope-internal callId. On call_end
  ///   server passes this to sendVoipCancel so the BG isolate's `endCall(callId)`
  ///   matches the Connection raised at invite time. Other signal types may pass null.
  void sendSealedCallSignaling({
    required String recipientSnowchatId,
    required String envelope,
    String signalType = 'other',
    String? callId,
    void Function(dynamic)? onAck,
  }) {
    if (!_isReadyToSend()) {
      onAck?.call({
        'error': {
          'code': 'NOT_CONNECTED',
          'message': 'Socket not connected',
        },
      });
      return;
    }
    // Don't log envelope/recipient — Zero-Trace §23
    final payload = <String, dynamic>{
      'recipientSnowchatId': recipientSnowchatId,
      'envelope': envelope,
      'signalType': signalType,
    };
    if (callId != null) {
      payload['callId'] = callId;
    }
    _socket!.emitWithAck(
      'sealed_call_signaling',
      payload,
      ack: (response) {
        onAck?.call(response);
      },
    );
  }
}
