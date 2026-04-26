/// @file        call_log_tool.dart
/// @description Call log search Tool
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; call log search tool)

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class CallLogTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/call_log');

  @override
  String get name => 'call_log';
  @override
  String get description => 'Search call history';

  @override
  Future<bool> hasPermission() => Permission.phone.isGranted;
  @override
  Future<bool> requestPermission() async =>
      (await Permission.phone.request()).isGranted;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final contact = params['contact'] as String? ?? '';
    final type = params['type'] as String? ?? 'all'; // all, missed, incoming, outgoing
    final limit = params['limit'] as int? ?? 10;

    try {
      final result = await _channel.invokeMethod('getCallLog', {
        'contact': contact,
        'type': type,
        'limit': limit,
      });

      final calls = (result as List?)?.cast<Map>() ?? [];

      if (calls.isEmpty) {
        return ToolResult(
          success: true,
          summary: 'No call records found.',
          transparencyLabel: 'Call log checked · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('Found ${calls.length} call(s):');
      for (final call in calls) {
        final name = call['name'] ?? call['number'] ?? 'Unknown';
        final callType = call['type'] ?? '?';
        final duration = call['duration'] ?? 0;
        final date = call['date'] ?? '';
        final icon = switch (callType) {
          'incoming' => 'incoming',
          'outgoing' => 'outgoing',
          'missed' => 'MISSED',
          _ => callType,
        };
        buf.writeln('  $icon $name — ${duration}s — $date');
      }

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${calls.length} call(s) accessed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('Call log not available on this platform.');
    } catch (e) {
      return ToolResult.error('Call log search failed: $e');
    }
  }
}
