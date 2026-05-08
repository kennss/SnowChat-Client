/// @file        ai_provider.dart
/// @description On-Device AI Riverpod Providers — agentic Tool Use integration.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-05-06 (aiModelManagerProvider now fires
///              syncStatusFromDisk() on first read — replaces the old
///              cold-launch startBackgroundDownload() call site in
///              app.dart. The chat list builds → AiChatTile reads the
///              provider → manager constructs and reflects the on-disk
///              install state on its ValueNotifier. No download, just
///              status truth. Earlier: 2026-04-26 header + inline
///              English translation; agentic Tool Use integration.)
///
/// @functions
///  - aiModelManagerProvider: AIModelManager singleton
///  - toolRouterProvider: ToolRouter singleton (tool registration)
///  - onDeviceAIProvider: OnDeviceAIService singleton
///  - aiAvailableProvider: AI model install + initialization state

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../service/ai_model_manager.dart';
import '../service/on_device_ai_service.dart';
import '../service/tool_router.dart';
import '../tools/contact_tool.dart';
import '../tools/calendar_tool.dart';
import '../tools/photo_tool.dart';
import '../tools/clipboard_tool.dart';
import '../tools/location_tool.dart';
import '../tools/device_info_tool.dart';
import '../tools/file_search_tool.dart';
import '../tools/wifi_tool.dart';
import '../tools/bluetooth_tool.dart';
import '../tools/media_tool.dart';
// Android-only tools
import '../tools/sms_tool.dart';
import '../tools/call_log_tool.dart';
import '../tools/alarm_tool.dart';
import '../tools/installed_apps_tool.dart';
import '../tools/app_usage_tool.dart';
import '../tools/notification_tool.dart';

// --- AI Model Manager ---
final aiModelManagerProvider = Provider<AIModelManager>((ref) {
  final manager = AIModelManager();
  // Lazy disk sync on first provider read. The chat list builds →
  // AiChatTile watches the provider → this fires once → if the model
  // is already on disk, downloadStatus flips to complete and the
  // "On-Device" badge appears without any user interaction. No
  // download is triggered here — that path is reserved for the
  // user-initiated tap on the AI tile (RAM gate first, then onboarding).
  unawaited(manager.syncStatusFromDisk());
  return manager;
});

// --- Tool Router (per-platform tool registration) ---
final toolRouterProvider = Provider<ToolRouter>((ref) {
  final router = ToolRouter();

  // Common to both platforms
  router.registerTool(ContactTool());
  router.registerTool(CalendarQueryTool());
  router.registerTool(CalendarCreateTool());
  router.registerTool(PhotoTool());
  router.registerTool(ClipboardTool());
  router.registerTool(LocationTool());
  router.registerTool(DeviceInfoTool());
  router.registerTool(FileSearchTool());
  router.registerTool(VideoSearchTool());

  // Android-only
  if (Platform.isAndroid) {
    router.registerTool(SmsTool());
    router.registerTool(CallLogTool());
    router.registerTool(AlarmQueryTool());
    router.registerTool(AlarmCreateTool());
    router.registerTool(InstalledAppsTool());
    router.registerTool(AppUsageTool());
    router.registerTool(NotificationTool());
    router.registerTool(WifiTool());
    router.registerTool(BluetoothTool());
  }

  return router;
});

// --- On-Device AI Service ---
final onDeviceAIProvider = Provider<OnDeviceAIService>((ref) {
  final service = OnDeviceAIService();
  service.setToolRouter(ref.read(toolRouterProvider));
  ref.onDispose(() => service.dispose());
  return service;
});

// --- AI availability state ---
/// Bridges AIModelManager's downloadStatus ValueNotifier into a Riverpod state.
/// Whenever the model download completes/fails, this Provider emits a new value
/// and `aiAvailableProvider` watching it auto re-evaluates.
final modelDownloadStatusProvider = StreamProvider<ModelDownloadStatus>((ref) {
  final manager = ref.watch(aiModelManagerProvider);
  final controller = StreamController<ModelDownloadStatus>();
  controller.add(manager.downloadStatus.value);

  void listener() {
    if (!controller.isClosed) {
      controller.add(manager.downloadStatus.value);
    }
  }

  manager.downloadStatus.addListener(listener);
  ref.onDispose(() {
    manager.downloadStatus.removeListener(listener);
    controller.close();
  });
  return controller.stream;
});

/// AI availability state — exposes `aiService.isInitialized` changes as a stream.
///
/// ## V1.0.1 stability fix (2026-04-20)
/// Flow of previous versions:
/// - 5329cb5 (malicious): auto-init on download completion → GPU 4GB → IME kill
/// - First V1 fix (broken): returned `installed` only → UI enabled even when not
///   downloaded (violates owner intent: "enable only when init done")
///
/// **Current right way**: expose `OnDeviceAIService.isInitializedNotifier` as a
/// stream. Enter AI chat screen → init → notifier=true → Summary/Translate auto
/// enable. Dispose AI chat → false → auto disable.
///
/// No auto init trigger (does not init even when download completes). Memory
/// usage starts only when the user explicitly enters AI chat → guarantees V1
/// stability.
///
/// Lazy init helper (`ensureInitialized`) retained at use sites as a fail-safe.
final aiAvailableProvider = StreamProvider<bool>((ref) {
  final aiService = ref.read(onDeviceAIProvider);
  final controller = StreamController<bool>();
  controller.add(aiService.isInitialized);

  void listener() {
    if (!controller.isClosed) {
      controller.add(aiService.isInitialized);
    }
  }

  aiService.isInitializedNotifier.addListener(listener);
  ref.onDispose(() {
    aiService.isInitializedNotifier.removeListener(listener);
    controller.close();
  });
  return controller.stream;
});
