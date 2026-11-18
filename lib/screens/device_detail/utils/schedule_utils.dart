import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../models/valve_device.dart';
import '../../../utils/app_log.dart';

// =============================================================================
// SCHEDULE UTILS
// =============================================================================
// Day options, HH:mm time formatting/parsing and the parser for the
// `device_schedule` WebSocket payload. Pure functions — no widgets, no state.
// =============================================================================

/// Days offered in the add/edit schedule dialog.
const List<String> kScheduleDayOptions = [
  'Every day',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats a [TimeOfDay] as `HH:mm` — the format the backend stores.
String formatScheduleTime(TimeOfDay time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Parses an `HH:mm` string back into a [TimeOfDay]. Unparseable parts fall
/// back to 0.
TimeOfDay parseScheduleTime(String timeStr) {
  final parts = timeStr.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

/// Parses the schedule list out of a `device_schedule` event.
///
/// Server sends:
///   {"event":"device_schedule", "device_id":"...",
///    "schedule":{"schedule":"[{\"day\":\"Monday\",\"08:00-08:20\":\"90\"}]"},
///    "Sensor":{...}}
///
/// The inner `schedule` may be a JSON string or an already-decoded list.
///
/// Returns [] when the device has no schedule, and null when the payload
/// carries nothing usable — the caller keeps the list it already has.
List<ScheduleEntry>? parseSchedulePayload(Map<String, dynamic> data) {
  try {
    final scheduleData = data['schedule'];
    if (scheduleData == null) return null;

    final scheduleJson = scheduleData['schedule'];
    if (scheduleJson == null || scheduleJson.toString().isEmpty) {
      return [];
    }

    final List<dynamic> raw;
    if (scheduleJson is String) {
      raw = jsonDecode(scheduleJson);
    } else if (scheduleJson is List) {
      raw = scheduleJson;
    } else {
      logD("⚠️ Unexpected schedule format: ${scheduleJson.runtimeType}");
      return null;
    }

    return raw
        .whereType<Map>()
        .expand((e) => ScheduleEntry.listFromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (e) {
    logD("❌ Error parsing schedule data: $e");
    return null;
  }
}

/// Seconds since midnight → `HH:mm:ss` — the format the valve stores.
String formatScheduleSeconds(int seconds) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(seconds ~/ 3600)}:${two((seconds % 3600) ~/ 60)}:'
      '${two(seconds % 60)}';
}

/// Parses `HH:mm:ss` (or legacy `HH:mm`, seconds = 0) into seconds since
/// midnight. Unparseable parts fall back to 0.
int parseScheduleSeconds(String timeStr) {
  final parts = timeStr.split(':');
  int part(int i) => i < parts.length ? int.tryParse(parts[i].trim()) ?? 0 : 0;
  return part(0) * 3600 + part(1) * 60 + part(2);
}
