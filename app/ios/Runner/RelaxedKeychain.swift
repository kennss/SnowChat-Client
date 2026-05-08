//
// @file        RelaxedKeychain.swift
// @description MethodChannel `snowchat/keychain_relaxed` — write/read/delete
//              for the *relaxed* keychain accessibility class
//              kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly. Routed from
//              Dart for the small set of keys that VoipPushBridge / CallAccept
//              Coordinator need to read after a CallKit accept while the
//              device may still be in a Before-First-Unlock-style state
//              (post-restart) or in the foreground but with the Flutter
//              engine not yet booted.
//
//              Relaxed keys (3): auth_token, auth_refresh_token, device_id.
//              Anything else MUST stay on flutter_secure_storage's default
//              accessibility (WhenUnlockedThisDeviceOnly). Writing through
//              this channel forces a delete-then-add cycle so a stale
//              flutter_secure_storage entry under a stricter class is
//              displaced (otherwise SecItemAdd returns errSecDuplicateItem
//              and the write is a no-op — the symptom we hit on first ship).
//
//              Same kSecAttrService as flutter_secure_storage so reads
//              round-trip correctly via SecureStorageReader.
//
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-30
// @lastUpdated 2026-04-30
//
// @functions
//  - register(messenger): attach the MethodChannel + handler
//  - handle(call, result): dispatch read|write|delete
//  - write(key, value): SecItemDelete + SecItemAdd with AfterFirstUnlockThisDeviceOnly
//  - read(key): forwards to SecureStorageReader.read
//  - delete(key): SecItemDelete
//

import Foundation
import Flutter
import Security

@objc final class RelaxedKeychain: NSObject {

    private static let service = "flutter_secure_storage_service"
    private static var channel: FlutterMethodChannel?

    @objc public static func register(with messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(
            name: "snowchat/keychain_relaxed",
            binaryMessenger: messenger
        )
        ch.setMethodCallHandler { call, result in
            RelaxedKeychain.handle(call: call, result: result)
        }
        channel = ch
    }

    private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String, !key.isEmpty else {
            result(FlutterError(code: "BAD_ARG", message: "key missing", details: nil))
            return
        }
        switch call.method {
        case "read":
            result(SecureStorageReader.read(key: key))
        case "write":
            guard let value = args["value"] as? String else {
                result(FlutterError(code: "BAD_ARG", message: "value missing", details: nil))
                return
            }
            write(key: key, value: value)
            result(nil)
        case "delete":
            delete(key: key)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func write(key: String, value: String) {
        // Force delete-then-add so a pre-existing entry under a different
        // accessibility class doesn't make SecItemAdd a no-op.
        let baseQuery: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var add = baseQuery
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecValueData as String] = value.data(using: .utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[RelaxedKeychain] write failed status=\(status) key=\(key)")
        }
    }

    private static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
