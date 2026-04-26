/**
 * @file        LiteRtLmBridge.kt
 * @description LiteRT-LM Engine ↔ Flutter MethodChannel 브릿지.
 *              Gemma 4 E2B .litertlm 모델을 로드하고 스트리밍 추론을 수행.
 *              Google AI Edge Gallery의 LlmChatModelHelper 패턴 참조.
 * @author      Kennt Kim
 * @company     Calida Lab
 * @created     2026-04-16
 * @lastUpdated 2026-04-20
 *
 * @functions
 *  - initialize(): Engine + Conversation 생성
 *  - sendMessage(): 스트리밍 추론 (EventChannel)
 *  - resetConversation(): 대화 히스토리 초기화
 *  - dispose(): 리소스 해제
 */

package com.snowchat.snowchat

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CancellationException

private const val TAG = "LiteRtLmBridge"
private const val METHOD_CHANNEL = "com.snowchat/litert_lm"
private const val EVENT_CHANNEL = "com.snowchat/litert_lm_stream"

class LiteRtLmBridge(
    private val context: Context,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler {

    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    // V1 안정성: GPU backend 가 4GB GL mtrack 점유 → IME process kill 유발.
    // CPU 를 default 로 (E2B 사이즈는 CPU 도 충분히 빠름). GPU 옵션은 V2 사용자 설정으로.
    private var currentBackend: Backend = Backend.CPU()
    private var modelPath: String? = null
    private var maxTokens: Int = 2048
    private var lastTopK: Int = 40
    private var lastTopP: Double = 0.95
    private var lastTemperature: Double = 0.7
    private var isBusy = false

    init {
        methodChannel.setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val modelPath = call.argument<String>("modelPath") ?: run {
                    result.error("MISSING_ARG", "modelPath required", null)
                    return
                }
                val maxTokens = call.argument<Int>("maxTokens") ?: 2048
                val topK = call.argument<Int>("topK") ?: 40
                val topP = call.argument<Double>("topP") ?: 0.95
                val temperature = call.argument<Double>("temperature") ?: 0.7
                initialize(modelPath, maxTokens, topK, topP, temperature, result)
            }
            "sendMessage" -> {
                val text = call.argument<String>("text") ?: run {
                    result.error("MISSING_ARG", "text required", null)
                    return
                }
                sendMessage(text, result)
            }
            "resetConversation" -> {
                val topK = call.argument<Int>("topK") ?: 40
                val topP = call.argument<Double>("topP") ?: 0.95
                val temperature = call.argument<Double>("temperature") ?: 0.7
                resetConversation(topK, topP, temperature, result)
            }
            "stopResponse" -> {
                conversation?.cancelProcess()
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            "isInitialized" -> {
                result.success(engine != null && conversation != null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(
        modelPath: String,
        maxTokens: Int,
        topK: Int,
        topP: Double,
        temperature: Double,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                Log.d(TAG, "Initializing engine: $modelPath")
                this.modelPath = modelPath
                this.maxTokens = maxTokens
                this.lastTopK = topK
                this.lastTopP = topP
                this.lastTemperature = temperature

                // 기존 리소스 정리
                dispose()

                // V1 안정성 default: CPU backend.
                // GPU backend 는 GL mtrack 4GB 점유 → 시스템 메모리 압박 →
                // Android Low Memory Killer 가 IME (키보드) process kill →
                // 사용자 입력 불가. CPU backend 는 native heap ~1GB 만 사용.
                val selectedBackend: Backend = Backend.CPU()
                val cpuConfig = EngineConfig(
                    modelPath = modelPath,
                    backend = selectedBackend,
                    maxNumTokens = maxTokens,
                )
                val newEngine = Engine(cpuConfig)
                newEngine.initialize()
                currentBackend = selectedBackend
                Log.d(TAG, "CPU backend initialized (V1 stability default)")

                val conv = newEngine.createConversation(
                    ConversationConfig(
                        samplerConfig = SamplerConfig(
                            topK = topK,
                            topP = topP,
                            temperature = temperature,
                        )
                    )
                )

                engine = newEngine
                conversation = conv

                Log.d(TAG, "Engine + conversation ready (backend: $selectedBackend)")
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                Log.e(TAG, "Initialize failed", e)
                mainHandler.post { result.error("INIT_FAILED", e.message, null) }
            }
        }.start()
    }

    private fun sendMessage(text: String, result: MethodChannel.Result) {
        val conv = conversation
        if (conv == null) {
            result.error("NOT_INITIALIZED", "Call initialize first", null)
            return
        }
        if (isBusy) {
            result.error("BUSY", "Inference in progress", null)
            return
        }

        isBusy = true
        val fullResponse = StringBuilder()

        conv.sendMessageAsync(
            Contents.of(listOf(Content.Text(text))),
            object : MessageCallback {
                override fun onMessage(message: Message) {
                    val token = message.toString()
                    fullResponse.append(token)
                    mainHandler.post {
                        eventSink?.success(mapOf(
                            "type" to "token",
                            "data" to fullResponse.toString()
                        ))
                    }
                }

                override fun onDone() {
                    isBusy = false
                    mainHandler.post {
                        eventSink?.success(mapOf(
                            "type" to "done",
                            "data" to fullResponse.toString()
                        ))
                        result.success(fullResponse.toString())
                    }
                }

                override fun onError(throwable: Throwable) {
                    isBusy = false
                    if (throwable is CancellationException) {
                        Log.i(TAG, "Inference cancelled")
                        mainHandler.post { result.success(fullResponse.toString()) }
                    } else {
                        Log.e(TAG, "Inference error", throwable)
                        mainHandler.post { result.error("INFERENCE_ERROR", throwable.message, null) }
                    }
                }
            },
            emptyMap()
        )
    }

    private fun resetConversation(topK: Int, topP: Double, temperature: Double, result: MethodChannel.Result) {
        try {
            conversation?.close()
            val conv = engine?.createConversation(
                ConversationConfig(
                    samplerConfig = SamplerConfig(
                        topK = topK,
                        topP = topP,
                        temperature = temperature,
                    )
                )
            )
            conversation = conv
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "Reset failed", e)
            result.error("RESET_FAILED", e.message, null)
        }
    }

    private fun dispose() {
        try { conversation?.close() } catch (_: Exception) {}
        try { engine?.close() } catch (_: Exception) {}
        conversation = null
        engine = null
        isBusy = false
    }
}
