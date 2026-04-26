/// @file        contact_tool.dart
/// @description Contacts search Tool — physical device only (stub on simulator)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-14
/// @lastUpdated 2026-04-26 (header + inline English translation; contacts search tool — physical device only)

import 'package:permission_handler/permission_handler.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class ContactTool extends BaseTool {
  @override
  String get name => 'contact_search';

  @override
  String get description => 'Search contacts by name or phone number';

  @override
  Future<bool> hasPermission() async {
    return await Permission.contacts.isGranted;
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.contacts.request();
    return status.isGranted;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final query = params['query'] as String? ?? '';
    if (query.isEmpty) {
      return ToolResult.error('Search query is empty');
    }

    try {
      // TODO: wire up flutter_contacts for physical devices
      // final contacts = await FlutterContacts.getContacts(withProperties: true);
      // final matched = contacts.where((c) => c.displayName.toLowerCase().contains(query.toLowerCase()));

      // Stub for simulator
      return ToolResult(
        success: true,
        summary: '[Simulator stub] Contact search for "$query" — '
            'connect a real device to test.',
        transparencyLabel: 'Contact search (stub) · No server transmission',
      );
    } catch (e) {
      return ToolResult.error('Contact search failed: $e');
    }
  }
}
