/// @file        ai_model_manager.dart
/// @description AI model download/install management.
///              Model configuration is centrally managed in ai_models_config.dart's
///              AIModels.iosModel / androidModel — only modify that file when swapping.
///
///              Both iOS/Android use background_downloader →
///              downloads continue even when the app goes to background.
///              iOS pre-resolves HuggingFace 302 redirects, then calls
///              background_downloader with the real CDN URL.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation; AI model download/install management)
///
/// @functions
///  - AIModelManager.isModelInstalled(): whether the model is installed
///  - AIModelManager.startBackgroundDownload(): auto-invoked at app startup
///  - AIModelManager.startManualDownload(): manual download
///  - AIModelManager.modelPath: absolute path to the model file
///  - AIModelManager.deleteModel(): delete the model
///  - AIModelManager.isWifiConnected(): check Wi-Fi connectivity
///  - AIModelManager.currentProfile: active ModelProfile for the current platform

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:background_downloader/background_downloader.dart';

import 'ai_models_config.dart';

/// iOS foreground downloader native channel
const _iosDownloaderChannel = MethodChannel('com.snowchat/ios_downloader');
const _iosDownloaderEventChannel = EventChannel('com.snowchat/ios_downloader_progress');

/// Download task group
const _downloadTaskGroup = 'ai-model';

/// Download status
enum ModelDownloadStatus { idle, downloading, complete, error }

/// Gemma model download/install manager.
///
/// To swap the model: edit AIModels.iosModel / androidModel constants in
/// `ai_models_config.dart` and rebuild. Old files are auto cleaned up.
class AIModelManager {
  /// Current download progress (0.0 ~ 1.0) — watchable from UI
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);

  /// Current download status
  final ValueNotifier<ModelDownloadStatus> downloadStatus =
      ValueNotifier(ModelDownloadStatus.idle);

  String? _cachedModelPath;
  bool _legacyCleaned = false;

  /// Active model profile for the current platform
  ModelProfile get currentProfile => AIModels.currentProfile();

  /// Model size for UI display
  String get modelSizeDisplay => currentProfile.sizeDisplay;

  /// Model name for UI display
  String get modelDisplayName => currentProfile.displayName;

  /// Absolute path to the model file.
  /// On first call, clean up any leftover legacy files.
  Future<String> get modelPath async {
    if (_cachedModelPath != null) return _cachedModelPath!;
    final dir = await getApplicationDocumentsDirectory();

    // On first access, clean up old model files (active model excluded)
    if (!_legacyCleaned) {
      _legacyCleaned = true;
      for (final legacyName in AIModels.legacyForCurrentPlatform()) {
        final legacyPath = '${dir.path}/$legacyName';
        final file = File(legacyPath);
        if (await file.exists()) {
          try {
            await file.delete();
            debugPrint('[AIModelManager] Deleted legacy model: $legacyName');
          } catch (e) {
            debugPrint('[AIModelManager] Failed to delete legacy $legacyName: $e');
          }
        }
      }
    }

    _cachedModelPath = '${dir.path}/${currentProfile.filename}';
    return _cachedModelPath!;
  }

  /// Check whether the model file is installed locally
  Future<bool> isModelInstalled() async {
    try {
      final path = await modelPath;
      final file = File(path);
      if (!await file.exists()) return false;
      final size = await file.length();
      return size >= currentProfile.expectedMinSize;
    } catch (e) {
      debugPrint('[AIModelManager] isModelInstalled check failed: $e');
      return false;
    }
  }

  /// Check network connection state (Wi-Fi recommended)
  Future<bool> isWifiConnected() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  /// Auto-invoked at app startup — start background download if on WiFi.
  Future<void> startBackgroundDownload() async {
    final installed = await isModelInstalled();
    if (installed) {
      downloadStatus.value = ModelDownloadStatus.complete;
      downloadProgress.value = 1.0;
      return;
    }

    final wifi = await isWifiConnected();
    if (!wifi) {
      debugPrint('[AIModelManager] Not on WiFi — skipping auto download');
      return;
    }

    _enqueueDownload();
  }

  /// Manual download (also called over cellular after user consent).
  ///
  /// If a valid model already exists on disk, just set `complete` and return —
  /// after cold start the ValueNotifier resets to idle, and this avoids the trap
  /// where the user inadvertently taps the onboarding "Download" button and the
  /// 2.5GB file gets deleted and re-downloaded. Cases that genuinely need a
  /// re-download (AiChatScreen._redownloadModel) call deleteModel() first, so
  /// they are unaffected.
  Future<void> startManualDownload() async {
    if (await isModelInstalled()) {
      downloadStatus.value = ModelDownloadStatus.complete;
      downloadProgress.value = 1.0;
      return;
    }
    await deleteModel();
    _enqueueDownload();
  }

  bool _downloaderConfigured = false;

  /// Configure FileDownloader foreground service (one-time)
  Future<void> _configureDownloader() async {
    if (_downloaderConfigured) return;
    _downloaderConfigured = true;

    if (Platform.isAndroid) {
      // Android: switch to foreground service for files >= 100MB
      await FileDownloader().configure(
        globalConfig: [(Config.runInForegroundIfFileLargerThan, 100000000)],
      );
    }
    // iOS: the plugin automatically uses NSURLSession background configuration.
    // OS keeps the download going even when the app is backgrounded/terminated.

    FileDownloader().configureNotification(
      running: const TaskNotification(
        'SnowChat AI',
        'Downloading AI model — {progress}%',
      ),
      complete: const TaskNotification(
        'SnowChat AI',
        'AI model ready',
      ),
      error: const TaskNotification(
        'SnowChat AI',
        'Download failed — tap to retry',
      ),
      progressBar: true,
    );
  }

  /// Actual download trigger.
  /// iOS: foreground URLSession (full bandwidth + Range resume + bgTask grace).
  /// Android: background_downloader (WorkManager, already fast).
  void _enqueueDownload() {
    downloadStatus.value = ModelDownloadStatus.downloading;
    downloadProgress.value = 0.0;
    if (Platform.isIOS) {
      _downloadWithIosForeground();
    } else {
      _downloadWithBackgroundDownloader();
    }
  }

  StreamSubscription? _iosProgressSub;

  /// iOS foreground URLSession-based download.
  /// NSURLSession.default (not background) → bypass Apple rate limiter, full bandwidth.
  /// beginBackgroundTask grace period → keeps running ~30s-3min after app backgrounds.
  /// Range header resume → continues after interruption.
  void _downloadWithIosForeground() {
    () async {
      try {
        final profile = currentProfile;
        final path = await modelPath;

        debugPrint('[AIModelManager] iOS foreground download: ${profile.filename} '
            '(${profile.sizeDisplay})');

        // Listen progress events
        _iosProgressSub?.cancel();
        final completer = Completer<bool>();
        DateTime? lastProgressLog;

        _iosProgressSub = _iosDownloaderEventChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is! Map) return;
            final progress = (event['progress'] as num?)?.toDouble();
            final status = event['status'] as String?;
            if (progress != null) {
              downloadProgress.value = progress;
              final now = DateTime.now();
              if (lastProgressLog == null ||
                  now.difference(lastProgressLog!).inSeconds >= 2) {
                debugPrint('[AIModelManager] iOS Progress: '
                    '${(progress * 100).toStringAsFixed(1)}%');
                lastProgressLog = now;
              }
            }
            if (status == 'complete') {
              if (!completer.isCompleted) completer.complete(true);
            } else if (status == 'error' || status == 'cancelled') {
              final msg = event['message'] as String? ?? status;
              debugPrint('[AIModelManager] iOS download $status: $msg');
              if (!completer.isCompleted) completer.complete(false);
            }
          },
          onError: (e) {
            debugPrint('[AIModelManager] iOS event stream error: $e');
            if (!completer.isCompleted) completer.complete(false);
          },
        );

        await _iosDownloaderChannel.invokeMethod<bool>('startDownload', {
          'url': profile.url,
          'destinationPath': path,
          'expectedMinSize': profile.expectedMinSize,
        });

        final ok = await completer.future;
        await _iosProgressSub?.cancel();
        _iosProgressSub = null;

        if (ok) {
          final file = File(path);
          if (await file.exists() &&
              await file.length() >= profile.expectedMinSize) {
            downloadStatus.value = ModelDownloadStatus.complete;
            downloadProgress.value = 1.0;
            debugPrint('[AIModelManager] iOS download complete: $path');
          } else {
            debugPrint('[AIModelManager] iOS file missing or incomplete');
            downloadStatus.value = ModelDownloadStatus.error;
          }
        } else {
          downloadStatus.value = ModelDownloadStatus.error;
        }
      } catch (e) {
        debugPrint('[AIModelManager] iOS download error: $e');
        downloadStatus.value = ModelDownloadStatus.error;
        await _iosProgressSub?.cancel();
        _iosProgressSub = null;
      }
    }();
  }

  /// Both platforms: use background_downloader (iOS NSURLSession background,
  /// Android WorkManager). Continues after the app is backgrounded/terminated.
  ///
  /// HF 302 redirects are handled at the native layer on both platforms
  /// automatically (NSURLSession / OkHttp default behavior). Manual resolve is
  /// avoided because it can cause signed URL scope mismatches.
  void _downloadWithBackgroundDownloader() {
    () async {
      try {
        await _configureDownloader();

        final profile = currentProfile;

        final task = DownloadTask(
          url: profile.url,
          directory: '',
          baseDirectory: BaseDirectory.applicationDocuments,
          filename: profile.filename,
          group: _downloadTaskGroup,
          updates: Updates.statusAndProgress,
          requiresWiFi: false,
          retries: 5,
          allowPause: true,
        );

        debugPrint('[AIModelManager] Enqueuing download: ${profile.filename} '
            '(${profile.sizeDisplay})');

        DateTime? lastProgressLog;
        final result = await FileDownloader().download(
          task,
          onProgress: (progress) {
            if (progress >= 0) {
              downloadProgress.value = progress;
              // Diagnostic: log at most once every 2 seconds (anti-spam)
              final now = DateTime.now();
              if (lastProgressLog == null ||
                  now.difference(lastProgressLog!).inSeconds >= 2) {
                debugPrint('[AIModelManager] Progress: '
                    '${(progress * 100).toStringAsFixed(1)}%');
                lastProgressLog = now;
              }
            }
          },
          onStatus: (status) {
            debugPrint('[AIModelManager] Download status: $status');
          },
        );

        if (result.status == TaskStatus.complete) {
          final path = await modelPath;
          final file = File(path);
          if (await file.exists() &&
              await file.length() >= profile.expectedMinSize) {
            downloadStatus.value = ModelDownloadStatus.complete;
            downloadProgress.value = 1.0;
            debugPrint('[AIModelManager] Download complete: $path');
          } else {
            debugPrint('[AIModelManager] File missing or incomplete');
            downloadStatus.value = ModelDownloadStatus.error;
          }
        } else {
          debugPrint('[AIModelManager] Download failed: ${result.status}');
          downloadStatus.value = ModelDownloadStatus.error;
        }
      } catch (e) {
        debugPrint('[AIModelManager] Download error: $e');
        downloadStatus.value = ModelDownloadStatus.error;
      }
    }();
  }

  /// Delete local model
  Future<void> deleteModel() async {
    try {
      final path = await modelPath;

      // iOS foreground downloader cancel + .part cleanup
      if (Platform.isIOS) {
        try {
          await _iosDownloaderChannel.invokeMethod('deleteDownload', {
            'destinationPath': path,
          });
        } catch (e) {
          debugPrint('[AIModelManager] iOS deleteDownload failed: $e');
        }
        await _iosProgressSub?.cancel();
        _iosProgressSub = null;
      }

      final tasks = await FileDownloader().allTasks();
      final aiTasks = tasks
          .where((t) => t.group == _downloadTaskGroup)
          .map((t) => t.taskId)
          .toList();
      if (aiTasks.isNotEmpty) {
        await FileDownloader().cancelTasksWithIds(aiTasks);
      }
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[AIModelManager] Model deleted');
      }
    } catch (e) {
      debugPrint('[AIModelManager] Delete failed: $e');
    }
  }
}
