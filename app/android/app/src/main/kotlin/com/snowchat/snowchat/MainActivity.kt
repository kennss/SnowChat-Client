/**
 * @file        MainActivity.kt
 * @description Android 앱 메인 Activity. Flutter 엔진 + LiteRT-LM AI 브리지 등록.
 *
 *              Phase 2 (2026-04-22): runtime setShowWhenLocked / setTurnScreenOn +
 *              requestDismissKeyguard 제거. Samsung Knox 가 이 flag 를 "visible
 *              only" 로만 해석 + 모든 launch 경로 (홈 아이콘 포함) 에서 lock
 *              bypass 가 되어 security regression 이었음.
 *
 *              전용 CallActivity (`CallActivity.kt`) 가 통화 경로만 lock bypass
 *              담당 — manifest 선언 showWhenLocked="true" 로 OS install time 인지
 *              + fresh launch full-screen intent priority 취득. Signal
 *              WebRtcCallActivity 패턴.
 *
 *              SignalBridge / SignalStore 는 Pure Dart 전환 (Phase 6.x) 으로 완전
 *              폐기됨 — Kotlin 파일 + Gradle `org.signal:libsignal-client`
 *              dependency 2026-04-21 삭제.
 * @author      Kennt Kim
 * @company     Calida Lab
 * @created     2026-03-29
 * @lastUpdated 2026-04-22 (CallActivity 분리 — MainActivity lock bypass flag 제거)
 *
 * @functions
 *  - MainActivity.configureFlutterEngine(): LiteRT-LM AI 브리지 등록
 */

package com.snowchat.snowchat

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {

    private var liteRtLmBridge: LiteRtLmBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Phase 10: LiteRT-LM on-device AI bridge.
        liteRtLmBridge = LiteRtLmBridge(applicationContext, flutterEngine)
    }
}
