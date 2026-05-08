//
// @file        VoipNativeBridge.swift
// @description MethodChannel `snowchat/voip_native` — bidirectional bridge
//              between Dart and CallAcceptCoordinator.
//
//              Native → Dart (one-way invokeMethod from coordinator):
//                "voipAcceptedEnvelopes": { nonce, envelopes }
//
//              Dart → Native (incoming MethodCall):
//                "setBaseUrl"   : { url }   — push resolved API base. Required
//                                            before fetch can run.
//                "drainPending" : {}        — request immediate drain of any
//                                            queued envelopes (idempotent).
//                "ack"          : { nonce } — Dart confirmed accept handed
//                                            off to call_provider; coordinator
//                                            removes nonce from pendingByNonce
//                                            (already happened in drain, but
//                                            keep for symmetry with future
//                                            socket path).
//
//              Drain channel and inbound channel share the same name so
//              VoipNativeBridge.attach is the single attach point —
//              CallAcceptCoordinator.attachMessenger uses the SAME channel.
//
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-30
// @lastUpdated 2026-05-02 (Phase 8.2 v2.2 — replay invocation forwarding:
//              Dart MethodChannel → handle() → SwiftFlutterCallkitIncomingPlugin
//              .replayLastActivationIfRecent / .replayLastAcceptIfRecent.
//              Path A (EventChannel direct subscribe in CallService) was removed
//              because EventChannel.receiveBroadcastStream() is single-subscriber
//              at the native onListen layer — having two subscribers causes the
//              second to overwrite the first sink, killing CallKitManager's
//              event reception. Plugin events now reach Dart only through the
//              plugin's own EventChannel listener (CallKitManager).
//
// @functions
//  - register(messenger): attach inbound handler
//  - handle(call, result): dispatch setBaseUrl | drainPending | ack
//  - notifyAudioSessionActivated(sampleRate): native → Dart audio activate event
//  - notifyAudioSessionDeactivated(): native → Dart audio deactivate event
//  - notifySystemReset(): native → Dart CallKit providerDidReset cleanup signal
//

import Foundation
import Flutter
import flutter_callkit_incoming

@objc final class VoipNativeBridge: NSObject {

    private static var channel: FlutterMethodChannel?

    @objc public static func register(with messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(
            name: "snowchat/voip_native",
            binaryMessenger: messenger
        )
        ch.setMethodCallHandler { call, result in
            VoipNativeBridge.handle(call: call, result: result)
        }
        channel = ch
        // Also hand the messenger to CallAcceptCoordinator so it can use the
        // SAME channel for native→Dart drain.
        CallAcceptCoordinator.attachMessenger(messenger)
    }

    // MARK: – Phase 8.2 v2.1 — Audio session CallKit delegation (path B)
    //
    // Path A (primary): SwiftFlutterCallkitIncomingPlugin.sendEvent → Dart EventChannel
    //   `flutter_callkit_incoming_events`
    // Path B (backup):  AppDelegate.didActivateAudioSession → these methods →
    //   Dart MethodChannel `snowchat/voip_native`
    // Dart's CallService completes its _audioSessionActivatedCompleter on whichever
    // path fires first (idempotent guard via `if (!isCompleted)`).
    //
    // FlutterMethodChannel.invokeMethod must be called on the main thread per Apple
    // docs. CallKit fires didActivate on its internal queue → DispatchQueue.main.async.

    @objc public static func notifyAudioSessionActivated(sampleRate: Double) {
        DispatchQueue.main.async {
            channel?.invokeMethod(
                "audioSessionActivated",
                arguments: ["sampleRate": sampleRate]
            )
        }
    }

    @objc public static func notifyAudioSessionDeactivated() {
        DispatchQueue.main.async {
            channel?.invokeMethod("audioSessionDeactivated", arguments: nil)
        }
    }

    @objc public static func notifySystemReset() {
        DispatchQueue.main.async {
            channel?.invokeMethod("systemReset", arguments: nil)
        }
    }

    private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setBaseUrl":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String, !url.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "url missing", details: nil))
                return
            }
            CallAcceptCoordinator.setBaseUrl(url)
            result(nil)
        case "drainPending":
            // No-op — internal coordinator drains automatically on attach +
            // on fetch completion. Provided so Dart can request a drain
            // proactively after a hot-restart that lost the previous channel.
            result(nil)
        case "ack":
            guard let args = call.arguments as? [String: Any],
                  let nonce = args["nonce"] as? String, !nonce.isEmpty else {
                result(FlutterError(code: "BAD_ARG", message: "nonce missing", details: nil))
                return
            }
            // Idempotent — coordinator already cleaned this nonce on drain.
            // Kept for future socket-path symmetry.
            _ = nonce
            result(nil)
        case "replayLastActivationIfRecent":
            // Phase 8.2 v2.2 — forward to plugin. CallService used to invoke the
            // plugin's MethodChannel directly via path A's EventChannel subscribe;
            // now path A is gone and Dart routes everything through this bridge.
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.replayLastActivationIfRecent()
            result(nil)
        case "replayLastAcceptIfRecent":
            // Phase 8.2 v2.2 — forward to plugin. Plugin replays the cached
            // ACTION_CALL_ACCEPT via sendEvent → EventChannel → CallKitManager
            // → CallNotifier._onCallKitEvent (the same path the original sendEvent
            // would have taken if the sink hadn't been nil).
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.replayLastAcceptIfRecent()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
