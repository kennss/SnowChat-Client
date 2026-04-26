/// @file        media_tool.dart
/// @description Media (video/audio) search Tool
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header English translation; media (video/audio) search tool)

import 'package:photo_manager/photo_manager.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class VideoSearchTool extends BaseTool {
  @override
  String get name => 'video_search';
  @override
  String get description => 'Search videos on device';

  @override
  Future<bool> hasPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(type: RequestType.video, mediaLocation: false),
      ),
    );
    return state.isAuth;
  }

  @override
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(type: RequestType.video, mediaLocation: false),
      ),
    );
    return state.isAuth;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final dateFrom = params['date_from'] as String?;
    final limit = params['limit'] as int? ?? 10;

    try {
      DateTime start;
      if (dateFrom != null) {
        final lower = dateFrom.toLowerCase();
        final now = DateTime.now();
        if (lower == 'today' || lower == '오늘') {
          start = DateTime(now.year, now.month, now.day);
        } else if (lower == 'last week' || lower == '지난주') {
          start = now.subtract(const Duration(days: 7));
        } else {
          try { start = DateTime.parse(dateFrom); }
          catch (_) { start = now.subtract(const Duration(days: 30)); }
        }
      } else {
        start = DateTime.now().subtract(const Duration(days: 30));
      }

      final filterOptions = FilterOptionGroup(
        videoOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        createTimeCond: DateTimeCond(min: start, max: DateTime.now()),
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      );

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        filterOption: filterOptions,
      );

      final allVideos = <AssetEntity>[];
      for (final album in albums) {
        final assets = await album.getAssetListRange(start: 0, end: limit);
        allVideos.addAll(assets);
      }

      final seen = <String>{};
      final unique = allVideos.where((a) => seen.add(a.id)).take(limit).toList();

      if (unique.isEmpty) {
        return const ToolResult(
          success: true,
          summary: 'No videos found.',
          transparencyLabel: 'Videos searched · No server transmission',
        );
      }

      final buf = StringBuffer();
      buf.writeln('Found ${unique.length} video(s):');
      for (final v in unique) {
        final date = v.createDateTime;
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final dur = v.duration;
        final durStr = '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}';
        buf.writeln('  $dateStr — $durStr (${v.width}x${v.height})');
      }

      return ToolResult(
        success: true,
        summary: buf.toString().trim(),
        transparencyLabel: '${unique.length} video(s) accessed · No server transmission',
      );
    } catch (e) {
      return ToolResult.error('Video search failed: $e');
    }
  }
}
