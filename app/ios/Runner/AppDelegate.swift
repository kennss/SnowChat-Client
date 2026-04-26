//
// @file        AppDelegate.swift
// @description iOS 앱 진입점으로 Flutter 엔진 초기화 및 Signal Protocol MethodChannel 브릿지 등록
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-03-29
// @lastUpdated 2026-04-18
//
// @functions
//  - AppDelegate.application(_:didFinishLaunchingWithOptions:): 앱 실행 시 초기화
//  - AppDelegate.didInitializeImplicitFlutterEngine(_:): Flutter 엔진 초기화 후 플러그인 및 SignalBridge 등록
//

import Flutter
import UIKit
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Retains the SignalBridge so the MethodChannel handler stays alive.
  private var signalBridge: SignalBridge?
  /// Phase 10: llama.cpp AI bridge
  private var llamaBridge: LlamaBridge?
  /// Phase 10: Apple Translation API bridge
  private var translationBridge: AnyObject?
  /// Phase 10: Foreground URLSession downloader for large AI models
  private var foregroundDownloader: IOSForegroundDownloader?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required for flutter_local_notifications to display notifications
    // while the app is in the foreground. FlutterAppDelegate already
    // conforms to UNUserNotificationCenterDelegate — this line activates it.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate

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
      NSLog("[AppDelegate] All bridges registered via FlutterViewController")
    } else if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LlamaBridge") {
      let messenger = registrar.messenger()
      llamaBridge = LlamaBridge.register(with: messenger)
      if #available(iOS 18.0, *) {
        translationBridge = TranslationBridge.register(with: messenger)
      }
      foregroundDownloader = IOSForegroundDownloader.register(with: messenger)
      NSLog("[AppDelegate] Bridges registered via engineBridge fallback")
    } else {
      NSLog("[AppDelegate] WARNING: Could not register bridges")
    }
  }
}
