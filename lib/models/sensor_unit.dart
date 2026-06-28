import 'dart:convert';

// =============================================================================
// SENSOR UNIT MODEL
// =============================================================================
// A WiFi sensor unit (device id starts with "SU"). Mirrors ValveDevice in
// style, but the detail payload is messier than the valve's, so fromJson owns
// the cleanup:
//   - no_sensors  arrives as a String ("3")         -> parsed to int
//   - sensor_data arrives as an ESCAPED JSON STRING  -> decoded to List<Sensor>
//     (same trick the valve schedule uses). Parsing is defensive: a missing or
//     malformed payload yields an empty list instead of throwing.
// =============================================================================

/// One reading inside a sensor unit (Temperature, Humidity, Moisture, ...).
class Sensor {
  final String id;     // sensor_id    e.g. "SU202601003_S01"
  final String type;   // sensor_type  e.g. "Temperature"
  final String name;   // sensor_name  (editable tag name) e.g. "Temp 1"
  final String value;  // sensor_value e.g. "25" (kept as String; format varies)

  const Sensor({
    required this.id,
    required this.type,
    required this.name,
    required this.value,
  });

  factory Sensor.fromJson(Map<String, dynamic> json) {
    return Sensor(
      id: json['sensor_id']?.toString() ?? '',
      type: json['sensor_type']?.toString() ?? '',
      name: json['sensor_name']?.toString() ?? '',
      value: json['sensor_value']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'sensor_id': id,
        'sensor_type': type,
        'sensor_name': name,
        'sensor_value': value,
      };
}

class SensorUnit {
  final String id;         // "SU202601003"
  final String name;       // unit_name
  final String version;    // unit_version  e.g. "Sensor unit v1.0"
  final String? lastSeen;  // unit_last_seen (raw server string)
  final int sensorCount;   // no_sensors (server sends a String)
  final List<Sensor> sensors;

  const SensorUnit({
    required this.id,
    required this.name,
    required this.version,
    this.lastSeen,
    this.sensorCount = 0,
    this.sensors = const [],
  });

  factory SensorUnit.fromJson(Map<String, dynamic> json) {
    return SensorUnit(
      id: json['id']?.toString() ?? '',
      name: json['unit_name']?.toString() ?? '',
      version: json['unit_version']?.toString() ?? '',
      lastSeen: json['unit_last_seen']?.toString(),
      sensorCount: _parseInt(json['no_sensors']),
      sensors: _parseSensors(json['sensor_data']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'unit_name': name,
        'unit_version': version,
        'unit_last_seen': lastSeen,
        'no_sensors': sensorCount,
        'sensor_data': sensors.map((s) => s.toJson()).toList(),
      };

  // -- no_sensors comes through as a String like "3" --
  static int _parseInt(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  // -- sensor_data is an escaped JSON string; decode defensively. Falls back
  //    to an empty list on null / empty / malformed input instead of throwing.
  //    Also tolerates the server ever sending a real List instead of a String.
  static List<Sensor> _parseSensors(dynamic raw) {
    if (raw == null) return const [];

    dynamic decoded = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((m) => Sensor.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    return const [];
  }
}