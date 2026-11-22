/// @file        notification_service.dart
/// @description Local notification service. Displays local notifications based on decrypted messages, iOS permission requests, notification tap navigation handling.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-11-22 (asks no permission: the notification prompt is askStartupPrompts only — requestPermissions() removed). Earlier 2026-11-22 (route payloads are `route:<path>` — the group invite notification opens the chat list, where invites wait, instead of /chat/<groupId>; a tap that launched the app — getNotificationAppLaunchDetails — is
///              delivered once its callback is set, so a friend notification tapped after the app was
///              closed still opens the Friends tab (and a message one its chat); handleTapPayload()
///              routes a payload). Earlier 2026-11-22 (showFriendNotification(): a friend request
///              received or accepted while the
///              app is open — the tap opens the Friends tab (onRouteTap, payload friendsPayload) instead
///              of a chat; a friend request used to open `/chat/__friend_request__…`, a room that does
///              not exist). Earlier 2026-11-22 (showGroupInviteNotification(): an invite that arrives while the app is open — the server's push is not shown in the foreground, and nothing else told the user)
///
/// @functions
///  - NotificationService: local notification initialization and management class
///  - NotificationService.initialize(): initialize notification plugin and request permissions
///  - NotificationService.showMessageNotification(): show 1:1 message local notification
///  - NotificationService.showGroupNotification(): show group message local notification
///  - NotificationService.showGroupInviteNotification(): an invite that arrived while the app is open
///  - NotificationService.showFriendNotification(): a friend request received / accepted (tap → Friends tab)
///  - NotificationService.friendsPayload / onRouteTap: a notification that opens a tab, not a chat
///  - NotificationService.handleTapPayload(): route a tapped notification's payload (a tap that
///    launched the app waits for its callback)

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

  NotificationTapCallback? _onNotificationTap;
  void Function(String route)? _onRouteTap;

  /// The payload of the notification whose tap launched the app, until the
  /// callback that takes it is set.
  String? _launchPayload;

  /// Callback invoked when user taps a notification.
  NotificationTapCallback? get onNotificationTap => _onNotificationTap;
  set onNotificationTap(NotificationTapCallback? callback) {
    _onNotificationTap = callback;
    _deliverLaunchTap();
  }

  /// Callback invoked when the user taps a notification that opens a screen
  /// of the app rather than a chat (the route, e.g. `/friends`).
  void Function(String route)? get onRouteTap => _onRouteTap;
  set onRouteTap(void Function(String route)? callback) {
    _onRouteTap = callback;
    _deliverLaunchTap();
  }

  /// The payload of a friend notification: its tap opens the Friends tab.
  /// Never a conversation id (those are snowIds or 64-hex group ids).
  static const String _routePrefix = 'route:';
  static const String friendsPayload = '${_routePrefix}/friends';

  /// The chat list, where group invites wait for an answer.
  static const String chatListPayload = '${_routePrefix}/chat';

  /// Initialize the local notification plugin and request permissions.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // No prompt here: the notification prompt is asked in one place,
    // askStartupPrompts (core/permissions/microphone_permission.dart) — two
    // requests at once make Android answer the second "denied" unseen.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // A tap on one of this app's notifications after the app was closed
    // launches it without a response event: its payload is taken here and
    // delivered once the app set the callback for it.
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) &&
          payload != null &&
          payload.isNotEmpty) {
        _launchPayload = payload;
        _deliverLaunchTap();
      }
    } catch (e) {
      debugPrint('[NotificationService] launch details not read: ${e.runtimeType}');
    }

    _initialized = true;
    debugPrint('[NotificationService] Initialized');
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

  /// An invite to a group, shown while the app is open (in the background
  /// the server's push covers it). The tap opens the chat list, where the
  /// invite waits for an answer ([groupId] names no conversation yet).
  Future<void> showGroupInviteNotification({
    required String inviterName,
    required String? groupTitle,
    required String groupId,
  }) async {
    if (!_initialized) {
      debugPrint('[NotificationService] Not initialized, skipping notification');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'snowchat_group_invites',
      'Group Invitations',
      channelDescription: 'Invitations to join a group',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: false,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final title = (groupTitle == null || groupTitle.isEmpty) ? 'a group' : groupTitle;
    await _plugin.show(
      groupId.hashCode,
      'Group invitation',
      '$inviterName invited you to $title',
      details,
      payload: chatListPayload,
    );
  }

  /// A friend request received ([accepted] false: "[name] sent you a friend
  /// request") or this user's request accepted ("[name] accepted your
  /// friend request"), shown while the app is open (in the background the
  /// server's "New message" push covers it — the two cannot be told apart
  /// there, by design). The tap opens the Friends tab. One notification per
  /// account ([peer]): a newer one replaces it.
  Future<void> showFriendNotification({
    required String name,
    required String peer,
    required bool accepted,
  }) async {
    if (!_initialized) {
      debugPrint('[NotificationService] Not initialized, skipping notification');
      return;
    }
    const androidDetails = AndroidNotificationDetails(
      'snowchat_friends',
      'Friends',
      channelDescription: 'Friend requests and acceptances',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      playSound: true,
      enableVibration: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: false,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _plugin.show(
      'friend:$peer'.hashCode,
      'SnowChat',
      accepted
          ? '$name accepted your friend request'
          : '$name sent you a friend request',
      details,
      payload: friendsPayload,
    );
  }

  /// Handle notification tap — open the screen it names, or the
  /// conversation.
  void _onNotificationResponse(NotificationResponse response) =>
      handleTapPayload(response.payload);

  /// Route the payload of a tapped notification: the Friends tab for a
  /// friend notification ([friendsPayload]), else the conversation it names.
  void handleTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith(_routePrefix)) {
      _onRouteTap?.call(payload.substring(_routePrefix.length));
      return;
    }
    debugPrint('[NotificationService] Notification tapped');
    _onNotificationTap?.call(payload);
  }

  /// Hand the launching tap's payload to its callback once that is set.
  void _deliverLaunchTap() {
    final payload = _launchPayload;
    if (payload == null) return;
    final ready = payload.startsWith(_routePrefix)
        ? _onRouteTap != null
        : _onNotificationTap != null;
    if (!ready) return;
    _launchPayload = null;
    // Not inside the caller's frame: the callbacks are set while the app's
    // widget tree builds, and a tap navigates.
    scheduleMicrotask(() => handleTapPayload(payload));
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
