/// @file        version.dart
/// @description App buildNumber 헬퍼. server 의 PATHB_MIN_CLIENT_VERSION
///              gate 와 매칭 가능하도록 pubspec.yaml 의 +NNN 만 추출.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-05-02
/// @lastUpdated 2026-05-03 (appDisplayVersionProvider 추가 — settings 화면에서
///              "1.0.0+2211" 형식으로 표시. PackageInfo 는 platform channel
///              async 라 FutureProvider 로 cache.)
///
/// @functions
///  - getAppBuildNumber(): pubspec buildNumber 정수 (e.g. 211). 실패 시 null
///  - getAppVersionForServer(): server payload 용 string ("211"). null 이면 field omit
///  - appDisplayVersionProvider: UI 표시용 "1.0.0+2211" 형식 FutureProvider
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// split-per-abi 가 적용된 Android build 의 buildNumber 는 ABI prefix 가
/// 자동으로 붙는다 (arm64 = 2*1000+base, armeabi = 1*1000+base, x86_64 =
/// 4*1000+base). 사용자/서버 표시용으로는 base 만 필요하므로 prefix 제거.
/// 1000 미만이면 base 그대로 (iOS / fat APK 케이스).
int _stripSplitAbiPrefix(int n) => n >= 1000 ? n % 1000 : n;

Future<int?> getAppBuildNumber() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final raw = int.tryParse(info.buildNumber);
    if (raw == null) return null;
    return _stripSplitAbiPrefix(raw);
  } catch (e) {
    debugPrint('[version] getAppBuildNumber failed: $e');
    return null;
  }
}

/// Phase 8.2 Path B v4 (C2) — server 의 PATHB_MIN_CLIENT_VERSION gate
/// (Plan §2.5) 와 비교하기 위한 string 형식. server 가 `parseInt(d.appVersion ?? '0', 10)`
/// 로 parse 하므로 buildNumber 만 넘긴다 ("1.0.0+203" 전체 보내면 parseInt → 1).
Future<String?> getAppVersionForServer() async {
  final bn = await getAppBuildNumber();
  return bn?.toString();
}

/// UI 표시용 version string ("1.0.0+2211"). settings 화면 등에서 watch.
/// PackageInfo.fromPlatform 은 platform channel async 호출이라 FutureProvider
/// 로 app lifetime cache. 실패 시 "unknown".
final appDisplayVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final raw = int.tryParse(info.buildNumber);
    final base = raw != null ? _stripSplitAbiPrefix(raw) : info.buildNumber;
    return '${info.version}+$base';
  } catch (e) {
    debugPrint('[version] appDisplayVersionProvider failed: $e');
    return 'unknown';
  }
});
