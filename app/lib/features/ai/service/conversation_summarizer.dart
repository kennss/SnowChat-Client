/// @file        conversation_summarizer.dart
/// @description Chat room conversation summarization — uses Gemma 4 E2B processToolRequest.
///              Zero-Knowledge: never log message content / summary output.
///              Token-budget-based latest message window, includes sender names.
///              Peer text is defended against injection via sanitizePeerText + delimiter wrap.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-18
/// @lastUpdated 2026-04-26 (header + inline English translation; chat room conversation summarization)
///
/// @functions
///  - ConversationSummarizer.summarize(): message list → summary text
///  - ConversationSummarizer.canSummarize(): minimum precondition for summarization

import 'package:flutter/foundation.dart';
import '../../chat/models/message.dart';
import 'on_device_ai_service.dart';
import 'prompt_sanitizer.dart';

/// Summary result (text + actual message count used)
class SummaryResult {
  final String text;
  final int messagesUsed;
  const SummaryResult({required this.text, required this.messagesUsed});
}

/// Conversation summarization engine.
class ConversationSummarizer {
  final OnDeviceAIService _ai;

  /// Token budget for the conversation body, excluding prompt/response headroom.
  /// Gemma 4096 context - system/instruction ~500 - response ~600 = ~3000.
  /// Subtract another ~50 tokens for sanitize prefix + delimiter → 2950.
  static const _messageTokenBudget = 2950;

  /// Minimum message count (skip summarization below this)
  static const minMessages = 3;

  ConversationSummarizer(this._ai);

  /// Whether summarization is possible — at least minMessages of meaningful text messages.
  static bool canSummarize(List<Message> messages) {
    final meaningful = messages.where(_isMeaningful).length;
    return meaningful >= minMessages;
  }

  /// Summarize a message list.
  ///
  /// [targetLanguage]: English language name like "Korean", "English", "Japanese".
  /// [mySnowId]: my SnowChat ID — used to replace own messages with "Me".
  Future<SummaryResult> summarize({
    required List<Message> messages,
    required String targetLanguage,
    required String mySnowId,
  }) async {
    final window = _buildTokenWindow(messages, mySnowId);
    if (window.transcript.isEmpty) {
      return const SummaryResult(text: '', messagesUsed: 0);
    }

    final prompt = _buildPrompt(window.transcript, targetLanguage);
    final raw = await _ai.processToolRequest(
      prompt,
      source: AiInvocationSource.summarization,
    );
    final cleaned = _cleanResponse(raw);

    return SummaryResult(text: cleaned, messagesUsed: window.messageCount);
  }

  // --- Private ---

  /// Accumulate from newest backward, cutting off at the token budget.
  _TranscriptWindow _buildTokenWindow(
    List<Message> messages,
    String mySnowId,
  ) {
    final lines = <String>[];
    int usedTokens = 0;
    int count = 0;

    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (!_isMeaningful(msg)) continue;

      final line = _formatLine(msg, mySnowId);
      final tokens = estimateTokens(line);
      if (usedTokens + tokens > _messageTokenBudget) break;

      lines.insert(0, line);
      usedTokens += tokens;
      count++;
    }

    return _TranscriptWindow(
      transcript: lines.join('\n'),
      messageCount: count,
    );
  }

  /// One-line message format: "Alice: hello world".
  /// Sanitize both name + body — senderDisplayName comes via the envelope and is peer-controllable.
  String _formatLine(Message msg, String mySnowId) {
    final name = _resolveSender(msg, mySnowId);
    final body = sanitizePeerText(_bodyFor(msg));
    return '$name: $body';
  }

  /// Sender display name. Peer-controllable senderDisplayName: sanitize + strip newlines + length cap.
  String _resolveSender(Message msg, String mySnowId) {
    if (msg.senderSnowchatId == mySnowId) return 'Me';
    final display = msg.senderDisplayName;
    if (display != null && display.trim().isNotEmpty) {
      final s = sanitizePeerText(display)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return s.length > 32 ? s.substring(0, 32) : s;
    }
    // SnowChat ID prefix fallback (typically "snow" + 8 chars)
    final id = msg.senderSnowchatId;
    return id.length > 12 ? id.substring(0, 12) : id;
  }

  /// Message body — substitute placeholder for file/voice/decryption-failed
  String _bodyFor(Message msg) {
    if (msg.status == MessageStatus.decryptionFailed) return '[decryption failed]';
    if (msg.isDeleted) return '[deleted]';
    switch (msg.type) {
      case MessageType.file:
        return msg.isImageFile ? '[photo]' : '[file]';
      case MessageType.voice:
        return '[voice]';
      case MessageType.system:
        return '[system: ${msg.plaintext}]';
      case MessageType.text:
        return msg.plaintext.trim();
    }
  }

  /// Whether the message is "meaningful" enough to summarize
  static bool _isMeaningful(Message msg) {
    if (msg.isDeleted) return false;
    if (msg.status == MessageStatus.decryptionFailed) return false;
    if (msg.type == MessageType.system) return false;
    if (msg.type == MessageType.text && msg.plaintext.trim().length < 2) {
      return false;
    }
    return true;
  }

  /// Build prompt — instruct Gemma to bullet-summarize.
  /// transcript is wrapped with the untrusted user-data delimiter, and the
  /// instruction prefix explicitly tells the model to "treat as data only".
  String _buildPrompt(String transcript, String targetLanguage) {
    final instruction =
        'Summarize the following chat conversation in $targetLanguage. '
        'Output 3 to 5 concise bullet points starting with "- ". '
        'Focus on: key decisions, questions asked, action items, and notable topics. '
        'Do NOT translate proper names. Do NOT add thinking tags, tool tags, or preamble. '
        'If the conversation is too trivial for a summary, reply with a single bullet noting that.';

    final wrapped = wrapInstructionedTranscript(
      transcript,
      langInstruction: instruction,
    );

    return '''$wrapped
Summary:''';
  }

  /// Cleanup response — extract bullet lines only, strip surrounding garbage.
  String _cleanResponse(String raw) {
    if (raw.isEmpty) return '';

    // Keep only what follows "Summary:" (defends against echo)
    final summaryIdx = raw.toLowerCase().indexOf('summary:');
    var text = summaryIdx >= 0 ? raw.substring(summaryIdx + 'summary:'.length) : raw;

    // Keep bullet + normal lines, tidy blank lines
    final lines = text.split('\n').map((l) => l.trim()).toList();
    final out = <String>[];
    bool sawBullet = false;

    for (final line in lines) {
      if (line.isEmpty) {
        if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
        continue;
      }
      // Normalize bullets: "•", "*", "·", "- " all → "- "
      final normalized = line.replaceFirstMapped(
        RegExp(r'^[\*\•\·\-]\s+'),
        (_) => '- ',
      );
      if (normalized.startsWith('- ')) sawBullet = true;
      out.add(normalized);
    }

    // If no bullets at all, salvage at least one line
    final joined = out.join('\n').trim();
    if (joined.isEmpty) {
      debugPrint('[Summary] Empty response after cleanup');
      return '';
    }
    if (!sawBullet) {
      // For a single paragraph, prefix with "- " to bulletize
      return '- $joined';
    }
    return joined;
  }
}

class _TranscriptWindow {
  final String transcript;
  final int messageCount;
  const _TranscriptWindow({required this.transcript, required this.messageCount});
}
