/// @file        on_device_ai_service.dart
/// @description On-device AI inference service — agentic Tool Use pipeline.
///              Ports SnowClaw's agentic architecture + integrates SnowChat Platform Channels.
///              ** Only dart:io Platform allowed; network imports forbidden **
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation; on-device AI inference service)
///
/// @functions
///  - OnDeviceAIService.initialize(): per-platform AI engine initialization
///  - OnDeviceAIService.ensureInitialized(): lazy init helper (V1 stability)
///  - OnDeviceAIService.sendMessage(): streaming conversation (auto-detects Tool Use)
///  - OnDeviceAIService.processToolRequest(): one-shot tool request (translate, summarize, suggest)
///  - OnDeviceAIService.processWithTools(): agentic Tool Use pipeline
///  - OnDeviceAIService.resetChat(): clear history
///  - OnDeviceAIService.dispose(): release resources

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'tool_router.dart';

/// Channels common to both platforms
const _methodChannel = MethodChannel('com.snowchat/litert_lm');
const _eventChannel = EventChannel('com.snowchat/litert_lm_stream');

/// System prompt — Android (full tool set)
const _systemPromptAndroid = '''You are SnowChat AI, a privacy-first assistant.
All processing happens on-device. No data leaves this device.

Available tools:
- contact_search(query: string) → Search contacts
- calendar_query(date: string) → Query calendar events
- calendar_create(title: string, date: string, time: string) → Create event [CONFIRM]
- photo_search(date_from?: string) → Search photos
- device_info(type: string) → Battery, storage, network info
- sms_search(keyword?: string) → Search SMS messages
- call_log(type?: string) → Call history
- current_location() → Current GPS location
- clipboard() → Read clipboard
- installed_apps(query?: string) → List installed apps
- alarm_query() → List alarms
- alarm_create(hour: int, minute: int, label?: string) → Set alarm [CONFIRM]
- file_search(query?: string) → Search files
- app_usage(period?: string) → Screen time
- bluetooth_devices() → Paired Bluetooth devices
- wifi_info() → WiFi info
- notifications(app?: string) → Read notifications
- chat_search(keyword?: string) → Search chat history

When a tool is needed, respond with:
<tool_name>{"param": "value"}</tool_name>

You CANNOT: browse web, send emails, make calls.
Respond in the same language the user writes in. Be concise.
Do not use thinking tags or explain reasoning.''';

/// System prompt — iOS (restricted tool set)
const _systemPromptIOS = '''You are SnowChat AI, a privacy-first assistant.
All processing happens on-device. No data leaves this device.

Available tools:
- contact_search(query: string) → Search contacts
- calendar_query(date: string) → Query calendar events
- calendar_create(title: string, date: string, time: string) → Create event [CONFIRM]
- photo_search(date_from?: string) → Search photos
- device_info(type: string) → Battery, storage info
- current_location() → Current GPS location
- clipboard() → Read clipboard
- file_search(query?: string) → Search files
- chat_search(keyword?: string) → Search chat history

When a tool is needed, respond with:
<tool_name>{"param": "value"}</tool_name>

You CANNOT: read SMS, access call logs, list apps, read notifications, browse web, send emails.
Respond in the same language the user writes in. Be concise.
Do not use thinking tags or explain reasoning.''';

String get _systemPrompt => Platform.isIOS ? _systemPromptIOS : _systemPromptAndroid;

/// AI inference invocation source — metadata used to decide prompt-injection defense policy.
/// - [agenticChat]: SnowChat AI room conversation itself (the only path that allows tool dispatch).
/// - [summarization]: conversation summarization from AIActionBar / SummaryNotifier.
/// - [translation]: translation from AIActionBar (note: actual translation uses the native bridge).
/// - [suggestion]: reply suggestion from AIActionBar.
/// - [manualToolBar]: other explicit user invocations.
enum AiInvocationSource {
  agenticChat,
  summarization,
  translation,
  suggestion,
  manualToolBar,
}

/// Token estimation: Korean ~3.0 tok/char, English ~0.25 tok/char
int estimateTokens(String text) {
  final koreanChars = RegExp(r'[\uAC00-\uD7A3]').allMatches(text).length;
  final total = text.length;
  if (total == 0) return 0;
  final ratio = koreanChars / total;
  return (total * (0.25 + ratio * 2.75)).ceil();
}

/// AI conversation history entry
class AiMessageEntry {
  final String content;
  final bool isUser;
  final String? toolUsed;
  final String? transparencyLabel;

  const AiMessageEntry({
    required this.content,
    required this.isUser,
    this.toolUsed,
    this.transparencyLabel,
  });
}

/// AI response result
class AiResponse {
  final String text;
  final String? toolUsed;
  final String? transparencyLabel;
  final bool requiresConfirmation;
  final Map<String, dynamic>? confirmationData;

  const AiResponse({
    required this.text,
    this.toolUsed,
    this.transparencyLabel,
    this.requiresConfirmation = false,
    this.confirmationData,
  });
}

/// On-device AI — Zero-Knowledge, agentic Tool Use.
class OnDeviceAIService {
  /// V1.0.1 stability: expose init state changes via ValueNotifier.
  /// `aiAvailableProvider` watches it to auto-enable the Summary/Translate
  /// icons right after init. init-only activation (not installed-only) keeps
  /// UX consistent with owner intent.
  final ValueNotifier<bool> isInitializedNotifier = ValueNotifier(false);
  bool _chatBusy = false;
  bool _toolBusy = false;
  StreamSubscription<dynamic>? _streamSub;

  ToolRouter? _toolRouter;

  bool get isInitialized => isInitializedNotifier.value;
  bool get isChatBusy => _chatBusy;
  bool get isToolBusy => _toolBusy;
  bool get isBusy => _chatBusy || _toolBusy;

  /// Set Tool Router (injected by Provider)
  void setToolRouter(ToolRouter router) {
    _toolRouter = router;
  }

  /// Initialize AI engine.
  Future<void> initialize({
    required String modelPath,
    int maxTokens = 2048,
    int topK = 40,
    double topP = 0.95,
    double temperature = 0.7,
  }) async {
    if (isInitialized) return;

    debugPrint('[AI] Initializing engine...');
    await _methodChannel.invokeMethod('initialize', {
      'modelPath': modelPath,
      'maxTokens': maxTokens,
      'topK': topK,
      'topP': topP,
      'temperature': temperature,
    });

    isInitializedNotifier.value = true;
    debugPrint('[AI] Engine ready');
  }

  /// Lazy init helper — must be called right before using AI, because for V1
  /// stability `aiAvailableProvider` removed its auto init trigger.
  ///
  /// Returns true immediately if already initialized. Returns false if not
  /// installed / init fails.
  /// [modelPathProvider] is the async path fetcher (typically `AIModelManager.modelPath`).
  Future<bool> ensureInitialized(Future<String> Function() modelPathProvider) async {
    if (isInitialized) return true;
    try {
      final path = await modelPathProvider();
      await initialize(modelPath: path);
      return isInitialized;
    } catch (e) {
      debugPrint('[AI] ensureInitialized failed: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Agentic Tool Use pipeline
  // ---------------------------------------------------------------------------

  /// Auto-detect Tool Use — system prompt + history + user input → AI inference
  /// → detect <tool_name> → run tool → 2nd inference → natural language reply
  Future<AiResponse> processWithTools(
    List<AiMessageEntry> history,
    String userInput,
  ) async {
    if (!isInitialized) throw StateError('AI not initialized');
    if (_chatBusy) throw StateError('AI is busy');
    _chatBusy = true;

    try {
      // 1st inference: system prompt + history + user input
      final prompt = _buildAgenticPrompt(history, userInput);
      final rawResponse = await _infer(prompt);

      // Detect tool call
      if (_toolRouter != null) {
        final toolCall = _toolRouter!.parseToolCall(rawResponse);
        if (toolCall != null) {
          final toolResult = await _toolRouter!.dispatch(
            toolCall,
            source: AiInvocationSource.agenticChat,
          );

          // Write action requires confirmation
          if (toolResult.requiresConfirmation) {
            return AiResponse(
              text: toolResult.confirmationMessage ?? 'Confirm this action?',
              toolUsed: toolCall.tool,
              requiresConfirmation: true,
              confirmationData: {
                'tool': toolCall.tool,
                'params': toolCall.params,
              },
            );
          }

          // 2nd inference: tool result → natural language response
          final followUp =
              'The user asked: "$userInput"\n\n'
              'I used ${toolCall.tool} and got:\n${toolResult.summary}\n\n'
              'Provide a concise response based on this result. '
              'Same language as user. No thinking tags.';
          final finalResponse = await _infer(followUp);

          return AiResponse(
            text: _cleanFollowUpResponse(finalResponse, toolResult.summary),
            toolUsed: toolCall.tool,
            transparencyLabel: toolResult.transparencyLabel,
          );
        }
      }

      // Plain text response
      final cleaned = _cleanTags(rawResponse);
      if (cleaned.isEmpty) {
        return const AiResponse(
          text: 'I can help with contacts, calendar, photos, device info, '
              'and more. What would you like to know?',
        );
      }
      return AiResponse(text: cleaned);
    } finally {
      _chatBusy = false;
    }
  }

  /// Execute a confirmed write action
  Future<AiResponse> executeConfirmedAction(
    Map<String, dynamic> confirmationData,
  ) async {
    if (_toolRouter == null) {
      return const AiResponse(text: 'Tool system not available');
    }
    final tool = confirmationData['tool'] as String;
    final params = Map<String, dynamic>.from(confirmationData['params'] as Map);
    final call = ToolCall(tool: tool, params: params);
    final result = await _toolRouter!.dispatch(
      call,
      source: AiInvocationSource.agenticChat,
      confirmed: true,
    );
    return AiResponse(
      text: result.summary,
      toolUsed: tool,
      transparencyLabel: result.transparencyLabel,
    );
  }

  // ---------------------------------------------------------------------------
  // Legacy API (backward compatibility)
  // ---------------------------------------------------------------------------

  /// Streaming conversation (without Tool Use).
  Future<String> sendMessage(
    String userMessage, {
    ValueChanged<String>? onToken,
  }) async {
    if (!isInitialized) throw StateError('AI not initialized');
    if (_chatBusy) throw StateError('Chat session is busy.');

    _chatBusy = true;
    _streamSub?.cancel();
    _streamSub = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final type = event['type'] as String?;
        final data = event['data'] as String? ?? '';
        if (type == 'token') onToken?.call(data);
      }
    });

    try {
      final result = await _methodChannel.invokeMethod<String>('sendMessage', {
        'text': userMessage,
      });
      return result?.trim() ?? '';
    } finally {
      _chatBusy = false;
      _streamSub?.cancel();
      _streamSub = null;
    }
  }

  /// One-shot tool request (translate, summarize, reply suggestion).
  /// On iOS, the native bridge has a single isBusy flag, so this can only run
  /// after chatBusy is released.
  ///
  /// [source] is consumed by the prompt-injection defense policy (currently
  /// metadata). Callers must specify an [AiInvocationSource] value.
  Future<String> processToolRequest(
    String prompt, {
    required AiInvocationSource source,
  }) async {
    assert(
      // ignore: unnecessary_null_comparison
      source != null,
      'AiInvocationSource is required for processToolRequest',
    );
    if (!isInitialized) throw StateError('AI not initialized');
    if (_toolBusy) throw StateError('Tool session is busy.');

    // iOS: native bridge has a single isBusy — wait for chatBusy to finish
    int waited = 0;
    while (_chatBusy && waited < 30000) {
      await Future.delayed(const Duration(milliseconds: 200));
      waited += 200;
    }
    if (_chatBusy) return ''; // 30-second timeout

    _toolBusy = true;
    try {
      final result = await _methodChannel.invokeMethod<String>('sendMessage', {
        'text': prompt,
      });
      return _cleanTags(result?.trim() ?? '');
    } finally {
      _toolBusy = false;
    }
  }

  /// Reset history.
  Future<void> resetChat() async {
    await _methodChannel.invokeMethod('resetConversation', {
      'topK': 40, 'topP': 0.95, 'temperature': 0.7,
    });
  }

  /// Release resources.
  Future<void> dispose() async {
    _streamSub?.cancel();
    try { await _methodChannel.invokeMethod('dispose'); } catch (_) {}
    isInitializedNotifier.value = false;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  /// Native bridge inference (non-streaming)
  Future<String> _infer(String prompt) async {
    final result = await _methodChannel.invokeMethod<String>('sendMessage', {
      'text': prompt,
    });
    return result?.trim() ?? '';
  }

  /// Build agentic prompt
  String _buildAgenticPrompt(List<AiMessageEntry> history, String userInput) {
    final buf = StringBuffer();
    buf.writeln(_systemPrompt);
    buf.writeln();

    // Token-budget-based history window
    int budget = 4000;
    final window = <AiMessageEntry>[];
    for (int i = history.length - 1; i >= 0; i--) {
      final tokens = estimateTokens(history[i].content);
      if (budget - tokens < 0) break;
      budget -= tokens;
      window.insert(0, history[i]);
    }

    for (final msg in window) {
      buf.writeln('${msg.isUser ? "User" : "Assistant"}: ${msg.content}');
    }
    buf.writeln('User: $userInput');
    buf.writeln('Assistant:');
    return buf.toString();
  }

  /// Strip prompt echo from 2nd-inference response (an iOS llama.cpp quirk)
  String _cleanFollowUpResponse(String response, String toolSummary) {
    var cleaned = _cleanTags(response);
    // Strip prompt-echo pattern: "The user asked..." ~ "based on this result."
    final echoEnd = cleaned.indexOf('based on this result.');
    if (echoEnd > 0) {
      cleaned = cleaned.substring(echoEnd + 'based on this result.'.length).trim();
    }
    // Strip "User:" / "Assistant:" prompt markers
    cleaned = cleaned.replaceAll(RegExp(r'^(User|Assistant):.*$', multiLine: true), '').trim();
    // Strip tool-result JSON
    cleaned = cleaned.replaceAll(RegExp(r'\{[^}]*"events"[^}]*\}', dotAll: true), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\{[^}]*"tool"[^}]*\}', dotAll: true), '').trim();
    // Tidy blank lines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return cleaned.isEmpty ? _cleanTags(response) : cleaned;
  }

  /// Cleanup response — strip tags only (minimal)
  String _cleanTags(String response) {
    return response
        .replaceAll(RegExp(r'<channel-thought>.*?</channel-thought>', dotAll: true), '')
        .replaceAll(RegExp(r'<tool_call>.*?</tool_call>', dotAll: true), '')
        .replaceAll(RegExp(r'<\w+>\s*\{[^}]*\}\s*</\w+>', dotAll: true), '')
        .replaceAll('<end_of_turn>', '')
        .replaceAll(RegExp(r'<start_of_turn>\w*'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
