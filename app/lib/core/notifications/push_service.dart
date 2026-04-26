/// @file        push_service.dart
/// @description Push notification service. FCM token management + background notification trigger based on Socket.IO events.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - PushService: service that receives push notification events and triggers local notifications
///  - PushService.initialize(): obtain FCM token + register socket event listeners
///  - PushService.registerFcmToken(): register FCM token with server
///  - PushService.unregisterPushToken(): unregister push token from server (on logout)
///  - PushService.dispose(): resource cleanup

import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../network/socket_manager.dart';
import '../storage/secure_storage.dart';
import 'notification_service.dart';

/// Manages push notification triggers based on FCM + Socket.IO events.
///
/// Privacy policy (Zero-Knowledge):
/// - Push payload contains NO message content
/// - Data-only: { type: "new_message", conversationId: "..." }
/// - Client receives silent push -> fetches encrypted message -> decrypts -> shows local notification
class PushService {
  final SocketManager _socketManager;
  final NotificationService _notificationService;
  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;

  /// Current user's SnowChat ID — used to filter out own messages.
  String? mySnowId;

  // Recently notified message IDs — prevents Socket.IO + FCM duplicate alerts.
  final Set<String> _recentlyNotifiedIds = {};

  StreamSubscription<Map<String, dynamic>>? _groupInviteSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  PushService({
    required SocketManager socketManager,
    required NotificationService notificationService,
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
  })  : _socketManager = socketManager,
        _notificationService = notificationService,
        _apiClient = apiClient,
        _secureStorage = secureStorage;

  String? _cachedFcmToken;

  /// Initialize push service: request permission, get FCM token, register listeners.
  Future<void> initialize() async {
    // Socket.IO listeners (group invites)
    _groupInviteSubscription =
        _socketManager.onGroupInvite.listen(_onGroupInvite);

    // FCM setup
    final fcm = FirebaseMessaging.instance;

    // Request permission (iOS shows dialog, Android 13+ shows dialog)
    await fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get FCM token and register with server
    _cachedFcmToken = await fcm.getToken();
    if (_cachedFcmToken != null) {
      await registerFcmToken(_cachedFcmToken!);
    }

    // Listen for token refresh
    _tokenRefreshSubscription =
        fcm.onTokenRefresh.listen(registerFcmToken);

    // Foreground FCM messages — Socket.IO handles these, so we skip
    FirebaseMessaging.onMessage.listen(_onForegroundFcm);

    debugPrint('[PushService] Initialized with FCM');
  }

  /// Retry FCM token registration after auth completes (device_id now available).
  Future<void> retryTokenRegistration() async {
    _cachedFcmToken ??= await FirebaseMessaging.instance.getToken();
    if (_cachedFcmToken != null) {
      await registerFcmToken(_cachedFcmToken!);
    }
  }

  /// Register FCM token with the server.
  Future<void> registerFcmToken(String token) async {
    try {
      final deviceId = await _secureStorage.read('device_id');
      if (deviceId == null) {
        debugPrint('[PushService] No device_id — skipping token registration');
        return;
      }
      await _apiClient.dio.put(
        ApiEndpoints.devicePushToken(deviceId),
        data: {
          'pushToken': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
      debugPrint(
          '[PushService] FCM token registered: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('[PushService] Failed to register FCM token: $e');
    }
  }

  /// Unregister push token from server (call on logout).
  Future<void> unregisterPushToken() async {
    try {
      final deviceId = await _secureStorage.read('device_id');
      if (deviceId == null) return;
      await _apiClient.dio.put(
        ApiEndpoints.devicePushToken(deviceId),
        data: {
          'pushToken': null,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
      debugPrint('[PushService] Push token unregistered');
    } catch (_) {
      // Network failure on logout is OK — token will expire
    }
  }

  /// Handle foreground FCM message — Socket.IO already handles this, skip.
  void _onForegroundFcm(RemoteMessage message) {
    final type = message.data['type'] as String?;
    final msgId = message.data['messageId'] as String?;

    // Phase 3: AI Desktop Task completed push
    if (type == 'ai_task_completed') {
      final taskId = message.data['conversationId'] as String? ?? '';
      debugPrint('[PushService] AI task completed push: $taskId');
      _notificationService.showMessageNotification(
        senderName: 'SnowClaw AI',
        preview: 'Desktop task completed',
        conversationId: taskId,
      );
      return;
    }

    // Phase I (§25): FCM Voice Push — foreground safety belt.
    // The server `callHandler` only sends when `recipientSocketIds.length === 0`,
    // so this path itself is unreachable while in foreground + connected. Only
    // reachable in the race window where the socket briefly disconnects. In that
    // case `sealed_call_signaling` arrives again on reconnect, so skip silently
    // here (avoids duplicate CallKit).
    if (type == 'incoming_call') {
      debugPrint('[PushService] Foreground incoming_call — socket path will handle');
      return;
    }

    debugPrint('[PushService] Foreground FCM received (skipped): $msgId');
  }

  /// Deduplicate notification by message ID.
  /// Returns true if this ID was already notified recently.
  bool _isDuplicate(String? msgId) {
    if (msgId == null) return false;
    if (_recentlyNotifiedIds.contains(msgId)) return true;
    _recentlyNotifiedIds.add(msgId);
    Future.delayed(const Duration(minutes: 5),
        () => _recentlyNotifiedIds.remove(msgId));
    return false;
  }

  /// Set the currently active conversation (for notification suppression).
  void setActiveConversation(String? conversationId) {}

  /// Handle incoming group invite from socket.
  void _onGroupInvite(Map<String, dynamic> data) {
    debugPrint('[PushService] Group invite received: ${data['groupName']}');
    final groupName = (data['groupName'] ?? 'Group') as String;
    final inviterName =
        ((data['invitedBy'] as Map?)?['displayName'] ?? 'Someone') as String;

    _notificationService.showMessageNotification(
      senderName: groupName,
      preview: '$inviterName invited you to join',
      conversationId: data['groupId'] as String? ?? '',
    );
  }

  /// Clean up subscriptions.
  void dispose() {
    _groupInviteSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
  }
}
