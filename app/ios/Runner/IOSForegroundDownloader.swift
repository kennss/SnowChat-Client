//
// @file        IOSForegroundDownloader.swift
// @description Foreground URLSession 기반 대용량 모델 다운로더.
//              background_downloader (NSURLSession background discretionary)
//              대신 full-bandwidth foreground 세션 사용 + Range header resume +
//              beginBackgroundTask grace period.
//              Apple rate limiter 우회 → Enclave AI / Locally AI 등 실제
//              iOS 온디바이스 AI 앱들이 쓰는 표준 패턴.
// @author      Kennt Kim
// @company     Calida Lab
// @created     2026-04-18
// @lastUpdated 2026-04-18
//
// @functions
//  - IOSForegroundDownloader.register(with:): MethodChannel + EventChannel 등록
//  - startDownload(url, destinationPath): 다운로드 시작/재개 (Range resume)
//  - cancelDownload(): 현재 다운로드 취소 (.part 파일 보존)
//  - deleteDownload(destinationPath): .part + 최종 파일 모두 삭제
//

import Foundation
import UIKit
import Flutter

/// Foreground URLSession 다운로더.
/// 대용량(수 GB) 파일을 풀 대역폭으로 받기 위함.
class IOSForegroundDownloader: NSObject {

  // MARK: - Channels

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let streamHandler: DownloaderStreamHandler

  // MARK: - Session & task state

  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 60 * 60 * 2  // 2h total
    config.waitsForConnectivity = true
    config.allowsCellularAccess = true
    config.httpMaximumConnectionsPerHost = 6
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  private var currentTask: URLSessionDataTask?
  private var outputHandle: FileHandle?
  private var partPath: String?
  private var finalPath: String?
  private var expectedTotal: Int64 = 0
  private var downloadedSoFar: Int64 = 0
  private var startByteOffset: Int64 = 0
  private var lastProgressEmit: Date = .distantPast
  private var bgTaskId: UIBackgroundTaskIdentifier = .invalid

  // MARK: - Registration

  @discardableResult
  static func register(with messenger: FlutterBinaryMessenger) -> IOSForegroundDownloader {
    let method = FlutterMethodChannel(
      name: "com.snowchat/ios_downloader", binaryMessenger: messenger)
    let event = FlutterEventChannel(
      name: "com.snowchat/ios_downloader_progress", binaryMessenger: messenger)
    let streamHandler = DownloaderStreamHandler()
    event.setStreamHandler(streamHandler)

    let instance = IOSForegroundDownloader(
      methodChannel: method, eventChannel: event, streamHandler: streamHandler)
    method.setMethodCallHandler { [weak instance] call, result in
      instance?.handle(call, result: result)
    }
    NSLog("[iOSDownloader] Registered MethodChannel + EventChannel")
    return instance
  }

  private init(methodChannel: FlutterMethodChannel,
               eventChannel: FlutterEventChannel,
               streamHandler: DownloaderStreamHandler) {
    self.methodChannel = methodChannel
    self.eventChannel = eventChannel
    self.streamHandler = streamHandler
    super.init()
  }

  // MARK: - MethodChannel dispatch

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startDownload":
      guard let args = call.arguments as? [String: Any],
            let urlStr = args["url"] as? String,
            let dest = args["destinationPath"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "url/destinationPath required", details: nil))
        return
      }
      let expectedMinSize = (args["expectedMinSize"] as? Int) ?? 0
      startDownload(urlString: urlStr, destinationPath: dest, expectedMinSize: Int64(expectedMinSize), result: result)

    case "cancelDownload":
      cancelDownload()
      result(true)

    case "deleteDownload":
      guard let args = call.arguments as? [String: Any],
            let dest = args["destinationPath"] as? String else {
        result(FlutterError(code: "BAD_ARGS", message: "destinationPath required", details: nil))
        return
      }
      deleteDownload(destinationPath: dest)
      result(true)

    case "isDownloading":
      result(currentTask != nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Core download

  private func startDownload(urlString: String, destinationPath: String,
                             expectedMinSize: Int64, result: @escaping FlutterResult) {
    guard currentTask == nil else {
      result(FlutterError(code: "BUSY", message: "Another download in progress", details: nil))
      return
    }
    guard let url = URL(string: urlString) else {
      result(FlutterError(code: "BAD_URL", message: "Invalid URL", details: nil))
      return
    }

    let part = destinationPath + ".part"
    partPath = part
    finalPath = destinationPath
    expectedTotal = 0

    // Resume support: if .part exists, start from its size
    let fm = FileManager.default
    if fm.fileExists(atPath: part) {
      let attrs = try? fm.attributesOfItem(atPath: part)
      let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
      startByteOffset = size
      downloadedSoFar = size
      NSLog("[iOSDownloader] Resuming from byte \(size)")
    } else {
      // Ensure parent dir exists + create empty .part
      let parent = (part as NSString).deletingLastPathComponent
      try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
      fm.createFile(atPath: part, contents: nil, attributes: nil)
      startByteOffset = 0
      downloadedSoFar = 0
    }

    // Open FileHandle for appending
    guard let handle = FileHandle(forWritingAtPath: part) else {
      result(FlutterError(code: "FILE_OPEN", message: "Cannot open .part file", details: nil))
      return
    }
    handle.seekToEndOfFile()
    outputHandle = handle

    // Begin background task so we get grace period when user backgrounds app
    beginBgTask()

    // Build request with Range header if resuming
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    if startByteOffset > 0 {
      request.setValue("bytes=\(startByteOffset)-", forHTTPHeaderField: "Range")
    }

    let task = session.dataTask(with: request)
    currentTask = task
    task.resume()

    NSLog("[iOSDownloader] Started: \(url.lastPathComponent) (offset=\(startByteOffset))")
    result(true)
  }

  private func cancelDownload() {
    currentTask?.cancel()
    currentTask = nil
    closeHandle()
    endBgTask()
  }

  private func deleteDownload(destinationPath: String) {
    cancelDownload()
    let fm = FileManager.default
    let part = destinationPath + ".part"
    try? fm.removeItem(atPath: part)
    try? fm.removeItem(atPath: destinationPath)
  }

  // MARK: - Background task grace

  private func beginBgTask() {
    guard bgTaskId == .invalid else { return }
    bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "snowchat.model-download") { [weak self] in
      // Expiration handler — OS is about to kill us
      NSLog("[iOSDownloader] BG task expiring, task will pause (resumable)")
      self?.endBgTask()
    }
  }

  private func endBgTask() {
    if bgTaskId != .invalid {
      UIApplication.shared.endBackgroundTask(bgTaskId)
      bgTaskId = .invalid
    }
  }

  // MARK: - Cleanup

  private func closeHandle() {
    try? outputHandle?.close()
    outputHandle = nil
  }

  fileprivate func emitProgress(_ value: Double) {
    // Throttle: 200ms
    let now = Date()
    if now.timeIntervalSince(lastProgressEmit) < 0.2 && value < 1.0 {
      return
    }
    lastProgressEmit = now
    DispatchQueue.main.async { [weak self] in
      self?.streamHandler.send(["progress": value])
    }
  }

  fileprivate func emitStatus(_ status: String, message: String? = nil) {
    DispatchQueue.main.async { [weak self] in
      var payload: [String: Any] = ["status": status]
      if let m = message { payload["message"] = m }
      self?.streamHandler.send(payload)
    }
  }
}

// MARK: - URLSessionDataDelegate

extension IOSForegroundDownloader: URLSessionDataDelegate {

  func urlSession(_ session: URLSession,
                  dataTask: URLSessionDataTask,
                  didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    if let http = response as? HTTPURLResponse {
      // 200 (fresh) or 206 (partial) both fine
      let status = http.statusCode
      if status != 200 && status != 206 {
        NSLog("[iOSDownloader] HTTP \(status) — aborting")
        completionHandler(.cancel)
        emitStatus("error", message: "HTTP \(status)")
        closeHandle()
        endBgTask()
        currentTask = nil
        return
      }
      // Total size: Content-Length is chunk size; Content-Range has total
      if let range = http.value(forHTTPHeaderField: "Content-Range"),
         let totalStr = range.split(separator: "/").last,
         let total = Int64(totalStr) {
        expectedTotal = total
      } else {
        expectedTotal = startByteOffset + response.expectedContentLength
      }
      NSLog("[iOSDownloader] Total expected: \(expectedTotal) bytes")
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession,
                  dataTask: URLSessionDataTask,
                  didReceive data: Data) {
    guard let handle = outputHandle else { return }
    do {
      try handle.write(contentsOf: data)
      downloadedSoFar += Int64(data.count)
      if expectedTotal > 0 {
        let pct = Double(downloadedSoFar) / Double(expectedTotal)
        emitProgress(min(pct, 0.999))
      }
    } catch {
      NSLog("[iOSDownloader] Write failed: \(error)")
      dataTask.cancel()
    }
  }

  func urlSession(_ session: URLSession,
                  task: URLSessionTask,
                  didCompleteWithError error: Error?) {
    closeHandle()

    if let err = error {
      let nsErr = err as NSError
      // Cancelled is expected for user-initiated cancel
      if nsErr.code == NSURLErrorCancelled {
        NSLog("[iOSDownloader] Cancelled — .part preserved for resume")
        emitStatus("cancelled")
      } else {
        NSLog("[iOSDownloader] Completed with error: \(err.localizedDescription)")
        emitStatus("error", message: err.localizedDescription)
      }
      currentTask = nil
      endBgTask()
      return
    }

    // Success — rename .part → final
    guard let part = partPath, let final = finalPath else {
      emitStatus("error", message: "missing paths")
      currentTask = nil
      endBgTask()
      return
    }
    let fm = FileManager.default
    do {
      if fm.fileExists(atPath: final) {
        try fm.removeItem(atPath: final)
      }
      try fm.moveItem(atPath: part, toPath: final)
      emitProgress(1.0)
      emitStatus("complete")
      NSLog("[iOSDownloader] Complete: \(final)")
    } catch {
      NSLog("[iOSDownloader] Rename failed: \(error)")
      emitStatus("error", message: "rename failed: \(error.localizedDescription)")
    }
    currentTask = nil
    endBgTask()
  }

  // Follow redirects (HF → CloudFront)
  func urlSession(_ session: URLSession,
                  task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) {
    // Preserve Range header across redirect if we're resuming
    var req = request
    if startByteOffset > 0 {
      req.setValue("bytes=\(startByteOffset)-", forHTTPHeaderField: "Range")
    }
    completionHandler(req)
  }
}

// MARK: - EventChannel stream handler

private class DownloaderStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func send(_ payload: [String: Any]) {
    sink?(payload)
  }
}
