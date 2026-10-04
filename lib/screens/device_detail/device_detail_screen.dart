import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/device_control_api.dart';
import '../../services/auth_service.dart';
import '../motor_calibration_screen.dart';
import '../../models/valve_device.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass/glass.dart';
import '../../controllers/device_repository.dart';

// Controllers (live data + confirmation wait)
import 'controllers/device_feeds.dart';
import 'controllers/valve_confirmation_controller.dart';

// Dialogs
import 'dialogs/edit_device_name_dialog.dart';
import 'dialogs/schedule_dialogs.dart';
import 'dialogs/sensor_dialogs.dart';
import 'dialogs/wifi_credentials_dialog.dart';

// Pure helpers
import 'utils/schedule_utils.dart';
import 'utils/sensor_utils.dart';
import 'utils/valve_utils.dart';

// Card widgets
import 'widgets/change_wifi_button.dart';
import 'widgets/control_tabs.dart';
import 'widgets/motor_calibration_button.dart';
import 'widgets/runs_on_card.dart';
import 'widgets/save_pill.dart';
import 'widgets/schedule_card.dart';
import 'widgets/sensor_card.dart';
import 'widgets/valve_control_card.dart';
import 'widgets/valve_header.dart';
import '../../utils/app_log.dart';

// =============================================================================
// DEVICE DETAIL SCREEN
// =============================================================================
// Screen for one valve. It owns the UI state and wires everything together;
// the heavy lifting lives next door:
//
//   services/device_control_api.dart      → REST calls to control_device.php
//   controllers/device_feeds.dart         → WebSocket / ESP32 subscriptions
//   controllers/valve_confirmation_*.dart → "waiting for the valve" countdown
//   dialogs/                              → add-edit schedule, rename, wifi
//   utils/                                → time + angle + payload parsing
//   widgets/                              → the cards this screen composes
//
// Two modes:
//   - Server mode (isDirectMode = false): WebSocket + REST through the cloud
//   - Direct mode (isDirectMode = true):  Talks straight to the ESP32 over
//                                         its AP via EspDirectService
// =============================================================================

class DeviceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData;
  final bool isDirectMode;

  const DeviceDetailScreen({
    super.key,
    required this.deviceData,
    this.isDirectMode = false,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  // ===========================================================================
  // SECTION 1: STATE
  // ===========================================================================

  // -- Device data --
  late Map<String, dynamic> _device;

  // -- Connection state --
  bool _wsConnected = false;

  // -- Control mode: 'manual' | 'schedule' | 'sensor' --
  String _controlMode = 'manual';

  // -- Schedule/Manual mode toggle (synced with user_schedule_ctrl in DB) --
  bool _isScheduleMode = false;
  bool _isSensorMode = false;
  bool _isManualMode = false;
  bool _isAutomateMode = false;   // master switch position (see note below)
  bool _isSwitchingMode = false;

  // -- Valve control (state mode) --
  bool _isUpdating = false;
  bool _valveControlEnabled = true; // ON = state mode, OFF = angle mode

  // -- Angle control (angle mode) --
  double _sliderAngle = 0;
  bool _isAngleUpdating = false;
  bool _userIsEditingAngle = false;
  Timer? _angleEditDebounce;

  // -- Schedule data --
  List<ScheduleEntry> _schedules = []; 
  bool _isSavingSchedule = false;
  bool _schedulesLocallyEdited = false;

    // -- Sensor data (Control by → sensor) --
  SensorReading? _sensorReading;
  List<SensorRule> _sensorRules = [];
  bool _isSavingSensorRules = false;
  bool _sensorRulesLocallyEdited = false;
  bool _isLoadingSensorUnits = false;

  // -- Controllers --
  late final ValveConfirmationController _confirmation;
  ServerDeviceFeed? _serverFeed;
  DirectDeviceFeed? _directFeed;

  // -- Shortcuts --
  bool get _isDirectMode => widget.isDirectMode;

  String get _deviceName =>
      _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown';

  /// Position the valve actually reports, in degrees.
  int get _actualPosition => parseAngle(_device['vwv_pos']);

  /// Where the valve will be once the pending command lands.
  bool get _isValveOpen {
    final pending = _confirmation.targetAngle;
    if (_confirmation.isWaiting && pending != null) {
      return pending >= kValveOpenAngle;
    }
    return _actualPosition >= kValveOpenAngle;
  }

  // ===========================================================================
  // SECTION 2: LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.deviceData);
    logD("🔍 INIT _device = $_device");

    _confirmation = ValveConfirmationController(
      onChanged: () {
        if (mounted) setState(() {});
      },
      onSuccess: () => _showMessage(
        '✅ Valve position confirmed!',
        color: GlassTokens.success,
        duration: const Duration(seconds: 2),
      ),
      onTimeout: _onConfirmationTimeout,
    );

    // Read initial schedule mode from DB field user_schedule_ctrl
    _isScheduleMode = _readScheduleFlag(_device['user_schedule_ctrl']);
    _isSensorMode = _readScheduleFlag(_device['user_sensor_ctrl']);
    _isManualMode = _readScheduleFlag(_device['user_set_pos']);
    _isAutomateMode =  _isScheduleMode || _isSensorMode;

    if (_isDirectMode) {
      // Direct mode: only manual control is allowed; clear cached state so
      // the first ESP32 poll response is the source of truth.
      _controlMode = 'manual';
      _isManualMode = true;
      _isScheduleMode = false;
      _isSensorMode = false;
      _device['vwv_pos'] = null;
      _device['vwv_is_open'] = null;
      _device['vwv_is_close'] = null;
    } else {
      final online = isDeviceOnline(_device['vwv_last_seen']?.toString());
      if (!online) {
        _controlMode = 'schedule';
      } else {
        _controlMode = _isScheduleMode ? 'schedule' : 'manual';
      }
    }

    // Initialize slider angle from DB
    if (_device['vwv_pos'] != null) {
      _sliderAngle = _actualPosition.toDouble();
    }

    if (_isDirectMode) {
      _startDirectFeed();
    } else {
      _startServerFeed();
    }
  }

  @override
  void dispose() {
    _serverFeed?.dispose();
    _directFeed?.dispose();
    _confirmation.dispose();
    _angleEditDebounce?.cancel();
    super.dispose();
  }

  /// `user_schedule_ctrl` arrives as 1, '1' or true depending on the source.
  bool _readScheduleFlag(Object? raw) =>
      raw == 1 || raw == '1' || raw == true;

  // ===========================================================================
  // SECTION 3: LIVE DATA (server WebSocket / ESP32 direct)
  // ===========================================================================

  void _startServerFeed() {
    final feed = ServerDeviceFeed(
      deviceId: _device['id']?.toString(),
      onConnectionChanged: (connected) {
        if (mounted) setState(() => _wsConnected = connected);
      },
      onDeviceUpdate: _onServerDeviceUpdate,
      onScheduleUpdate: _onServerScheduleUpdate,
    );

    _serverFeed = feed;
    _wsConnected = feed.isConnected;
    feed.start();
  }

  void _startDirectFeed() {
    final feed = DirectDeviceFeed(
      device: () => _device,
      onConnectionChanged: (connected) {
        if (mounted) setState(() => _wsConnected = connected);
      },
      onValveData: _onDirectValveData,
    );

    _directFeed = feed;
    _wsConnected = feed.isConnected;
    feed.start();
  }

  void _onServerDeviceUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    setState(() => _device = {..._device, ...data});

    // Sync schedule mode from server (unless we're in the middle of sending a
    // switch ourselves)
    if (!_isSwitchingMode) {
      final serverScheduleMode = _readScheduleFlag(_device['user_schedule_ctrl']);
      final serverSensorMode   = _readScheduleFlag(_device['user_sensor_ctrl']);
      final serverManualMode   = _readScheduleFlag(_device['user_set_pos']);
      if (serverScheduleMode != _isScheduleMode || serverSensorMode != _isSensorMode || serverManualMode != _isManualMode) {
        setState(() {
          _isScheduleMode = serverScheduleMode;
          _isSensorMode   = serverSensorMode;
          _isManualMode = serverManualMode;
          
          final pickingAutomation = _isAutomateMode && !_isScheduleMode && !_isSensorMode;
          if (!pickingAutomation) {
            _isAutomateMode = serverScheduleMode || serverSensorMode;
          }
        });
      }
    }

    // Did vwv_pos catch up to our pending target? (-1 so a missing position
    // can never be mistaken for a real 0°)
    _confirmation.reportPosition(parseAngle(_device['vwv_pos'], fallback: -1));

    // Follow the reported position while the user isn't dragging and we aren't
    // waiting on an angle-mode confirmation.
    if (!_userIsEditingAngle &&
        !(_confirmation.isWaiting && !_valveControlEnabled)) {
      final reported = _device['vwv_pos'];
      final parsed = reported == null ? null : int.tryParse(reported.toString());
      if (parsed != null) {
        setState(() => _sliderAngle = parsed.toDouble());
      }
    }
  }

  void _onServerScheduleUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    // -- Schedule half (unchanged) --
    if (!_schedulesLocallyEdited) {
      final parsed = parseSchedulePayload(data);
      if (parsed != null) {
        setState(() => _schedules = parsed);
        logD("📅 Loaded ${_schedules.length} schedule entries from server");
      }
    }

    // -- Sensor half: same push, "Sensor" block. Guarded by its OWN edit flag
    //    so saving one table never discards unsaved edits in the other. --
    final sensor = parseSensorPayload(data);
    if (sensor != null) {
      setState(() {
        _sensorReading = sensor.reading;   // live value: always follows server
        if (!_sensorRulesLocallyEdited) {
          _sensorRules = sensor.rules;
        }
      });
      logD("🌡️ Loaded ${sensor.rules.length} sensor rules from server");
    }
  }

  /// Maps the ESP32's `get_valvedata` fields onto the server DB-equivalent
  /// fields, so the rest of this screen works the same in both modes.
  void _onDirectValveData(Map<String, dynamic> valveData) {
    if (!mounted) return;

    final angle = valveData['angle'];
    if (angle != null) {
      final angleInt = parseAngle(angle);
      setState(() {
        _device['vwv_pos'] = angleInt.toString();
        _device['vwv_is_open'] = (valveData['is_open'] == true) ? 1 : 0;
        _device['vwv_is_close'] = (valveData['is_close'] == true) ? 1 : 0;
        if (!_userIsEditingAngle) {
          _sliderAngle = angleInt.toDouble();
        }
      });
    }

    _confirmation.reportPosition(_actualPosition);
  }

  // ===========================================================================
  // SECTION 4: MODE SWITCH (Manual ↔ Schedule) REST API calling setup ----------------
  // ===========================================================================

  void _onAutomateChanged(bool automate) {
    setState(() => _isAutomateMode = automate);

    // Turning Automate ON sends nothing — there's no automation picked yet.
    if (!automate && (_isScheduleMode || _isSensorMode)) {
      _sendControlMethod(schedule: false, sensor: false);
    }
  }

  void _onScheduleChanged(bool enabled) =>
      _sendControlMethod(schedule: enabled, sensor: _isSensorMode);

  void _onSensorChanged(bool enabled) =>
      _sendControlMethod(schedule: _isScheduleMode, sensor: enabled);

  Future<void> _sendControlMethod({
    required bool schedule,
    required bool sensor,
  }) async {
    setState(() => _isSwitchingMode = true);

    final result = await DeviceControlApi.switchControlMode(
      deviceId: _device['id'],
      deviceName: _deviceName,
      angle: _actualPosition,
      scheduleMode: schedule,
      sensorMode: sensor,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isScheduleMode = schedule;
        _isSensorMode   = sensor;
        _isManualMode   = !schedule && !sensor;
        if (schedule || sensor) _isAutomateMode = true;
      });
      _showMessage(_controlMethodMessage(schedule: schedule, sensor: sensor),
          color: GlassTokens.primary, duration: const Duration(seconds: 2));
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _isSwitchingMode = false);
  }

  String _controlMethodMessage({required bool schedule, required bool sensor}) {
    if (schedule && sensor) return 'Schedule + Sensor — schedule runs with sensor override';
    if (schedule) return 'Switched to Schedule mode — valve follows schedule';
    if (sensor)   return 'Switched to Sensor mode — valve follows the sensor';
    return 'Switched to Manual mode — you control the valve';
  }

  // ===========================================================================
  // SECTION 5: VALVE COMMANDS (Open/Close + Angle)
  // ===========================================================================

  Future<void> _sendControlCommand(String command) async {
    final bool opening = command == 'Open';
    final int targetAngle = opening ? 90 : 0;

    setState(() => _isUpdating = true);

    if (_isDirectMode) {
      _sendDirectAngle(targetAngle);
      _showMessage(
        'Direct command sent! Valve ${opening ? "opening" : "closing"}...',
        color: GlassTokens.primary,
        duration: const Duration(seconds: 2),
      );
      setState(() => _isUpdating = false);
      return;
    }

    final result = await DeviceControlApi.setValveAngle(
      deviceId: _device['id'],
      deviceName: _deviceName,
      angle: targetAngle,
    );

    if (!mounted) return;

    if (result.success) {
      _startConfirmationWait(targetAngle);
      _showMessage(
        'Command sent! Waiting for valve to ${opening ? "open" : "close"}...',
        color: GlassTokens.primary,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _isUpdating = false);
  }

  Future<void> _sendAngleCommand(int angle) async {
    setState(() => _isAngleUpdating = true);

    if (_isDirectMode) {
      _sendDirectAngle(angle);
      _showMessage(
        'Direct command sent! Setting angle to $angle°...',
        color: GlassTokens.primary,
        duration: const Duration(seconds: 2),
      );
      setState(() => _isAngleUpdating = false);
      return;
    }

    final result = await DeviceControlApi.setValveAngle(
      deviceId: _device['id'],
      deviceName: _deviceName,
      angle: angle,
    );

    if (!mounted) return;

    if (result.success) {
      _startConfirmationWait(angle);
      _showMessage(
        'Command sent! Waiting for valve to reach $angle°...',
        color: GlassTokens.primary,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _isAngleUpdating = false);
  }

  /// Direct mode: straight to the ESP32, no REST round trip.
  void _sendDirectAngle(int angle) {
    _directFeed?.setValveAngle(angle);
    _startConfirmationWait(angle);
  }

  void _startConfirmationWait(int targetAngle) {
    _confirmation.start(
      targetAngle,
      timeoutSeconds: _isDirectMode
          ? kDirectConfirmationTimeoutSeconds
          : kServerConfirmationTimeoutSeconds,
    );
  }

  /// Timeout: do NOT revert the slider — the next WebSocket / ESP push will
  /// carry the real position within ~2 seconds and the UI self-corrects.
  void _onConfirmationTimeout(int targetAngle) {
    if (_actualPosition == targetAngle) {
      _showMessage(
        '✅ Valve position confirmed!',
        color: GlassTokens.success,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    _showMessage(
      '⏳ Valve is still responding. Position will update shortly.',
      color: GlassTokens.warning,
      duration: const Duration(seconds: 3),
    );
  }

  // ===========================================================================
  // SECTION 6a: SCHEDULE (add / edit / delete / save)
  // ===========================================================================

  Future<void> _showScheduleDialog({int? editIndex}) async {
    final entry = await showScheduleEntryDialog(
      context,
      initial: editIndex != null ? _schedules[editIndex] : null,
    );
    if (entry == null || !mounted) return;

    setState(() {
      _schedulesLocallyEdited = true;
      if (editIndex != null) {
        _schedules[editIndex] = entry;
      } else {
        _schedules.add(entry);
      }
    });
  }

  Future<void> _deleteSchedule(int index) async {
    final confirmed = await showDeleteScheduleDialog(context, _schedules[index]);
    if (!confirmed || !mounted) return;

    setState(() {
      _schedulesLocallyEdited = true;
      _schedules.removeAt(index);
    });
  }

  Future<void> _saveSchedule() async {
    setState(() => _isSavingSchedule = true);

    final result = await DeviceControlApi.saveSchedule(
      deviceId: _device['id'],
      schedules: _schedules,
    );

    if (!mounted) return;

    if (result.success) {
      // Saved — the server is authoritative again.
      setState(() => _schedulesLocallyEdited = false);
      _showMessage('Schedule saved successfully!', color: GlassTokens.success);
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _isSavingSchedule = false);
  }

  // ===========================================================================
  // SECTION 6b: SENSOR RULE (add / edit / delete / save)
  // ===========================================================================

  Future<void> _showSensorRuleDialog({int? editIndex}) async {
    final rule = await showSensorRuleDialog(
      context,
      initial: editIndex != null ? _sensorRules[editIndex] : null,
      existingRules: _sensorRules,
    );
    if (rule == null || !mounted) return;

    setState(() {
      if (editIndex != null) {
        _sensorRules[editIndex] = rule;
      } else {
        _sensorRules.add(rule);
      }
      _sensorRules.sort((a, b) => a.from.compareTo(b.from));
      _sensorRulesLocallyEdited = true;
    });
  }

  void _deleteSensorRule(int index) {
    setState(() {
      _sensorRules.removeAt(index);
      _sensorRulesLocallyEdited = true;
    });
  }

  /// The push carries unit_id but no unit_name, and set_valve_sensor wants
  /// both. The home list already knows the name, so fill it from there — this
  /// screen is subscribed to device_detail, but the repository still holds the
  /// last device_list snapshot, which is exactly what we need.
  SensorReading _sensorForSave(SensorReading sensor) {
    if (sensor.unitName.isNotEmpty) return sensor;
    final String name =
        DeviceRepository.instance.deviceById(sensor.unitId)?.name ?? '';
    return sensor.copyWith(unitName: name);
  }

  Future<void> _saveSensorRules() async {
    final SensorReading? sensor = _sensorReading;
    if (sensor == null) {
      _showMessage('No sensor is assigned to this valve',
          color: GlassTokens.danger);
      return;
    }

    setState(() => _isSavingSensorRules = true);

    final result = await DeviceControlApi.saveSensorRules(
      deviceId: _device['id'],
      sensor: _sensorForSave(sensor),
      rules: _sensorRules,
    );

    if (!mounted) return;

    if (result.success) {
      // Saved — let the server's pushes drive the table again.
      setState(() => _sensorRulesLocallyEdited = false);
      _showMessage('Sensor rules saved successfully!',
          color: GlassTokens.success);
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _isSavingSensorRules = false);
  }

  /// "+ Add sensor" — fetch the account's units, run the two-step picker, then
  /// bind the chosen sensor.
  ///
  /// Binding sends an EMPTY sensor_rule: the ranges that were there belonged
  /// to the previous sensor, and a moisture range means nothing to a
  /// temperature probe.
  Future<void> _addSensor() async {
    setState(() => _isLoadingSensorUnits = true);

    final result = await DeviceControlApi.getUserSensors(
      userId: AuthService.currentUser?['id'],
      deviceId: _device['id'],
    );

    if (!mounted) return;
    setState(() => _isLoadingSensorUnits = false);

    if (!result.success) {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
      return;
    }
    if (result.units.isEmpty) {
      _showMessage('No sensor units found on this account',
          color: GlassTokens.warning);
      return;
    }

    final SensorReading? picked =
        await showAddSensorFlow(context, units: result.units);
    if (picked == null || !mounted) return;

    setState(() => _isSavingSensorRules = true);

    final saved = await DeviceControlApi.saveSensorRules(
      deviceId: _device['id'],
      sensor: picked,
      rules: const [],   // new sensor → the table starts empty
    );

    if (!mounted) return;
    setState(() => _isSavingSensorRules = false);

    if (saved.success) {
      setState(() {
        _sensorReading = picked;
        _sensorRules = [];
        _sensorRulesLocallyEdited = false; // let the server drive again
      });
      _showMessage('Sensor assigned to this valve',
          color: GlassTokens.success);
    } else {
      _showMessage(saved.displayMessage, color: GlassTokens.danger);
    }
  }


  /// "Remove" on the sensor panel. Unbinds the sensor and drops the rules with
  /// it — the ranges only mean something for the sensor they were written for.
  Future<void> _removeSensor() async {
    final bool? confirmed = await showRemoveSensorDialog(
      context,
      ruleCount: _sensorRules.length,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSavingSensorRules = true);

    final result =
        await DeviceControlApi.clearValveSensor(deviceId: _device['id']);

    if (!mounted) return;
    setState(() => _isSavingSensorRules = false);

    if (result.success) {
      setState(() {
        _sensorReading = null;
        _sensorRules = [];
        _sensorRulesLocallyEdited = false; // server drives again
      });
      _showMessage('Sensor removed', color: GlassTokens.success);
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }
  }

  // ===========================================================================
  // SECTION 7: DEVICE NAME
  // ===========================================================================

  Future<void> _showEditNameDialog() async {
    final newName = await showEditDeviceNameDialog(
      context,
      currentName: _device['vwv_name'] ?? _device['device_name'],
      onSave: _saveDeviceName,
    );
    if (newName == null || !mounted) return;

    setState(() {
      _device['vwv_name'] = newName;
      _device['device_name'] = newName;
    });
    _showMessage('Device name updated!', color: GlassTokens.success);
  }

  Future<bool> _saveDeviceName(String newName) async {
    final result = await DeviceControlApi.renameDevice(
      deviceId: _device['id'],
      newName: newName,
      angle: _actualPosition,
      scheduleMode: _isScheduleMode,
    );

    if (!result.success) {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }
    return result.success;
  }

  // ===========================================================================
  // SECTION 8: SNACKBAR HELPER
  // ===========================================================================

  void _showMessage(String message, {Color? color, Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  // ===========================================================================
  // SECTION 9: BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final bool isOnline = _isDirectMode
        ? true
        : isDeviceOnline(_device['vwv_last_seen']?.toString());

    // Which control card owns the screen.
    //
    // The mode toggle is authoritative: when it has schedule or sensor on, the
    // Control-by selector is hidden (9.3), so _controlMode is stale and must
    // not get a vote. That stale value is what leaked a second card in sensor
    // mode — schedule had its own `_isScheduleMode ||` override, sensor didn't.
    //
    // Both switches on → schedule wins, matching ModeToggleCard's own summary
    // ("Schedule + Sensor — schedule with sensor override").
    final String activeCard = _isScheduleMode
        ? 'schedule'
        : _isSensorMode
            ? 'sensor'
            : _controlMode;

    // UI v2 tabs replace the Control-by card. Same rules: while an automation
    // runs, only its card is reachable; offline, manual control is locked.
    final bool automated = _isScheduleMode || _isSensorMode;
    final Set<String> lockedTabs = automated
        ? ({'manual', 'schedule', 'sensor'}..remove(activeCard))
        : (!isOnline ? {'manual'} : <String>{});

    final double topInset = MediaQuery.paddingOf(context).top;

    // 9.8  Save pill — separate from the lists; floats up only while there is
    //      something to save on the active tab.
    final FloatingSavePill? savePill = activeCard == 'schedule'
        ? FloatingSavePill(
            hasUnsavedChanges: _schedulesLocallyEdited,
            isSaving: _isSavingSchedule,
            onSavePressed: _saveSchedule,
          )
        : activeCard == 'sensor' && _sensorReading != null
            ? FloatingSavePill(
                hasUnsavedChanges: _sensorRulesLocallyEdited,
                isSaving: _isSavingSensorRules,
                onSavePressed: _saveSensorRules,
              )
            : null;

    return GlassScaffold(
      // The forest header draws behind the status bar itself.
      useSafeArea: false,

      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              bottom: 16 +
                  MediaQuery.paddingOf(context).bottom +
                  (savePill?.visible == true
                      ? FloatingSavePill.reservedHeight
                      : 0),
            ),
            children: [
              // 9.1  Device header (replaces the app bar + DeviceInfoCard)
              ValveHeader(
                deviceName: _deviceName,
                deviceId: _device['id']?.toString() ?? '',
                productType: _device['vwv_version']?.toString() ?? 'Unknown',
                isOnline: isOnline,
                isDirectMode: _isDirectMode,
                linkConnected: _wsConnected,
                onEditName: _showEditNameDialog,
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 9.2  What the valve runs on (server mode only)
                    if (!_isDirectMode && isOnline) ...[
                      RunsOnCard(
                        isAutomateMode: _isAutomateMode,
                        isScheduleMode: _isScheduleMode,
                        isSensorMode: _isSensorMode,
                        isSwitching: _isSwitchingMode,
                        onAutomateChanged: _onAutomateChanged,
                        onScheduleChanged: _onScheduleChanged,
                        onSensorChanged: _onSensorChanged,
                      ),
                      const SizedBox(height: 10),
                    ],

                    // 9.3  Which card is shown: tabs online, a note in direct
                    //      mode (where only manual control works)
                    if (_isDirectMode)
                      _directModeNote()
                    else
                      ControlTabs(
                        selected: activeCard,
                        locked: lockedTabs,
                        onSelected: (mode) =>
                            setState(() => _controlMode = mode),
                        onLockedTap: (mode) => _showMessage(
                          automated
                              ? 'Switch the valve to Manual to use this'
                              : 'Manual control needs the device online',
                          duration: const Duration(seconds: 2),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // 9.4  Schedule card
                    if (activeCard == 'schedule')
                      ScheduleCard(
                        schedules: _schedules,
                        isSavingSchedule: _isSavingSchedule,
                        onAddPressed: _showScheduleDialog,
                        onRowTapped: (i) => _showScheduleDialog(editIndex: i),
                        onRowDeleted: _deleteSchedule,
                        onSavePressed: _saveSchedule,
                      )
                    // 9.5  Manual mode → Valve control card
                    else if (activeCard == 'manual')
                      ValveControlCard(
                        valveControlEnabled: _valveControlEnabled,
                        onValveControlEnabledChanged: (v) =>
                            setState(() => _valveControlEnabled = v),
                        isOpen: _isValveOpen,
                        actualPosition: _actualPosition,
                        isUpdating: _isUpdating,
                        onOpenCloseToggled: (open) =>
                            _sendControlCommand(open ? 'Open' : 'Closed'),
                        sliderAngle: _sliderAngle,
                        isAngleUpdating: _isAngleUpdating,
                        onSliderChanged: (v) =>
                            setState(() => _sliderAngle = v),
                        onSliderEditStart: () {
                          // User started dragging — block WS from
                          // overwriting the angle
                          _userIsEditingAngle = true;
                          _angleEditDebounce?.cancel();
                        },
                        onSliderEditEnd: () {
                          // Keep editing flag for 3s so the WS doesn't snap
                          // back before the user taps "Set"
                          _angleEditDebounce?.cancel();
                          _angleEditDebounce = Timer(
                            const Duration(seconds: 3),
                            () {
                              if (mounted) {
                                setState(() => _userIsEditingAngle = false);
                              }
                            },
                          );
                        },
                        onSetAnglePressed: (angle) {
                          _angleEditDebounce?.cancel();
                          _userIsEditingAngle = false;
                          _sendAngleCommand(angle);
                        },
                        waitingForConfirmation: _confirmation.isWaiting,
                        pendingTargetAngle: _confirmation.targetAngle,
                        confirmationCountdown: _confirmation.countdown,
                      )
                    // 9.6  Sensor mode → sensor settings card
                    else if (activeCard == 'sensor')
                      SensorCard(
                        onAddSensorPressed: _addSensor,
                        onRemoveSensor: _removeSensor,
                        isLoadingUnits: _isLoadingSensorUnits,
                        reading: _sensorReading,
                        isUnitOnline: isDeviceOnline(_sensorReading?.lastSeen),
                        rules: _sensorRules,
                        isSavingRules: _isSavingSensorRules,
                        onAddPressed: _showSensorRuleDialog,
                        onRowTapped: (i) => _showSensorRuleDialog(editIndex: i),
                        onRowDeleted: _deleteSensorRule,
                        onSavePressed: _saveSensorRules,
                      ),

                    // 9.7  Direct-mode device tools
                    if (_isDirectMode) ...[
                      const SizedBox(height: 14),
                      GlassCard(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Device tools',
                              style: TextStyle(
                                fontFamily: GlassTokens.displayFont,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: GlassTokens.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ChangeWifiButton(
                              onPressed: () =>
                                  showWifiCredentialsDialog(context),
                            ),
                            const Divider(height: 1, color: GlassTokens.border),
                            MotorCalibrationButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MotorCalibrationScreen(
                                        deviceData: _device),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          if (savePill != null) savePill,

          // Forest strip behind the status bar, so the clock and battery stay
          // on green (with light icons) after the header scrolls away.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topInset,
            child: const AnnotatedRegion<SystemUiOverlayStyle>(
              value: GlassTokens.systemOverlayOnForest,
              child: ColoredBox(color: GlassTokens.forest),
            ),
          ),
        ],
      ),
    );
  }

  /// Direct mode: one plain note instead of locked tabs.
  Widget _directModeNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: GlassTokens.goldSoft,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: GlassTokens.onGold),
          SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Manual control only\n',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: 'Schedule and sensor rules need the internet. '
                        'Reconnect the phone to your farm Wi-Fi to use them.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: GlassTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
