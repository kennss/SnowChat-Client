/// @file        alarm_tool.dart
/// @description Alarm query/create Tool
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; alarm query/create tool)

import 'package:flutter/services.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class AlarmQueryTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/alarm');

  @override
  String get name => 'alarm_query';
  @override
  String get description => 'Query set alarms';

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    try {
      final result = await _channel.invokeMethod('getAlarms');
      final alarms = (result as List?)?.cast<Map>() ?? [];

      if (alarms.isEmpty) {
        return const ToolResult(
          success: true,
          summary: 'No alarms set.',
          transparencyLabel: 'Alarms checked · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('${alarms.length} alarm(s):');
      for (final alarm in alarms) {
        final time = alarm['time'] ?? '?';
        final enabled = alarm['enabled'] == true ? 'ON' : 'OFF';
        final label = alarm['label'] ?? '';
        buf.writeln('  $time [$enabled] $label');
      }

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${alarms.length} alarm(s) accessed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('Alarm access not available on this platform.');
    } catch (e) {
      return ToolResult.error('Alarm query failed: $e');
    }
  }
}

class AlarmCreateTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/alarm');

  @override
  String get name => 'alarm_create';
  @override
  String get description => 'Create a new alarm';
  @override
  bool get requiresConfirmation => true;

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String> previewAction(Map<String, dynamic> params) async {
    final hour = params['hour'] ?? '?';
    final minute = params['minute'] ?? '00';
    final label = params['label'] ?? '';
    return 'Set alarm: $hour:$minute $label\n\nConfirm?';
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final hour = params['hour'] as int? ?? 7;
    final minute = params['minute'] as int? ?? 0;
    final label = params['label'] as String? ?? '';

    try {
      await _channel.invokeMethod('createAlarm', {
        'hour': hour,
        'minute': minute,
        'label': label,
      });

      return ToolResult(
        success: true,
        summary: 'Alarm set for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $label',
        transparencyLabel: 'Alarm created · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('Alarm not available on this platform.');
    } catch (e) {
      return ToolResult.error('Alarm create failed: $e');
    }
  }
}
