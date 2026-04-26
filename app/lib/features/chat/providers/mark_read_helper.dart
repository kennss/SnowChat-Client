/// @file        mark_read_helper.dart
/// @description Signal's MarkReadHelper pattern — mark-as-read on chat-room entry, 200ms debounce, drift DB SSoT
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-01
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-01)
///
/// @functions
///  - MarkReadHelper: Signal-pattern read processing (drift DB + debounce + Sticky Thread)
///  - isConversationActive(): check whether a specific conversation is currently open (static)
///  - activate(): called on chat-room entry (ChatScreen.initState)
///  - deactivate(): called on chat-room exit (ChatScreen.dispose)
///  - markAllVisibleAsRead(): mark all as read on chat-room entry
///  - onViewportChanged(): mark visible messages as read on scroll (200ms debounce)
///  - dispose(): resource cleanup

import 'dart:async';

import 'package:flutter/foundation.dart';
import '../../../core/network/socket_manager.dart';
import '../../../core/storage/daos/message_dao.dart';
import '../../../core/storage/database.dart';
import 'expiring_message_manager.dart';

/// Dart implementation of Signal's MarkReadHelper.
/// Bound to the ChatScreen Widget lifecycle (initState/dispose).
/// Operates fully independently of ChatNotifier — writes only to the drift DB.
class MarkReadHelper {
  final String conversationId;
  final MessageDao _messageDao;
  final SocketManager? _socketManager;
  final ExpiringMessageManager? _expiringManager;
  final String _myId;

  /// Callback when messages are marked as read (for notification cancel, etc.)
  final void Function(List<LocalMessage> markedMessages)? onMarkedRead;

  static const _debounceDelay = Duration(milliseconds: 200);

  // --- Global active conversation tracking (Sticky Thread) ---
  // Static Set tracks which conversations are currently open.
  // Used by MessageRepository to decide read=true vs read=false on insert.
  static final _activeConversations = <String>{};

  /// Check if a conversation is currently being viewed by the user.
  static bool isConversationActive(String id) =>
      _activeConversations.contains(id);

  /// Debug: expose active set for logging.
  static String get debugActiveSet => _activeConversations.toString();

  Timer? _debounceTimer;
  int _latestVisibleTimestamp = 0;
  bool _disposed = false;

  MarkReadHelper({
    required this.conversationId,
    required MessageDao messageDao,
    SocketManager? socketManager,
    ExpiringMessageManager? expiringManager,
    required String myId,
    this.onMarkedRead,
  })  : _messageDao = messageDao,
        _socketManager = socketManager,
        _expiringManager = expiringManager,
        _myId = myId;

  /// Called in ChatScreen.initState. Marks this conversation as actively viewed.
  void activate() {
    _activeConversations.add(conversationId);
    debugPrint('[MarkReadHelper] Activated: $conversationId');
  }

  /// Called in ChatScreen.dispose. Marks this conversation as no longer viewed.
  void deactivate() {
    _activeConversations.remove(conversationId);
    debugPrint('[MarkReadHelper] Deactivated: $conversationId');
  }

  /// Mark all messages as read on chat room entry.
  /// Uses current time to mark everything up to now.
  void markAllVisibleAsRead() {
    if (_disposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _latestVisibleTimestamp = now;
    _markRead(now);
  }

  /// Called when viewport changes (scroll). 200ms debounce.
  void onViewportChanged(int latestTimestamp) {
    if (_disposed) return;
    if (latestTimestamp <= _latestVisibleTimestamp) return;
    _latestVisibleTimestamp = latestTimestamp;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () {
      if (!_disposed) _markRead(_latestVisibleTimestamp);
    });
  }

  Future<void> _markRead(int upToTimestamp) async {
    if (_disposed) return;

    try {
      final marked = await _messageDao.markAsRead(
        conversationId: conversationId,
        upToTimestamp: upToTimestamp,
      );

      if (marked.isNotEmpty && !_disposed) {
        // Send read receipts to server via socket
        final receiptIds = marked.map((m) => m.id).toList();
        _socketManager?.sendReadReceipt(receiptIds);
        debugPrint(
            '[MarkReadHelper] Marked ${marked.length} messages as read, sent receipts');

        // Signal pattern: start expiry timer the moment a message is read
        if (_expiringManager != null) {
          for (final msg in marked) {
            if (msg.expiresIn > 0 && msg.expireStarted == 0) {
              _expiringManager.schedule(msg.id, msg.expiresIn);
              debugPrint('[MarkReadHelper] Started expiry timer: ${msg.id} ttl=${msg.expiresIn}s');
            }
          }
        }

        onMarkedRead?.call(marked);
      }
    } catch (e) {
      debugPrint('[MarkReadHelper] markRead failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    deactivate();
    _debounceTimer?.cancel();
  }
}
