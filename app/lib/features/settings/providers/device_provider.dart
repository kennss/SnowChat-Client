/// @file        device_provider.dart
/// @description Device-management state Provider — fetch device list from server, remove device, track current device.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - DeviceInfo: device-info data class
///  - DeviceListState: device-list state (loading, data, error)
///  - DeviceNotifier: StateNotifier managing device-list state
///  - deviceProvider: StateNotifierProvider exposing the device list
///  - currentDeviceIdProvider: current-device-ID StateProvider
///  - fetchDevices(): fetch device list from server
///  - removeDevice(): remove device on server

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../app/providers.dart';

/// Device information model.
class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String platform; // 'ios', 'android', 'web', 'desktop'
  final DateTime lastSeen;
  final DateTime createdAt;
  final bool isCurrent;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.lastSeen,
    required this.createdAt,
    this.isCurrent = false,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json, {String? currentDeviceId}) {
    return DeviceInfo(
      deviceId: json['deviceId'] as String,
      deviceName: (json['deviceName'] as String?) ?? 'Unknown Device',
      platform: (json['platform'] as String?) ?? 'unknown',
      lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      isCurrent: currentDeviceId != null && json['deviceId'] == currentDeviceId,
    );
  }
}

/// State for the device list.
class DeviceListState {
  final bool isLoading;
  final List<DeviceInfo> devices;
  final String? error;

  const DeviceListState({
    this.isLoading = false,
    this.devices = const [],
    this.error,
  });

  DeviceListState copyWith({
    bool? isLoading,
    List<DeviceInfo>? devices,
    String? error,
  }) {
    return DeviceListState(
      isLoading: isLoading ?? this.isLoading,
      devices: devices ?? this.devices,
      error: error,
    );
  }
}

/// Current device ID — set during device registration at login.
final currentDeviceIdProvider = StateProvider<String?>((ref) => null);

/// Device list state notifier.
class DeviceNotifier extends StateNotifier<DeviceListState> {
  final ApiClient _apiClient;
  final Ref _ref;

  DeviceNotifier(this._apiClient, this._ref) : super(const DeviceListState());

  /// Fetch all linked devices from the server.
  Future<void> fetchDevices() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiClient.get(ApiEndpoints.devices);
      final data = response.data;
      final currentDeviceId = _ref.read(currentDeviceIdProvider);

      List<DeviceInfo> devices = [];
      if (data is Map && data['devices'] is List) {
        devices = (data['devices'] as List)
            .map((d) => DeviceInfo.fromJson(
                  d as Map<String, dynamic>,
                  currentDeviceId: currentDeviceId,
                ))
            .toList();
      } else if (data is List) {
        devices = data
            .map((d) => DeviceInfo.fromJson(
                  d as Map<String, dynamic>,
                  currentDeviceId: currentDeviceId,
                ))
            .toList();
      }

      // Sort: current device first, then by lastSeen descending
      devices.sort((a, b) {
        if (a.isCurrent && !b.isCurrent) return -1;
        if (!a.isCurrent && b.isCurrent) return 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });

      state = state.copyWith(isLoading: false, devices: devices);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load devices. Please try again.',
      );
    }
  }

  /// Remove a device by ID.
  Future<bool> removeDevice(String deviceId) async {
    try {
      await _apiClient.delete(ApiEndpoints.device(deviceId));
      state = state.copyWith(
        devices: state.devices.where((d) => d.deviceId != deviceId).toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Provider for the device list.
final deviceProvider =
    StateNotifierProvider<DeviceNotifier, DeviceListState>((ref) {
  final apiClient = ref.read(apiClientProvider);
  return DeviceNotifier(apiClient, ref);
});
