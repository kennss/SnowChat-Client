/// @file        expiring_message_manager.dart
/// @description Expiring-message manager — Signal ExpiringMessageManager pattern.
///              drift DB-based expiry scheduling, physical deletion, recovery on app restart
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-02
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-02)
///
/// @functions
///  - ExpiringMessageManager: expiring-message management class
///  - initialize(): on app start, load pending expiring messages and schedule them
///  - schedule(): register a Timer for a new expiring message
///  - rekey(): swap Timer key on ACK (localId -> serverId)
///  - cancel(): cancel a Timer
///  - _deleteExpiredMessage(): physical deletion (message + attachments + local files)

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../../core/storage/daos/attachment_dao.dart';
import '../../../core/storage/daos/message_dao.dart';

/// Signal's ExpiringMessageManager adapted for Flutter/drift.
///
/// On app startup, loads all messages with expireStarted > 0 from drift,
/// calculates remaining TTL, and schedules Timer-based deletion.
/// When a timer fires, physically deletes the message + attachments + local files.
class ExpiringMessageManager {
  final MessageDao _messageDao;
  final AttachmentDao _attachmentDao;
  final Map<String, Timer> _timers = {};

  ExpiringMessageManager({
    required MessageDao messageDao,
    required AttachmentDao attachmentDao,
  })  : _messageDao = messageDao,
        _attachmentDao = attachmentDao;

  /// Load all pending expirations from drift and schedule timers.
  /// Called once on app startup (after auth).
  Future<void> initialize() async {
    try {
      final pending = await _messageDao.getExpiringMessages();
      var expiredCount = 0;
      var scheduledCount = 0;

      for (final msg in pending) {
        final expiresAtMs = msg.expireStarted + msg.expiresIn * 1000;
        final remainingMs =
            expiresAtMs - DateTime.now().millisecondsSinceEpoch;

        if (remainingMs <= 0) {
          // Already expired — delete immediately
          await _deleteExpiredMessage(msg.id);
          expiredCount++;
        } else {
          _scheduleTimer(msg.id, Duration(milliseconds: remainingMs));
          scheduledCount++;
        }
      }

      if (expiredCount > 0 || scheduledCount > 0) {
        debugPrint(
            '[ExpiringManager] Initialized: $expiredCount expired (deleted), '
            '$scheduledCount scheduled');
      }
    } catch (e) {
      debugPrint('[ExpiringManager] Initialize failed: $e');
    }
  }

  /// Schedule deletion for a new expiring message.
  void schedule(String messageId, int ttlSeconds) {
    if (ttlSeconds <= 0) return;
    _scheduleTimer(messageId, Duration(seconds: ttlSeconds));
  }

  /// Replace timer key when server ACK replaces local ID with CUID.
  void rekey(String oldId, String newId) {
    final timer = _timers.remove(oldId);
    if (timer != null) {
      // Timer is still running with the old callback referencing oldId.
      // Cancel it and create a new one with the remaining time.
      // Since we can't read remaining time from a Timer, we check drift.
      timer.cancel();
      _rekeyAsync(newId);
    }
  }

  /// Async rekey: read the updated drift row to get accurate remaining time.
  Future<void> _rekeyAsync(String newId) async {
    try {
      final msg = await _messageDao.getMessageById(newId);
      if (msg == null || msg.expiresIn <= 0 || msg.expireStarted <= 0) return;

      final expiresAtMs = msg.expireStarted + msg.expiresIn * 1000;
      final remainingMs =
          expiresAtMs - DateTime.now().millisecondsSinceEpoch;

      if (remainingMs <= 0) {
        await _deleteExpiredMessage(newId);
      } else {
        _scheduleTimer(newId, Duration(milliseconds: remainingMs));
      }
    } catch (e) {
      debugPrint('[ExpiringManager] Rekey failed for $newId: $e');
    }
  }

  /// Cancel a pending timer (e.g., message manually deleted before expiry).
  void cancel(String messageId) {
    _timers.remove(messageId)?.cancel();
  }

  /// Number of active timers (for debugging).
  int get activeTimerCount => _timers.length;

  /// Clean up all timers.
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _scheduleTimer(String messageId, Duration duration) {
    _timers[messageId]?.cancel();
    _timers[messageId] = Timer(duration, () {
      _timers.remove(messageId);
      _deleteExpiredMessage(messageId);
    });
  }

  /// Physically delete an expired message and its attachments + local files.
  Future<void> _deleteExpiredMessage(String messageId) async {
    try {
      // 1. Get and delete local attachment files
      final attachments = await _attachmentDao.getForMessage(messageId);
      for (final att in attachments) {
        if (att.localPath != null) {
          try {
            final file = File(att.localPath!);
            if (file.existsSync()) file.deleteSync();
          } catch (_) {}
        }
      }

      // 2. Delete attachment rows
      if (attachments.isNotEmpty) {
        await _attachmentDao.deleteForMessage(messageId);
      }

      // 3. Delete message row (triggers drift watch → UI update)
      await _messageDao.deleteMessage(messageId);

      debugPrint('[ExpiringManager] Deleted expired message $messageId '
          '(${attachments.length} attachments)');
    } catch (e) {
      debugPrint('[ExpiringManager] Delete failed for $messageId: $e');
    }
  }
}
