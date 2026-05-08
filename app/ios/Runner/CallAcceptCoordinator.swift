//
// @file        CallAcceptCoordinator.swift
// @description Single source of truth for VoIP CallKit accept handoff. Static
//              shared state across the BFU (Before First Unlock) boundary,
//              the protectedDataDidBecomeAvailable observer, the URLSession
//              fetch lifecycle, and the Dart drain queue. Phase E-2 v3.1.
//
//              Responsibilities (all idempotent — 3-way guard):
//                1. handleAccept(nonce): fulfill the CXAnswerCallAction
//                   IMMEDIATELY on the calling main thread (P2 — caller is on
//                   main per CXProvider contract; deferring to async risks
//                   exceeding Apple's 5s deadline on cold launches), then
//                   start a background task + 30s watchdog + ephemeral
//                   URLSession fetch of /calls/pending/<nonce>.
//                2. On fetch success: enqueue {nonce, envelopes} into the
//                   pending map. If Dart is attached (binaryMessenger known),
//                   drain immediately; otherwise wait for attachMessenger.
//                3. On BFU: register protectedDataDidBecomeAvailable observer.
//                   Upon unlock, retry SecureStorageReader (auth_token /
//                   auth_refresh_token / device_id) once and resume fetch.
//                   Hard cap is the 30s watchdog (P3 — UIApplication
//                   beginBackgroundTask is bounded around the same window
//                   on locked iOS, so a higher cap is dead code).
//                4. completedNonces: ledger of (nonce → reason) for telemetry
//                   and idempotency. action.fulfill | watchdog | fetchOk |
//                   fetchErr | bgTaskExpired | bfuGiveUp.
//                5. pruneOld (P5): on each handleAccept entry, drop ledger
//                   entries older than 1 hour to bound memory growth.
//
//              Zero-Trace (§23): only nonce.prefix(8) is logged. No envelope
//              body, no Authorization header value, no HTTP body bytes.
//
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-30
// @lastUpdated 2026-04-29 (v195: 410 → softCleanup, do NOT endAllCalls — Dart
//              parallel-fetch path consumed envelopes; native dismiss killed
//              the call user just answered. Field-confirmed via Console.app)
//
// @functions
//  - handleAccept(nonce, action, call): fulfill + start fetch flow
//  - attachMessenger(messenger): hooked from AppDelegate; drains pending now
//  - setBaseUrl(url): hooked from Dart MethodChannel; required before fetch
//  - drainPending(): emit pending {nonce, envelopes} to Dart
//  - expirePending(nonce, reason): cancel everything, dismiss CallKit
//  - softCleanup_locked(nonce, reason): release resources WITHOUT dismissing
//    CallKit (used on 410 — parallel Dart path owns lifecycle)
//  - protectedDataDidBecomeAvailable(): re-attempt fetch once after unlock
//  - pruneOld_locked(): TTL prune of ledger maps
//  - logSafe(_): nonce.prefix(8) only logger
//

import Foundation
import UIKit
import CallKit
import Flutter
import flutter_callkit_incoming

@objc final class CallAcceptCoordinator: NSObject {

    // MARK: – Constants

    /// P3: 30s. Matches the de-facto UIApplication beginBackgroundTask budget
    /// on locked iOS. v3's 300s "absoluteCap" was dead code — bgTask expires
    /// first. Document in CLAUDE.md §2.8 as the user-visible "answer window".
    private static let watchdogTimeout: TimeInterval = 30

    /// P5: ledger prune horizon. Anything older than this on the next
    /// handleAccept entry is dropped from completedNonces and
    /// handleAcceptTimeByNonce so the maps don't grow unbounded.
    private static let ledgerPruneAge: TimeInterval = 3600

    private static let queueLabel = "ai.calidalab.snowchat.voip.coordinator"

    // MARK: – Static shared state (Lock via accessQueue)

    private static let accessQueue = DispatchQueue(label: queueLabel)

    /// nonce → envelopes fetched and waiting for Dart to drain.
    private static var pendingByNonce: [String: [String]] = [:]

    /// nonce → DispatchWorkItem watchdog (30s single-attempt).
    private static var watchdogs: [String: DispatchWorkItem] = [:]

    /// nonce → UIBackgroundTaskIdentifier (kept alive until expire/done).
    private static var bgTaskByNonce: [String: UIBackgroundTaskIdentifier] = [:]

    /// nonce → ledger ("action.fulfill"|"watchdog"|"fetchOk"|"fetchErr"|"bgTaskExpired"|"bfuGiveUp").
    /// 3-way idempotency guard: any subsequent re-entry on same nonce is no-op.
    private static var completedNonces: [String: String] = [:]

    /// nonce → handleAccept timestamp. Used by the prune sweep.
    private static var handleAcceptTimeByNonce: [String: Date] = [:]

    /// nonce → URLSession instance (per-fetch, invalidated after completion).
    /// N-Maj-3 / Δ3: per-nonce instance prevents header-overwrite races
    /// between concurrent fetches.
    private static var sessionByNonce: [String: URLSession] = [:]

    /// Dart-supplied baseUrl (e.g. https://snowchat.calidalab.ai/api/v2).
    /// Until this is non-nil, fetches are deferred (kept in pendingFetchNonces).
    private static var baseUrl: String?

    /// nonce of accepts received before baseUrl arrived. Drained once setBaseUrl fires.
    private static var pendingFetchNonces: [String] = []

    /// FlutterBinaryMessenger from the rooted FlutterViewController. Until non-nil,
    /// drains are deferred. Set in attachMessenger.
    private static weak var messenger: FlutterBinaryMessenger?

    /// MethodChannel for Dart drain (`snowchat/voip_native`).
    private static var drainChannel: FlutterMethodChannel?

    /// One-time registration of the BFU observer.
    private static var observerRegistered: Bool = false

    // MARK: – Public entry points

    /// Called from AppDelegate.onAccept (CallkitIncomingAppDelegate). Per
    /// CXProvider contract this fires on the main thread. P2: fulfill
    /// IMMEDIATELY on main BEFORE any async hop so iOS reports the call as
    /// answered within its 5s deadline even on cold launches where the main
    /// thread is busy bootstrapping the Flutter engine.
    @objc public static func handleAccept(nonce: String,
                                          action: CXAnswerCallAction,
                                          call: Call) {
        // P2: fulfill on main (caller is main per CXProvider contract). Setup
        // work below is allowed to slip onto the access queue.
        action.fulfill()

        accessQueue.async {
            // P5: opportunistic ledger prune. Cheap when small, bounds growth.
            pruneOld_locked()

            // Idempotency guard: same accept replayed (e.g. user double-taps).
            // After P2 the action is already fulfilled — second action.fulfill()
            // would be a contract violation, so we just skip setup silently.
            if let prev = completedNonces[nonce] {
                logSafe("handleAccept ignored — already completed:\(prev) nonce=\(nonce.prefix(8))")
                return
            }

            handleAcceptTimeByNonce[nonce] = Date()
            startBackgroundTask(for: nonce)
            startWatchdog(for: nonce)
            ensureBfuObserver()

            // Mark fulfill in ledger so idempotency guard fires on re-entry.
            completedNonces[nonce] = "action.fulfill"
            logSafe("handleAccept fulfill nonce=\(nonce.prefix(8))")

            // Decide fetch path:
            //  - BFU → enqueue, will run on protectedDataDidBecomeAvailable.
            //  - baseUrl missing → enqueue, will run on setBaseUrl.
            //  - Otherwise → fetch now.
            if !UIApplication.shared.isProtectedDataAvailable {
                logSafe("BFU — fetch deferred until unlock nonce=\(nonce.prefix(8))")
                pendingFetchNonces.append(nonce)
                return
            }
            guard baseUrl != nil else {
                logSafe("baseUrl missing — fetch deferred nonce=\(nonce.prefix(8))")
                pendingFetchNonces.append(nonce)
                return
            }
            startFetch(nonce: nonce)
        }
    }

    /// Hooked from AppDelegate after FlutterViewController is rooted.
    /// Once messenger is known, register the drain channel + drain anything
    /// queued. Idempotent: re-call (e.g. on hot restart) replaces channel.
    @objc public static func attachMessenger(_ messenger: FlutterBinaryMessenger) {
        accessQueue.async {
            self.messenger = messenger
            let ch = FlutterMethodChannel(name: "snowchat/voip_native",
                                          binaryMessenger: messenger)
            self.drainChannel = ch
            // Drain channel is one-way native → Dart for now; no inbound handler.
            // (setBaseUrl uses a separate channel — see VoipNativeBridge.swift.)
            logSafe("attachMessenger ok — draining \(self.pendingByNonce.count) entries")
            self.drainPending_locked()
        }
    }

    /// Called by VoipNativeBridge when Dart pushes the resolved baseUrl
    /// (typically after Riverpod / DNS resolve). Idempotent.
    @objc public static func setBaseUrl(_ url: String) {
        accessQueue.async {
            guard self.baseUrl != url else { return }
            self.baseUrl = url
            logSafe("baseUrl set len=\(url.count)")
            // Drain accepts that arrived before baseUrl. Mirror the
            // protectedDataDidBecomeAvailable guard so a nonce whose watchdog
            // already fired (between handleAccept and baseUrl arrival) does
            // NOT trigger a duplicate fetch — see audit P0 race.
            let toFetch = self.pendingFetchNonces
            self.pendingFetchNonces.removeAll()
            for nonce in toFetch where self.sessionByNonce[nonce] == nil {
                guard self.completedNonces[nonce] == "action.fulfill" else { continue }
                self.startFetch(nonce: nonce)
            }
        }
    }

    // MARK: – BFU observer

    private static func ensureBfuObserver() {
        guard !observerRegistered else { return }
        observerRegistered = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: nil
        ) { _ in
            CallAcceptCoordinator.protectedDataDidBecomeAvailable()
        }
        logSafe("BFU observer registered")
    }

    @objc public static func protectedDataDidBecomeAvailable() {
        accessQueue.async {
            // Re-attempt every nonce that's still pending fetch. The 30s
            // watchdog is the de-facto cap; if it has already fired,
            // completedNonces[nonce] != "action.fulfill" and pruneOld will
            // drop the entry within an hour.
            let toFetch = pendingFetchNonces
            pendingFetchNonces = []
            guard baseUrl != nil else {
                // baseUrl still missing — re-enqueue, will resume on setBaseUrl.
                pendingFetchNonces.append(contentsOf: toFetch)
                return
            }
            for nonce in toFetch where sessionByNonce[nonce] == nil {
                // Skip if watchdog already fired and expired this nonce.
                guard completedNonces[nonce] == "action.fulfill" else { continue }
                startFetch(nonce: nonce)
            }
        }
    }

    // MARK: – Background task + watchdog

    private static func startBackgroundTask(for nonce: String) {
        let task = UIApplication.shared.beginBackgroundTask(withName: "voip-\(nonce.prefix(8))") {
            CallAcceptCoordinator.expirePending(nonce: nonce, reason: "bgTaskExpired")
        }
        bgTaskByNonce[nonce] = task
    }

    private static func endBackgroundTask(for nonce: String) {
        if let task = bgTaskByNonce.removeValue(forKey: nonce),
           task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private static func startWatchdog(for nonce: String) {
        let work = DispatchWorkItem {
            CallAcceptCoordinator.accessQueue.async {
                guard CallAcceptCoordinator.pendingByNonce[nonce] == nil,
                      CallAcceptCoordinator.completedNonces[nonce] == "action.fulfill" else {
                    return
                }
                logSafe("watchdog fire — expire nonce=\(nonce.prefix(8))")
                expirePending_locked(nonce: nonce, reason: "watchdog")
            }
        }
        watchdogs[nonce] = work
        accessQueue.asyncAfter(deadline: .now() + watchdogTimeout, execute: work)
    }

    // MARK: – P5 ledger prune (caller must hold accessQueue)

    private static func pruneOld_locked() {
        let cutoff = Date().addingTimeInterval(-ledgerPruneAge)
        let stale = handleAcceptTimeByNonce.filter { $0.value < cutoff }.keys
        for nonce in stale {
            handleAcceptTimeByNonce.removeValue(forKey: nonce)
            completedNonces.removeValue(forKey: nonce)
        }
    }

    // MARK: – Fetch (per-nonce ephemeral URLSession)

    private static func startFetch(nonce: String) {
        guard let baseUrl = baseUrl else { return }
        guard let token = SecureStorageReader.read(key: "auth_token"),
              let deviceId = SecureStorageReader.read(key: "device_id"),
              !token.isEmpty, !deviceId.isEmpty else {
            // Likely BFU read miss — let observer retry. Don't expire yet.
            logSafe("auth_token/device_id read miss — wait nonce=\(nonce.prefix(8))")
            pendingFetchNonces.append(nonce)
            return
        }

        guard let url = URL(string: "\(baseUrl)/calls/pending/\(nonce)") else {
            logSafe("bad url — expire nonce=\(nonce.prefix(8))")
            expirePending_locked(nonce: nonce, reason: "fetchErr")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // No User-Agent override — let URLSession default.

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 30
        let session = URLSession(configuration: cfg)
        sessionByNonce[nonce] = session

        let task = session.dataTask(with: req) { data, resp, err in
            CallAcceptCoordinator.accessQueue.async {
                defer {
                    session.invalidateAndCancel()
                    self.sessionByNonce.removeValue(forKey: nonce)
                }
                if let err = err {
                    logSafe("fetch error \(err.localizedDescription.prefix(40)) nonce=\(nonce.prefix(8))")
                    self.expirePending_locked(nonce: nonce, reason: "fetchErr")
                    return
                }
                guard let http = resp as? HTTPURLResponse else {
                    self.expirePending_locked(nonce: nonce, reason: "fetchErr")
                    return
                }
                if http.statusCode == 410 {
                    // 410 GONE = server's atomic MULTI/DEL was already consumed
                    // by the parallel Dart-side fetch in `acceptPendingVoipCall`
                    // (call_provider.dart:769). That path will inject the
                    // envelope and call acceptCall(), so CallKit must NOT be
                    // dismissed here — doing so kills the very call the user
                    // just answered. Soft-clean only.
                    logSafe("410 — consumed by Dart path, soft cleanup nonce=\(nonce.prefix(8))")
                    self.softCleanup_locked(nonce: nonce, reason: "consumedByDart")
                    return
                }
                guard http.statusCode == 200, let data = data else {
                    logSafe("fetch \(http.statusCode) nonce=\(nonce.prefix(8))")
                    self.expirePending_locked(nonce: nonce, reason: "fetchErr")
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let envs = json["envelopes"] as? [String], !envs.isEmpty else {
                    logSafe("bad json nonce=\(nonce.prefix(8))")
                    self.expirePending_locked(nonce: nonce, reason: "fetchErr")
                    return
                }
                self.pendingByNonce[nonce] = envs
                self.completedNonces[nonce] = "fetchOk"
                logSafe("fetch ok envCount=\(envs.count) nonce=\(nonce.prefix(8))")
                self.watchdogs.removeValue(forKey: nonce)?.cancel()
                self.drainPending_locked()
            }
        }
        task.resume()
    }

    // MARK: – Drain to Dart

    /// Caller must hold accessQueue.
    private static func drainPending_locked() {
        guard let channel = drainChannel else { return }
        guard !pendingByNonce.isEmpty else { return }

        let snapshot = pendingByNonce
        pendingByNonce.removeAll()

        DispatchQueue.main.async {
            for (nonce, envelopes) in snapshot {
                channel.invokeMethod(
                    "voipAcceptedEnvelopes",
                    arguments: ["nonce": nonce, "envelopes": envelopes]
                )
            }
            CallAcceptCoordinator.accessQueue.async {
                for nonce in snapshot.keys {
                    self.endBackgroundTask(for: nonce)
                }
            }
        }
    }

    // MARK: – Expire path

    @objc public static func expirePending(nonce: String, reason: String) {
        accessQueue.async { expirePending_locked(nonce: nonce, reason: reason) }
    }

    /// Caller must hold accessQueue.
    private static func expirePending_locked(nonce: String, reason: String) {
        watchdogs.removeValue(forKey: nonce)?.cancel()
        sessionByNonce.removeValue(forKey: nonce)?.invalidateAndCancel()
        pendingByNonce.removeValue(forKey: nonce)
        endBackgroundTask(for: nonce)
        completedNonces[nonce] = reason
        // Dismiss CallKit so user isn't stuck on "answered" UI with no audio.
        DispatchQueue.main.async {
            SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endAllCalls()
        }
        logSafe("expirePending \(reason) nonce=\(nonce.prefix(8))")
    }

    /// Soft cleanup — release native resources without dismissing CallKit.
    /// Used when the Dart-side parallel fetch path won the race (server returned
    /// 410 to us). The Dart path owns the CallKit lifecycle from this point;
    /// dismissing here would kill the call the user just answered.
    /// Caller must hold accessQueue.
    private static func softCleanup_locked(nonce: String, reason: String) {
        watchdogs.removeValue(forKey: nonce)?.cancel()
        sessionByNonce.removeValue(forKey: nonce)?.invalidateAndCancel()
        pendingByNonce.removeValue(forKey: nonce)
        endBackgroundTask(for: nonce)
        completedNonces[nonce] = reason
        logSafe("softCleanup \(reason) nonce=\(nonce.prefix(8))")
    }

    // MARK: – Logging (Zero-Trace)

    private static func logSafe(_ msg: String) {
        NSLog("[CallAcceptCoordinator] \(msg)")
    }
}
