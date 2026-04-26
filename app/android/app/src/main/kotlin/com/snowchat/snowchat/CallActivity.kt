/**
 * @file        CallActivity.kt
 * @description 전용 통화 Activity — Signal WebRtcCallActivity 패턴 이식.
 *              Samsung Knox 에서 MainActivity 의 runtime setShowWhenLocked 가
 *              OS PIN bypass 안 먹히는 문제 해결용. 신규 Activity + manifest
 *              선언 showWhenLocked="true" 가 OS 에 install 시점에 인지되어
 *              keyguard 위 priority 인정 (full-screen intent 특별 처리).
 *
 *              Phase 1 (probe): skeleton 만 — onCreate 에서 flag 적용 + native
 *              "Connecting..." UI (ProgressBar) 표시 + MainActivity 로 intent
 *              redirect. 가설 검증용 — Galaxy S25 FE "앱 살아있음 + 화면 잠금
 *              + 수신 → Accept" 시나리오에서 OS PIN 미요구 확인.
 *
 *              Phase 2+ (probe 성공 시): FlutterEngineCache + cached engine 으로
 *              /call 라우트 직접 렌더. Dual Flutter Engine 상태 동기화.
 * @author      Kennt Kim
 * @company     Calida Lab
 * @created     2026-04-22
 * @lastUpdated 2026-04-22 (Phase 1 probe skeleton)
 *
 * @functions
 *  - CallActivity.onCreate(): showWhenLocked/turnScreenOn 적용 + keyguard dismiss
 *                             + MainActivity 로 redirect (Phase 1 temporary)
 */

package com.snowchat.snowchat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView

class CallActivity : Activity() {

    companion object {
        /** BroadcastReceiver / MainActivity 에서 CallActivity launch 시 사용. */
        const val EXTRA_CALL_DATA = "snowchat.extra.CALL_DATA"

        /**
         * CallActivity 로 진입하는 Intent 생성 — keyguard dismiss + new task 필수 flag
         * 포함. 호출자는 call metadata (nonce, callId 등) 를 extras 로 주입.
         */
        fun newIntent(context: Context, callData: Bundle? = null): Intent {
            return Intent(context, CallActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                if (callData != null) {
                    putExtra(EXTRA_CALL_DATA, callData)
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 1. Show-when-locked + turn-screen-on — manifest XML 선언 + runtime 중복 적용
        //    (API 27+ 권장 runtime 방식).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }

        // 2. 약한 lock (swipe) 은 자동 dismiss — 강한 lock (PIN/지문) 은 Accept 뒤
        //    사용자 인증 UI 뜸. 하지만 **Activity 자체는 visible + 통화 진행 가능**.
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (km?.isKeyguardLocked == true) {
            km.requestDismissKeyguard(this, null)
        }

        // 3. Native placeholder UI — Flutter 대체 전까지. 검정 배경 + Progress + 텍스트.
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }
        val progress = ProgressBar(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply { gravity = Gravity.CENTER }
        }
        val label = TextView(this).apply {
            text = "SnowChat Call"
            setTextColor(Color.WHITE)
            textSize = 18f
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.CENTER
                topMargin = 240
            }
        }
        root.addView(progress)
        root.addView(label)
        setContentView(root)

        // 4. Phase 1 (probe): MainActivity 로 redirect — 기존 Flutter /call 라우트 활용.
        //    MainActivity 는 FLAG_ACTIVITY_REORDER_TO_FRONT 로 resume, CallActivity 는
        //    1.5초 뒤 finish. Samsung Knox 에서 이 시점에 OS PIN 요구 여부 검증.
        //
        //    Phase 2+ 에서는 CallActivity 자체에 Flutter engine 을 embed 하여 MainActivity
        //    redirect 없이 바로 /call 렌더. 현재는 가설 probe 이므로 최소 변경.
        val forward = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            // MainActivity 가 call data extras 를 보고 /call 라우트로 자동 이동하도록 전달.
            // (현재 FCM / plugin 경로가 이미 같은 역할 — 중복되면 MainActivity 측에서 무시)
            intent.getBundleExtra(EXTRA_CALL_DATA)?.let { putExtras(it) }
        }
        if (forward != null) {
            startActivity(forward)
        }
        // 짧은 시간 후 self-finish. MainActivity 가 lock 위로 올라오면 우리가 사라져도
        // 사용자는 시각적으로 MainActivity 그대로 인식 (transition 자연스러움).
        window.decorView.postDelayed({
            if (!isFinishing) {
                finish()
                overridePendingTransition(0, 0)
            }
        }, 300)
    }
}
