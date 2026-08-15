class ValveDevice {
  final String id;
  final String name;
  final ValveStatus status;
  final int position;
  final bool isConnected;
  final DateTime? lastUpdated;
  final String? macAddress;

  ValveDevice({
    required this.id,
    required this.name,
    this.status = ValveStatus.offline,
    this.position = 0,
    this.isConnected = false,
    this.lastUpdated,
    this.macAddress,
  });

  ValveDevice copyWith({
    String? id,
    String? name,
    ValveStatus? status,
    int? position,
    bool? isConnected,
    DateTime? lastUpdated,
    String? macAddress,
  }) {
    return ValveDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      position: position ?? this.position,
      isConnected: isConnected ?? this.isConnected,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      macAddress: macAddress ?? this.macAddress,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'status': status.name,
      'position': position,
      'isConnected': isConnected,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'macAddress': macAddress,
    };
  }

  factory ValveDevice.fromJson(Map<String, dynamic> json) {
    return ValveDevice(
      id: json['id'],
      name: json['name'],
      status: ValveStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ValveStatus.offline,
      ),
      position: json['position'] ?? 0,
      isConnected: json['isConnected'] ?? false,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : null,
      macAddress: json['macAddress'],
    );
  }
}

enum ValveStatus { open, closed, partial, offline, error }

extension ValveStatusExtension on ValveStatus {
  String get displayName {
    switch (this) {
      case ValveStatus.open: return 'Open';
      case ValveStatus.closed: return 'Closed';
      case ValveStatus.partial: return 'Partial';
      case ValveStatus.offline: return 'Offline';
      case ValveStatus.error: return 'Error';
    }
  }
}




// =============================================================================
// SCHEDULE ENTRY
// =============================================================================
// One row of the schedule table: a day, a time range, and the angle the valve
// should hold during it.
//
// The wire format puts the time range in the KEY:
//     {"day": "Monday", "08:00-08:20": "90"}
// so this class is the only place that knows about that shape. Everything else
// works with named fields.
// =============================================================================

class ScheduleEntry {
  final String day;    // "Every day" | "Monday" | ...
  final String start;  // "08:00"
  final String end;    // "08:20"
  final int angle;     // 0–90

  const ScheduleEntry({
    required this.day,
    required this.start,
    required this.end,
    required this.angle,
  });

  /// "08:00-08:20" — the wire format's key.
  String get timeRange => '$start-$end';

  /// Matches a time-range key and captures both ends. Also the reason `day`
  /// is skipped without special-casing it.
  static final RegExp _timeRangeKey =
      RegExp(r'^\s*(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*$');

  /// Wire → model. One JSON object can legally hold several time-range keys,
  /// so this returns a list rather than a single entry.
  static List<ScheduleEntry> listFromJson(Map<String, dynamic> json) {
    final day = json['day']?.toString() ?? '';
    final entries = <ScheduleEntry>[];

    json.forEach((key, value) {
      final match = _timeRangeKey.firstMatch(key);
      if (match == null) return;   // 'day', or anything unrecognised

      entries.add(ScheduleEntry(
        day: day,
        start: match.group(1)!,
        end: match.group(2)!,
        angle: int.tryParse(value.toString()) ?? 0,
      ));
    });

    return entries;
  }

  /// Model → wire. Angle goes out as a string, matching the server.
  Map<String, dynamic> toJson() => {
        'day': day,
        timeRange: angle.toString(),
      };

  ScheduleEntry copyWith({String? day, String? start, String? end, int? angle}) =>
      ScheduleEntry(
        day: day ?? this.day,
        start: start ?? this.start,
        end: end ?? this.end,
        angle: angle ?? this.angle,
      );
}