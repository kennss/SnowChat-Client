/// @file        location_tool.dart
/// @description Current location Tool — GPS coordinates + reverse geocoding
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; current location tool — GPS + reverse geocoding)

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class LocationTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/location');

  @override
  String get name => 'current_location';
  @override
  String get description => 'Get current GPS location';

  @override
  Future<bool> hasPermission() => Permission.location.isGranted;
  @override
  Future<bool> requestPermission() async =>
      (await Permission.location.request()).isGranted;

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    try {
      final result = await _channel.invokeMethod('getCurrentLocation');
      final data = Map<String, dynamic>.from(result as Map);

      final lat = data['latitude'] ?? 0.0;
      final lng = data['longitude'] ?? 0.0;
      final address = data['address'] as String? ?? 'Unknown';
      final accuracy = data['accuracy'] ?? 0.0;

      return ToolResult(
        success: true,
        summary: 'Current location:\n'
            '  Address: $address\n'
            '  Coordinates: $lat, $lng\n'
            '  Accuracy: ${(accuracy as double).toStringAsFixed(0)}m',
        transparencyLabel: 'GPS location accessed · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('Location not available on this platform.');
    } catch (e) {
      return ToolResult.error('Location failed: $e');
    }
  }
}
