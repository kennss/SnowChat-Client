/// @file        device_capability.dart
/// @description Hardware-capability gate for SnowChat AI. Single source of
///              truth that the AI tile (and any future AI entry point)
///              consults before letting the user kick off a 2.9 GB model
///              download or load it into memory.
///
///              The cutoff is RAM-based because OOM under the Gemma 4 E2B
///              load is the actual failure mode on iPhone 13 / 4 GB Galaxy
///              budget tier. CPU/NPU class would also work but RAM is the
///              cleanest signal across iOS + Android and the easiest to
///              read accurately at runtime.
///
///              Cutoff: 7000 MB — covers all 8 GB tier devices (iPhone 15
///              Pro reports ~7400 MB, Galaxy S25 FE ~7600 MB) while keeping
///              every 6 GB tier device (~5800 MB report) firmly out.
///
///              Fail-closed: if the native channel errors or returns
///              garbage the helper reports 0 MB, which means the gate
///              denies AI rather than silently letting a low-RAM phone
///              through. Better one false-block than one false-pass.
///
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-06
/// @lastUpdated 2026-05-06
///
/// @functions
///  - DeviceCapability.totalRamMB(): MethodChannel-backed total physical RAM in MB, cached for the session
///  - DeviceCapability.canRunAI(): true iff totalRamMB ≥ kMinAiRamMB
///  - DeviceCapability.kMinAiRamMB: 7000 — 8 GB tier cutoff with margin both directions

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceCapability {
  static const _channel = MethodChannel('snowchat/device_capability');

  /// Minimum total physical RAM (MB) required to run the on-device AI
  /// model. Gemma 4 E2B in Q4_K_M is ~2.89 GB on iOS and ~2.58 GB on
  /// Android; the model plus KV cache plus runtime overhead pushes the
  /// per-app working set past what 6 GB phones can spare without OS
  /// jetsam / LMK kicking in.
  static const int kMinAiRamMB = 7000;

  static int? _cachedRamMB;

  /// Returns total physical RAM in megabytes (binary 1024×1024).
  /// Cached after the first successful read. On error returns 0 so the
  /// gate denies AI access (fail-closed).
  static Future<int> totalRamMB() async {
    if (_cachedRamMB != null) return _cachedRamMB!;
    try {
      final bytes = await _channel.invokeMethod<int>('getTotalRamBytes');
      if (bytes != null && bytes > 0) {
        _cachedRamMB = bytes ~/ (1024 * 1024);
        return _cachedRamMB!;
      }
    } catch (e) {
      debugPrint('[DeviceCapability] channel error: $e');
    }
    _cachedRamMB = 0;
    return 0;
  }

  /// True iff this device meets the SnowChat AI hardware bar.
  static Future<bool> canRunAI() async {
    final ram = await totalRamMB();
    return ram >= kMinAiRamMB;
  }
}
