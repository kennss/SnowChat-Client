/// @file        diag_log.dart
/// @description 릴리즈 빌드에서도 살아남는 진단 로그 유틸. Flutter release 는
///              Dart `print` / `debugPrint` 를 Android logcat 에서 stripping
///              해버려서 VoIP DECLINE → call_end 못 도달하는 release-only race
///              가 invisible 한 게 컸다 (2026-05-05 진단). MethodChannel 로
///              MainActivity 의 Log.d 를 호출해서 logcat 에 native tag 로
///              직접 출력. iOS 는 미구현 (현재 Galaxy 만 release 타겟).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-05
/// @lastUpdated 2026-05-05
///
/// @functions
///  - diagLog(tag, msg): 릴리즈에서도 logcat 에 보이는 fire-and-forget 로그.
///                       Android only; 다른 플랫폼에선 debugPrint 로 fallback.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('snowchat/diag_log');

void diagLog(String tag, String msg) {
  // Always echo to debugPrint for debug/profile builds (free + colored).
  debugPrint('[$tag] $msg');
  // Android: route to native Log.d via MainActivity bridge so release builds
  // (which strip Dart print) still surface the line in logcat.
  if (Platform.isAndroid) {
    _channel.invokeMethod<void>('log', {'tag': tag, 'msg': msg}).catchError(
      (_) {
        // Channel not yet attached (e.g., very-early boot) — silently drop.
      },
    );
  }
}
