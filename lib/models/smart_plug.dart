import 'dart:convert';

import 'valve_device.dart' show SensorReading;

// =============================================================================
// SMART PLUG MODELS
// =============================================================================
// A WiFi smart plug (device id starts with "SP"). Two hardware versions:
//
//   single plug → base_A only
//   dual plug   → base_A + base_B
//
// base_A is always there. base_B is VALID only when its name is non-empty —
// a single plug still sends a base_B block, just with name "". That is the
// one and only rule for single vs dual (see PlugBase.isValid).
//
// Every base is controlled on its own: its own ON/OFF state, its own mode
// flags (sch_ctrl / sen_ctrl), its own schedule and its own sensor.
//
// TWO PUSHES, TWO MODELS (same split as the valve):
//   device_basic_detail → SmartPlug        name, version, last_seen, bases
//   device_schedule     → PlugControl      per-base schedule + sensor
//
//   {"event":"device_basic_detail", "device_id":"SP202601003",
//    "data":{"id":"SP202601003", "plug_name":"plug_1", "plug_version":"v_1.0",
//            "plug_last_seen":"",
//            "base_A":{"name":"base 1","state":false,"usr_state":false,
//                      "sch_ctrl":false,"sen_ctrl":false},
//            "base_B":{"name":"base 2","state":false,"usr_state":false,
//                      "sch_ctrl":false,"sen_ctrl":false},
//
//   state      = what the PLUG reports (shown in the UI)
//   usr_state  = the user's COMMAND (written by set_plug_basic, read by the plug)
//            "wattage":{"base_A":0,"base_B":0}}}
//
//   {"event":"device_schedule", "device_id":"SP202601003",
//    "base_A":{"schedule":{"schedule_info":"[{\"day\":\"Monday\",
//                                             \"08:00-08:20\":\"1\",
//                                             \"step\":\"600:0\"}]"},
//              "Sensor":{"sensor_rule":{"0-30":"1"}, "sensor_data":{...}}},
//    "base_B":{...}}
//
// The live sensor reading (SensorReading) is shared with the valve — same
// wire shape, same card. Everything else here is plug-specific because the
// valve talks in angles and the plug talks in ON/OFF.
//
// Pure Dart, no Flutter imports — widgets and REST live elsewhere.
// =============================================================================

// -----------------------------------------------------------------------------
// Shared helpers
// -----------------------------------------------------------------------------

/// Flags arrive as true / 1 / '1' / 'true' depending on the source.
bool _readFlag(Object? raw) =>
    raw == true || raw == 1 || raw == '1' || raw.toString().toLowerCase() == 'true';

/// Trims, and collapses null / '' / the literal 'NULL' to '' (PHP serializes
/// SQL NULL as the string — same gotcha Device and SensorReading handle).
String _clean(Object? raw) {
  final String text = raw?.toString().trim() ?? '';
  return text.toUpperCase() == 'NULL' ? '' : text;
}

Map<String, dynamic>? _asMap(Object? raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : null;

/// ON/OFF on the wire is a string: "1" = ON, "0" = OFF. Anything non-zero
/// reads as ON so an old valve-style value ("90", "75") can't read as OFF.
bool _readOnOff(Object? raw) => (int.tryParse(_clean(raw)) ?? 0) != 0;
String _writeOnOff(bool on) => on ? '1' : '0';

// =============================================================================
// PLUG BASE (one socket)
// =============================================================================

/// Which socket. [key] is the wire key used in every payload.
enum PlugBaseId {
  a('base_A', 'A'),
  b('base_B', 'B');

  final String key;
  final String letter;
  const PlugBaseId(this.key, this.letter);
}

/// How one base is being driven right now. Derived from sch_ctrl / sen_ctrl —
/// both false means manual.
enum PlugControlMode { manual, schedule, sensor, scheduleAndSensor }

/// Live state of one socket, from device_basic_detail.
class PlugBase {
  final PlugBaseId id;

  /// User-given socket name. '' means this base does not exist (single plug).
  final String name;

  /// true = ON. What the PLUG reports it is doing right now.
  final bool state;

  /// usr_state — what the USER last asked for in manual mode. Can differ from
  /// [state] for a moment after a command, until the plug catches up. This is
  /// the field set_plug_basic writes, so the untouched base is resent with
  /// its own usrState (NOT its reported state — that could cancel a command
  /// the plug hasn't carried out yet).
  final bool usrState;

  /// sch_ctrl — base follows its schedule.
  final bool scheduleCtrl;

  /// sen_ctrl — base follows its sensor.
  final bool sensorCtrl;

  /// Live draw from the `wattage` block, in watts. 0 when not reported.
  final double wattage;

  const PlugBase({
    required this.id,
    required this.name,
    required this.state,
    bool? usrState,
    required this.scheduleCtrl,
    required this.sensorCtrl,
    this.wattage = 0,
  }) : usrState = usrState ?? state;

  /// An empty placeholder — used when the block is missing entirely.
  const PlugBase.absent(this.id)
      : name = '',
        state = false,
        usrState = false,
        scheduleCtrl = false,
        sensorCtrl = false,
        wattage = 0;

  factory PlugBase.fromJson(
    PlugBaseId id,
    Map<String, dynamic>? json, {
    Object? wattage,
  }) {
    if (json == null) return PlugBase.absent(id);
    return PlugBase(
      id: id,
      name: _clean(json['name']),
      state: _readFlag(json['state']),
      // Older pushes without usr_state fall back to the reported state.
      usrState: json.containsKey('usr_state')
          ? _readFlag(json['usr_state'])
          : null,
      scheduleCtrl: _readFlag(json['sch_ctrl']),
      sensorCtrl: _readFlag(json['sen_ctrl']),
      wattage: double.tryParse(_clean(wattage)) ?? 0,
    );
  }

  /// The single-vs-dual rule: a base with no name is not a real socket.
  bool get isValid => name.isNotEmpty;

  /// True when schedule and/or sensor is driving the base — manual ON/OFF is
  /// hidden in that case.
  bool get isAutomated => scheduleCtrl || sensorCtrl;

  PlugControlMode get controlMode {
    if (scheduleCtrl && sensorCtrl) return PlugControlMode.scheduleAndSensor;
    if (scheduleCtrl) return PlugControlMode.schedule;
    if (sensorCtrl) return PlugControlMode.sensor;
    return PlugControlMode.manual;
  }

  /// Wattage for display: "0 W", "12.5 W", "1500 W".
  String get wattageLabel {
    final w = wattage == wattage.roundToDouble()
        ? wattage.toStringAsFixed(0)
        : wattage.toStringAsFixed(1);
    return '$w W';
  }

  /// This base's block inside set_plug_basic:
  ///   {"set_controller":{"schedule":true,"sensor":false},
  ///    "set_data":{"name":"plug_1","usr_state":true}}
  ///
  /// control_plug.php writes `usr_state` (only while schedule and sensor are
  /// both off); it ignores a `state` key, so don't send one.
  Map<String, dynamic> toBasicJson() => {
        'set_controller': {
          'schedule': scheduleCtrl,
          'sensor': sensorCtrl,
        },
        'set_data': {
          'name': name,
          'usr_state': usrState,
        },
      };

  PlugBase copyWith({
    String? name,
    bool? state,
    bool? usrState,
    bool? scheduleCtrl,
    bool? sensorCtrl,
    double? wattage,
  }) =>
      PlugBase(
        id: id,
        name: name ?? this.name,
        state: state ?? this.state,
        usrState: usrState ?? this.usrState,
        scheduleCtrl: scheduleCtrl ?? this.scheduleCtrl,
        sensorCtrl: sensorCtrl ?? this.sensorCtrl,
        wattage: wattage ?? this.wattage,
      );

  @override
  String toString() => 'PlugBase(${id.letter} "$name" '
      '${state ? 'ON' : 'OFF'} ${controlMode.name} $wattageLabel)';
}

// =============================================================================
// SMART PLUG (device_basic_detail)
// =============================================================================

class SmartPlug {
  final String id;          // "SP202601003"
  final String userId;
  final String name;        // plug_name
  final String version;     // plug_version, e.g. "v_1.0"

  /// Raw server timestamp, or null when never seen. Feed it to
  /// isDeviceOnline() — same rule as the valve.
  final String? lastSeen;

  final PlugBase baseA;

  /// Always present as an object; check [isDual] (baseB.isValid) before
  /// drawing it.
  final PlugBase baseB;

  const SmartPlug({
    required this.id,
    required this.userId,
    required this.name,
    required this.version,
    required this.lastSeen,
    required this.baseA,
    required this.baseB,
  });

  /// [json] is the `data` object of device_basic_detail (WebSocketService
  /// already unwraps it). A flat map without `data` works too.
  factory SmartPlug.fromJson(Map<String, dynamic> json) {
    final data = _asMap(json['data']) ?? json;
    final wattage = _asMap(data['wattage']) ?? const {};
    final seen = _clean(data['plug_last_seen'] ?? data['last_seen']);

    return SmartPlug(
      id: _clean(data['id'] ?? json['device_id']),
      userId: _clean(data['user_id']),
      name: _clean(data['plug_name'] ?? data['name']),
      version: _clean(data['plug_version'] ?? data['version']),
      lastSeen: seen.isEmpty ? null : seen,
      baseA: PlugBase.fromJson(
        PlugBaseId.a,
        _asMap(data[PlugBaseId.a.key]),
        wattage: wattage[PlugBaseId.a.key],
      ),
      baseB: PlugBase.fromJson(
        PlugBaseId.b,
        _asMap(data[PlugBaseId.b.key]),
        wattage: wattage[PlugBaseId.b.key],
      ),
    );
  }

  /// Dual plug ⇔ base_B has a name.
  bool get isDual => baseB.isValid;

  /// The bases that actually exist, in order — what the UI iterates.
  List<PlugBase> get bases => isDual ? [baseA, baseB] : [baseA];

  PlugBase base(PlugBaseId id) => id == PlugBaseId.a ? baseA : baseB;

  /// Sum of the valid bases' wattage.
  double get totalWattage =>
      bases.fold(0.0, (sum, b) => sum + b.wattage);

  /// Replace one base, keep everything else.
  SmartPlug withBase(PlugBase updated) => copyWith(
        baseA: updated.id == PlugBaseId.a ? updated : null,
        baseB: updated.id == PlugBaseId.b ? updated : null,
      );

  /// The whole set_plug_basic body minus event/timestamp (the API layer adds
  /// those). The server expects BOTH bases every time, so the untouched one
  /// is resent with its current values. A single plug sends base_A only.
  ///
  /// Only VALID bases go out: the server would write a blank name straight
  /// into base_X_name, and '' is what marks a base as missing. (Before the
  /// first device_basic_detail push base_A is still the empty placeholder,
  /// so this also keeps an early rename from blanking it.)
  Map<String, dynamic> toBasicJson() => {
        'device_id': id,
        'plug_name': name,
        if (baseA.isValid) PlugBaseId.a.key: baseA.toBasicJson(),
        if (baseB.isValid) PlugBaseId.b.key: baseB.toBasicJson(),
      };

  SmartPlug copyWith({
    String? name,
    String? lastSeen,
    PlugBase? baseA,
    PlugBase? baseB,
  }) =>
      SmartPlug(
        id: id,
        userId: userId,
        name: name ?? this.name,
        version: version,
        lastSeen: lastSeen ?? this.lastSeen,
        baseA: baseA ?? this.baseA,
        baseB: baseB ?? this.baseB,
      );

  @override
  String toString() =>
      'SmartPlug($id "$name" ${isDual ? 'dual' : 'single'} $baseA'
      '${isDual ? ' $baseB' : ''})';
}

// =============================================================================
// PLUG SCHEDULE ENTRY
// =============================================================================
// One schedule row: a day, a time range, ON/OFF, and the advanced "step".
//
//   {"day":"Monday", "08:00-08:10":"1", "step":"60:60"}
//
// STEP = "<on seconds>:<off seconds>", cycled inside the time range:
//   600 s range, "60:60"  → ON 60 s, OFF 60 s, ON 60 s, … until 08:10
//   600 s range, "600:0"  → ON for the whole range (the DEFAULT)
// off = 0 means "continuous" — the base just stays ON for the whole range.
// =============================================================================

class PlugScheduleEntry {
  final String day;    // "Every day" | "Monday" | ...
  final String start;  // "08:00"
  final String end;    // "08:10"

  /// ON/OFF for the range. Wire "1" / "0".
  final bool state;

  /// Step cycle, in seconds. [offSeconds] == 0 means continuous.
  final int onSeconds;
  final int offSeconds;

  const PlugScheduleEntry({
    required this.day,
    required this.start,
    required this.end,
    this.state = true,
    required this.onSeconds,
    this.offSeconds = 0,
  });

  /// A new entry with the default step (ON for the whole range).
  factory PlugScheduleEntry.continuous({
    required String day,
    required String start,
    required String end,
    bool state = true,
  }) =>
      PlugScheduleEntry(
        day: day,
        start: start,
        end: end,
        state: state,
        onSeconds: durationSecondsOf(start, end),
        offSeconds: 0,
      );

  /// "08:00-08:10" — the wire format's key.
  String get timeRange => '$start-$end';

  /// "600:0" — the wire format's step value.
  String get step => '$onSeconds:$offSeconds';

  /// No OFF phase → ON for the whole range (the default / non-advanced case).
  bool get isContinuous => offSeconds <= 0;

  /// Range length in seconds.
  int get durationSeconds => durationSecondsOf(start, end);

  /// Range length for "HH:mm"–"HH:mm". An end at or before the start wraps
  /// past midnight (22:00-02:00 → 4 h).
  static int durationSecondsOf(String start, String end) {
    final s = _minutes(start);
    final e = _minutes(end);
    if (s == null || e == null) return 0;
    final diff = e > s ? e - s : e + 24 * 60 - s;
    return diff * 60;
  }

  static int? _minutes(String hhmm) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static final RegExp _timeRangeKey =
      RegExp(r'^\s*(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*$');

  static final RegExp _stepValue = RegExp(r'^\s*(\d+)\s*:\s*(\d+)\s*$');

  /// Wire → model. One object may hold several time-range keys; they all
  /// share the object's `day` and `step`. A missing / bad step falls back to
  /// the default (continuous for that range).
  static List<PlugScheduleEntry> listFromJson(Map<String, dynamic> json) {
    final day = _clean(json['day']);
    final stepMatch = _stepValue.firstMatch(_clean(json['step']));
    final entries = <PlugScheduleEntry>[];

    json.forEach((key, value) {
      final match = _timeRangeKey.firstMatch(key);
      if (match == null) return; // 'day', 'step', anything unrecognised

      final start = match.group(1)!;
      final end = match.group(2)!;

      int on = durationSecondsOf(start, end);
      int off = 0;
      if (stepMatch != null) {
        on = int.tryParse(stepMatch.group(1)!) ?? on;
        off = int.tryParse(stepMatch.group(2)!) ?? 0;
      }

      entries.add(PlugScheduleEntry(
        day: day,
        start: start,
        end: end,
        state: _readOnOff(value),
        onSeconds: on,
        offSeconds: off,
      ));
    });

    return entries;
  }

  /// Model → wire.
  Map<String, dynamic> toJson() => {
        'day': day,
        timeRange: _writeOnOff(state),
        'step': step,
      };

  /// Changing the time range of a CONTINUOUS entry keeps it continuous, so
  /// its ON phase follows the new length. A custom step is left alone.
  PlugScheduleEntry copyWith({
    String? day,
    String? start,
    String? end,
    bool? state,
    int? onSeconds,
    int? offSeconds,
  }) {
    final newStart = start ?? this.start;
    final newEnd = end ?? this.end;
    final rangeChanged = newStart != this.start || newEnd != this.end;
    final stepGiven = onSeconds != null || offSeconds != null;

    return PlugScheduleEntry(
      day: day ?? this.day,
      start: newStart,
      end: newEnd,
      state: state ?? this.state,
      onSeconds: (isContinuous && rangeChanged && !stepGiven)
          ? durationSecondsOf(newStart, newEnd)
          : (onSeconds ?? this.onSeconds),
      offSeconds: offSeconds ?? this.offSeconds,
    );
  }

  /// Whole list → the `schedule_info` STRING the server expects (a JSON
  /// array encoded as text, like the valve's).
  static String encodeList(List<PlugScheduleEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());

  /// `schedule_info` → list. Takes the escaped string or an already-decoded
  /// list. Returns [] for empty, null when the value is unreadable.
  static List<PlugScheduleEntry>? decodeList(Object? raw) {
    try {
      if (raw == null) return [];
      final List<dynamic> list;
      if (raw is String) {
        if (raw.trim().isEmpty) return [];
        final decoded = jsonDecode(raw);
        if (decoded is! List) return null;
        list = decoded;
      } else if (raw is List) {
        list = raw;
      } else {
        return null;
      }
      return list
          .whereType<Map>()
          .expand((m) => listFromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return null;
    }
  }
}

// =============================================================================
// PLUG SENSOR RULE
// =============================================================================
// One row of a base's sensor table: a reading range → ON/OFF.
//   "sensor_rule": {"0-30": "1", "31-60": "0"}
// Same key shape as the valve's SensorRule, but the value is ON/OFF instead of
// an angle.
// =============================================================================

class PlugSensorRule {
  final int from;
  final int to;
  final bool state; // true = ON

  const PlugSensorRule({
    required this.from,
    required this.to,
    required this.state,
  });

  /// "0-30" — the wire key.
  String get range => '$from-$to';

  /// "0 – 30" — for the table.
  String get rangeLabel => '$from – $to';

  bool overlaps(PlugSensorRule other) => from <= other.to && other.from <= to;

  static final RegExp _rangeKey = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$');

  /// Wire → model, sorted low to high. Unrecognised keys are skipped.
  static List<PlugSensorRule> listFromJson(Map<String, dynamic> json) {
    final rules = <PlugSensorRule>[];
    json.forEach((key, value) {
      final match = _rangeKey.firstMatch(key);
      if (match == null) return;
      rules.add(PlugSensorRule(
        from: int.tryParse(match.group(1)!) ?? 0,
        to: int.tryParse(match.group(2)!) ?? 0,
        state: _readOnOff(value),
      ));
    });
    rules.sort((a, b) => a.from.compareTo(b.from));
    return rules;
  }

  /// Whole table → the sensor_rule OBJECT.
  static Map<String, dynamic> mapFromList(List<PlugSensorRule> rules) => {
        for (final r in rules) r.range: _writeOnOff(r.state),
      };

  PlugSensorRule copyWith({int? from, int? to, bool? state}) => PlugSensorRule(
        from: from ?? this.from,
        to: to ?? this.to,
        state: state ?? this.state,
      );
}

// =============================================================================
// PLUG CONTROL (device_schedule)
// =============================================================================

/// Schedule + sensor setup of ONE base.
class PlugBaseControl {
  final PlugBaseId id;

  final List<PlugScheduleEntry> schedules;

  /// null when no sensor is bound to this base.
  final SensorReading? sensor;

  final List<PlugSensorRule> sensorRules;

  const PlugBaseControl({
    required this.id,
    this.schedules = const [],
    this.sensor,
    this.sensorRules = const [],
  });

  const PlugBaseControl.empty(this.id)
      : schedules = const [],
        sensor = null,
        sensorRules = const [];

  /// [json] is one base block:
  ///   {"schedule":{"schedule_info":"[...]"}, "Sensor":{...}}
  /// Returns null when the block is missing, so the caller keeps what it has.
  static PlugBaseControl? fromJson(PlugBaseId id, Map<String, dynamic>? json) {
    if (json == null) return null;

    // -- schedule --
    final scheduleBlock = _asMap(json['schedule']);
    final schedules =
        PlugScheduleEntry.decodeList(scheduleBlock?['schedule_info']) ??
            const <PlugScheduleEntry>[];

    // -- Sensor (capital S from the server; lowercase accepted too) --
    final sensorBlock = _asMap(json['Sensor'] ?? json['sensor']);
    SensorReading? reading;
    final rawData = _asMap(sensorBlock?['sensor_data']);
    if (rawData != null && rawData.isNotEmpty) {
      reading = SensorReading.fromJson(rawData);
      // A block with no unit is not a sensor, whatever else it carries.
      if (reading.unitId.isEmpty && reading.sensorId.isEmpty) reading = null;
    }
    final rawRules = _asMap(sensorBlock?['sensor_rule']);
    final rules = rawRules == null
        ? const <PlugSensorRule>[]
        : PlugSensorRule.listFromJson(rawRules);

    return PlugBaseControl(
      id: id,
      schedules: schedules,
      sensor: reading,
      sensorRules: rules,
    );
  }

  /// This base's block inside set_plug_schedule → set_sheduledata.
  Map<String, dynamic> toScheduleJson() => {
        'schedule_info': PlugScheduleEntry.encodeList(schedules),
      };

  /// This base's block inside set_plug_sensor → set_sensordata. An unbound
  /// base sends empty objects, which clears its sensor.
  Map<String, dynamic> toSensorJson() => {
        'sensor_rule': PlugSensorRule.mapFromList(sensorRules),
        'sensor_data': sensor?.toJson() ?? const <String, dynamic>{},
      };

  PlugBaseControl copyWith({
    List<PlugScheduleEntry>? schedules,
    SensorReading? sensor,
    bool clearSensor = false,
    List<PlugSensorRule>? sensorRules,
  }) =>
      PlugBaseControl(
        id: id,
        schedules: schedules ?? this.schedules,
        sensor: clearSensor ? null : (sensor ?? this.sensor),
        sensorRules: sensorRules ?? this.sensorRules,
      );
}

/// A whole device_schedule push, split per base.
class PlugControl {
  /// null = that base's block was missing from the push (keep what you have).
  final PlugBaseControl? baseA;
  final PlugBaseControl? baseB;

  const PlugControl({this.baseA, this.baseB});

  factory PlugControl.fromJson(Map<String, dynamic> json) => PlugControl(
        baseA: PlugBaseControl.fromJson(
            PlugBaseId.a, _asMap(json[PlugBaseId.a.key])),
        baseB: PlugBaseControl.fromJson(
            PlugBaseId.b, _asMap(json[PlugBaseId.b.key])),
      );

  PlugBaseControl? base(PlugBaseId id) => id == PlugBaseId.a ? baseA : baseB;
}
