//
// @file        SecureStorageReader.swift
// @description Read flutter_secure_storage values from native code, matching
//              the exact schema the plugin uses on iOS so the Dart-side
//              `SecureStorageService.write('auth_token', ...)` value can be
//              read back here. Used by CallAcceptCoordinator to authenticate
//              the /calls/pending fetch in the post-CallKit-accept window
//              while the Flutter engine may still be cold.
//
//              flutter_secure_storage iOS schema (verified against the
//              package source rev 9.x): the plugin stores all entries in
//              kSecClassGenericPassword keychain items with:
//                kSecAttrAccount = <user-supplied key>
//                kSecAttrService = "flutter_secure_storage_service"
//                kSecValueData   = <UTF-8 string bytes>
//              + kSecAttrAccessible from IOSOptions. SnowChat config:
//                accessibility: KeychainAccessibility.first_unlock_this_device
//                              (=> kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
//              for the relaxed key set (auth_token, auth_refresh_token,
//              device_id) per RelaxedKeychain.swift; everything else is
//              KeychainAccessibility.unlocked_this_device. We attempt the
//              relaxed query first, fall back to unlocked, and finally to
//              the no-accessibility query (which matches any).
//
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-30
// @lastUpdated 2026-04-30
//
// @functions
//  - read(key): SecItemCopyMatching with multi-accessibility fallback. Returns nil on miss.
//

import Foundation
import Security

@objc final class SecureStorageReader: NSObject {

    /// flutter_secure_storage's kSecAttrService default on iOS.
    private static let service = "flutter_secure_storage_service"

    @objc public static func read(key: String) -> String? {
        // Try AfterFirstUnlockThisDeviceOnly first (relaxed keys: auth_token /
        // auth_refresh_token / device_id), then WhenUnlockedThisDeviceOnly, then
        // unconstrained. We can't issue a single query with no accessibility —
        // SecItemCopyMatching returns the first match across accessibility
        // classes anyway, but on some iOS versions a strict-class query
        // out-prioritizes a strict match, so the explicit cascade is safer.
        let candidates: [CFString] = [
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        for accessibility in candidates {
            if let value = readWith(key: key, accessibility: accessibility) {
                return value
            }
        }
        // Final fallback — no accessibility constraint (matches any class
        // currently unlocked).
        return readWith(key: key, accessibility: nil)
    }

    private static func readWith(key: String, accessibility: CFString?) -> String? {
        var query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     key,
            kSecMatchLimit as String:      kSecMatchLimitOne,
            kSecReturnData as String:      true,
        ]
        if let accessibility = accessibility {
            query[kSecAttrAccessible as String] = accessibility
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
