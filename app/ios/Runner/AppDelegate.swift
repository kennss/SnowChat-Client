//
// @file        AppDelegate.swift
// @description iOS 앱 진입점으로 Flutter 엔진 초기화 및 Signal Protocol MethodChannel 브릿지 등록.
//              Phase E-2 v3.1: CallkitIncomingAppDelegate conform → CXAnswerCallAction
//              handoff to CallAcceptCoordinator. RelaxedKeychain + VoipNativeBridge
//              registration mirrored in both engine-bridge paths (CM-2 audit fix).
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-03-29
// @lastUpdated 2026-05-06 (snowchat/device_capability MethodChannel — exposes
//              ProcessInfo.physicalMemory to Dart so the SnowChat AI tile
//              can RAM-gate the Gemma 4 E2B download/load. iPhone 13 (4 GB)
//              OOMs on model load, so denial happens before the user
//              triggers the 2.9 GB fetch. Earlier 2026-05-03 v215: APNs
//              alert token registration. cert-era VoIP-only 집중기에 일반
//              message push (alert APNs) path 가 누락됐음.
//              FirebaseAppDelegateProxyEnabled=false (PushKit token
//              가로채기 방지) 환경이라 Firebase 가 register 콜백 못 받아
//              APNs token 어디로도 전달 안 됨 → DB pushToken=NULL → server
//              sendPush skip → BG/Lock 알림 0건. didRegisterForRemote-
//              NotificationsWithDeviceToken 직접 구현 + Messaging.apnsToken
//              forward 로 fcm.getToken/getAPNSToken 정상 작동시킴. Earlier
//              Phase 8.2 v2.1: audio session CallKit delegation —
//              didActivate/Deactivate stub → VoipNativeBridge.notify* bridge,
//              providerDidReset hook neu für system reset cleanup)
//
// @functions
//  - AppDelegate.application(_:didFinishLaunchingWithOptions:): 앱 실행 시 초기화 + APNs alert 등록
//  - AppDelegate.didInitializeImplicitFlutterEngine(_:): Flutter 엔진 초기화 후 플러그인 및 SignalBridge 등록
//  - AppDelegate.onAccept(_:_:): CallKit accept hand-off to CallAcceptCoordinator
//  - AppDelegate.onDecline(_:_:) / onEnd(_:_:) / onTimeOut(_:): CallKit lifecycle
//  - AppDelegate.didActivate/DeactivateAudioSession(_:): CallKit audio session → Dart bridge
//  - AppDelegate.providerDidReset(): CallKit system reset → Dart cleanup
//  - AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:): APNs alert token → FirebaseMessaging forward (v215)
//  - AppDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:): APNs register failure log (v215)
//

import AVFoundation
import CallKit
import FirebaseMessaging
import Flutter
import UIKit
import flutter_callkit_incoming
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, CallkitIncomingAppDelegate {

  /// Retains the SignalBridge so the MethodChannel handler stays alive.
  private var signalBridge: SignalBridge?
  /// Phase 10: llama.cpp AI bridge
  private var llamaBridge: LlamaBridge?
  /// Phase 10: Apple Translation API bridge
  private var translationBridge: AnyObject?
  /// Phase 10: Foreground URLSession downloader for large AI models
  private var foregroundDownloader: IOSForegroundDownloader?
  /// Phase E-2 (2026-04-29): PushKit VoIP — wakes the app on incoming call
  /// when backgrounded/locked. Registered after Flutter engine init so the
  /// plugin's sharedInstance is available.
  private var voipPushBridge: VoipPushBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for flutter_local_notifications to display notifications
    // while the app is in the foreground. FlutterAppDelegate already
    // conforms to UNUserNotificationCenterDelegate — this line activates it.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate

    // 2026-04-29 reverted: starting voipPushBridge here ran BEFORE
    // GeneratedPluginRegistrant, so SwiftFlutterCallkitIncomingPlugin.sharedInstance
    // was nil when PKPushRegistry's didUpdate fired → token was silent-dropped
    // by Optional chaining → DB never received voipPushToken → push gate
    // disabled for the device. start() is re-deferred to
    // didInitializeImplicitFlutterEngine (after plugin load). Cold-launch-by-push
    // race is a separate concern blocked by sandbox unreliability anyway.

    // v215 (2026-05-03): APNs alert push 등록 trigger. Firebase swizzle off
    // 환경이라 firebase_messaging.requestPermission 만으로는 register 콜백
    // 안 옴. 명시 호출 + AppDelegate didRegisterForRemoteNotificationsWith-
    // DeviceToken 콜백에서 Messaging.apnsToken forward.
    // 권한 없으면 silent fail (no error, no callback) — push_service.dart 의
    // requestPermission 후 자동 cycle 됨. Cold-launch 마다 호출해서 token
    // refresh 보장.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Required for flutter_local_notifications action isolate communication
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register Signal Protocol MethodChannel bridge + AI bridge + Translation bridge
    if let controller = window?.rootViewController as? FlutterViewController {
      let messenger = controller.binaryMessenger
      signalBridge = SignalBridge.register(with: messenger)
      llamaBridge = LlamaBridge.register(with: messenger)
      if #available(iOS 18.0, *) {
        translationBridge = TranslationBridge.register(with: messenger)
      }
      foregroundDownloader = IOSForegroundDownloader.register(with: messenger)
      // Phase E-2 v3.1: relaxed keychain + native VoIP bridge. Order matters —
      // VoipNativeBridge.register also calls CallAcceptCoordinator.attachMessenger,
      // so any pending accepts (e.g. cold-launch) drain immediately after attach.
      RelaxedKeychain.register(with: messenger)
      VoipNativeBridge.register(with: messenger)
      // Phase E-2: VoIP PushKit. Must come AFTER GeneratedPluginRegistrant so
      // SwiftFlutterCallkitIncomingPlugin.sharedInstance is initialized — else
      // PKPushRegistry's didUpdate silently drops the token (Optional chaining).
      voipPushBridge = VoipPushBridge()
      voipPushBridge?.start()
      // Phase 10 RAM gate (2026-05-06): physical memory query for the AI
      // tile gating in DeviceCapability (Dart). Read once on demand from
      // ProcessInfo.physicalMemory and return raw bytes; conversion to MB
      // and the 7000 MB cutoff live on the Dart side so iOS + Android stay
      // identical.
      registerDeviceCapabilityChannel(messenger: messenger)
      NSLog("[AppDelegate] All bridges registered via FlutterViewController")
    } else if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LlamaBridge") {
      let messenger = registrar.messenger()
      llamaBridge = LlamaBridge.register(with: messenger)
      if #available(iOS 18.0, *) {
        translationBridge = TranslationBridge.register(with: messenger)
      }
      foregroundDownloader = IOSForegroundDownloader.register(with: messenger)
      // Phase E-2 v3.1: mirror relaxed keychain + native VoIP bridge in
      // fallback path too (audit CM-2 — fallback fires on some launches).
      RelaxedKeychain.register(with: messenger)
      VoipNativeBridge.register(with: messenger)
      // Phase E-2: VoIP PushKit fallback path (engineBridge case — actual
      // code path per field logs). Same plugin-readiness rationale.
      voipPushBridge = VoipPushBridge()
      voipPushBridge?.start()
      // Phase 10 RAM gate (2026-05-06) — mirror in fallback path so cold
      // launches via the engineBridge route still expose the channel.
      registerDeviceCapabilityChannel(messenger: messenger)
      NSLog("[AppDelegate] Bridges registered via engineBridge fallback")
    } else {
      NSLog("[AppDelegate] WARNING: Could not register bridges")
    }
  }

  // MARK: – CallkitIncomingAppDelegate (Phase E-2 v3.1)
  //
  // Plugin's CXAnswerCallAction handler calls onAccept exactly once per accept.
  // We hand off to CallAcceptCoordinator immediately. Coordinator owns:
  //   - action.fulfill (must happen ≤5s for iOS — coordinator does it on main)
  //   - background task (~30s continued execution)
  //   - 30s watchdog (single-attempt cap, P3 v3.1)
  //   - per-nonce ephemeral URLSession fetch
  //   - drain to Dart via MethodChannel `snowchat/voip_native`
  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    let nonce = call.uuid.uuidString
    NSLog("[AppDelegate] onAccept nonce=\(nonce.prefix(8))")
    CallAcceptCoordinator.handleAccept(nonce: nonce, action: action, call: call)
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    NSLog("[AppDelegate] onDecline nonce=\(call.uuid.uuidString.prefix(8))")
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    NSLog("[AppDelegate] onEnd nonce=\(call.uuid.uuidString.prefix(8))")
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    let nonce = call.uuid.uuidString
    NSLog("[AppDelegate] onTimeOut nonce=\(nonce.prefix(8))")
    CallAcceptCoordinator.expirePending(nonce: nonce, reason: "ringerTimeout")
  }

  // Phase 8.2 v2.1 — Audio session CallKit delegation, path B (backup channel).
  // Path A is SwiftFlutterCallkitIncomingPlugin.sendEvent → Dart EventChannel.
  // We use VoipNativeBridge MethodChannel as a second source so Dart's CallService
  // can complete its _audioSessionActivatedCompleter on whichever fires first.
  // Dual-source ensures cold-launch / hot-restart edges are covered.
  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    NSLog("[AppDelegate] didActivateAudioSession sr=\(audioSession.sampleRate)")
    VoipNativeBridge.notifyAudioSessionActivated(sampleRate: audioSession.sampleRate)
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    NSLog("[AppDelegate] didDeactivateAudioSession")
    VoipNativeBridge.notifyAudioSessionDeactivated()
  }

  // Phase 8.2 v2.1 — CallKit system reset hook (airplane mode toggle, callservicesd
  // restart). Triggers Dart-side cleanup of any in-flight call state to avoid
  // dangling CallService / alias map / Completer leaks.
  func providerDidReset() {
    NSLog("[AppDelegate] providerDidReset (system reset) — notifying Dart for cleanup")
    VoipNativeBridge.notifySystemReset()
  }

  // MARK: – APNs alert push registration (v215, 2026-05-03)
  //
  // Path: didFinishLaunching 의 application.registerForRemoteNotifications() →
  //   iOS APNs handshake → 이 콜백 → Messaging.apnsToken 에 forward →
  //   FirebaseMessaging.instance.getToken() 또는 getAPNSToken() 이 valid
  //   token 반환 → push_service.dart 가 server PUT /devices/:id/push-token →
  //   DB UserDevice.pushToken 채워짐 → server PushNotificationService.sendPush
  //   가 device 발견 → APNs HTTP/2 alert 발사 → BG/Lock 알림 표시.
  //
  // Why direct forward (not Firebase swizzle): Info.plist 의
  //   FirebaseAppDelegateProxyEnabled=false (Phase E-2 §25.7 함정 #4 — VoIP
  //   PushKit token 가로채기 방지를 위해 disable). Firebase swizzle off 이면
  //   APNs register 콜백을 firebase 가 못 받아서 token 어디로도 전달 안 됨.
  //   AppDelegate 에서 직접 받아서 Messaging 에 set.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
  ) {
    // `Foundation.Data` 명시 — `import flutter_callkit_incoming` 이 자체
    // `Data` 클래스를 노출해서 unqualified `Data` 가 ambiguous 됨.
    let tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
    NSLog("[AppDelegate] APNs alert token registered \(tokenHex.prefix(8))…")
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[AppDelegate] APNs alert register FAILED: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // MARK: – Device capability (Phase 10 RAM gate, 2026-05-06)
  //
  // Returns ProcessInfo.physicalMemory raw bytes to Dart's
  // DeviceCapability.totalRamMB(). Dart applies the 7000 MB cutoff and
  // surfaces the AI-unavailable dialog on the SnowChat AI tile. iOS
  // reports physicalMemory close to the actual installed RAM (e.g.
  // iPhone 13 4 GB → ~3.74 GB, iPhone 15 Pro 8 GB → ~7.4 GB), so the
  // bytes value passed back is faithful enough to gate on directly.
  private func registerDeviceCapabilityChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "snowchat/device_capability",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getTotalRamBytes":
        let bytes = ProcessInfo.processInfo.physicalMemory
        // UInt64 → Int64 — iPhone 5s+ is all 64-bit, max physicalMemory
        // we will see on shipping hardware is ~12 GB which fits in Int64.
        result(NSNumber(value: bytes))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
