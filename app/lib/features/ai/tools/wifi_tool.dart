/// @file        wifi_tool.dart
/// @description WiFi info Tool — current network, signal strength
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; WiFi info tool — current network, signal strength)

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class WifiTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/wifi');

  @override
  String get name => 'wifi_info';
  @override
  String get description => 'Get current WiFi network info';

  @override
  Future<bool> hasPermission() => Permission.location.isGranted;
  @override
  Future<bool> requestPermission() async =>
      (await Permission.location.request()).isGranted;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    try {
      final result = await _channel.invokeMethod('getWifiInfo');
      final data = Map<String, dynamic>.from(result as Map);

      final ssid = data['ssid'] ?? 'Unknown';
      final bssid = data['bssid'] ?? '';
      final signal = data['signal'] ?? 0;
      final speed = data['speed'] ?? 0;
      final ip = data['ip'] ?? '';
      final frequency = data['frequency'] ?? 0;

      return ToolResult(
        success: true,
        summary: 'WiFi info:\n'
            '  Network: $ssid\n'
            '  Signal: $signal dBm\n'
            '  Speed: $speed Mbps\n'
            '  IP: $ip\n'
            '  Frequency: $frequency MHz',
        transparencyLabel: 'WiFi info accessed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('WiFi info not available on this platform.');
    } catch (e) {
      return ToolResult.error('WiFi query failed: $e');
    }
  }
}
