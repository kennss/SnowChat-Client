//
// @file        LlamaBridge.swift
// @description llama.cpp ↔ Flutter MethodChannel 브릿지 (LlamaSwift SPM).
//              Gemma 4 E2B GGUF 모델을 로드하고 스트리밍 추론을 수행.
//              Android의 LiteRtLmBridge.kt와 동일한 채널 인터페이스.
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-17
// @lastUpdated 2026-04-18
//
// @functions
//  - initialize(): llama.cpp 모델 로드
//  - sendMessage(): 스트리밍 추론 (EventChannel)
//  - resetConversation(): 컨텍스트 초기화
//  - dispose(): 리소스 해제
//

import Flutter
import Foundation
import LlamaSwift

class LlamaBridge: NSObject {
    private let methodChannel: FlutterMethodChannel
    private var eventSink: FlutterEventSink?

    private var model: OpaquePointer? // llama_model
    private var ctx: OpaquePointer?   // llama_context
    private var isBusy = false
    private var backendInitialized = false

    private var savedModelPath: String?
    private var savedMaxTokens: Int32 = 2048

    static func register(with messenger: FlutterBinaryMessenger) -> LlamaBridge {
        return LlamaBridge(messenger: messenger)
    }

    private init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.snowchat/litert_lm",
            binaryMessenger: messenger
        )
        super.init()
        methodChannel.setMethodCallHandler(handle)

        let eventChannel = FlutterEventChannel(
            name: "com.snowchat/litert_lm_stream",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let modelPath = args["modelPath"] as? String else {
                result(FlutterError(code: "MISSING_ARG", message: "modelPath required", details: nil))
                return
            }
            let maxTokens = args["maxTokens"] as? Int ?? 2048
            initialize(modelPath: modelPath, maxTokens: maxTokens, result: result)

        case "sendMessage":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String else {
                result(FlutterError(code: "MISSING_ARG", message: "text required", details: nil))
                return
            }
            sendMessage(text: text, result: result)

        case "resetConversation":
            resetConversation(result: result)

        case "stopResponse":
            result(nil)

        case "dispose":
            cleanUp()
            result(nil)

        case "isInitialized":
            result(model != nil && ctx != nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Initialize

    private func initialize(modelPath: String, maxTokens: Int, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            NSLog("[LlamaBridge] Initializing: \(modelPath)")
            self.cleanUp()

            if !self.backendInitialized {
                llama_backend_init()
                self.backendInitialized = true
            }

            var modelParams = llama_model_default_params()
            modelParams.n_gpu_layers = 99

            guard let newModel = llama_model_load_from_file(modelPath, modelParams) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "INIT_FAILED", message: "Failed to load model", details: nil))
                }
                return
            }

            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = UInt32(maxTokens)
            ctxParams.n_batch = 512
            let nThreads = Int32(max(ProcessInfo.processInfo.processorCount - 2, 1))
            ctxParams.n_threads = nThreads
            ctxParams.n_threads_batch = nThreads

            guard let newCtx = llama_init_from_model(newModel, ctxParams) else {
                llama_model_free(newModel)
                DispatchQueue.main.async {
                    result(FlutterError(code: "INIT_FAILED", message: "Failed to create context", details: nil))
                }
                return
            }

            self.model = newModel
            self.ctx = newCtx
            self.savedModelPath = modelPath
            self.savedMaxTokens = Int32(maxTokens)

            NSLog("[LlamaBridge] Model + context ready")
            DispatchQueue.main.async { result(true) }
        }
    }

    // MARK: - Send Message

    private func sendMessage(text: String, result: @escaping FlutterResult) {
        guard let model = model, let ctx = ctx else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Call initialize first", details: nil))
            return
        }
        guard !isBusy else {
            result(FlutterError(code: "BUSY", message: "Inference in progress", details: nil))
            return
        }

        isBusy = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // KV 캐시 클리어 — 이전 대화 컨텍스트 제거
            let mem = llama_get_memory(ctx)
            llama_memory_clear(mem, true)

            let prompt = "<start_of_turn>user\n\(text)<end_of_turn>\n<start_of_turn>model\n"
            guard let vocab = llama_model_get_vocab(model) else {
                self.isBusy = false
                DispatchQueue.main.async {
                    result(FlutterError(code: "INFERENCE_ERROR", message: "Failed to get vocab", details: nil))
                }
                return
            }

            // 토큰화
            let promptTokens = self.tokenize(vocab: vocab, text: prompt)
            if promptTokens.isEmpty {
                self.isBusy = false
                DispatchQueue.main.async {
                    result(FlutterError(code: "INFERENCE_ERROR", message: "Tokenization failed", details: nil))
                }
                return
            }

            // Batch: prefill
            let batchSize = Int32(promptTokens.count)
            var batch = llama_batch_init(batchSize, 0, 1)
            defer { llama_batch_free(batch) }

            batch.n_tokens = batchSize
            for i in 0..<Int(batchSize) {
                batch.token[i] = promptTokens[i]
                batch.pos[i] = Int32(i)
                batch.n_seq_id[i] = 1
                if let seqIds = batch.seq_id, let seqId = seqIds[i] {
                    seqId[0] = 0
                }
                batch.logits[i] = (i == Int(batchSize) - 1) ? 1 : 0
            }

            guard llama_decode(ctx, batch) == 0 else {
                self.isBusy = false
                DispatchQueue.main.async {
                    result(FlutterError(code: "INFERENCE_ERROR", message: "Prefill decode failed", details: nil))
                }
                return
            }

            // Autoregressive generation
            var fullResponse = ""
            var nCur = batchSize
            let eosToken = llama_vocab_eos(vocab)
            let vocabSize = Int(llama_vocab_n_tokens(vocab))

            for _ in 0..<2048 {
                guard let logits = llama_get_logits_ith(ctx, batch.n_tokens - 1) else { break }

                // Greedy sampling
                var maxLogit = logits[0]
                var nextToken: llama_token = 0
                for j in 1..<vocabSize {
                    if logits[j] > maxLogit {
                        maxLogit = logits[j]
                        nextToken = llama_token(j)
                    }
                }

                if nextToken == eosToken { break }

                // Token → text
                var buf = [CChar](repeating: 0, count: 256)
                let len = llama_token_to_piece(vocab, nextToken, &buf, Int32(buf.count), 0, false)
                if len > 0 {
                    buf[Int(len)] = 0
                    let tokenText = String(cString: buf)

                    fullResponse += tokenText

                    // <end_of_turn> 감지 — 토큰 분할 대응 (append 후 체크)
                    if fullResponse.contains("<end_of_turn>") {
                        fullResponse = fullResponse.replacingOccurrences(of: "<end_of_turn>", with: "")
                        break
                    }
                    if fullResponse.contains("<start_of_turn>") {
                        fullResponse = fullResponse.replacingOccurrences(of: "<start_of_turn>", with: "")
                        break
                    }

                    let streamData = fullResponse
                        .replacingOccurrences(of: "<end_of_turn>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        self.eventSink?(["type": "token", "data": streamData])
                    }
                }

                // Decode next token
                batch.n_tokens = 1
                batch.token[0] = nextToken
                batch.pos[0] = nCur
                batch.n_seq_id[0] = 1
                if let seqIds = batch.seq_id, let seqId = seqIds[0] {
                    seqId[0] = 0
                }
                batch.logits[0] = 1

                guard llama_decode(ctx, batch) == 0 else { break }
                nCur += 1
            }

            self.isBusy = false
            let finalResponse = fullResponse
                .replacingOccurrences(of: "<end_of_turn>", with: "")
                .replacingOccurrences(of: "<start_of_turn>model", with: "")
                .replacingOccurrences(of: "<start_of_turn>user", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                self.eventSink?(["type": "done", "data": finalResponse])
                result(finalResponse)
            }
        }
    }

    // MARK: - Reset

    private func resetConversation(result: FlutterResult) {
        guard let model = model else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "No model", details: nil))
            return
        }

        if let c = ctx { llama_free(c) }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(savedMaxTokens)
        ctxParams.n_batch = 2048
        let nThreads = Int32(max(ProcessInfo.processInfo.processorCount - 2, 1))
        ctxParams.n_threads = nThreads
        ctxParams.n_threads_batch = nThreads

        ctx = llama_init_from_model(model, ctxParams)
        result(true)
    }

    // MARK: - Cleanup

    private func cleanUp() {
        if let c = ctx { llama_free(c); ctx = nil }
        if let m = model { llama_model_free(m); model = nil }
        isBusy = false
    }

    // MARK: - Helpers

    private func tokenize(vocab: OpaquePointer, text: String) -> [llama_token] {
        let utf8Count = text.utf8.count
        let maxTokens = utf8Count + 1
        var tokens = [llama_token](repeating: 0, count: maxTokens)
        let n = llama_tokenize(vocab, text, Int32(utf8Count), &tokens, Int32(maxTokens), true, true)
        guard n > 0 else { return [] }
        return Array(tokens.prefix(Int(n)))
    }
}

// MARK: - FlutterStreamHandler

extension LlamaBridge: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
