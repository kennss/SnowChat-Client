/// @file        photo_tool.dart
/// @description Photo search Tool — local photo search by date + GPS location
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-14
/// @lastUpdated 2026-04-26 (header + inline English translation; added GPS location filtering, metadata-based search)

import 'dart:math';

import 'package:photo_manager/photo_manager.dart';

import '../service/tool_router.dart';
import 'base_tool.dart';

class PhotoTool extends BaseTool {
  @override
  String get name => 'photo_search';

  @override
  String get description => 'Search photos by date range and/or location';

  @override
  Future<bool> hasPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: true, // requires GPS coordinate access
        ),
      ),
    );
    return state.isAuth;
  }

  @override
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: const PermissionRequestOption(
        androidPermission: AndroidPermission(
          type: RequestType.image,
          mediaLocation: true,
        ),
      ),
    );
    return state.isAuth;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final dateFrom = params['date_from'] as String?;
    final dateTo = params['date_to'] as String?;
    final query = (params['query'] as String? ?? '').trim();
    final location = (params['location'] as String? ?? '').trim();

    try {
      // Date filter
      DateTime? start;
      DateTime? end;

      if (dateFrom != null) start = _parseDate(dateFrom);
      if (dateTo != null) {
        end = _parseDate(dateTo);
      } else if (start != null) {
        end = start.add(const Duration(days: 1));
      }

      // If there's a location query, widen the period (GPS filter across all photos)
      final locationQuery = location.isNotEmpty ? location : _extractLocation(query);
      final coords = locationQuery != null ? _resolveLocation(locationQuery) : null;

      if (coords != null && start == null) {
        // For location search, widen the date range (last 2 years)
        start = DateTime.now().subtract(const Duration(days: 730));
        end = DateTime.now();
      }

      // Default: last 7 days
      start ??= DateTime.now().subtract(const Duration(days: 7));
      end ??= DateTime.now();

      final filterOptions = FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        createTimeCond: DateTimeCond(min: start, max: end),
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      );

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: filterOptions,
      );

      final allPhotos = <AssetEntity>[];
      for (final album in albums) {
        final assets = await album.getAssetListRange(start: 0, end: 200);
        allPhotos.addAll(assets);
      }

      // Dedup
      final seen = <String>{};
      var unique = allPhotos.where((a) => seen.add(a.id)).toList();

      // GPS location filtering
      if (coords != null) {
        final filtered = <AssetEntity>[];
        for (final photo in unique) {
          final latLng = await photo.latlngAsync();
          if (latLng != null && latLng.latitude != 0 && latLng.longitude != 0) {
            final dist = _distanceKm(
                latLng.latitude!, latLng.longitude!, coords.$1, coords.$2);
            if (dist < coords.$3) {
              filtered.add(photo);
            }
          }
        }
        unique = filtered;
      }

      final results = unique.take(20).toList();

      if (results.isEmpty) {
        final reason = coords != null
            ? 'No photos found from "$locationQuery".'
            : 'No photos found for the specified date range.';
        return ToolResult(
          success: true,
          summary: reason,
          transparencyLabel: 'Photos searched · No matches · No server transmission',
        );
      }

      final summary = StringBuffer();
      if (coords != null) {
        summary.writeln('Found ${results.length} photo(s) from "$locationQuery":');
      } else {
        summary.writeln('Found ${results.length} photo(s):');
      }
      for (final photo in results.take(10)) {
        final date = photo.createDateTime;
        final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        summary.writeln('  $dateStr (${photo.width}x${photo.height})');
      }
      if (results.length > 10) {
        summary.writeln('  ... and ${results.length - 10} more');
      }

      return ToolResult(
        success: true,
        summary: summary.toString().trim(),
        transparencyLabel: '${results.length} photo(s) accessed · GPS filtered · No server transmission',
        data: results.map((a) => {
          'id': a.id,
          'width': a.width,
          'height': a.height,
          'createDate': a.createDateTime.toIso8601String(),
        }).toList(),
      );
    } catch (e) {
      return ToolResult.error('Photo search failed: $e');
    }
  }

  // ── Location keyword extraction ──

  /// Extract location keyword from query (e.g. "발리에서 찍은" → "발리")
  String? _extractLocation(String query) {
    if (query.isEmpty) return null;
    final lower = query.toLowerCase();

    // English pattern: "photos from Bali", "in Tokyo", "at Paris"
    final enMatch = RegExp(r'(?:from|in|at)\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+)*)', caseSensitive: false)
        .firstMatch(query);
    if (enMatch != null) return enMatch.group(1)!.trim();

    // Korean pattern: "발리에서", "도쿄에서", "파리에서"
    final koMatch = RegExp(r'(\S+?)(?:에서|에|의|가|를|을)').firstMatch(lower);
    if (koMatch != null) {
      final loc = koMatch.group(1)!;
      if (_knownLocations.keys.any((k) => k.contains(loc) || loc.contains(k))) {
        return loc;
      }
    }

    // Direct match
    for (final key in _knownLocations.keys) {
      if (lower.contains(key)) return key;
    }

    return null;
  }

  /// Location name → (latitude, longitude, radius km)
  (double, double, double)? _resolveLocation(String location) {
    final lower = location.toLowerCase();
    for (final entry in _knownLocations.entries) {
      if (lower.contains(entry.key) || entry.key.contains(lower)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Haversine distance (km)
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  DateTime _parseDate(String input) {
    final lower = input.toLowerCase().trim();
    final now = DateTime.now();

    if (lower == 'today' || lower == '오늘') return DateTime(now.year, now.month, now.day);
    if (lower == 'yesterday' || lower == '어제') {
      final y = now.subtract(const Duration(days: 1));
      return DateTime(y.year, y.month, y.day);
    }
    if (lower.startsWith('last week') || lower == '지난주') {
      return now.subtract(const Duration(days: 7));
    }

    try {
      return DateTime.parse(input);
    } catch (_) {
      return now.subtract(const Duration(days: 7));
    }
  }
}

/// Major travel destinations/cities → (latitude, longitude, search radius km)
const _knownLocations = <String, (double, double, double)>{
  // Asia
  '발리': (-8.41, 115.19, 80),
  'bali': (-8.41, 115.19, 80),
  '도쿄': (35.68, 139.69, 50),
  'tokyo': (35.68, 139.69, 50),
  '오사카': (34.69, 135.50, 40),
  'osaka': (34.69, 135.50, 40),
  '방콕': (13.76, 100.50, 50),
  'bangkok': (13.76, 100.50, 50),
  '싱가포르': (1.35, 103.82, 30),
  'singapore': (1.35, 103.82, 30),
  '홍콩': (22.32, 114.17, 30),
  'hong kong': (22.32, 114.17, 30),
  '다낭': (16.05, 108.22, 40),
  'da nang': (16.05, 108.22, 40),
  '타이베이': (25.03, 121.57, 30),
  'taipei': (25.03, 121.57, 30),
  '세부': (10.31, 123.89, 50),
  'cebu': (10.31, 123.89, 50),
  '보라카이': (11.97, 121.93, 20),
  'boracay': (11.97, 121.93, 20),
  // Korea
  '서울': (37.57, 126.98, 30),
  'seoul': (37.57, 126.98, 30),
  '부산': (35.18, 129.08, 30),
  'busan': (35.18, 129.08, 30),
  '제주': (33.50, 126.53, 40),
  'jeju': (33.50, 126.53, 40),
  '강남': (37.50, 127.03, 5),
  '이태원': (37.53, 126.99, 3),
  '홍대': (37.56, 126.92, 3),
  // Americas/Europe
  '뉴욕': (40.71, -74.01, 40),
  'new york': (40.71, -74.01, 40),
  '파리': (48.86, 2.35, 30),
  'paris': (48.86, 2.35, 30),
  '런던': (51.51, -0.13, 40),
  'london': (51.51, -0.13, 40),
  '로마': (41.90, 12.50, 30),
  'rome': (41.90, 12.50, 30),
  '하와이': (20.80, -156.33, 100),
  'hawaii': (20.80, -156.33, 100),
  '괌': (13.44, 144.79, 30),
  'guam': (13.44, 144.79, 30),
  '사이판': (15.19, 145.75, 20),
  'saipan': (15.19, 145.75, 20),
  'la': (34.05, -118.24, 50),
  'los angeles': (34.05, -118.24, 50),
  'san francisco': (37.77, -122.42, 30),
};
