/// @file        notification_service.dart
/// @description Local notification service. Displays local notifications based on decrypted messages, iOS permission requests, notification tap navigation handling.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - NotificationService: local notification initialization and management class
///  - NotificationService.initialize(): initialize notification plugin and request permissions
///  - NotificationService.showMessageNotification(): show 1:1 message local notification
///  - NotificationService.showGroupNotification(): show group message local notification
///  - NotificationService.requestPermissions(): request iOS notification permission

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Callback type for handling notification taps.
/// Receives the conversationId to navigate to.
typedef NotificationTapCallback = void Function(String conversationId);

/// Service for displaying local notifications after E2EE message decryption.
///
/// Push notification flow (Zero-Knowledge):
/// 1. Server sends data-only push: { type: "new_message", conversationId }
/// 2. Client receives silent push / socket event while backgrounded
/// 3. Client fetches encrypted message from server
/// 4. Client decrypts locally with libsignal
/// 5. This service shows a local notification with decrypted content
///
/// The push payload NEVER contains message content.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Callback invoked when user taps a notification.
  NotificationTapCallback? onNotificationTap;

  /// Initialize the local notification plugin and request permissions.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Request permissions on iOS and Android 13+
    await requestPermissions();

    _initialized = true;
    debugPrint('[NotificationService] Initialized');
  }

  /// Request notification permissions (iOS and Android 13+).
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final iosPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin == null) return false;

      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[NotificationService] iOS permissions granted: $granted');
      return granted ?? false;
    }

    if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return false;

      final granted = await androidPlugin.requestNotificationsPermission();
      debugPrint('[NotificationService] Android permissions granted: $granted');
      return granted ?? false;
    }

    return true;
  }

  /// Show a local notification for a 1:1 message.
  ///
  /// Called after the client has decrypted the message locally.
  /// [senderName] — display name of the sender.
  /// [preview] — decrypted message preview text.
  /// [conversationId] — used for navigation on tap.
  Future<void> showMessageNotification({
    required String senderName,
    required String preview,
    required String conversationId,
  }) async {
    if (!_initialized) {
      debugPrint('[NotificationService] Not initialized, skipping notification');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'snowchat_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      onlyAlertOnce: false, // Re-alert (sound+banner) on every update
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Android: fixed ID per conversation (update in place, re-alert via onlyAlertOnce:false)
    // iOS: unique ID per message (iOS silently updates same-ID notifications without re-alerting)
    final notificationId = Platform.isAndroid
        ? conversationId.hashCode
        : DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;

    await _plugin.show(
      notificationId,
      senderName,
      preview,
      details,
      payload: conversationId,
    );
  }

  /// Show a local notification for a group message.
  ///
  /// [groupName] — display name of the group.
  /// [senderName] — display name of the message sender.
  /// [preview] — decrypted message preview text.
  /// [conversationId] — used for navigation on tap.
  Future<void> showGroupNotification({
    required String groupName,
    required String senderName,
    required String preview,
    required String conversationId,
  }) async {
    if (!_initialized) {
      debugPrint('[NotificationService] Not initialized, skipping notification');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'snowchat_group_messages',
      'Group Messages',
      channelDescription: 'New group message notifications',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final notificationId = Platform.isAndroid
        ? conversationId.hashCode
        : DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;

    await _plugin.show(
      notificationId,
      groupName,
      '$senderName: $preview',
      details,
      payload: conversationId,
    );
  }

  /// Handle notification tap — navigate to the conversation.
  void _onNotificationResponse(NotificationResponse response) {
    final conversationId = response.payload;
    if (conversationId != null && conversationId.isNotEmpty) {
      debugPrint(
        '[NotificationService] Notification tapped: $conversationId',
      );
      onNotificationTap?.call(conversationId);
    }
  }

  /// Cancel all notifications.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Cancel notifications for a specific conversation.
  Future<void> cancelForConversation(String conversationId) async {
    await _plugin.cancel(conversationId.hashCode);
  }
}
