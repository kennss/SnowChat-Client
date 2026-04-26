/// @file        notification_tool.dart
/// @description Notification read Tool — backed by NotificationListenerService
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; notification read tool — NotificationListenerService)

import 'package:flutter/services.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class NotificationTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/notifications');

  @override
  String get name => 'notifications';
  @override
  String get description => 'Read active notifications';

  @override
  Future<bool> hasPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('hasNotificationAccess');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationAccess');
      return await hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final app = params['app'] as String? ?? '';
    final limit = params['limit'] as int? ?? 10;

    try {
      final result = await _channel.invokeMethod('getNotifications', {
        'app': app,
        'limit': limit,
      });

      final notifications = (result as List?)?.cast<Map>() ?? [];

      if (notifications.isEmpty) {
        return const ToolResult(
          success: true,
          summary: 'No active notifications.',
          transparencyLabel: 'Notifications checked · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('${notifications.length} notification(s):');
      for (final n in notifications) {
        final appName = n['app'] ?? 'Unknown';
        final title = n['title'] ?? '';
        final text = n['text'] ?? '';
        final preview = text.length > 60 ? '${text.substring(0, 60)}...' : text;
        buf.writeln('  [$appName] $title — $preview');
      }

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${notifications.length} notification(s) accessed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('Notification access not available on this platform.');
    } catch (e) {
      return ToolResult.error('Notification read failed: $e');
    }
  }
}
