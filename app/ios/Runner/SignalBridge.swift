//
// @file        SignalBridge.swift
// @description Flutter MethodChannel을 통한 Signal Protocol 연산 처리 브릿지 (키 생성, 세션 관리, 1:1/그룹 암호화)
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-03-29
// @lastUpdated 2026-03-29
//
// @functions
//  - SignalBridge.register(with:): MethodChannel 등록 및 브릿지 인스턴스 반환
//  - handle(call:result:): MethodChannel 호출 라우팅
//  - handleGenerateIdentityKeyPair(result:): Identity Key Pair 생성
//  - handleGenerateSignedPreKey(keyId:result:): Signed Pre Key 생성
//  - handleGenerateOneTimePreKeys(startId:count:result:): One-Time Pre Key 배치 생성
//  - handleGetPreKeyBundle(result:): Pre Key Bundle 조회
//  - handleCreateSession(recipientId:deviceId:preKeyBundle:result:): X3DH 세션 생성
//  - handleHasSession(recipientId:deviceId:result:): 세션 존재 여부 확인
//  - handleDeleteSession(recipientId:deviceId:result:): 세션 삭제
//  - handleEncryptMessage(recipientId:deviceId:plaintextBase64:result:): 1:1 메시지 암호화
//  - handleDecryptMessage(senderId:deviceId:ciphertextBase64:messageType:result:): 1:1 메시지 복호화
//  - handleCreateSenderKey(groupId:result:): 그룹 Sender Key 생성
//  - handleProcessSenderKey(groupId:senderId:senderKeyMessageBase64:result:): 그룹 Sender Key 처리
//  - handleEncryptGroupMessage(groupId:plaintextBase64:result:): 그룹 메시지 암호화
//  - handleDecryptGroupMessage(groupId:senderId:ciphertextBase64:result:): 그룹 메시지 복호화
//  - handleSaveSessionStore(path:result:): 세션 스토어 파일 저장
//  - handleLoadSessionStore(path:result:): 세션 스토어 파일 로드
//  - Data.hexString: Data를 hex 문자열로 변환
//  - Data.init(hex:): hex 문자열에서 Data 초기화
//

import Flutter
import Foundation
// TODO: Uncomment when LibSignalClient SPM package is added to the Xcode project
// import LibSignalClient

/// SignalBridge handles MethodChannel calls from Flutter for Signal Protocol operations.
///
/// Channel name: "com.snowchat/signal"
///
/// Current status: STUB implementation using CommonCrypto for development.
/// When libsignal-client is integrated via SPM, replace stub calls with real
/// LibSignalClient API calls (marked with TODO comments).
class SignalBridge: NSObject {
    static let channelName = "com.snowchat/signal"

    private let storeManager = SignalStoreManager()

    // Local identity state (generated or loaded)
    private var localIdentityPublicKey: Data?
    private var localIdentityPrivateKey: Data?
    private var localRegistrationId: UInt32 = 0

    // MARK: - Channel Registration

    /// Call this from AppDelegate to register the MethodChannel.
    static func register(with messenger: FlutterBinaryMessenger) -> SignalBridge {
        let bridge = SignalBridge()
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        channel.setMethodCallHandler { (call, result) in
            bridge.handle(call: call, result: result)
        }

        return bridge
    }

    // MARK: - Method Router

    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        switch call.method {

        // --- Key Generation ---
        case "generateIdentityKeyPair":
            handleGenerateIdentityKeyPair(result: result)

        case "generateSignedPreKey":
            guard let keyId = args?["keyId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "keyId required", details: nil))
                return
            }
            handleGenerateSignedPreKey(keyId: UInt32(keyId), result: result)

        case "generateOneTimePreKeys":
            guard let startId = args?["startId"] as? Int,
                  let count = args?["count"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "startId and count required", details: nil))
                return
            }
            handleGenerateOneTimePreKeys(startId: UInt32(startId), count: count, result: result)

        case "getPreKeyBundle":
            handleGetPreKeyBundle(result: result)

        // --- Session Management ---
        case "createSession":
            guard let recipientId = args?["recipientId"] as? String,
                  let deviceId = args?["deviceId"] as? Int,
                  let preKeyBundle = args?["preKeyBundle"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "recipientId, deviceId, preKeyBundle required", details: nil))
                return
            }
            handleCreateSession(recipientId: recipientId, deviceId: UInt32(deviceId), preKeyBundle: preKeyBundle, result: result)

        case "hasSession":
            guard let recipientId = args?["recipientId"] as? String,
                  let deviceId = args?["deviceId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "recipientId and deviceId required", details: nil))
                return
            }
            handleHasSession(recipientId: recipientId, deviceId: UInt32(deviceId), result: result)

        case "deleteSession":
            guard let recipientId = args?["recipientId"] as? String,
                  let deviceId = args?["deviceId"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "recipientId and deviceId required", details: nil))
                return
            }
            handleDeleteSession(recipientId: recipientId, deviceId: UInt32(deviceId), result: result)

        // --- 1:1 Message Encryption ---
        case "encryptMessage":
            guard let recipientId = args?["recipientId"] as? String,
                  let deviceId = args?["deviceId"] as? Int,
                  let plaintext = args?["plaintext"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "recipientId, deviceId, plaintext required", details: nil))
                return
            }
            handleEncryptMessage(recipientId: recipientId, deviceId: UInt32(deviceId), plaintextBase64: plaintext, result: result)

        case "decryptMessage":
            guard let senderId = args?["senderId"] as? String,
                  let deviceId = args?["deviceId"] as? Int,
                  let ciphertext = args?["ciphertext"] as? String,
                  let messageType = args?["messageType"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "senderId, deviceId, ciphertext, messageType required", details: nil))
                return
            }
            handleDecryptMessage(senderId: senderId, deviceId: UInt32(deviceId), ciphertextBase64: ciphertext, messageType: messageType, result: result)

        // --- Group (Sender Key) ---
        case "createSenderKey":
            guard let groupId = args?["groupId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "groupId required", details: nil))
                return
            }
            handleCreateSenderKey(groupId: groupId, result: result)

        case "processSenderKey":
            guard let groupId = args?["groupId"] as? String,
                  let senderId = args?["senderId"] as? String,
                  let senderKeyMessage = args?["senderKeyMessage"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "groupId, senderId, senderKeyMessage required", details: nil))
                return
            }
            handleProcessSenderKey(groupId: groupId, senderId: senderId, senderKeyMessageBase64: senderKeyMessage, result: result)

        case "encryptGroupMessage":
            guard let groupId = args?["groupId"] as? String,
                  let plaintext = args?["plaintext"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "groupId and plaintext required", details: nil))
                return
            }
            handleEncryptGroupMessage(groupId: groupId, plaintextBase64: plaintext, result: result)

        case "decryptGroupMessage":
            guard let groupId = args?["groupId"] as? String,
                  let senderId = args?["senderId"] as? String,
                  let ciphertext = args?["ciphertext"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "groupId, senderId, ciphertext required", details: nil))
                return
            }
            handleDecryptGroupMessage(groupId: groupId, senderId: senderId, ciphertextBase64: ciphertext, result: result)

        // --- Persistence ---
        case "saveSessionStore":
            guard let path = args?["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "path required", details: nil))
                return
            }
            handleSaveSessionStore(path: path, result: result)

        case "loadSessionStore":
            guard let path = args?["path"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "path required", details: nil))
                return
            }
            handleLoadSessionStore(path: path, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Key Generation

    private func handleGenerateIdentityKeyPair(result: @escaping FlutterResult) {
        // TODO: Replace with LibSignalClient:
        //   let identityKeyPair = IdentityKeyPair.generate()
        //   let publicKey = identityKeyPair.publicKey.serialize()
        //   let privateKey = identityKeyPair.privateKey.serialize()

        // STUB: Generate random 32-byte keys for development
        let privateKey = generateRandomBytes(count: 32)
        let publicKey = generateRandomBytes(count: 32)

        guard let privateKey = privateKey, let publicKey = publicKey else {
            result(FlutterError(code: "KEYGEN_FAILED", message: "Failed to generate random bytes", details: nil))
            return
        }

        self.localIdentityPrivateKey = privateKey
        self.localIdentityPublicKey = publicKey
        self.localRegistrationId = UInt32.random(in: 1...0x3FFF)

        // Store in identity store
        // For real impl, this would be the serialized IdentityKeyPair
        storeManager.identityStore.setIdentityKeyPair(privateKey + publicKey)
        storeManager.identityStore.setLocalRegistrationId(self.localRegistrationId)

        result([
            "publicKey": publicKey.hexString,
            "privateKey": privateKey.hexString,
            "registrationId": Int(self.localRegistrationId)
        ])
    }

    private func handleGenerateSignedPreKey(keyId: UInt32, result: @escaping FlutterResult) {
        // TODO: Replace with LibSignalClient:
        //   guard let identityKeyPair = ... else { error }
        //   let signedPreKey = PrivateKey.generate()
        //   let signedPreKeyPublic = signedPreKey.publicKey
        //   let signature = identityKeyPair.privateKey.generateSignature(message: signedPreKeyPublic.serialize())
        //   let record = SignedPreKeyRecord(
        //       id: keyId,
        //       timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
        //       privateKey: signedPreKey,
        //       signature: signature
        //   )
        //   signedPreKeyStore.storeSignedPreKey(record, id: keyId, context: NullContext())

        // STUB: Generate random key data
        let privateKey = generateRandomBytes(count: 32)
        let publicKey = generateRandomBytes(count: 32)
        let signature = generateRandomBytes(count: 64)

        guard let privateKey = privateKey, let publicKey = publicKey, let signature = signature else {
            result(FlutterError(code: "KEYGEN_FAILED", message: "Failed to generate signed pre key", details: nil))
            return
        }

        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)

        // Store the signed pre key record
        let recordData = privateKey + publicKey  // Simplified; real impl uses SignedPreKeyRecord.serialize()
        storeManager.signedPreKeyStore.storeSignedPreKey(id: keyId, record: recordData)

        result([
            "keyId": Int(keyId),
            "publicKey": publicKey.hexString,
            "signature": signature.hexString,
            "timestamp": Int(timestamp)
        ])
    }

    private func handleGenerateOneTimePreKeys(startId: UInt32, count: Int, result: @escaping FlutterResult) {
        // TODO: Replace with LibSignalClient:
        //   var preKeys: [[String: Any]] = []
        //   for i in 0..<count {
        //       let id = startId + UInt32(i)
        //       let preKey = PrivateKey.generate()
        //       let record = PreKeyRecord(id: id, publicKey: preKey.publicKey, privateKey: preKey)
        //       preKeyStore.storePreKey(record, id: id, context: NullContext())
        //       preKeys.append(["keyId": Int(id), "publicKey": preKey.publicKey.serialize().hexString])
        //   }

        // STUB: Generate random keys
        var preKeys: [[String: Any]] = []

        for i in 0..<count {
            let id = startId + UInt32(i)
            let privateKey = generateRandomBytes(count: 32)
            let publicKey = generateRandomBytes(count: 32)

            guard let privateKey = privateKey, let publicKey = publicKey else {
                result(FlutterError(code: "KEYGEN_FAILED", message: "Failed to generate one-time pre key \(id)", details: nil))
                return
            }

            let recordData = privateKey + publicKey
            storeManager.preKeyStore.storePreKey(id: id, record: recordData)

            preKeys.append([
                "keyId": Int(id),
                "publicKey": publicKey.hexString
            ])
        }

        result(preKeys)
    }

    private func handleGetPreKeyBundle(result: @escaping FlutterResult) {
        guard let publicKey = localIdentityPublicKey else {
            result(FlutterError(code: "NO_IDENTITY", message: "Identity key pair not generated. Call generateIdentityKeyPair first.", details: nil))
            return
        }

        // Collect the latest signed pre key and some one-time pre keys
        let signedPreKeys = storeManager.signedPreKeyStore.allSignedPreKeys()
        let preKeys = storeManager.preKeyStore.allPreKeys()

        // Use the first signed pre key found (in real impl, use the latest)
        var signedPreKeyInfo: [String: Any]?
        if let firstSPK = signedPreKeys.first {
            signedPreKeyInfo = [
                "keyId": Int(firstSPK.key),
                "publicKey": firstSPK.value.suffix(32).hexString,  // Stub: last 32 bytes as "public"
                "signature": generateRandomBytes(count: 64)?.hexString ?? ""
            ]
        }

        var oneTimePreKeys: [[String: Any]] = []
        for (keyId, data) in preKeys {
            oneTimePreKeys.append([
                "keyId": Int(keyId),
                "publicKey": data.suffix(32).hexString
            ])
        }

        result([
            "identityKey": publicKey.hexString,
            "registrationId": Int(localRegistrationId),
            "signedPreKey": signedPreKeyInfo as Any,
            "oneTimePreKeys": oneTimePreKeys
        ])
    }

    // MARK: - Session Management

    private func handleCreateSession(recipientId: String, deviceId: UInt32, preKeyBundle: [String: Any], result: @escaping FlutterResult) {
        // TODO: Replace with LibSignalClient:
        //   let remoteIdentityKey = try IdentityKey(bytes: Data(hex: preKeyBundle["identityKey"]))
        //   let remoteRegistrationId = preKeyBundle["registrationId"] as! UInt32
        //   let signedPreKeyPublic = try PublicKey(preKeyBundle["signedPreKey"]["publicKey"])
        //   let signedPreKeySignature = Data(hex: preKeyBundle["signedPreKey"]["signature"])
        //   let signedPreKeyId = preKeyBundle["signedPreKey"]["keyId"] as! UInt32
        //   let preKeyPublic = try PublicKey(preKeyBundle["oneTimePreKey"]["publicKey"])  // optional
        //   let preKeyId = preKeyBundle["oneTimePreKey"]["keyId"] as! UInt32  // optional
        //
        //   let bundle = try PreKeyBundle(
        //       registrationId: remoteRegistrationId,
        //       deviceId: deviceId,
        //       prekeyId: preKeyId,
        //       prekey: preKeyPublic,
        //       signedPrekeyId: signedPreKeyId,
        //       signedPrekey: signedPreKeyPublic,
        //       signedPrekeySignature: signedPreKeySignature,
        //       identity: remoteIdentityKey
        //   )
        //
        //   let remoteAddress = try ProtocolAddress(name: recipientId, deviceId: deviceId)
        //   try processPreKeyBundle(
        //       bundle,
        //       for: remoteAddress,
        //       sessionStore: sessionStore,
        //       identityStore: identityStore,
        //       context: NullContext()
        //   )

        // STUB: Create a placeholder session
        let sessionData = generateRandomBytes(count: 64) ?? Data()
        storeManager.sessionStore.storeSession(recipientId: recipientId, deviceId: deviceId, record: sessionData)

        // Save remote identity
        if let identityKeyHex = preKeyBundle["identityKey"] as? String,
           let identityKeyData = Data(hex: identityKeyHex) {
            _ = storeManager.identityStore.saveIdentity(address: "\(recipientId):\(deviceId)", identityKey: identityKeyData)
        }

        result([
            "success": true,
            "recipientId": recipientId,
            "deviceId": Int(deviceId)
        ])
    }

    private func handleHasSession(recipientId: String, deviceId: UInt32, result: @escaping FlutterResult) {
        let exists = storeManager.sessionStore.containsSession(recipientId: recipientId, deviceId: deviceId)
        result(exists)
    }

    private func handleDeleteSession(recipientId: String, deviceId: UInt32, result: @escaping FlutterResult) {
        storeManager.sessionStore.deleteSession(recipientId: recipientId, deviceId: deviceId)
        result(nil)
    }

    // MARK: - 1:1 Message Encryption/Decryption

    /// Message types matching Signal Protocol:
    /// 2 = PreKeySignalMessage (initial message with X3DH info)
    /// 3 = SignalMessage (regular ratchet message)
    private static let messageTypePreKey = 2
    private static let messageTypeSignal = 3

    private func handleEncryptMessage(recipientId: String, deviceId: UInt32, plaintextBase64: String, result: @escaping FlutterResult) {
        guard let plaintextData = Data(base64Encoded: plaintextBase64) else {
            result(FlutterError(code: "INVALID_DATA", message: "plaintext must be valid base64", details: nil))
            return
        }

        guard storeManager.sessionStore.containsSession(recipientId: recipientId, deviceId: deviceId) else {
            result(FlutterError(code: "NO_SESSION", message: "No session for \(recipientId):\(deviceId). Call createSession first.", details: nil))
            return
        }

        // TODO: Replace with LibSignalClient:
        //   let remoteAddress = try ProtocolAddress(name: recipientId, deviceId: deviceId)
        //   let ciphertext = try signalEncrypt(
        //       message: plaintextData,
        //       for: remoteAddress,
        //       sessionStore: sessionStore,
        //       identityStore: identityStore,
        //       context: NullContext()
        //   )
        //   let messageType = ciphertext.messageType == .preKey ? 2 : 3
        //   let ciphertextBase64 = ciphertext.serialize().base64EncodedString()

        // STUB: XOR with a session-derived "key" for development testing
        let stubKey = storeManager.sessionStore.loadSession(recipientId: recipientId, deviceId: deviceId) ?? Data(repeating: 0x42, count: 32)
        let ciphertextData = xorEncrypt(data: plaintextData, key: stubKey)
        let messageType = SignalBridge.messageTypeSignal

        result([
            "ciphertext": ciphertextData.base64EncodedString(),
            "messageType": messageType
        ])
    }

    private func handleDecryptMessage(senderId: String, deviceId: UInt32, ciphertextBase64: String, messageType: Int, result: @escaping FlutterResult) {
        guard let ciphertextData = Data(base64Encoded: ciphertextBase64) else {
            result(FlutterError(code: "INVALID_DATA", message: "ciphertext must be valid base64", details: nil))
            return
        }

        guard storeManager.sessionStore.containsSession(recipientId: senderId, deviceId: deviceId) else {
            result(FlutterError(code: "NO_SESSION", message: "No session for \(senderId):\(deviceId)", details: nil))
            return
        }

        // TODO: Replace with LibSignalClient:
        //   let remoteAddress = try ProtocolAddress(name: senderId, deviceId: deviceId)
        //   let plaintext: Data
        //   if messageType == SignalBridge.messageTypePreKey {
        //       let preKeyMessage = try PreKeySignalMessage(bytes: ciphertextData)
        //       plaintext = Data(try signalDecryptPreKey(
        //           message: preKeyMessage,
        //           from: remoteAddress,
        //           sessionStore: sessionStore,
        //           identityStore: identityStore,
        //           preKeyStore: preKeyStore,
        //           signedPreKeyStore: signedPreKeyStore,
        //           context: NullContext()
        //       ))
        //   } else {
        //       let signalMessage = try SignalMessage(bytes: ciphertextData)
        //       plaintext = Data(try signalDecrypt(
        //           message: signalMessage,
        //           from: remoteAddress,
        //           sessionStore: sessionStore,
        //           identityStore: identityStore,
        //           context: NullContext()
        //       ))
        //   }

        // STUB: XOR decrypt
        let stubKey = storeManager.sessionStore.loadSession(recipientId: senderId, deviceId: deviceId) ?? Data(repeating: 0x42, count: 32)
        let plaintextData = xorEncrypt(data: ciphertextData, key: stubKey)

        result(plaintextData.base64EncodedString())
    }

    // MARK: - Group (Sender Key) Encryption

    private func handleCreateSenderKey(groupId: String, result: @escaping FlutterResult) {
        guard let publicKey = localIdentityPublicKey else {
            result(FlutterError(code: "NO_IDENTITY", message: "Identity key pair not generated", details: nil))
            return
        }

        let localSenderId = publicKey.hexString
        let localDeviceId: UInt32 = 1

        // TODO: Replace with LibSignalClient:
        //   let senderAddress = try ProtocolAddress(name: localSenderId, deviceId: localDeviceId)
        //   let groupSender = SenderKeyName(groupName: groupId, sender: senderAddress)
        //   let distributionMessage = try SenderKeyDistributionMessage(
        //       from: senderAddress,
        //       distributionId: UUID(),
        //       store: senderKeyStore,
        //       context: NullContext()
        //   )
        //   return distributionMessage.serialize().base64EncodedString()

        // STUB: Generate a fake sender key distribution message
        let senderKeyData = generateRandomBytes(count: 64) ?? Data()
        storeManager.senderKeyStore.storeSenderKey(groupId: groupId, senderId: localSenderId, deviceId: localDeviceId, record: senderKeyData)

        result([
            "senderKeyDistributionMessage": senderKeyData.base64EncodedString(),
            "groupId": groupId,
            "senderId": localSenderId
        ])
    }

    private func handleProcessSenderKey(groupId: String, senderId: String, senderKeyMessageBase64: String, result: @escaping FlutterResult) {
        guard let senderKeyData = Data(base64Encoded: senderKeyMessageBase64) else {
            result(FlutterError(code: "INVALID_DATA", message: "senderKeyMessage must be valid base64", details: nil))
            return
        }

        // TODO: Replace with LibSignalClient:
        //   let senderAddress = try ProtocolAddress(name: senderId, deviceId: 1)
        //   let distributionMessage = try SenderKeyDistributionMessage(bytes: senderKeyData)
        //   try processSenderKeyDistributionMessage(
        //       distributionMessage,
        //       from: senderAddress,
        //       for: groupId,
        //       store: senderKeyStore,
        //       context: NullContext()
        //   )

        // STUB: Store the sender key
        storeManager.senderKeyStore.storeSenderKey(groupId: groupId, senderId: senderId, deviceId: 1, record: senderKeyData)

        result(nil)
    }

    private func handleEncryptGroupMessage(groupId: String, plaintextBase64: String, result: @escaping FlutterResult) {
        guard let plaintextData = Data(base64Encoded: plaintextBase64) else {
            result(FlutterError(code: "INVALID_DATA", message: "plaintext must be valid base64", details: nil))
            return
        }

        guard let publicKey = localIdentityPublicKey else {
            result(FlutterError(code: "NO_IDENTITY", message: "Identity key pair not generated", details: nil))
            return
        }

        let localSenderId = publicKey.hexString
        let localDeviceId: UInt32 = 1

        guard let senderKey = storeManager.senderKeyStore.loadSenderKey(groupId: groupId, senderId: localSenderId, deviceId: localDeviceId) else {
            result(FlutterError(code: "NO_SENDER_KEY", message: "No sender key for group \(groupId). Call createSenderKey first.", details: nil))
            return
        }

        // TODO: Replace with LibSignalClient:
        //   let senderAddress = try ProtocolAddress(name: localSenderId, deviceId: localDeviceId)
        //   let ciphertext = try groupEncrypt(
        //       plaintextData,
        //       from: senderAddress,
        //       distributionId: distributionId,
        //       store: senderKeyStore,
        //       context: NullContext()
        //   )

        // STUB: XOR encrypt with sender key
        let ciphertextData = xorEncrypt(data: plaintextData, key: senderKey)

        result(ciphertextData.base64EncodedString())
    }

    private func handleDecryptGroupMessage(groupId: String, senderId: String, ciphertextBase64: String, result: @escaping FlutterResult) {
        guard let ciphertextData = Data(base64Encoded: ciphertextBase64) else {
            result(FlutterError(code: "INVALID_DATA", message: "ciphertext must be valid base64", details: nil))
            return
        }

        guard let senderKey = storeManager.senderKeyStore.loadSenderKey(groupId: groupId, senderId: senderId, deviceId: 1) else {
            result(FlutterError(code: "NO_SENDER_KEY", message: "No sender key for \(senderId) in group \(groupId). Call processSenderKey first.", details: nil))
            return
        }

        // TODO: Replace with LibSignalClient:
        //   let senderAddress = try ProtocolAddress(name: senderId, deviceId: 1)
        //   let plaintext = try groupDecrypt(
        //       ciphertextData,
        //       from: senderAddress,
        //       store: senderKeyStore,
        //       context: NullContext()
        //   )

        // STUB: XOR decrypt with sender key
        let plaintextData = xorEncrypt(data: ciphertextData, key: senderKey)

        result(plaintextData.base64EncodedString())
    }

    // MARK: - Persistence

    private func handleSaveSessionStore(path: String, result: @escaping FlutterResult) {
        do {
            try storeManager.save(to: path)
            result(true)
        } catch {
            result(FlutterError(code: "SAVE_FAILED", message: "Failed to save session store: \(error.localizedDescription)", details: nil))
        }
    }

    private func handleLoadSessionStore(path: String, result: @escaping FlutterResult) {
        do {
            try storeManager.load(from: path)

            // Restore local identity state from loaded data
            if let ikpData = storeManager.identityStore.identityKeyPairData {
                if ikpData.count >= 64 {
                    self.localIdentityPrivateKey = ikpData.prefix(32)
                    self.localIdentityPublicKey = ikpData.suffix(32)
                }
            }
            self.localRegistrationId = storeManager.identityStore.localRegistrationId

            result(true)
        } catch {
            result(FlutterError(code: "LOAD_FAILED", message: "Failed to load session store: \(error.localizedDescription)", details: nil))
        }
    }

    // MARK: - Crypto Helpers (Stub)

    /// Generates cryptographically random bytes using SecRandomCopyBytes.
    private func generateRandomBytes(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { return nil }
        return Data(bytes)
    }

    /// Simple XOR "encryption" for stub/development purposes only.
    /// NOT SECURE. Will be replaced by libsignal-client real encryption.
    private func xorEncrypt(data: Data, key: Data) -> Data {
        var result = Data(count: data.count)
        for i in 0..<data.count {
            result[i] = data[i] ^ key[i % key.count]
        }
        return result
    }
}

// MARK: - Data Extensions

extension Data {
    /// Hex string representation of the data.
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }

    /// Initialize Data from a hex string.
    init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        var index = hex.startIndex
        for _ in 0..<len {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
