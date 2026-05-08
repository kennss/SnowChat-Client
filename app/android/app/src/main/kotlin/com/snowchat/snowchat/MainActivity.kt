/**
 * @file        MainActivity.kt
 * @description Android main Activity. Hosts the only FlutterEngine for the
 *              entire app — chat / wallet / call all render in this Activity.
 *              The manifest declares showWhenLocked=true so the call path
 *              can render /call over the keyguard without forcing a PIN.
 *
 *              Option 2 (dedicated CallActivity hosting a cached engine)
 *              was attempted on 2026-05-06 and reverted: FlutterFragment
 *              exclusively locks an attached engine, so a second Activity
 *              cannot attach to the same engine. WebRTC peer connection
 *              state lives in the Dart isolate, which would have to be
 *              re-hosted in a native foreground service to support a
 *              separate CallActivity — out of scope for now.
 *
 *              The lockscreen security gap that comes with a single host
 *              is closed on the Dart side: when /call ends with the
 *              keyguard still locked, app.dart's idle listener calls
 *              SystemNavigator.pop() to finish this Activity instead of
 *              popping into the underlying chat / wallet route, returning
 *              the user to the lock screen.
 *
 *              SignalBridge / SignalStore were retired during the Pure
 *              Dart migration (Phase 6.x); the Kotlin file + Gradle
 *              libsignal dependency were removed 2026-04-21.
 * @author      Kennt Kim
 * @company     Calida Lab
 * @created     2026-03-29
 * @lastUpdated 2026-05-06 (snowchat/device_capability channel — exposes
 *              ActivityManager.MemoryInfo.totalMem to Dart for the
 *              SnowChat AI tile RAM gate. Cold-launch auto-download was
 *              removed on the Dart side; the gate decides whether the
 *              user even sees the model download flow. Earlier same-day:
 *              option 1 restored — single-host MainActivity,
 *              showWhenLocked manifest, snowchat/keyguard channel for the
 *              Dart-side post-call activity-finish)
 *
 * @functions
 *  - MainActivity.attachBaseContext(): wraps the base context with an
 *    English locale so every Resources.getConfiguration call from this
 *    Activity (and its child services that derive their context from
 *    here) resolves to English regardless of the device language setting.
 *  - MainActivity.configureFlutterEngine(): registers the five
 *    SnowChat-owned MethodChannels — LiteRtLm, voip_decline_recovery,
 *    diag_log, keyguard, device_capability.
 */

package com.snowchat.snowchat

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.Context
import android.content.res.Configuration
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {

    private var liteRtLmBridge: LiteRtLmBridge? = null

    // 2026-05-08 i18n locale lock (Phase 0) — match iOS
    // CFBundleLocalizations=['en']. Wraps the Activity's base context
    // with an English locale so Resources lookups inside our process
    // return English strings even when the device is set to Korean.
    // Companion build-time guard sits in app/build.gradle.kts
    // (resourceConfigurations.add("en")). Note that ConnectionService's
    // system incoming-call UI is rendered by the Telecom service in the
    // device's locale and is not affected by this — see the TO-DO doc
    // for the limitation.
    override fun attachBaseContext(newBase: Context?) {
        val english = Locale("en")
        Locale.setDefault(english)
        val baseConfig = newBase?.resources?.configuration
        val config = if (baseConfig != null) Configuration(baseConfig) else Configuration()
        config.setLocale(english)
        val wrapped = newBase?.createConfigurationContext(config)
        super.attachBaseContext(wrapped ?: newBase)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Phase 10: LiteRT-LM on-device AI bridge.
        liteRtLmBridge = LiteRtLmBridge(applicationContext, flutterEngine)

        // [SnowChat 2026-05-05] VoIP DECLINE cold-launch recovery channel.
        // The flutter_callkit_incoming fork (CallkitIncomingBroadcastReceiver
        // ACTION_CALL_DECLINE branch) writes the declined nonce to
        // SharedPreferences and starts MainActivity when CallKit was raised
        // by a BG FCM handler (no MAIN engine, no Dart listener for the
        // sendEvent broadcast). Dart calls `consumePending` shortly after
        // boot to retrieve the nonce and run declinePendingVoipCall, which
        // sends call_end via the sealed_call_signaling socket path.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "snowchat/voip_decline_recovery",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "consumePending" -> {
                    val prefs = applicationContext.getSharedPreferences(
                        "snowchat_voip_decline",
                        Context.MODE_PRIVATE,
                    )
                    val nonce = prefs.getString("pending_nonce", null)
                    val storedAt = prefs.getLong("pending_at", 0L)
                    val ageMs = System.currentTimeMillis() - storedAt
                    // Always clear (one-shot), but only return if recent.
                    prefs.edit().clear().apply()
                    if (nonce != null && ageMs in 0..60_000L) {
                        Log.d("VoipDeclineRecovery", "[DIAG] consumePending RETURN nonce=$nonce ageMs=$ageMs")
                        result.success(nonce)
                    } else {
                        Log.d("VoipDeclineRecovery", "[DIAG] consumePending null (nonce=${nonce ?: "null"} ageMs=$ageMs)")
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // [SnowChat 2026-05-05] Diagnostic log echo bridge for release builds.
        // Flutter release strips Dart `print` / `debugPrint` from Android
        // logcat (only engine bootstrap "I flutter" survives). To diagnose
        // release-only races (notably the VoIP decline → call_end → caller
        // never sees end-of-call symptom), Dart calls
        //   MethodChannel('snowchat/diag_log').invokeMethod('log', {'tag': T, 'msg': M})
        // and Kotlin emits a Log.d(T, M) so the line appears under the same
        // logcat tag as native code.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "snowchat/diag_log",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "log" -> {
                    val args = call.arguments as? Map<*, *>
                    val tag = (args?.get("tag") as? String) ?: "SnowChatDiag"
                    val msg = (args?.get("msg") as? String) ?: ""
                    Log.d(tag, msg)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // [SnowChat 2026-05-06] Keyguard query channel.
        //
        // MainActivity is shared by the chat / wallet / call surfaces and
        // carries showWhenLocked=true in the manifest so a call accepted
        // on a locked phone can render /call without forcing PIN entry.
        // Once the call ends, Dart pops the /call route — without further
        // action the underlying chat / wallet route would become visible
        // on top of the still-locked keyguard.
        //
        // Dart's idle listener (app.dart) calls `isLocked` here at the
        // /call → idle transition. If the keyguard is still locked, Dart
        // runs SystemNavigator.pop() to finish this Activity instead of
        // popping into the underlying route, returning the user to the
        // lock screen.
        //
        // Implementation note: KeyguardManager.isKeyguardLocked is a
        // sync call against the OS state; safe to invoke on the main
        // thread.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "snowchat/keyguard",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isLocked" -> {
                    val km = applicationContext
                        .getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                    val locked = km?.isKeyguardLocked == true
                    val secure = km?.isKeyguardSecure == true
                    val deviceLocked = km?.isDeviceLocked == true
                    Log.d(
                        "SnowChatDiag",
                        "[keyguard:native] isLocked=$locked secure=$secure deviceLocked=$deviceLocked",
                    )
                    result.success(locked)
                }
                else -> result.notImplemented()
            }
        }

        // [SnowChat 2026-05-06] Device capability channel — RAM gate for
        // the SnowChat AI tile. Dart's DeviceCapability.totalRamMB()
        // applies the 7000 MB cutoff and decides whether to show the
        // AI-unavailable dialog or route to the model download / chat.
        //
        // We return ActivityManager.MemoryInfo.totalMem as a Long
        // (bytes). Dart converts to MB. Same channel name and contract
        // as iOS — keeps platform parity.
        //
        // Why totalMem and not Runtime.maxMemory or available heap:
        // we want the physical hardware capacity to gate "can this
        // device run a 2.58 GB model at all" — not the per-app heap,
        // which is a separate constraint LiteRT-LM handles internally.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "snowchat/device_capability",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTotalRamBytes" -> {
                    val am = applicationContext
                        .getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                    if (am == null) {
                        result.success(0L)
                        return@setMethodCallHandler
                    }
                    val info = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(info)
                    Log.d(
                        "SnowChatDiag",
                        "[deviceCap:native] totalMem=${info.totalMem} lowRam=${am.isLowRamDevice}",
                    )
                    result.success(info.totalMem)
                }
                else -> result.notImplemented()
            }
        }
    }
}
