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
//
// TWO PAYLOAD SHAPES, TWO FACTORIES:
//   - fromJson        CLOUD  device_basic_detail push (via Ratchet server)
//                     keys: id / unit_name / unit_version / unit_last_seen /
//                           no_sensors / sensor_data
//   - fromDirectJson  DIRECT sensor_unit_info reply (ESP32 AP mode)
//                     keys: device_id / device_name / no_sensors / data
//                     No version or last_seen fields — the ESP32 doesn't
//                     send them, so version falls back to a static label
//                     and lastSeen stays null (screen must NOT run the
//                     30s online check in direct mode).
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
  final String name;       // unit_name (cloud) / device_name (direct)
  final String version;    // unit_version  e.g. "Sensor unit v1.0"
  final String? lastSeen;  // unit_last_seen (raw server string; null in direct)
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

  /// CLOUD payload — device_basic_detail push from the Ratchet server.
  /// Architecture Doc v3, section B "WiFi Sensor Unit Details Screen":
  /// { "event":"device_basic_detail", "id":"SU...", "unit_name":"garden 1",
  ///   "unit_version":"Sensor unit v1.0", "unit_last_seen":"...",
  ///   "no_sensors":"3", "sensor_data":"[{...}]" }
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

  /// DIRECT payload — sensor_unit_info reply from the ESP32 in AP mode.
  /// Architecture Doc v3, "Vortex Sensor Unit / Details Screen":
  /// { "event":"sensor_unit_info", "device_id":"SU202601003",
  ///   "device_name":"garden 1", "timestamp":"...",
  ///   "no_sensors":"3", "data":"[{...}]" }
  /// 
  /// `data` is the same escaped-JSON-string trick as cloud `sensor_data`,
  /// so it reuses _parseSensors unchanged. version/lastSeen are not sent
  /// in direct mode: version gets a static fallback label, lastSeen null.
  factory SensorUnit.fromDirectJson(Map<String, dynamic> json) {
    return SensorUnit(
      id: json['device_id']?.toString() ?? '',
      name: json['device_name']?.toString() ?? '',
      version: 'Sensor unit',        // not sent over direct link
      lastSeen: null,                // not sent over direct link
      sensorCount: _parseInt(json['no_sensors']),
      sensors: _parseSensors(json['data']),
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

  // -- sensor_data / data is an escaped JSON string; decode defensively.
  //    Falls back to an empty list on null / empty / malformed input instead
  //    of throwing. Also tolerates the device ever sending a real List
  //    instead of a String.
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