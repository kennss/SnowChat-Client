/// @file        app_usage_tool.dart
/// @description App usage time Tool — screen time analysis
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; app usage time tool — screen time analysis)

import 'package:flutter/services.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class AppUsageTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/usage');

  @override
  String get name => 'app_usage';
  @override
  String get description => 'Get app usage statistics (screen time)';

  @override
  Future<bool> hasPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('hasUsagePermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      await _channel.invokeMethod('requestUsagePermission');
      return await hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final period = params['period'] as String? ?? 'today'; // today, week

    try {
      final result = await _channel.invokeMethod('getAppUsage', {
        'period': period,
      });

      final usage = (result as List?)?.cast<Map>() ?? [];

      if (usage.isEmpty) {
        return const ToolResult(
          success: true,
          summary: 'No app usage data available.',
          transparencyLabel: 'Usage stats checked · No server transmission',
        );
      }

      int totalMinutes = 0;
      final buf = StringBuffer();
      buf.writeln('Screen time ($period):');
      for (final app in usage.take(10)) {
        final name = app['name'] ?? 'Unknown';
        final minutes = app['minutes'] as int? ?? 0;
        totalMinutes += minutes;
        final h = minutes ~/ 60;
        final m = minutes % 60;
        final timeStr = h > 0 ? '${h}h ${m}m' : '${m}m';
        buf.writeln('  $name — $timeStr');
      }
      final totalH = totalMinutes ~/ 60;
      final totalM = totalMinutes % 60;
      buf.writeln('\nTotal: ${totalH}h ${totalM}m');

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${usage.length} app(s) usage analyzed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('App usage not available on this platform.');
    } catch (e) {
      return ToolResult.error('App usage query failed: $e');
    }
  }
}
