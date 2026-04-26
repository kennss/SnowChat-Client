/// @file        presence_service.dart
/// @description User online/offline presence tracking service. Subscribes to Socket.IO presence events and manages connection state and last-seen time.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///  - changed to snowchatId-based matching (removed userId/CUID usage)
///  - added bulk online_users event handling
///
/// @functions
///  - PresenceService: online presence tracking service class
///  - isOnline(userId): return whether a specific user is online
///  - getLastSeen(userId): return last-seen time for a specific user
///  - dispose(): resource cleanup

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'socket_manager.dart';

/// Tracks online/offline presence for users via Socket.IO events.
class PresenceService extends ChangeNotifier {
  final SocketManager _socketManager;

  final Set<String> _onlineUsers = {};
  final Map<String, DateTime> _lastSeen = {};

  StreamSubscription<Map<String, dynamic>>? _presenceSubscription;

  PresenceService(this._socketManager) {
    // Replay buffered online_users data that may have arrived before subscription
    final buffered = _socketManager.lastOnlineUsersData;
    if (buffered != null && buffered['bulk'] == true) {
      final users = (buffered['users'] as List).cast<String>();
      _onlineUsers.addAll(users);
      debugPrint('[PresenceService] Loaded ${users.length} buffered online users');
    }
    _listenToPresence();
  }

  void _listenToPresence() {
    _presenceSubscription = _socketManager.onPresence.listen((data) {
      // Bulk online_users: replace entire set at once
      if (data['bulk'] == true) {
        final users = (data['users'] as List).cast<String>();
        _onlineUsers
          ..clear()
          ..addAll(users);
        notifyListeners();
        return;
      }

      // Individual presence: use snowchatId only (not userId/CUID)
      final snowchatId = data['snowchatId'] as String?;
      if (snowchatId == null) return;

      final isOnlineEvent = data['online'] as bool? ?? false;

      if (isOnlineEvent) {
        _onlineUsers.add(snowchatId);
      } else {
        _onlineUsers.remove(snowchatId);
        _lastSeen[snowchatId] = DateTime.now();
      }

      notifyListeners();
    });
  }

  /// Whether [userId] is currently online (connected via Socket.IO).
  bool isOnline(String userId) => _onlineUsers.contains(userId);

  /// The last time [userId] was seen online. Returns null if never seen.
  DateTime? getLastSeen(String userId) => _lastSeen[userId];

  /// Format last seen time as a human-readable string.
  String? formatLastSeen(String userId) {
    final lastSeen = _lastSeen[userId];
    if (lastSeen == null) return null;

    final diff = DateTime.now().difference(lastSeen);
    if (diff.inSeconds < 60) return 'Last seen just now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Last seen ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Last seen yesterday';
    return 'Last seen ${diff.inDays}d ago';
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    super.dispose();
  }
}
