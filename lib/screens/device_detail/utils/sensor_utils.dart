import '../../../models/valve_device.dart';

// =============================================================================
// SENSOR UTILS
// =============================================================================
// Parser for the "Sensor" block of the `device_schedule` payload — the sibling
// of parseSchedulePayload() in schedule_utils.dart, reading the SAME message.
// Pure functions: no widgets, no state.
// =============================================================================

/// Angle options offered in the add/edit rule dialog's slider (0–90, in 15°
/// steps) — kept here so the dialog and any future validation agree.
const int kSensorAngleMin = 0;
const int kSensorAngleMax = 90;

/// Everything the sensor card needs out of one push.
class SensorPayload {
  /// null when the device has no sensor bound.
  final SensorReading? reading;

  /// Empty when the device has a sensor but no rules yet.
  final List<SensorRule> rules;

  const SensorPayload({required this.reading, required this.rules});
}

/// Parses the "Sensor" block out of a `device_schedule` event.
///
/// Server sends:
///   {"event":"device_schedule", "device_id":"...",
///    "schedule":{...},
///    "Sensor":{"sensor_rule":{"0-30":"0"}, "sensor_data":{...}}}
///
/// Note the capital S on "Sensor" — that is what the server sends; lowercase
/// is accepted too so a backend tidy-up can't silently blank the card.
///
/// Returns null when the payload carries no "Sensor" block at all, so the
/// caller keeps whatever it already has. A present-but-empty block returns a
/// SensorPayload with null reading / empty rules — that genuinely means "this
/// valve has no sensor", and the card should fall back to its empty state.
SensorPayload? parseSensorPayload(Map<String, dynamic> data) {
  try {
    final sensorBlock = data['Sensor'] ?? data['sensor'];
    if (sensorBlock is! Map) return null;

    final block = Map<String, dynamic>.from(sensorBlock);

    // -- sensor_data --
    SensorReading? reading;
    final rawData = block['sensor_data'];
    if (rawData is Map && rawData.isNotEmpty) {
      reading = SensorReading.fromJson(Map<String, dynamic>.from(rawData));
      // A block with no unit is not a sensor, whatever else it carries.
      if (reading.unitId.isEmpty && reading.sensorId.isEmpty) reading = null;
    }

    // -- sensor_rule --
    final rawRules = block['sensor_rule'];
    final rules = rawRules is Map
        ? SensorRule.listFromJson(Map<String, dynamic>.from(rawRules))
        : <SensorRule>[];

    return SensorPayload(reading: reading, rules: rules);
  } catch (e) {
    print("❌ Error parsing sensor data: $e");
    return null;
  }
}