/// @file        base_tool.dart
/// @description AI Tool base interface — contract every Tool must implement
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-14
/// @lastUpdated 2026-04-26 (header + inline English translation; AI tool base interface)

import '../service/tool_router.dart';

/// Base interface for every AI Tool
abstract class BaseTool {
  /// Tool unique name (must match the name in the AI system prompt)
  String get name;

  /// Tool description (for debugging/logging)
  String get description;

  /// Whether this is a write action (true requires user confirmation)
  bool get requiresConfirmation => false;

  /// Check whether permission is held
  Future<bool> hasPermission();

  /// Request permission (Just-in-Time)
  Future<bool> requestPermission();

  /// Execute the Tool
  Future<ToolResult> execute(Map<String, dynamic> params);

  /// Preview a write action (for the confirmation dialog)
  Future<String> previewAction(Map<String, dynamic> params) async {
    return 'Confirm action: $name with $params';
  }
}
