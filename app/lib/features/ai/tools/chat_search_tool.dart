/// @file        chat_search_tool.dart
/// @description AI chat history search Tool
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header + inline English translation; AI chat history search tool)
///
/// @functions
///  - ChatSearchTool: keyword search over AI conversation history

import '../service/tool_router.dart';
import '../service/on_device_ai_service.dart';
import 'base_tool.dart';

/// AI conversation history search Tool
///
/// Keyword-search over the current session's AI conversation history.
/// No permission needed (self-owned data).
class ChatSearchTool extends BaseTool {
  final List<AiMessageEntry> Function() _historyResolver;

  ChatSearchTool({required List<AiMessageEntry> Function() historyResolver})
      : _historyResolver = historyResolver;

  @override
  String get name => 'chat_search';

  @override
  String get description => 'Search AI chat history by keyword';

  @override
  bool get requiresConfirmation => false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String> previewAction(Map<String, dynamic> params) async => '';

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final keyword = (params['keyword'] as String?)?.toLowerCase();
    if (keyword == null || keyword.isEmpty) {
      return ToolResult.error('No search keyword provided');
    }

    final history = _historyResolver();
    final matches = history
        .where((msg) => msg.content.toLowerCase().contains(keyword))
        .toList();

    if (matches.isEmpty) {
      return ToolResult(
        success: true,
        summary: 'No messages found matching "$keyword"',
        transparencyLabel: 'Chat history searched · No server transmission',
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('Found ${matches.length} message(s) matching "$keyword":');
    for (final msg in matches.take(10)) {
      final role = msg.isUser ? 'You' : 'AI';
      final preview = msg.content.length > 100
          ? '${msg.content.substring(0, 100)}...'
          : msg.content;
      buffer.writeln('  [$role] $preview');
    }

    return ToolResult(
      success: true,
      summary: buffer.toString(),
      transparencyLabel:
          '${matches.length} chat messages searched · No server transmission',
    );
  }
}
