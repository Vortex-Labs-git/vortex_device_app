import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/smart_plug.dart';
import '../utils/app_log.dart';
import 'device_control_api.dart' show DeviceApiResult, DeviceControlApi, SensorUnitsResult;

// =============================================================================
// PLUG CONTROL API
// =============================================================================
// Every REST call to control_plug.php — the smart-plug sibling of
// DeviceControlApi (control_device.php). Pure networking: no BuildContext, no
// widgets. Callers get the same DeviceApiResult the valve screen uses.
//
//   set_plug_basic     plug name + per base: name, ON/OFF, mode flags
//   set_plug_schedule  per base: schedule_info
//   set_plug_sensor    per base: sensor_rule + sensor_data
//   get_user_sensors   the account's sensor units, for the sensor picker
//
// THE SERVER WANTS EVERY BASE, EVERY TIME. Each message carries base_A and (on
// a dual plug) base_B, even when the user touched only one of them. So every
// call here takes the CURRENT state of the whole plug, changes one thing, and
// sends it all. A single plug sends base_A only.
// =============================================================================

class PlugControlApi {
  PlugControlApi._();

  static const String controlEndpoint =
      'https://vortexlabsofficial.com/device_app/control_plug.php';

  // ---------------------------------------------------------------------------
  // set_plug_basic
  // ---------------------------------------------------------------------------

  /// Sends [plug] as-is. The helpers below build the changed plug and call
  /// this; use it directly when several fields change at once.
  static Future<DeviceApiResult> setPlugBasic(SmartPlug plug) {
    return _post(
      logTag: 'Plug Basic',
      body: {
        'event': 'set_plug_basic',
        'timestamp': _now(),
        ...plug.toBasicJson(),
      },
    );
  }

  /// Manual ON/OFF of one base. Writes usr_state; the plug then switches and
  /// reports the new `state` (which PlugConfirmationController waits for).
  static Future<DeviceApiResult> setBaseState({
    required SmartPlug plug,
    required PlugBaseId base,
    required bool on,
  }) {
    return setPlugBasic(
      plug.withBase(plug.base(base).copyWith(usrState: on)),
    );
  }

  /// Control method of one base. Both false = manual.
  static Future<DeviceApiResult> setBaseMode({
    required SmartPlug plug,
    required PlugBaseId base,
    required bool schedule,
    required bool sensor,
  }) {
    return setPlugBasic(
      plug.withBase(
        plug.base(base).copyWith(scheduleCtrl: schedule, sensorCtrl: sensor),
      ),
    );
  }

  /// Renames the plug itself (plug_name).
  static Future<DeviceApiResult> renamePlug({
    required SmartPlug plug,
    required String newName,
  }) {
    return setPlugBasic(plug.copyWith(name: newName.trim()));
  }

  /// Renames one base. An empty name is refused here — '' is what marks a
  /// base as NOT existing, so sending it would turn a dual plug single.
  static Future<DeviceApiResult> renameBase({
    required SmartPlug plug,
    required PlugBaseId base,
    required String newName,
  }) async {
    final name = newName.trim();
    if (name.isEmpty) {
      return const DeviceApiResult.serverError('Base name cannot be empty');
    }
    return setPlugBasic(plug.withBase(plug.base(base).copyWith(name: name)));
  }

  // ---------------------------------------------------------------------------
  // set_plug_schedule
  // ---------------------------------------------------------------------------

  /// Replaces the schedules of every base of [plug].
  ///
  /// [controls] must hold the CURRENT setup of every base, with the edited
  /// one swapped in — a base missing from the map is sent as an empty
  /// schedule, which clears it on the server.
  static Future<DeviceApiResult> savePlugSchedule({
    required SmartPlug plug,
    required Map<PlugBaseId, PlugBaseControl> controls,
  }) {
    return _post(
      logTag: 'Plug Schedule',
      body: {
        'event': 'set_plug_schedule',
        'timestamp': _now(),
        'device_id': plug.id,
        'set_sheduledata': {   // (sic) — the server's key spelling
          for (final b in plug.bases)
            b.id.key: _controlFor(controls, b.id).toScheduleJson(),
        },
      },
    );
  }

  // ---------------------------------------------------------------------------
  // set_plug_sensor
  // ---------------------------------------------------------------------------

  /// Replaces the sensor binding + rules of every base of [plug].
  ///
  /// Same rule as savePlugSchedule: pass every base's current setup. A base
  /// with no sensor goes out as empty sensor_rule / sensor_data, which is how
  /// a sensor is unbound.
  static Future<DeviceApiResult> savePlugSensor({
    required SmartPlug plug,
    required Map<PlugBaseId, PlugBaseControl> controls,
  }) {
    return _post(
      logTag: 'Plug Sensor',
      body: {
        'event': 'set_plug_sensor',
        'timestamp': _now(),
        'device_id': plug.id,
        'set_sensordata': {
          for (final b in plug.bases)
            b.id.key: _controlFor(controls, b.id).toSensorJson(),
        },
      },
    );
  }

  /// Unbinds the sensor of ONE base; the other base is resent unchanged.
  static Future<DeviceApiResult> clearBaseSensor({
    required SmartPlug plug,
    required PlugBaseId base,
    required Map<PlugBaseId, PlugBaseControl> controls,
  }) {
    final cleared = _controlFor(controls, base)
        .copyWith(clearSensor: true, sensorRules: const []);
    return savePlugSensor(
      plug: plug,
      controls: {...controls, base: cleared},
    );
  }

  // ---------------------------------------------------------------------------
  // get_user_sensors
  // ---------------------------------------------------------------------------

  /// Every sensor unit on this account, for the "+ Add sensor" picker. Same
  /// request / reply as the valve's — only the endpoint differs.
  static Future<SensorUnitsResult> getUserSensors({
    required Object? userId,
    required Object? deviceId,
  }) {
    return DeviceControlApi.getUserSensors(
      userId: userId,
      deviceId: deviceId,
      endpoint: controlEndpoint,
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static PlugBaseControl _controlFor(
    Map<PlugBaseId, PlugBaseControl> controls,
    PlugBaseId id,
  ) {
    final control = controls[id];
    if (control == null) {
      logD("⚠️ Plug API: no control passed for ${id.key} — sending it empty");
      return PlugBaseControl.empty(id);
    }
    return control;
  }

  /// Same contract as DeviceControlApi._post: success ⇔ `success: true`.
  static Future<DeviceApiResult> _post({
    required Map<String, dynamic> body,
    required String logTag,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      logD("📤 $logTag Request: ${jsonEncode(body)}");

      final response = await http.post(
        Uri.parse(controlEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      logD("$logTag Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result is Map && result['success'] == true) {
        return const DeviceApiResult.ok();
      }
      return DeviceApiResult.serverError(
        result is Map ? result['message']?.toString() : 'Unexpected reply',
      );
    } catch (e) {
      logD("$logTag Error: $e");
      return DeviceApiResult.connectionFailed(e);
    }
  }
}
