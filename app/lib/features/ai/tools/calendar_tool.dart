/// @file        calendar_tool.dart
/// @description Calendar query/create Tool — search and create local calendar events
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-14
/// @lastUpdated 2026-04-26 (header + inline English translation; calendar query/create tool)

import 'package:device_calendar/device_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

import '../service/tool_router.dart';
import 'base_tool.dart';

class CalendarQueryTool extends BaseTool {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  @override
  String get name => 'calendar_query';

  @override
  String get description => 'Query calendar events for a date range';

  @override
  Future<bool> hasPermission() async {
    return await Permission.calendarFullAccess.isGranted;
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.calendarFullAccess.request();
    return status.isGranted;
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final dateStr = params['date'] as String? ?? '';
    final rangeDays = params['range_days'] as int? ?? 1;

    try {
      // Parse date (supports "today", "tomorrow", "2026-04-15", etc.)
      final date = _parseDate(dateStr);
      final start = DateTime(date.year, date.month, date.day);
      final end = start.add(Duration(days: rangeDays));

      // Get all calendars
      final calendarsResult = await _plugin.retrieveCalendars();
      final calendars = calendarsResult.data ?? [];

      final events = <Map<String, dynamic>>[];

      for (final cal in calendars) {
        if (cal.id == null) continue;
        final eventsResult = await _plugin.retrieveEvents(
          cal.id!,
          RetrieveEventsParams(startDate: start, endDate: end),
        );
        for (final event in eventsResult.data ?? <Event>[]) {
          events.add({
            'title': event.title ?? 'Untitled',
            'start': event.start?.toIso8601String(),
            'end': event.end?.toIso8601String(),
            'location': event.location,
            'calendar': cal.name,
            'allDay': event.allDay ?? false,
          });
        }
      }

      // Sort by start time
      events.sort((a, b) =>
          (a['start'] as String? ?? '').compareTo(b['start'] as String? ?? ''));

      if (events.isEmpty) {
        return ToolResult(
          success: true,
          summary: 'No events found for ${_formatDateRange(start, end)}.',
          transparencyLabel: 'Calendar checked · No events · No server transmission',
        );
      }

      final summary = StringBuffer();
      summary.writeln('Events for ${_formatDateRange(start, end)}:');
      for (final e in events) {
        final time = e['allDay'] == true
            ? 'All day'
            : _formatTime(e['start'] as String?);
        summary.writeln('• $time — ${e['title']}');
        if (e['location'] != null && (e['location'] as String).isNotEmpty) {
          summary.writeln('  📍 ${e['location']}');
        }
      }

      return ToolResult(
        success: true,
        summary: summary.toString().trim(),
        transparencyLabel: '${events.length} event(s) accessed · No server transmission',
        data: events,
      );
    } catch (e) {
      return ToolResult.error('Calendar query failed: $e');
    }
  }

  DateTime _parseDate(String input) {
    final lower = input.toLowerCase().trim();
    final now = DateTime.now();

    if (lower == 'today' || lower == '오늘') return now;
    if (lower == 'tomorrow' || lower == '내일') return now.add(const Duration(days: 1));
    if (lower == 'yesterday' || lower == '어제') return now.subtract(const Duration(days: 1));

    try {
      return DateTime.parse(input);
    } catch (_) {
      return now; // fallback to today
    }
  }

  String _formatDateRange(DateTime start, DateTime end) {
    if (end.difference(start).inDays == 1) {
      return '${start.month}/${start.day}';
    }
    return '${start.month}/${start.day} - ${end.month}/${end.day}';
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '?';
    try {
      final dt = DateTime.parse(isoString);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '?';
    }
  }
}

class CalendarCreateTool extends BaseTool {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  @override
  String get name => 'calendar_create';

  @override
  String get description => 'Create a new calendar event';

  @override
  bool get requiresConfirmation => true;

  @override
  Future<bool> hasPermission() async {
    return await Permission.calendarFullAccess.isGranted;
  }

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.calendarFullAccess.request();
    return status.isGranted;
  }

  @override
  Future<String> previewAction(Map<String, dynamic> params) async {
    final title = params['title'] ?? 'Untitled';
    final date = params['date'] ?? 'unknown date';
    final time = params['time'] ?? 'unknown time';
    return 'Create event:\n📅 $title\n🕐 $date $time\n\nConfirm?';
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> params) async {
    final title = params['title'] as String? ?? 'Untitled';
    final dateStr = params['date'] as String? ?? '';
    final timeStr = params['time'] as String? ?? '09:00';

    try {
      // Get writable calendar (prefer non-readonly, first available)
      final calendarsResult = await _plugin.retrieveCalendars();
      final calendars = calendarsResult.data ?? [];
      if (calendars.isEmpty) {
        return ToolResult.error('No calendars available on this device.');
      }
      // Prefer a writable calendar
      Calendar? writableCal;
      for (final c in calendars) {
        if (c.isReadOnly == false) {
          writableCal = c;
          break;
        }
      }
      writableCal ??= calendars.first;
      final calendarId = writableCal!.id!;

      // Parse date ("tomorrow", "내일", "2026-04-17", etc.)
      final date = _parseDate(dateStr);

      // Parse time ("14:00", "오후 2시", "2pm", etc.)
      final hour = _parseHour(timeStr);
      final minute = _parseMinute(timeStr);

      final start = tz.TZDateTime(
        tz.local,
        date.year, date.month, date.day,
        hour, minute,
      );
      final end = start.add(const Duration(hours: 1));

      final event = Event(calendarId, title: title, start: start, end: end);
      final result = await _plugin.createOrUpdateEvent(event);

      if (result?.isSuccess == true) {
        final dateLabel = '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
        final timeLabel = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
        return ToolResult(
          success: true,
          summary: 'Event created: "$title" on $dateLabel at $timeLabel',
          transparencyLabel: 'Calendar event created · No server transmission',
        );
      } else {
        return ToolResult.error('Failed to create event. Calendar might be read-only.');
      }
    } catch (e) {
      return ToolResult.error('Calendar create failed: $e');
    }
  }

  DateTime _parseDate(String input) {
    final lower = input.toLowerCase().trim();
    final now = DateTime.now();

    if (lower == 'today' || lower == '오늘') return now;
    if (lower == 'tomorrow' || lower == '내일') return now.add(const Duration(days: 1));
    if (lower == 'yesterday' || lower == '어제') return now.subtract(const Duration(days: 1));

    // Things like "다음주 월요일" fall back to ISO parsing
    try {
      return DateTime.parse(input);
    } catch (_) {
      return now.add(const Duration(days: 1)); // fallback: tomorrow
    }
  }

  int _parseHour(String time) {
    final lower = time.toLowerCase().trim();

    // "오후 2시", "오전 10시" (Korean PM/AM)
    final koMatch = RegExp(r'(오전|오후)\s*(\d+)').firstMatch(lower);
    if (koMatch != null) {
      var h = int.parse(koMatch.group(2)!);
      if (koMatch.group(1) == '오후' && h < 12) h += 12;
      if (koMatch.group(1) == '오전' && h == 12) h = 0;
      return h;
    }

    // "2pm", "10am"
    final enMatch = RegExp(r'(\d+)\s*(am|pm)', caseSensitive: false).firstMatch(lower);
    if (enMatch != null) {
      var h = int.parse(enMatch.group(1)!);
      if (enMatch.group(2)!.toLowerCase() == 'pm' && h < 12) h += 12;
      if (enMatch.group(2)!.toLowerCase() == 'am' && h == 12) h = 0;
      return h;
    }

    // "14:00", "14"
    final parts = lower.split(':');
    return int.tryParse(parts[0]) ?? 9;
  }

  int _parseMinute(String time) {
    final parts = time.split(':');
    if (parts.length > 1) {
      return int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }
    return 0;
  }
}
