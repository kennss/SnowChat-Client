/// @file        clipboard_tool.dart
/// @description Clipboard read Tool — access copied text
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; clipboard read tool)

import 'package:flutter/services.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class ClipboardTool extends BaseTool {
  @override
  String get name => 'clipboard';
  @override
  String get description => 'Read clipboard content';

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;

      if (text == null || text.isEmpty) {
        return const ToolResult(
          success: true,
          summary: 'Clipboard is empty.',
          transparencyLabel: 'Clipboard checked · No server transmission',
        );
      }

      final preview = text.length > 500 ? '${text.substring(0, 500)}...' : text;
      return ToolResult(
        success: true,
        summary: 'Clipboard content:\n$preview',
        transparencyLabel: 'Clipboard accessed · No server transmission',
      );
    } catch (e) {
      return ToolResult.error('Clipboard read failed: $e');
    }
  }
}
