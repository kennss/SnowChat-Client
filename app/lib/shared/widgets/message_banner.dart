/// @file        message_banner.dart
/// @description Top sliding in-app banner for incoming messages while the
///              user is viewing another screen. Mirrors Signal/WhatsApp/
///              KakaoTalk pattern (in-app overlay, NOT OS notification —
///              that is handled by push when the app is backgrounded).
///              Inserted into the root Overlay by [MessageBannerService].
///              Visual identity follows SnowToast (SnowColors.surface bg,
///              radius 12, 0.3α primary border, 12px gap).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-26
/// @lastUpdated 2026-08-03 (resolve the sender name from roster/contacts/friends
///              instead of rendering the raw snow-id a receive-first/sealed
///              sender carries — MessageBanner is now a ConsumerWidget)
///
/// @functions
///  - MessageBanner: animated top banner widget (resolves sender displayName)
///  - BannerMessageData: minimal payload (sender / preview / avatar id)

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chat/utils/sender_name_resolver.dart';
import '../constants/colors.dart';
import 'snow_avatar.dart';

class BannerMessageData {
  const BannerMessageData({
    required this.conversationId,
    required this.senderName,
    required this.preview,
    required this.snowId,
  });

  final String conversationId;
  final String senderName;
  final String preview;

  /// SnowChat ID — used by SnowAvatar for stable color hash + initials.
  final String snowId;
}

class MessageBanner extends ConsumerStatefulWidget {
  const MessageBanner({
    super.key,
    required this.data,
    required this.onTap,
    required this.onDismiss,
  });

  final BannerMessageData data;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  ConsumerState<MessageBanner> createState() => _MessageBannerState();
}

class _MessageBannerState extends ConsumerState<MessageBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  Future<void> _animateOutAndDispatch() async {
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Resolve the sender's name from contacts/friends. The banner builder
    // (message_queue) passes the raw snow-id as senderName when it has no name
    // (the MVP placeholder == snowId); treat that as "no hint" so the resolver
    // fills in a real name instead of showing the snow-id. roomId is omitted so
    // 1:1 banners don't trigger a group-roster fetch; group senders who aren't
    // contacts fall back to the short snow-id (the persistent group bubble
    // resolves those via the roster).
    final senderName = resolveSenderName(
      ref,
      widget.data.snowId,
      envelopeName: widget.data.senderName == widget.data.snowId
          ? null
          : widget.data.senderName,
    );
    return Positioned(
      top: mq.padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) < -100) {
                _animateOutAndDispatch();
              }
            },
            onTap: () {
              widget.onTap();
              _animateOutAndDispatch();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: SnowColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SnowColors.primary.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SnowAvatar(
                    snowId: widget.data.snowId,
                    size: 36,
                    displayName: senderName,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SnowColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.data.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SnowColors.textSecondary,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: SnowColors.textTertiary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
