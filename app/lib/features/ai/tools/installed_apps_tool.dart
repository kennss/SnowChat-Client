/// @file        installed_apps_tool.dart
/// @description Installed apps list Tool — no permission required
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; installed apps list tool — no permission required)

import 'package:flutter/services.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class InstalledAppsTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/apps');

  @override
  String get name => 'installed_apps';
  @override
  String get description => 'List or search installed apps';

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final query = params['query'] as String? ?? '';

    try {
      final result = await _channel.invokeMethod('getInstalledApps', {
        'query': query,
      });

      final apps = (result as List?)?.cast<Map>() ?? [];

      if (apps.isEmpty) {
        return ToolResult(
          success: true,
          summary: query.isEmpty
              ? 'No apps found.'
              : 'No apps matching "$query" found.',
          transparencyLabel: 'App list checked · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('Found ${apps.length} app(s):');
      for (final app in apps.take(20)) {
        buf.writeln('  • ${app['name']}');
      }
      if (apps.length > 20) buf.writeln('  ... and ${apps.length - 20} more');

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${apps.length} app(s) listed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('App listing not available on this platform.');
    } catch (e) {
      return ToolResult.error('App search failed: $e');
    }
  }
}
