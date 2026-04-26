/// @file        security_metrics.dart
/// @description AI security counters — stats for blocked prompt injections / suspicious outputs.
///              Never sent externally (Zero-Knowledge). debugPrint emits only names/counters.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation; AI security counters)
///
/// @functions
///  - AiSecurityMetrics.incrementBlockedToolCall(source): tool dispatch rejection counter
///  - AiSecurityMetrics.incrementSuspiciousSuggestion(): suspicious reply candidate block counter

import 'package:flutter/foundation.dart';

import 'on_device_ai_service.dart';

/// AI security event counters.
/// - process memory only.
/// - Never transmit externally / never log plaintext.
class AiSecurityMetrics {
  /// Number of times tool dispatch was rejected from a source other than agenticChat.
  static int blockedToolCalls = 0;

  /// Number of times a reply-suggestion candidate was blocked due to suspicious pattern.
  static int suspiciousSuggestions = 0;

  /// Call this when tool dispatch is blocked from a source other than agenticChat.
  /// Must never emit plaintext / prompt content.
  static void incrementBlockedToolCall(AiInvocationSource source) {
    blockedToolCalls++;
    debugPrint('[AiSecurityMetrics] Blocked tool call from $source');
  }

  /// Call this when a reply-suggestion candidate is blocked due to a suspicious pattern.
  static void incrementSuspiciousSuggestion() {
    suspiciousSuggestions++;
    debugPrint('[AiSecurityMetrics] Suspicious suggestion blocked');
  }
}
