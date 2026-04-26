/// @file        file_search_tool.dart
/// @description File/document search Tool — search downloads folder and documents
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; file/document search tool)

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class FileSearchTool extends BaseTool {
  static const _channel = MethodChannel('com.calidalab.snowclaw/files');

  @override
  String get name => 'file_search';
  @override
  String get description => 'Search files and documents on device';

  @override
  Future<bool> hasPermission() async =>
      await Permission.storage.isGranted ||
      await Permission.manageExternalStorage.isGranted;

  @override
  Future<bool> requestPermission() async {
    var status = await Permission.storage.request();
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    return status.isGranted;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final query = params['query'] as String? ?? '';
    final type = params['type'] as String? ?? 'all'; // all, pdf, doc, image, video
    final folder = params['folder'] as String? ?? 'downloads';

    try {
      final result = await _channel.invokeMethod('searchFiles', {
        'query': query,
        'type': type,
        'folder': folder,
      });

      final files = (result as List?)?.cast<Map>() ?? [];

      if (files.isEmpty) {
        return ToolResult(
          success: true,
          summary: 'No files found${query.isNotEmpty ? ' matching "$query"' : ''}.',
          transparencyLabel: 'Files searched · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('Found ${files.length} file(s):');
      for (final f in files.take(15)) {
        final name = f['name'] ?? 'Unknown';
        final size = f['size'] ?? 0;
        final sizeStr = _formatSize(size as int);
        buf.writeln('  $name ($sizeStr)');
      }
      if (files.length > 15) buf.writeln('  ... and ${files.length - 15} more');

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${files.length} file(s) found · No server transmission',
      );
    } on MissingPluginException {
      return ToolResult.error('File search not available on this platform.');
    } catch (e) {
      return ToolResult.error('File search failed: $e');
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
