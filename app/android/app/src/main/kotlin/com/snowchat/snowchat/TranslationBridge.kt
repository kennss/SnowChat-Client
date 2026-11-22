/**
 * @file        TranslationBridge.kt
 * @description Android on-device translation — Google ML Kit (Translate +
 *              Language ID) behind the `snowchat/mlkit_translation`
 *              MethodChannel. Mirrors the iOS Apple Translation bridge
 *              (ios/Runner/TranslationBridge.swift, channel
 *              `com.snowchat/apple_translation`): Dart only calls a channel,
 *              each platform owns its native engine.
 *
 *              Why native instead of the google_mlkit_* Flutter plugins:
 *              Flutter plugins link on every platform, so the plugins dragged
 *              the GoogleMLKit pods into the iOS app even though iOS never
 *              calls them. Those pods ship no arm64 iOS-Simulator slice,
 *              which forced x86_64-only simulator builds (rejected by the
 *              Xcode 27 / iOS 27 simulators). With ML Kit as a plain Gradle
 *              dependency here, iOS carries no ML Kit at all.
 *
 *              Behavior is identical to the former Dart implementation:
 *               - source language detected with Language ID (confidence 0.5);
 *                 "und" → no translation
 *               - only SnowChat's 9 UI languages are translated
 *               - same source and target → no translation
 *               - one Translator per language pair, cached; models are
 *                 downloaded on first use without a Wi-Fi requirement
 *              Everything stays on the device (zero-knowledge preserved).
 * @author      Kennt Kim
 * @company     Calida Lab
 * @created     2026-11-11
 * @lastUpdated 2026-11-11
 *
 * @functions
 *  - TranslationBridge.onMethodCall(): "translate" / "dispose" dispatch
 *  - TranslationBridge.translate(): detect → map → ensure model → translate
 *  - TranslationBridge.ensureModel(): one shared download Task per pair
 *  - TranslationBridge.dispose(): close every translator + the identifier
 *
 * @notes
 *  - "translate" args: {text: String, targetLang: BCP-47 String}. Returns the
 *    translated String, or null when there is nothing to translate
 *    (undetermined / unsupported / same language). Engine failures (model
 *    download, translation) are returned as a channel error.
 *  - All ML Kit Task listeners run on the main thread (no executor given), so
 *    MethodChannel.Result is always completed on the platform thread.
 *  - Never logs message text — only language codes and outcomes.
 */

package com.snowchat.snowchat

import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.languageid.LanguageIdentification
import com.google.mlkit.nl.languageid.LanguageIdentificationOptions
import com.google.mlkit.nl.languageid.LanguageIdentifier
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TranslationBridge(flutterEngine: FlutterEngine) : MethodChannel.MethodCallHandler {

    private val channel =
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

    private var identifier: LanguageIdentifier? = null

    /** key "src→tgt" (ML Kit language codes) → cached translator. */
    private val translators = HashMap<String, Translator>()

    /**
     * key "src→tgt" → model download in flight or finished. Concurrent calls
     * for the same pair share one Task; a failed Task is dropped so the next
     * call retries.
     */
    private val downloads = HashMap<String, Task<Void>>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "translate" -> {
                val text = call.argument<String>("text")
                val targetTag = call.argument<String>("targetLang")
                if (text.isNullOrEmpty() || targetTag.isNullOrEmpty()) {
                    result.error("bad_args", "text and targetLang are required", null)
                    return
                }
                translate(text, targetTag, result)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun translate(text: String, targetTag: String, result: MethodChannel.Result) {
        val target = toMlKitLanguage(targetTag)
        if (target == null) {
            Log.d(TAG, "unsupported target $targetTag")
            result.success(null)
            return
        }

        val id = identifier ?: LanguageIdentification.getClient(
            LanguageIdentificationOptions.Builder()
                .setConfidenceThreshold(CONFIDENCE_THRESHOLD)
                .build()
        ).also { identifier = it }

        id.identifyLanguage(text)
            .addOnSuccessListener { detected ->
                if (detected == LanguageIdentifier.UNDETERMINED_LANGUAGE_TAG) {
                    Log.d(TAG, "source language undetermined")
                    result.success(null)
                    return@addOnSuccessListener
                }
                val source = toMlKitLanguage(detected)
                if (source == null) {
                    Log.d(TAG, "unsupported source $detected")
                    result.success(null)
                    return@addOnSuccessListener
                }
                if (source == target) {
                    Log.d(TAG, "same language skip ($source)")
                    result.success(null)
                    return@addOnSuccessListener
                }

                val key = "$source→$target"
                val translator = translators.getOrPut(key) {
                    Translation.getClient(
                        TranslatorOptions.Builder()
                            .setSourceLanguage(source)
                            .setTargetLanguage(target)
                            .build()
                    )
                }
                ensureModel(key, translator)
                    .addOnSuccessListener {
                        translator.translate(text)
                            .addOnSuccessListener { translated ->
                                result.success(translated.trim())
                            }
                            .addOnFailureListener { e ->
                                Log.w(TAG, "translate failed ($key): ${e.javaClass.simpleName}")
                                result.error("translate_failed", e.javaClass.simpleName, null)
                            }
                    }
                    .addOnFailureListener { e ->
                        Log.w(TAG, "model download failed ($key): ${e.javaClass.simpleName}")
                        result.error("model_download_failed", e.javaClass.simpleName, null)
                    }
            }
            .addOnFailureListener { e ->
                Log.w(TAG, "language id failed: ${e.javaClass.simpleName}")
                result.error("language_id_failed", e.javaClass.simpleName, null)
            }
    }

    /** Shared model-download Task for [key]; a failed download is forgotten. */
    private fun ensureModel(key: String, translator: Translator): Task<Void> {
        downloads[key]?.let { existing ->
            if (!existing.isComplete || existing.isSuccessful) return existing
        }
        Log.d(TAG, "downloading model $key")
        val task = translator.downloadModelIfNeeded(DownloadConditions.Builder().build())
        downloads[key] = task
        task.addOnFailureListener {
            if (downloads[key] === task) downloads.remove(key)
        }
        return task
    }

    /** Release every native translator and the language identifier. */
    fun dispose() {
        translators.values.forEach { it.close() }
        translators.clear()
        downloads.clear()
        identifier?.close()
        identifier = null
    }

    /** Detaches the channel handler and frees ML Kit resources. */
    fun detach() {
        channel.setMethodCallHandler(null)
        dispose()
    }

    /**
     * BCP-47 tag ("ko", "zh-Hans", "zh_CN", …) → ML Kit language code, limited
     * to SnowChat's 9 UI languages (same set the Dart mapping used).
     */
    private fun toMlKitLanguage(tag: String): String? {
        val primary = tag.split('-', '_').first().lowercase()
        return when (primary) {
            "en" -> TranslateLanguage.ENGLISH
            "ko" -> TranslateLanguage.KOREAN
            "ja" -> TranslateLanguage.JAPANESE
            "zh" -> TranslateLanguage.CHINESE
            "fr" -> TranslateLanguage.FRENCH
            "de" -> TranslateLanguage.GERMAN
            "es" -> TranslateLanguage.SPANISH
            "ru" -> TranslateLanguage.RUSSIAN
            "ar" -> TranslateLanguage.ARABIC
            else -> null
        }
    }

    companion object {
        const val CHANNEL = "snowchat/mlkit_translation"
        private const val TAG = "SnowChatTranslate"
        private const val CONFIDENCE_THRESHOLD = 0.5f
    }
}
