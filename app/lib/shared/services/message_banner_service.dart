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
/// @lastUpdated 2026-04-26
///
/// @functions
///  - MessageBannerService.maybeShow(): main entry. Skips if user is
///    actively viewing the conversation, otherwise displays the banner.

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
