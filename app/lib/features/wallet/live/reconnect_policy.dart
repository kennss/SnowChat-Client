/// @file        reconnect_policy.dart
/// @description WS reconnect backoff policy (1→2→4→8→16→30s cap, ±20% jitter)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - ReconnectPolicy.delayFor(attempt): return backoff Duration based on attempt count
library;

import 'dart:math';

class ReconnectPolicy {
  static final _rand = Random();
  static const _baseSeconds = [1, 2, 4, 8, 16, 30];

  static Duration delayFor(int attempt) {
    final idx = attempt < 0 ? 0 : (attempt >= _baseSeconds.length ? _baseSeconds.length - 1 : attempt);
    final secs = _baseSeconds[idx];
    final jitter = _rand.nextDouble() * 0.4 - 0.2; // ±20%
    return Duration(milliseconds: ((secs * 1000) * (1 + jitter)).round());
  }
}
