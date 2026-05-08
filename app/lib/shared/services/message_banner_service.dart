/// @file        message_banner_service.dart
/// @description Singleton service that shows [MessageBanner] in the root
///              Overlay. Mirrors Signal/WhatsApp pattern: incoming messages
///              while the user is on another screen pop a top sliding
///              in-app banner. While the user is actively viewing the
///              same conversation, the banner is silent (the message is
///              already in the chat list). OS push notifications still
///              cover the backgrounded case (separate path).
///              Visual identity / spec: see message_banner.dart header.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-26
/// @lastUpdated 2026-04-28 (showFriendRequest — Friends tab 외 다른 화면에서
///                          친구 요청 도착 시 in-app 배너로 알림)
///
/// @functions
///  - MessageBannerService.maybeShow(): incoming message banner
///  - MessageBannerService.showFriendRequest(): incoming friend request banner
///    — 사용자가 Friends 탭에 있을 때는 silent (이미 list 에 즉시 반영됨)

library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart' show rootNavigatorKey;
import '../../features/chat/providers/mark_read_helper.dart';
import '../widgets/message_banner.dart';

class MessageBannerService {
  MessageBannerService._();
  static final MessageBannerService instance = MessageBannerService._();

  /// 4 second auto-dismiss — matches Signal / WhatsApp / KakaoTalk.
  static const _autoDismissDuration = Duration(seconds: 4);

  OverlayEntry? _current;
  Timer? _autoDismissTimer;

  /// Show banner for an incoming message. Caller passes the conversation /
  /// sender / preview. Service handles:
  ///  - skip if user is currently viewing that conversation (silent)
  ///  - skip if root navigator / overlay is unavailable (early boot,
  ///    splash, etc.)
  ///  - replace previous banner if one is already on-screen (latest wins)
  ///  - auto-dismiss after [_autoDismissDuration]
  ///  - tap → navigate to /chat/<conversationId>
  void maybeShow(BannerMessageData data) {
    // Guard 1: silently drop if user is in that chat (already visible).
    if (MarkReadHelper.isConversationActive(data.conversationId)) {
      return;
    }

    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Guard 2: app not yet built / splash. Drop silently.
      debugPrint('[MessageBanner] no overlay — drop banner');
      return;
    }

    // Replace any current banner — latest message takes precedence.
    _dismissCurrent();

    final entry = OverlayEntry(
      builder: (_) => MessageBanner(
        data: data,
        onTap: () => _navigateTo(data.conversationId),
        onDismiss: _dismissCurrent,
      ),
    );
    _current = entry;
    overlay.insert(entry);

    _autoDismissTimer = Timer(_autoDismissDuration, _dismissCurrent);
  }

  /// Show a friend-request banner. Caller passes requester display name +
  /// snowId for avatar. Tap → navigate to /friends. Silent if the user is
  /// already on the Friends tab (list updates immediately so banner = noise).
  void showFriendRequest({
    required String fromSnowchatId,
    required String fromDisplayName,
  }) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      debugPrint('[MessageBanner] no overlay — drop friend request banner');
      return;
    }

    // 현재 라우트가 /friends 면 silent (badge + list 가 즉시 반영).
    final ctx = rootNavigatorKey.currentContext;
    final currentLoc = ctx != null
        ? GoRouter.of(ctx).routerDelegate.currentConfiguration.uri.path
        : null;
    if (currentLoc == '/friends') return;

    _dismissCurrent();

    final data = BannerMessageData(
      conversationId: '__friend_request__$fromSnowchatId',
      senderName: fromDisplayName.isNotEmpty
          ? fromDisplayName
          : fromSnowchatId.substring(0, 12),
      preview: 'Sent you a friend request',
      snowId: fromSnowchatId,
    );

    final entry = OverlayEntry(
      builder: (_) => MessageBanner(
        data: data,
        onTap: _navigateToFriends,
        onDismiss: _dismissCurrent,
      ),
    );
    _current = entry;
    overlay.insert(entry);

    _autoDismissTimer = Timer(_autoDismissDuration, _dismissCurrent);
  }

  void _navigateToFriends() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ctx.go('/friends');
    } catch (e) {
      debugPrint('[MessageBanner] navigate to friends failed: $e');
    }
  }

  void _dismissCurrent() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    _current?.remove();
    _current = null;
  }

  void _navigateTo(String conversationId) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ctx.push('/chat/$conversationId');
    } catch (e) {
      debugPrint('[MessageBanner] navigate failed: $e');
    }
  }
}
