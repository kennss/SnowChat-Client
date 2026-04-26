//
// @file        SignalStore.swift
// @description Signal Protocol 상태 저장소 (Identity, PreKey, SignedPreKey, Session, SenderKey) 및 파일 기반 영속성 관리
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-03-29
// @lastUpdated 2026-03-29
//
// @functions
//  - StoredKeyData: 키 데이터의 Codable 래퍼 구조체
//  - StoredSessionData: 세션 데이터의 Codable 래퍼 구조체
//  - StoredSenderKeyData: Sender Key 데이터의 Codable 래퍼 구조체
//  - InMemorySignalIdentityKeyStore: 로컬 Identity Key Pair 및 신뢰된 원격 Identity Key 저장소
//  - InMemorySignalPreKeyStore: One-Time Pre Key 저장소
//  - InMemorySignalSignedPreKeyStore: Signed Pre Key 저장소
//  - InMemorySignalSessionStore: Double Ratchet 세션 상태 저장소
//  - InMemorySignalSenderKeyStore: 그룹 메시징용 Sender Key 저장소
//  - SignalStoreManager: 모든 Signal 프로토콜 스토어 통합 관리 및 파일 영속성 제공
//

import Foundation
// TODO: Uncomment when LibSignalClient SPM package is added to the Xcode project
// import LibSignalClient

// MARK: - In-Memory + File-Backed Signal Protocol Stores
// These stores hold cryptographic state for the Signal Protocol.
// Data is persisted to the app's Documents directory with iOS Data Protection (NSFileProtectionCompleteUntilFirstUserAuthentication).

// MARK: - Serialization Helpers

/// Wraps raw key/session data for Codable persistence.
struct StoredKeyData: Codable {
    let id: UInt32
    let data: Data
    let timestamp: UInt64?
}

struct StoredSessionData: Codable {
    let address: String  // "recipientId:deviceId"
    let data: Data
}

struct StoredSenderKeyData: Codable {
    let groupId: String
    let senderId: String
    let deviceId: UInt32
    let data: Data
}

// MARK: - InMemorySignalIdentityKeyStore

/// Stores the local identity key pair and trusted remote identity keys.
class InMemorySignalIdentityKeyStore {
    private(set) var identityKeyPairData: Data?
    private(set) var localRegistrationId: UInt32
    private var trustedIdentities: [String: Data] = [:]  // address -> identityKeyPublic

    init(registrationId: UInt32 = 0) {
        self.localRegistrationId = registrationId
    }

    func setIdentityKeyPair(_ data: Data) {
        self.identityKeyPairData = data
    }

    func setLocalRegistrationId(_ id: UInt32) {
        self.localRegistrationId = id
    }

    func isTrustedIdentity(address: String, identityKey: Data) -> Bool {
        guard let existing = trustedIdentities[address] else {
            // First time seeing this identity -- trust on first use (TOFU)
            return true
        }
        return existing == identityKey
    }

    func saveIdentity(address: String, identityKey: Data) -> Bool {
        let existed = trustedIdentities[address] != nil
        trustedIdentities[address] = identityKey
        return existed  // true if we replaced an existing key
    }

    func getIdentity(address: String) -> Data? {
        return trustedIdentities[address]
    }

    func removeIdentity(address: String) {
        trustedIdentities.removeValue(forKey: address)
    }
}

// MARK: - InMemorySignalPreKeyStore

/// Stores one-time pre keys (OPKs).
class InMemorySignalPreKeyStore {
    private var preKeys: [UInt32: Data] = [:]

    func loadPreKey(id: UInt32) -> Data? {
        return preKeys[id]
    }

    func storePreKey(id: UInt32, record: Data) {
        preKeys[id] = record
    }

    func removePreKey(id: UInt32) {
        preKeys.removeValue(forKey: id)
    }

    func containsPreKey(id: UInt32) -> Bool {
        return preKeys[id] != nil
    }

    func allPreKeys() -> [UInt32: Data] {
        return preKeys
    }
}

// MARK: - InMemorySignalSignedPreKeyStore

/// Stores signed pre keys (SPKs).
class InMemorySignalSignedPreKeyStore {
    private var signedPreKeys: [UInt32: Data] = [:]

    func loadSignedPreKey(id: UInt32) -> Data? {
        return signedPreKeys[id]
    }

    func storeSignedPreKey(id: UInt32, record: Data) {
        signedPreKeys[id] = record
    }

    func removeSignedPreKey(id: UInt32) {
        signedPreKeys.removeValue(forKey: id)
    }

    func containsSignedPreKey(id: UInt32) -> Bool {
        return signedPreKeys[id] != nil
    }

    func allSignedPreKeys() -> [UInt32: Data] {
        return signedPreKeys
    }
}

// MARK: - InMemorySignalSessionStore

/// Stores Double Ratchet session state per recipient+device.
class InMemorySignalSessionStore {
    private var sessions: [String: Data] = [:]  // "recipientId:deviceId" -> session data

    private func key(recipientId: String, deviceId: UInt32) -> String {
        return "\(recipientId):\(deviceId)"
    }

    func loadSession(recipientId: String, deviceId: UInt32) -> Data? {
        return sessions[key(recipientId: recipientId, deviceId: deviceId)]
    }

    func storeSession(recipientId: String, deviceId: UInt32, record: Data) {
        sessions[key(recipientId: recipientId, deviceId: deviceId)] = record
    }

    func containsSession(recipientId: String, deviceId: UInt32) -> Bool {
        return sessions[key(recipientId: recipientId, deviceId: deviceId)] != nil
    }

    func deleteSession(recipientId: String, deviceId: UInt32) {
        sessions.removeValue(forKey: key(recipientId: recipientId, deviceId: deviceId))
    }

    func deleteAllSessions(recipientId: String) {
        sessions = sessions.filter { !$0.key.hasPrefix("\(recipientId):") }
    }

    func allSessions() -> [String: Data] {
        return sessions
    }
}

// MARK: - InMemorySignalSenderKeyStore

/// Stores Sender Keys for group messaging.
class InMemorySignalSenderKeyStore {
    // Key: "groupId:senderId:deviceId"
    private var senderKeys: [String: Data] = [:]

    private func key(groupId: String, senderId: String, deviceId: UInt32) -> String {
        return "\(groupId):\(senderId):\(deviceId)"
    }

    func storeSenderKey(groupId: String, senderId: String, deviceId: UInt32, record: Data) {
        senderKeys[key(groupId: groupId, senderId: senderId, deviceId: deviceId)] = record
    }

    func loadSenderKey(groupId: String, senderId: String, deviceId: UInt32) -> Data? {
        return senderKeys[key(groupId: groupId, senderId: senderId, deviceId: deviceId)]
    }

    func removeSenderKey(groupId: String, senderId: String, deviceId: UInt32) {
        senderKeys.removeValue(forKey: key(groupId: groupId, senderId: senderId, deviceId: deviceId))
    }

    func allSenderKeys() -> [String: Data] {
        return senderKeys
    }
}

// MARK: - SignalStoreManager

/// Manages all Signal protocol stores and provides file-backed persistence.
/// Data is stored in the app's Documents directory with iOS Data Protection enabled.
class SignalStoreManager {
    let identityStore: InMemorySignalIdentityKeyStore
    let preKeyStore: InMemorySignalPreKeyStore
    let signedPreKeyStore: InMemorySignalSignedPreKeyStore
    let sessionStore: InMemorySignalSessionStore
    let senderKeyStore: InMemorySignalSenderKeyStore

    init() {
        self.identityStore = InMemorySignalIdentityKeyStore()
        self.preKeyStore = InMemorySignalPreKeyStore()
        self.signedPreKeyStore = InMemorySignalSignedPreKeyStore()
        self.sessionStore = InMemorySignalSessionStore()
        self.senderKeyStore = InMemorySignalSenderKeyStore()
    }

    // MARK: - Persistence

    /// Serializes all store state to a file at the given path.
    func save(to path: String) throws {
        let state = PersistedState(
            identityKeyPairData: identityStore.identityKeyPairData,
            localRegistrationId: identityStore.localRegistrationId,
            preKeys: preKeyStore.allPreKeys().map { StoredKeyData(id: $0.key, data: $0.value, timestamp: nil) },
            signedPreKeys: signedPreKeyStore.allSignedPreKeys().map { StoredKeyData(id: $0.key, data: $0.value, timestamp: nil) },
            sessions: sessionStore.allSessions().map { StoredSessionData(address: $0.key, data: $0.value) },
            senderKeys: senderKeyStore.allSenderKeys().map {
                let parts = $0.key.components(separatedBy: ":")
                return StoredSenderKeyData(
                    groupId: parts.count > 0 ? parts[0] : "",
                    senderId: parts.count > 1 ? parts[1] : "",
                    deviceId: parts.count > 2 ? UInt32(parts[2]) ?? 0 : 0,
                    data: $0.value
                )
            }
        )

        let data = try JSONEncoder().encode(state)

        let url = URL(fileURLWithPath: path)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Restores all store state from a file at the given path.
    func load(from path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder().decode(PersistedState.self, from: data)

        // Restore identity store
        if let ikpData = state.identityKeyPairData {
            identityStore.setIdentityKeyPair(ikpData)
        }
        identityStore.setLocalRegistrationId(state.localRegistrationId)

        // Restore pre keys
        for pk in state.preKeys {
            preKeyStore.storePreKey(id: pk.id, record: pk.data)
        }

        // Restore signed pre keys
        for spk in state.signedPreKeys {
            signedPreKeyStore.storeSignedPreKey(id: spk.id, record: spk.data)
        }

        // Restore sessions
        for session in state.sessions {
            let parts = session.address.components(separatedBy: ":")
            if parts.count >= 2, let deviceId = UInt32(parts[1]) {
                sessionStore.storeSession(recipientId: parts[0], deviceId: deviceId, record: session.data)
            }
        }

        // Restore sender keys
        for sk in state.senderKeys {
            senderKeyStore.storeSenderKey(
                groupId: sk.groupId,
                senderId: sk.senderId,
                deviceId: sk.deviceId,
                record: sk.data
            )
        }
    }
}

// MARK: - Persisted State (Codable)

private struct PersistedState: Codable {
    let identityKeyPairData: Data?
    let localRegistrationId: UInt32
    let preKeys: [StoredKeyData]
    let signedPreKeys: [StoredKeyData]
    let sessions: [StoredSessionData]
    let senderKeys: [StoredSenderKeyData]
}
