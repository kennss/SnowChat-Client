/// @file        device_info_tool.dart
/// @description Device info Tool — battery, storage, network status
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-14
/// @lastUpdated 2026-04-26 (header English translation; device info tool — battery/storage/network)

import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class DeviceInfoTool extends BaseTool {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  @override
  String get name => 'device_info';

  @override
  String get description => 'Get device info: battery, storage, network, model';

  // No special permission needed
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final type = (params['type'] as String? ?? 'all').toLowerCase();

    try {
      final info = StringBuffer();

      if (type == 'battery' || type == 'all') {
        final level = await _battery.batteryLevel;
        final state = await _battery.batteryState;
        final stateStr = switch (state) {
          BatteryState.charging => 'Charging',
          BatteryState.discharging => 'Discharging',
          BatteryState.full => 'Full',
          BatteryState.connectedNotCharging => 'Connected (not charging)',
          _ => 'Unknown',
        };
        info.writeln('🔋 Battery: $level% ($stateStr)');
      }

      if (type == 'network' || type == 'all') {
        final connectivity = await _connectivity.checkConnectivity();
        final netStr = connectivity.contains(ConnectivityResult.wifi)
            ? 'WiFi'
            : connectivity.contains(ConnectivityResult.mobile)
                ? 'Cellular'
                : 'Offline';
        info.writeln('📶 Network: $netStr');
      }

      if (type == 'storage' || type == 'all') {
        // Approximate free space
        final stat = await Process.run('df', ['-h', '/']);
        final lines = stat.stdout.toString().split('\n');
        if (lines.length > 1) {
          info.writeln('💾 Storage: ${lines[1].trim().replaceAll(RegExp(r'\s+'), ' ')}');
        }
      }

      if (type == 'device' || type == 'all') {
        if (Platform.isIOS) {
          final ios = await _deviceInfo.iosInfo;
          info.writeln('📱 ${ios.name} (${ios.model})');
          info.writeln('   iOS ${ios.systemVersion}');
        } else if (Platform.isAndroid) {
          final android = await _deviceInfo.androidInfo;
          info.writeln('📱 ${android.brand} ${android.model}');
          info.writeln('   Android ${android.version.release}');
        }
      }

      final result = info.toString().trim();
      return ToolResult(
        success: true,
        summary: result.isEmpty ? 'No device info available.' : result,
        transparencyLabel: 'Device info accessed · No server transmission',
      );
    } catch (e) {
      return ToolResult.error('Device info query failed: $e');
    }
  }
}
