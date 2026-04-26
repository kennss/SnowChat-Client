/// @file        bluetooth_tool.dart
/// @description Bluetooth devices Tool — list of paired devices
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; Bluetooth paired devices tool)

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class BluetoothTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/bluetooth');

  @override
  String get name => 'bluetooth_devices';
  @override
  String get description => 'List paired Bluetooth devices';

  @override
  Future<bool> hasPermission() => Permission.bluetoothConnect.isGranted;
  @override
  Future<bool> requestPermission() async =>
      (await Permission.bluetoothConnect.request()).isGranted;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    try {
      final result = await _channel.invokeMethod('getPairedDevices');
      final devices = (result as List?)?.cast<Map>() ?? [];

      if (devices.isEmpty) {
        return const ToolResult(
          success: true,
          summary: 'No paired Bluetooth devices found.',
          transparencyLabel: 'Bluetooth checked · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('${devices.length} paired device(s):');
      for (final d in devices) {
        final name = d['name'] ?? 'Unknown';
        final type = d['type'] ?? '';
        final connected = d['connected'] == true ? ' [Connected]' : '';
        buf.writeln('  $name ($type)$connected');
      }

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${devices.length} device(s) listed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('Bluetooth not available on this platform.');
    } catch (e) {
      return ToolResult.error('Bluetooth query failed: $e');
    }
  }
}
