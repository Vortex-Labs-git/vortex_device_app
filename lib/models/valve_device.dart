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
  
  /// The reading trimmed for display. The wire sends 33.45692475692 and the
  /// card has about 78px to draw it in, so anything numeric is cut to one
  /// decimal — and a whole number keeps no decimal at all, so 8 stays "8"
  /// rather than becoming "8.0".
  ///
  /// Non-numeric values pass through untouched: if a sensor ever reports a
  /// word or a value with a unit suffix, mangling it would be worse than
  /// letting it through.
  ///
  /// [value] itself stays raw — this is presentation only.
  String get displayValue {
    if (value.isEmpty) return '—';

    final double? number = double.tryParse(value);
    if (number == null) return value;

    return number == number.roundToDouble()
        ? number.toStringAsFixed(0)
        : number.toStringAsFixed(1);
  }

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

// =============================================================================
// SENSOR PICKER OPTIONS
// =============================================================================
// The `user_sensor_units` reply to get_user_sensors — what the "+ Add sensor"
// popup chooses from:
//
//   {"event":"user_sensor_units", "No_sensor_units":"2",
//    "sensor_units":[
//      {"unit_id":"SU200001001", "unit_name":"garden sensor",
//       "unit_last_seen":"2026-08-01 17:02:32", "no_sensors":"3",
//       "sensor_data":[{"sensor_id":"S00", "sensor_type":"Temperature",
//                       "sensor_name":"Inbuild Temp", "sensor_value":31.21}]}]}
//
// These are deliberately their OWN classes, not the SensorUnit / Sensor pair in
// models/sensor_unit.dart. Those two model a unit's own detail screen, keyed
// `id` / `unit_version` with sensor_data as an escaped JSON string. This is a
// picker payload: different keys, sensor_data is a real list, and the only
// thing it ever produces is a SensorReading for the valve. Keeping them apart
// means a change to the sensor-unit screen can't quietly break this popup —
// and it keeps everything the valve detail screen needs in this one file.
//
// The count fields (No_sensor_units, no_sensors) are ignored on purpose: the
// list length is the honest count, and trusting a separate counter is how you
// end up rendering blank rows.
// =============================================================================

/// One sensor inside a pickable unit.
class SensorOption {
  final String id;     // "S02"
  final String type;   // "Moisture"
  final String name;   // "moisture 1"

  /// Kept as a String — the wire sends 31.21185302734375 for one sensor and
  /// 8 for the next, and nothing here does arithmetic on it.
  final String value;

  const SensorOption({
    required this.id,
    required this.type,
    required this.name,
    required this.value,
  });

  factory SensorOption.fromJson(Map<String, dynamic> json) => SensorOption(
        id: json['sensor_id']?.toString().trim() ?? '',
        type: json['sensor_type']?.toString().trim() ?? '',
        name: json['sensor_name']?.toString().trim() ?? '',
        value: json['sensor_value']?.toString().trim() ?? '',
      );

  /// The picked sensor as the card's model. [unit] supplies unit_id/unit_name
  /// (both needed by set_valve_sensor) and last_seen, so the card's online dot
  /// is right immediately instead of waiting for the next push.
  SensorReading toReading(SensorUnitOption unit) => SensorReading(
        unitId: unit.id,
        unitName: unit.name,
        sensorId: id,
        sensorName: name,
        sensorType: type,
        value: value,
        lastSeen: unit.lastSeen,
        status: '',
      );
}

/// One unit in the "Available Sensor Units" list.
class SensorUnitOption {
  final String id;        // "SU200001001"
  final String name;      // "garden sensor"

  /// Raw server timestamp. Feed it to isDeviceOnline() for the state dot —
  /// DateTime.parse takes the space separator fine.
  final String? lastSeen;

  final List<SensorOption> sensors;

  const SensorUnitOption({
    required this.id,
    required this.name,
    required this.lastSeen,
    required this.sensors,
  });

  factory SensorUnitOption.fromJson(Map<String, dynamic> json) {
    final String seen = json['unit_last_seen']?.toString().trim() ?? '';

    return SensorUnitOption(
      id: json['unit_id']?.toString().trim() ?? '',
      name: json['unit_name']?.toString().trim() ?? '',
      // '' / 'NULL' both mean "never reported" — same PHP gotcha as
      // vwv_last_seen. isDeviceOnline() treats null as offline.
      lastSeen: (seen.isEmpty || seen.toUpperCase() == 'NULL') ? null : seen,
      sensors: _parseSensors(json['sensor_data']),
    );
  }

  /// Whole reply → the units to list. Defensive throughout: a missing or
  /// malformed `sensor_units` yields an empty list rather than throwing, and
  /// non-map entries are skipped.
  static List<SensorUnitOption> listFromResponse(Map<String, dynamic> json) {
    final raw = json['sensor_units'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => SensorUnitOption.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// `sensor_data` is a real JSON array in this payload — unlike the pushes,
  /// where it arrives as an escaped string.
  static List<SensorOption> _parseSensors(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => SensorOption.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }
}