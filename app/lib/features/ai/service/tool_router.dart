/// @file        tool_router.dart
/// @description AI Tool invocation router — <tool_call> parsing + Platform API dispatch.
///              dispatch is allowed only from the agenticChat source (prompt injection defense).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-14
/// @lastUpdated 2026-04-26 (header + inline English translation; AI tool invocation router)
///
/// @functions
///  - parseToolCall(): extract <tool_call> JSON from AI response
///  - dispatch(): invoke the appropriate handler by Tool name (source guard)
///  - registerTool(): register a new Tool

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../tools/base_tool.dart';
import 'on_device_ai_service.dart';
import 'security_metrics.dart';

/// Tool invocation info requested by AI
class ToolCall {
  final String tool;
  final Map<String, dynamic> params;
  const ToolCall({required this.tool, required this.params});

  @override
  String toString() => 'ToolCall($tool, $params)';
}

/// Tool execution result
class ToolResult {
  final bool success;
  final String summary;                  // text fed back to AI
  final String? transparencyLabel;       // e.g. "Read 3 contacts · no server transmission"
  final List<dynamic>? data;             // structured data (for UI rendering)
  final bool requiresConfirmation;       // write action requires confirmation
  final String? confirmationMessage;     // confirmation dialog message

  const ToolResult({
    required this.success,
    required this.summary,
    this.transparencyLabel,
    this.data,
    this.requiresConfirmation = false,
    this.confirmationMessage,
  });

  factory ToolResult.error(String message) =>
      ToolResult(success: false, summary: message);

  factory ToolResult.needsPermission(String toolName) =>
      ToolResult(
        success: false,
        summary: 'Permission required to use $toolName. Please grant access in Settings.',
      );
}

/// Tool router — dispatches registered Tools by name
class ToolRouter {
  final Map<String, BaseTool> _tools = {};

  /// Register a Tool
  void registerTool(BaseTool tool) {
    _tools[tool.name] = tool;
  }

  /// List of registered Tools
  List<String> get availableTools => _tools.keys.toList();

  /// Parse tool call from AI response — supports 2 formats
  ///
  /// Format 1 (system prompt standard):
  ///   <tool_call>{"tool": "calendar_query", "params": {"date": "tomorrow"}}</tool_call>
  ///
  /// Format 2 (actual output from Gemma 2.3B):
  ///   <calendar_query>{"date": "tomorrow"}</calendar_query>
  ToolCall? parseToolCall(String aiResponse) {
    // Format 1: <tool_call>{"tool": "name", "params": {...}}</tool_call>
    final stdMatch = RegExp(
      r'<tool_call>(.*?)</tool_call>',
      dotAll: true,
    ).firstMatch(aiResponse);
    if (stdMatch != null) {
      try {
        final json = jsonDecode(stdMatch.group(1)!) as Map<String, dynamic>;
        final tool = json['tool'] as String?;
        final params = json['params'] as Map<String, dynamic>? ?? {};
        if (tool != null && _tools.containsKey(tool)) {
          return ToolCall(tool: tool, params: params);
        }
      } catch (_) {}
    }

    // Format 2: <tool_name>{...params...}</tool_name>
    for (final toolName in _tools.keys) {
      final pattern = '<$toolName>(.*?)</$toolName>';
      final directMatch = RegExp(pattern, dotAll: true).firstMatch(aiResponse);
      if (directMatch != null) {
        final rawJson = directMatch.group(1)!.trim();
        debugPrint('[ToolRouter] Matched <$toolName>, raw: $rawJson');
        try {
          final json = jsonDecode(rawJson) as Map<String, dynamic>;
          return ToolCall(tool: toolName, params: json);
        } catch (e) {
          debugPrint('[ToolRouter] JSON parse failed: $e');
          return ToolCall(tool: toolName, params: {});
        }
      }
    }

    debugPrint('[ToolRouter] No tool call found in: ${aiResponse.substring(0, aiResponse.length.clamp(0, 120))}');
    return null;
  }

  /// Dispatch Tool — includes permission check.
  /// Reject immediately if [source] is not [AiInvocationSource.agenticChat] (prompt injection defense).
  Future<ToolResult> dispatch(
    ToolCall call, {
    required AiInvocationSource source,
    bool confirmed = false,
  }) async {
    if (source != AiInvocationSource.agenticChat) {
      AiSecurityMetrics.incrementBlockedToolCall(source);
      return ToolResult.error('Tool dispatch not allowed in $source');
    }

    final tool = _tools[call.tool];
    if (tool == null) {
      return ToolResult.error('Unknown tool: ${call.tool}');
    }

    // Permission check
    if (!await tool.hasPermission()) {
      final granted = await tool.requestPermission();
      if (!granted) {
        return ToolResult.needsPermission(call.tool);
      }
    }

    // Write actions require confirmation
    if (tool.requiresConfirmation && !confirmed) {
      final preview = await tool.previewAction(call.params);
      return ToolResult(
        success: true,
        summary: preview,
        requiresConfirmation: true,
        confirmationMessage: preview,
      );
    }

    // Execute
    return tool.execute(call.params);
  }
}
