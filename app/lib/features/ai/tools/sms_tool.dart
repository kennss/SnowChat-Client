/// @file        sms_tool.dart
/// @description SMS/MMS search Tool — package tracking, OTP codes, conversation search
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; SMS/MMS search tool)

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class SmsTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/sms');

  @override
  String get name => 'sms_search';
  @override
  String get description => 'Search SMS messages by keyword or sender';

  @override
  Future<bool> hasPermission() => Permission.sms.isGranted;
  @override
  Future<bool> requestPermission() async =>
      (await Permission.sms.request()).isGranted;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final keyword = params['keyword'] as String? ?? '';
    final sender = params['sender'] as String? ?? '';
    final limit = params['limit'] as int? ?? 10;

    try {
      final result = await _channel.invokeMethod('searchSms', {
        'keyword': keyword,
        'sender': sender,
        'limit': limit,
      });

      final messages = (result as List?)?.cast<Map>() ?? [];

      if (messages.isEmpty) {
        return ToolResult(
          success: true,
          summary: 'No SMS messages found${keyword.isNotEmpty ? ' matching "$keyword"' : ''}.',
          transparencyLabel: 'SMS searched · No matches · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('Found ${messages.length} message(s):');
      for (final msg in messages) {
        final from = msg['address'] ?? 'Unknown';
        final body = msg['body'] ?? '';
        final date = msg['date'] ?? '';
        final preview = body.length > 80 ? '${body.substring(0, 80)}...' : body;
        buf.writeln('  [$from] $date — $preview');
      }

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${messages.length} SMS accessed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('SMS access not available on this platform.');
    } catch (e) {
      return ToolResult.error('SMS search failed: $e');
    }
  }
}
