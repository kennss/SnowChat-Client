//
// @file        VoipPushBridge.swift
// @description PushKit (VoIP) registry + handoff to flutter_callkit_incoming.
//              iOS only. Phase E-2 (Apple Dev cert activated 2026-04-28,
//              .p8 + APNs key in prod).
//
//              Flow:
//                1. AppDelegate instantiates this bridge after Flutter engine init.
//                2. PKPushRegistry registers for type=.voIP.
//                3. didUpdate(pushCredentials) → forward token to plugin via
//                   setDevicePushTokenVoIP — triggers Dart onEvent
//                   actionDidUpdateDevicePushTokenVoip → Dart side uploads to server.
//                4. didReceiveIncomingPushWith(payload) → build CallKit Data dict +
//                   call SwiftFlutterCallkitIncomingPlugin.sharedInstance.showCallkitIncoming
//                   with fromPushKit:true. completion() must fire within ~5s or iOS kills app.
//
//              Zero-Knowledge / §2.6.1: payload from server is nonce-only.
//              CallKit displays "SnowChat Call" anonymous. After accept, Dart
//              foregrounds + fetches the real envelope via socket.
//
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-29
// @lastUpdated 2026-04-29
//

import Foundation
import PushKit
import UIKit
import flutter_callkit_incoming

@objc class VoipPushBridge: NSObject, PKPushRegistryDelegate {

    private var registry: PKPushRegistry?

    /// Dedicated serial queue for PKPushRegistry callbacks (Signal pattern,
    /// `org.signal.push-registration`). iOS 15+ has been observed to silently
    /// drop voip pushes when the registry is bound to `.main` — reports across
    /// Signal-iOS, Apple Forum thread/690569, and react-native-callkeep #148.
    /// Plugin calls (showCallkitIncoming) are dispatched back to main inside
    /// the delegate body since CallKit / CXProvider must run on main.
    private static let pushKitQueue = DispatchQueue(label: "com.calidalab.snowchat.pushkit")

    @objc public func start() {
        let registry = PKPushRegistry(queue: VoipPushBridge.pushKitQueue)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
        NSLog("[VoipPushBridge] PKPushRegistry started (queue=com.calidalab.snowchat.pushkit)")

        // Diagnostic: poll for an existing token (set on a previous launch).
        // PKPushRegistry can return the cached token here even before
        // didUpdate fires for the new session. Helpful to distinguish
        // "never registered" from "registered but didUpdate not fired yet".
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if let cred = self.registry?.pushToken(for: .voIP) {
                let hex = cred.map { String(format: "%02x", $0) }.joined()
                NSLog("[VoipPushBridge] poll(5s): cached voIP token len=\(hex.count) — pushing to plugin")
                SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(hex)
            } else {
                NSLog("[VoipPushBridge] poll(5s): no cached voIP token (registry didn't deliver yet)")
            }
        }
    }

    // MARK: PKPushRegistryDelegate

    /// PushKit token published — forward to plugin so Dart side uploads to server.
    public func pushRegistry(_ registry: PKPushRegistry,
                             didUpdate pushCredentials: PKPushCredentials,
                             for type: PKPushType) {
        NSLog("[VoipPushBridge] didUpdate FIRED (type=\(type.rawValue))")
        guard type == .voIP else { return }
        let tokenHex = pushCredentials.token
            .map { String(format: "%02x", $0) }
            .joined()
        NSLog("[VoipPushBridge] didUpdate voIP token len=\(tokenHex.count)")
        // The plugin stores the token + emits ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP
        // event on Dart side, which we listen to in voip_push_service.dart and
        // POST /devices/:deviceId/voip-token.
        if SwiftFlutterCallkitIncomingPlugin.sharedInstance == nil {
            NSLog("[VoipPushBridge] WARN: plugin sharedInstance nil — token will not reach Dart")
        }
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(tokenHex)
    }

    public func pushRegistry(_ registry: PKPushRegistry,
                             didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        NSLog("[VoipPushBridge] PushKit token invalidated")
        // Tell Dart so it can clear the server-side voipPushToken (best-effort).
        SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
    }

    /// Incoming VoIP push. iOS gives us ~5s in the same run loop to call
    /// reportNewIncomingCall, otherwise callservicesd silently throttles us.
    /// Apple Forum thread/758973: repeated misses → "VoIP push for app dropped
    /// on the floor" until reinstall / reboot / 24h cool-down.
    public func pushRegistry(_ registry: PKPushRegistry,
                             didReceiveIncomingPushWith payload: PKPushPayload,
                             for type: PKPushType,
                             completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }

        // Server payload (Zero-Knowledge): { type:"incoming_call", nonce, expiresAt }
        let dict = payload.dictionaryPayload
        let nonce = dict["nonce"] as? String ?? UUID().uuidString
        NSLog("[VoipPushBridge] didReceive nonce=\(nonce.prefix(8))…")

        // Build the plugin's expected NSDictionary. Anonymous display per §2.6.1
        // ("SnowChat Call" / handle:""). Real caller name resolves after accept
        // when Flutter foregrounds and fetches the envelope.
        // iconName intentionally OMITTED — `Unable to load icon` warning during
        // the deadline window slows the cold-launch path. CallKit falls back
        // to default icon, which is fine for nonce-only display.
        let params: [String: Any] = [
            "id": nonce,
            "nameCaller": "SnowChat Call",
            "appName": "SnowChat",
            "handle": "",
            "type": 0, // 0 = audio
            "duration": 60000,
            "textAccept": "Accept",
            "textDecline": "Decline",
            "missedCallNotification": [
                "showNotification": false,
                "isShowCallback": false,
                "subtitle": ""
            ],
            "ios": [
                "handleType": "generic",
                "supportsVideo": false,
                "maximumCallGroups": 1,
                "maximumCallsPerCallGroup": 1,
                "audioSessionMode": "voiceChat",
                "audioSessionActive": true,
                "audioSessionPreferredSampleRate": 44100.0,
                "audioSessionPreferredIOBufferDuration": 0.005,
                "supportsDTMF": false,
                "supportsHolding": false,
                "supportsGrouping": false,
                "supportsUngrouping": false,
                "ringtonePath": "system_ringtone_default"
            ]
        ]

        // CallKit / CXProvider must run on the main thread. We're on the
        // dedicated pushKitQueue here, so dispatch synchronously to main and
        // hold the PushKit completion until showCallkitIncoming returns.
        // `sync` (not `async`) keeps us inside the same run-loop window iOS
        // measures, so reportNewIncomingCall fires within the deadline.
        DispatchQueue.main.sync {
            let data = flutter_callkit_incoming.Data(args: params as NSDictionary)
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)
        }
        completion()
    }
}
