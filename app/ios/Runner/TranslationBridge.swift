//
// @file        TranslationBridge.swift
// @description Apple Translation API ↔ Flutter MethodChannel 브릿지.
//              iOS 18+ 온디바이스 번역 (Zero-Knowledge 유지).
//              Gemma AI와 완전 분리 — 번역 전용 채널.
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-18
// @lastUpdated 2026-04-18
//
// @functions
//  - TranslationBridge.register(): Flutter MethodChannel 등록
//  - translate(): Apple Translation API로 텍스트 번역
//  - isAvailable(): 번역 API 사용 가능 여부 확인
//

import Flutter
import UIKit
import SwiftUI
import Translation

@available(iOS 18.0, *)
class TranslationBridge: NSObject {
    private let methodChannel: FlutterMethodChannel
    private var translationService: AppleTranslationService?
    private var viewAttached = false

    static func register(with messenger: FlutterBinaryMessenger) -> TranslationBridge {
        return TranslationBridge(messenger: messenger)
    }

    private init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.snowchat/apple_translation",
            binaryMessenger: messenger
        )
        super.init()
        methodChannel.setMethodCallHandler(handle)
        NSLog("[TranslationBridge] MethodChannel registered")
    }

    /// Lazy attach: 첫 번역 요청 시 key window에서 rootViewController를 찾아 SwiftUI view 부착
    private func ensureViewAttached() {
        if viewAttached { return }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            NSLog("[TranslationBridge] No root view controller yet")
            return
        }

        let service = AppleTranslationService()
        self.translationService = service

        let hostingView = UIHostingController(
            rootView: HiddenTranslationView(service: service)
        )
        hostingView.view.frame = .zero
        hostingView.view.isHidden = true
        root.view.addSubview(hostingView.view)
        root.addChild(hostingView)
        hostingView.didMove(toParent: root)

        viewAttached = true
        NSLog("[TranslationBridge] Translation view attached to root")
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "translate":
            guard let args = call.arguments as? [String: Any],
                  let text = args["text"] as? String,
                  let targetLang = args["targetLang"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "text and targetLang required", details: nil))
                return
            }
            let sourceLang = args["sourceLang"] as? String
            translate(text: text, sourceLang: sourceLang, targetLang: targetLang, result: result)

        case "isAvailable":
            checkAvailability(result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func translate(text: String, sourceLang: String?, targetLang: String,
                           result: @escaping FlutterResult) {
        NSLog("[TranslationBridge] translate: '\(text.prefix(50))' \(sourceLang ?? "auto") → \(targetLang)")

        ensureViewAttached()

        guard let service = translationService else {
            NSLog("[TranslationBridge] ERROR: service not ready")
            result(FlutterError(code: "NOT_READY", message: "Translation view not attached", details: nil))
            return
        }

        service.translate(text: text, sourceLang: sourceLang, targetLang: targetLang) { translated, error in
            DispatchQueue.main.async {
                if let translated = translated {
                    NSLog("[TranslationBridge] OK: '\(translated.prefix(50))'")
                    result(translated)
                } else {
                    NSLog("[TranslationBridge] FAIL: \(error?.localizedDescription ?? "unknown")")
                    result(FlutterError(
                        code: "TRANSLATE_FAILED",
                        message: error?.localizedDescription ?? "Unknown error",
                        details: nil
                    ))
                }
            }
        }
    }

    private func checkAvailability(result: @escaping FlutterResult) {
        Task {
            let availability = LanguageAvailability()
            let status = await availability.status(
                from: Locale.Language(identifier: "en"),
                to: Locale.Language(identifier: "ko")
            )
            let available = status != .unsupported
            NSLog("[TranslationBridge] isAvailable: \(available) (status=\(status))")
            DispatchQueue.main.async {
                result(available)
            }
        }
    }
}

// MARK: - Apple Translation Service — 세션 캐시 + 재사용

@available(iOS 18.0, *)
class AppleTranslationService: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    /// 캐시된 세션 — 첫 .translationTask에서 획득, 이후 재사용
    private var cachedSession: TranslationSession?
    private var sessionLangKey: String = ""

    /// 대기 중인 번역 요청 큐
    private var pendingRequests: [(text: String, completion: (String?, Error?) -> Void)] = []
    private var isProcessing = false

    func translate(text: String, sourceLang: String?, targetLang: String,
                   completion: @escaping (String?, Error?) -> Void) {
        let langKey = "\(sourceLang ?? "auto")→\(targetLang)"

        // 캐시된 세션이 있고 같은 언어 쌍이면 바로 사용
        if let session = cachedSession, sessionLangKey == langKey {
            NSLog("[TranslationService] Using cached session for \(langKey)")
            translateWithSession(session, text: text, completion: completion)
            return
        }

        // 새 세션 필요 — 큐에 넣고 .translationTask 트리거
        pendingRequests.append((text: text, completion: completion))
        sessionLangKey = langKey

        // 캐시 무효화 후 새 config 설정
        cachedSession = nil
        self.configuration = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = sourceLang.map { Locale.Language(identifier: $0) }
            let target = Locale.Language(identifier: targetLang)
            self.configuration = .init(source: source, target: target)
            NSLog("[TranslationService] Config set: \(langKey)")
        }
    }

    /// .translationTask에서 호출 — 세션 캐시 + 대기 요청 처리
    func handleSession(_ session: TranslationSession) {
        NSLog("[TranslationService] Session received, caching...")
        self.cachedSession = session

        // 대기 중인 요청 처리
        let pending = pendingRequests
        pendingRequests.removeAll()

        for request in pending {
            translateWithSession(session, text: request.text, completion: request.completion)
        }
    }

    private func translateWithSession(_ session: TranslationSession, text: String,
                                      completion: @escaping (String?, Error?) -> Void) {
        Task {
            do {
                let response = try await session.translate(text)
                NSLog("[TranslationService] Translated: '\(response.targetText.prefix(50))'")
                completion(response.targetText, nil)
            } catch {
                NSLog("[TranslationService] Error: \(error)")
                // 세션 만료 시 캐시 무효화
                self.cachedSession = nil
                completion(nil, error)
            }
        }
    }
}

// MARK: - Hidden SwiftUI View (TranslationSession 획득용)

@available(iOS 18.0, *)
struct HiddenTranslationView: View {
    @ObservedObject var service: AppleTranslationService

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(service.configuration) { session in
                service.handleSession(session)
            }
    }
}
