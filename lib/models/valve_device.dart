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



// =============================================================================
// SENSOR CONTROL
// =============================================================================
// The "Sensor" half of a `device_schedule` push — the sibling of ScheduleEntry
// in models/valve_device.dart, and deliberately built the same way.
//
//   "Sensor": {
//     "sensor_rule": {"0-30": "0", "31-60": "75", "61-100": "0"},
//     "sensor_data": {"unit_id": "SU200001001", "sensor_id": "S02",
//                     "sensor_name": "moisture 1", "sensor_type": "Moisture",
//                     "sensor_value": 8, "last_seen": "2026-08-01 17:02:32",
//                     "status": "ok"}
//   }
//
// TWO PARTS, TWO CLASSES:
//   SensorReading  sensor_data — who is reporting, and what it last read.
//                  Read-only: the app never writes this back.
//   SensorRule     one "range → angle" pair out of sensor_rule. The wire puts
//                  the range in the KEY ("0-30": "0"), exactly like the
//                  schedule puts its time range there ("08:00-08:20": "90"),
//                  so this class is the only place that knows that shape.
// =============================================================================

/// The live sensor behind "Control by → sensor". Display only.
class SensorReading {
  final String unitId;      // "SU200001001"
  final String unitName;
  final String sensorId;    // "S02"
  final String sensorName;  // "moisture 1"
  final String sensorType;  // "Moisture"

  /// Kept as a String: the wire sends a number here, but the format varies
  /// by sensor type and the card only ever prints it.
  final String value;

  /// Raw server timestamp, e.g. "2026-08-01 17:02:32". Feed it to
  /// isDeviceOnline() — DateTime.parse takes the space separator fine.
  final String? lastSeen;

  /// "ok" / whatever else the unit reports. Parsed but not drawn yet.
  final String status;

  const SensorReading({
    required this.unitId,
    required this.unitName,
    required this.sensorId,
    required this.sensorName,
    required this.sensorType,
    required this.value,
    required this.lastSeen,
    required this.status,
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    return SensorReading(
      unitId: _clean(json['unit_id']),
      unitName: _clean(json['unit_name']),
      sensorId: _clean(json['sensor_id']),
      sensorName: _clean(json['sensor_name']),
      sensorType: _clean(json['sensor_type']),
      value: _clean(json['sensor_value']),
      lastSeen: _clean(json['last_seen']).isEmpty
          ? null
          : _clean(json['last_seen']),
      status: _clean(json['status']),
    );
  }

  /// Trims, and collapses null / '' / the literal 'NULL' to an empty string.
  /// (PHP serializes SQL NULL as the string — same gotcha Device handles for
  /// last_seen.)
  static String _clean(Object? raw) {
    final String text = raw?.toString().trim() ?? '';
    return text.toUpperCase() == 'NULL' ? '' : text;
  }

  /// The identity subset set_valve_sensor sends back. Deliberately NOT the
  /// full object: sensor_value, last_seen and status are things the server
  /// tells US, so echoing them would be writing back its own live data.
  Map<String, dynamic> toJson() => {
        'unit_id': unitId,
        'unit_name': unitName,
        'sensor_id': sensorId,
        'sensor_name': sensorName,
        'sensor_type': sensorType,
      };

  /// Only unit_name ever needs filling in — see the field's note above.
  SensorReading copyWith({String? unitName}) => SensorReading(
        unitId: unitId,
        unitName: unitName ?? this.unitName,
        sensorId: sensorId,
        sensorName: sensorName,
        sensorType: sensorType,
        value: value,
        lastSeen: lastSeen,
        status: status,
      );
}

/// One row of the sensor table: a reading range, and the angle the valve
/// should hold while the reading sits inside it.
class SensorRule {
  final int from;   // 0
  final int to;     // 30
  final int angle;  // 0–90

  const SensorRule({
    required this.from,
    required this.to,
    required this.angle,
  });

  /// "0-30" — the wire format's key.
  String get range => '$from-$to';

  /// "0 – 30" — the same thing with room to breathe, for the table.
  String get rangeLabel => '$from – $to';

  static final RegExp _rangeKey = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$');

  /// Wire → model. One sensor_rule object holds every range as a key, so this
  /// returns the whole list. Unrecognised keys are skipped, and the result is
  /// sorted by [from] so the table always reads low to high.
  static List<SensorRule> listFromJson(Map<String, dynamic> json) {
    final rules = <SensorRule>[];

    json.forEach((key, value) {
      final match = _rangeKey.firstMatch(key);
      if (match == null) return;

      rules.add(SensorRule(
        from: int.tryParse(match.group(1)!) ?? 0,
        to: int.tryParse(match.group(2)!) ?? 0,
        angle: int.tryParse(value.toString()) ?? 0,
      ));
    });

    rules.sort((a, b) => a.from.compareTo(b.from));
    return rules;
  }

  /// Model → wire. Angle goes out as a String, matching the server and the
  /// schedule payload.
  Map<String, dynamic> toJson() => {range: angle.toString()};

  SensorRule copyWith({int? from, int? to, int? angle}) => SensorRule(
        from: from ?? this.from,
        to: to ?? this.to,
        angle: angle ?? this.angle,
      );

  /// True when this range overlaps [other] — the add/edit dialog uses it to
  /// stop two rules claiming the same reading.
  bool overlaps(SensorRule other) => from <= other.to && other.from <= to;

  /// Model → wire, for the whole table at once: the sensor_rule OBJECT the
  /// server expects, {"0-30": "0", "31-60": "75"}. Ranges are the keys, so a
  /// duplicate range would silently collapse — the add/edit dialog's overlap
  /// check is what prevents that upstream.
  static Map<String, dynamic> mapFromList(List<SensorRule> rules) => {
        for (final rule in rules) rule.range: rule.angle.toString(),
      };
}