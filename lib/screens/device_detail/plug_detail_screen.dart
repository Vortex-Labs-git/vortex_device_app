import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/device_repository.dart';
import '../../models/smart_plug.dart';
import '../../models/valve_device.dart' show SensorReading;
import '../../services/auth_service.dart';
import '../../services/esp_direct_service.dart';
import '../../services/plug_control_api.dart';
import '../../theme/glass_theme.dart';
import '../../utils/app_log.dart';
import '../../widgets/glass/glass.dart';

// Controllers (live data + confirmation wait)
import 'controllers/plug_confirmation_controller.dart';
import 'controllers/plug_feed.dart';

// Dialogs
import 'dialogs/edit_device_name_dialog.dart';
import 'dialogs/plug_schedule_dialogs.dart';
import 'dialogs/wifi_credentials_dialog.dart';
import 'dialogs/sensor_dialogs.dart'
    show showAddSensorFlow, showPlugSensorRuleDialog, showRemoveSensorDialog;

// Pure helpers
import 'utils/valve_utils.dart' show isDeviceOnline;

// Card widgets
import 'widgets/change_wifi_button.dart';
import 'widgets/control_tabs.dart';
import 'widgets/plug_manual_card.dart';
import 'widgets/plug_schedule_card.dart';
import 'widgets/plug_sensor_card.dart';
import 'widgets/plug_socket_cards.dart';
import 'widgets/runs_on_card.dart';
import 'widgets/save_pill.dart';
import 'widgets/valve_header.dart';

// =============================================================================
// PLUG DETAIL SCREEN
// =============================================================================
// Screen for one smart plug (id "SP…"). Sibling of DeviceDetailScreen (valve)
// and SensorDetailScreen, built from the same cards where it can be:
//
//   1  ValveHeader           photo, plug name + rename, version, online state
//   2  PlugSocketCards       one card per socket (two on a dual plug, one on
//                            a single plug): name + rename, ON/OFF, watts
//   3  RunsOnCard            Manual | Automatic → Schedule, Sensor (per base,
//                            online only)
//   4  ControlTabs           Control · Schedule · Sensor rules
//   5  PlugManualCard        big power button
//      PlugScheduleCard      week strip + time cards (+ step cycle); the
//                            Save pill floats at the bottom
//      PlugSensorCard        the socket's own sensor + ON/OFF rules; the
//                            Save pill floats at the bottom
//
// Everything from 3 down belongs to the SELECTED base. Each base keeps its own
// UI state (automate switch, control-by choice, pending command).
//
// Cloud: live data via PlugServerFeed, commands via PlugControlApi.
//
// DIRECT MODE (isDirectMode, phone on the plug's own hotspot) — UI only for
// now: gold header, socket cards, a note that only ON / OFF works here, the
// power button and Device tools (Change Wi-Fi). The plug firmware's direct
// messages are not defined yet, so there is no live data (the cards show the
// home-list row) and ON / OFF and Wi-Fi say they need the firmware update.
// See TODO(plug-direct). The link state comes from EspDirectService.
// =============================================================================

class PlugDetailScreen extends StatefulWidget {
  /// The home-list row (Device.raw): id, name, version, last_seen. Enough to
  /// draw the info card until the first device_basic_detail push lands.
  final Map<String, dynamic> deviceData;

  /// Phone is on the plug's hotspot (no cloud). See the header comment.
  final bool isDirectMode;

  const PlugDetailScreen({
    super.key,
    required this.deviceData,
    this.isDirectMode = false,
  });

  @override
  State<PlugDetailScreen> createState() => _PlugDetailScreenState();
}

class _PlugDetailScreenState extends State<PlugDetailScreen> {
  // ===========================================================================
  // SECTION 1: STATE
  // ===========================================================================

  // -- Device data --
  late SmartPlug _plug;
  bool _hasDetail = false; // false until the first device_basic_detail push

  /// Per-base schedule + sensor setup exactly as the server last pushed it
  /// (device_schedule).
  final Map<PlugBaseId, PlugBaseControl> _controls = {
    PlugBaseId.a: const PlugBaseControl.empty(PlugBaseId.a),
    PlugBaseId.b: const PlugBaseControl.empty(PlugBaseId.b),
  };

  // -- Schedule tables (per base) --
  /// What the schedule card shows and edits. Follows the server's copy until
  /// the user edits a base; from then on that base's table is left alone by
  /// the 2-second pushes until it is saved (same idea as the valve's
  /// _schedulesLocallyEdited, but per base).
  final Map<PlugBaseId, List<PlugScheduleEntry>> _schedules = {
    PlugBaseId.a: [],
    PlugBaseId.b: [],
  };
  final Set<PlugBaseId> _schedulesEdited = {};
  final Set<PlugBaseId> _savingSchedule = {};

  // -- Sensor rule tables (per base) --
  /// Same idea as the schedules: follows the server's copy (_controls) until
  /// the user edits a base's rules, then waits for Save. Each socket has its
  /// own sensor and rules.
  final Map<PlugBaseId, List<PlugSensorRule>> _sensorRules = {
    PlugBaseId.a: [],
    PlugBaseId.b: [],
  };
  final Set<PlugBaseId> _sensorRulesEdited = {};
  final Set<PlugBaseId> _savingSensor = {};
  bool _loadingSensorUnits = false;

  // -- Connection state --
  bool _wsConnected = false;

  // -- Selected base --
  PlugBaseId _selected = PlugBaseId.a;

  // -- Per-base UI state --
  /// Master "Automate" switch position. Can be ON with neither schedule nor
  /// sensor picked yet (same as the valve), so it isn't derived from the flags.
  final Map<PlugBaseId, bool> _automate = {};

  /// Control-by choice while in manual mode: 'manual' | 'schedule' | 'sensor'.
  final Map<PlugBaseId, String> _controlMode = {};

  final Set<PlugBaseId> _switchingMode = {};
  final Set<PlugBaseId> _updatingState = {};

  // -- Controllers --
  late final PlugConfirmationController _confirmation;
  PlugServerFeed? _feed; // cloud only
  StreamSubscription<bool>? _espConnectionSub; // direct only

  // -- Shortcuts --
  PlugBase get _base => _plug.base(_selected);
  bool get _isOnline => isDeviceOnline(_plug.lastSeen);
  bool get _isDirectMode => widget.isDirectMode;

  // ===========================================================================
  // SECTION 2: LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _plug = SmartPlug.fromJson(widget.deviceData);
    logD("🔌 INIT plug = $_plug");

    _confirmation = PlugConfirmationController(
      onChanged: () {
        if (mounted) setState(() {});
      },
      onSuccess: (base, state) => _showMessage(
        '✅ ${_plug.base(base).name} is ${state ? 'ON' : 'OFF'}',
        color: GlassTokens.success,
        duration: const Duration(seconds: 2),
      ),
      onTimeout: (base, expected) => _showMessage(
        '⚠️ ${_plug.base(base).name} did not confirm '
        '${expected ? 'ON' : 'OFF'}. Check the plug is online.',
        color: GlassTokens.warning,
      ),
    );

    // Direct mode must not touch the cloud WebSocket. Only the ESP link
    // state is followed; there is no plug data feed over it yet.
    if (_isDirectMode) {
      final esp = EspDirectService.instance;
      _hasDetail = true; // show the home-list row; nothing else is coming
      _wsConnected = esp.isConnected;
      _espConnectionSub = esp.connectionStream.listen((connected) {
        if (mounted) setState(() => _wsConnected = connected);
      });
      // TODO(plug-direct): request the plug's status here and poll it, once
      // the firmware messages are defined.
      return;
    }

    final feed = PlugServerFeed(
      deviceId: _plug.id,
      onConnectionChanged: (connected) {
        if (mounted) setState(() => _wsConnected = connected);
      },
      onPlugUpdate: _onPlugUpdate,
      onControlUpdate: _onControlUpdate,
    );
    _feed = feed;
    _wsConnected = feed.isConnected;
    feed.start();
  }

  @override
  void dispose() {
    _feed?.dispose();
    _espConnectionSub?.cancel();
    _confirmation.dispose();
    super.dispose();
  }

  // ===========================================================================
  // SECTION 3: LIVE DATA
  // ===========================================================================

  void _onPlugUpdate(SmartPlug plug) {
    if (!mounted) return;

    setState(() {
      _plug = plug;
      _hasDetail = true;

      // A single plug can't stay on Base B.
      if (!_plug.isDual && _selected == PlugBaseId.b) {
        _selected = PlugBaseId.a;
      }

      // Sync each base's Automate switch from the server — unless a switch is
      // in flight, or the user just turned Automate on and hasn't picked
      // schedule/sensor yet (same rule as the valve screen).
      for (final base in _plug.bases) {
        if (_switchingMode.contains(base.id)) continue;
        final current = _automate[base.id];
        final pickingAutomation =
            current == true && !base.scheduleCtrl && !base.sensorCtrl;
        if (!pickingAutomation) _automate[base.id] = base.isAutomated;
      }
    });

    _confirmation.reportPlug(plug);
  }

  void _onControlUpdate(PlugControl control) {
    if (!mounted) return;
    setState(() {
      for (final id in PlugBaseId.values) {
        final c = control.base(id);
        if (c == null) continue;
        _controls[id] = c;

        // Don't overwrite a table the user is editing.
        if (!_schedulesEdited.contains(id)) {
          _schedules[id] = List.of(c.schedules);
        }
        if (!_sensorRulesEdited.contains(id)) {
          _sensorRules[id] = List.of(c.sensorRules);
        }
      }
    });
  }

  // ===========================================================================
  // SECTION 4: MODE SWITCH (per base)
  // ===========================================================================

  bool _automateOf(PlugBase base) => _automate[base.id] ?? base.isAutomated;

  String _controlModeOf(PlugBaseId id) =>
      _controlMode[id] ?? (_isOnline ? 'manual' : 'schedule');

  void _onAutomateChanged(bool automate) {
    final base = _base;
    setState(() => _automate[base.id] = automate);

    // Turning Automate ON sends nothing — nothing is picked yet.
    if (!automate && base.isAutomated) {
      _sendControlMethod(base.id, schedule: false, sensor: false);
    }
  }

  void _onScheduleChanged(bool enabled) => _sendControlMethod(
        _selected,
        schedule: enabled,
        sensor: _base.sensorCtrl,
      );

  void _onSensorChanged(bool enabled) => _sendControlMethod(
        _selected,
        schedule: _base.scheduleCtrl,
        sensor: enabled,
      );

  Future<void> _sendControlMethod(
    PlugBaseId id, {
    required bool schedule,
    required bool sensor,
  }) async {
    setState(() => _switchingMode.add(id));

    final result = await PlugControlApi.setBaseMode(
      plug: _plug,
      base: id,
      schedule: schedule,
      sensor: sensor,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _plug = _plug.withBase(
          _plug.base(id).copyWith(scheduleCtrl: schedule, sensorCtrl: sensor),
        );
        if (schedule || sensor) _automate[id] = true;
        if (!schedule && !sensor) _controlMode[id] = 'manual';
      });
      _showMessage(
        _controlMethodMessage(_plug.base(id).name,
            schedule: schedule, sensor: sensor),
        color: GlassTokens.primary,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _switchingMode.remove(id));
  }

  String _controlMethodMessage(
    String name, {
    required bool schedule,
    required bool sensor,
  }) {
    if (schedule && sensor) {
      return '$name: Schedule + Sensor — schedule runs with sensor override';
    }
    if (schedule) return '$name: switched to Schedule — follows the schedule';
    if (sensor) return '$name: switched to Sensor — follows the sensor';
    return '$name: switched to Manual — you switch it ON / OFF';
  }

  // ===========================================================================
  // SECTION 5: ON / OFF
  // ===========================================================================

  Future<void> _switchBase(bool on) async {
    final id = _selected;
    setState(() => _updatingState.add(id));

    final result = await PlugControlApi.setBaseState(
      plug: _plug,
      base: id,
      on: on,
    );

    if (!mounted) return;

    if (result.success) {
      _confirmation.start(id, on);
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _updatingState.remove(id));
  }

  // ===========================================================================
  // SECTION 5b: SCHEDULE (add / edit / delete / save, per base)
  // ===========================================================================

  Future<void> _showScheduleDialog({int? editIndex}) async {
    final id = _selected;
    final list = _schedules[id]!;

    final entry = await showPlugScheduleEntryDialog(
      context,
      baseName: _plug.base(id).name,
      initial: editIndex != null ? list[editIndex] : null,
    );
    if (entry == null || !mounted) return;

    setState(() {
      _schedulesEdited.add(id);
      if (editIndex != null) {
        list[editIndex] = entry;
      } else {
        list.add(entry);
      }
    });
  }

  Future<void> _deleteSchedule(int index) async {
    final id = _selected;
    final list = _schedules[id]!;

    final confirmed = await showDeletePlugScheduleDialog(context, list[index]);
    if (!confirmed || !mounted) return;

    setState(() {
      _schedulesEdited.add(id);
      list.removeAt(index);
    });
  }

  Future<void> _saveSchedule() async {
    final id = _selected;
    setState(() => _savingSchedule.add(id));

    final result = await PlugControlApi.saveBaseSchedule(
      plug: _plug,
      base: id,
      schedules: List.of(_schedules[id]!),
    );

    if (!mounted) return;

    if (result.success) {
      // Saved — the server's copy is authoritative again for this base.
      setState(() => _schedulesEdited.remove(id));
      _showMessage(
        '${_plug.base(id).name}: schedule saved',
        color: GlassTokens.success,
      );
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _savingSchedule.remove(id));
  }

  // ===========================================================================
  // SECTION 5c: SENSOR (link / unlink / rules, per base)
  // ===========================================================================
  // set_plug_sensor carries EVERY base, so each call sends the other base as
  // the server last pushed it (_controls) and only changes the selected one.

  Future<void> _showSensorRuleDialog({int? editIndex}) async {
    final id = _selected;
    final list = _sensorRules[id]!;

    final rule = await showPlugSensorRuleDialog(
      context,
      baseName: _plug.base(id).name,
      initial: editIndex != null ? list[editIndex] : null,
      existingRules: list,
    );
    if (rule == null || !mounted) return;

    setState(() {
      if (editIndex != null) {
        list[editIndex] = rule;
      } else {
        list.add(rule);
      }
      list.sort((a, b) => a.from.compareTo(b.from));
      _sensorRulesEdited.add(id);
    });
  }

  void _deleteSensorRule(int index) {
    final id = _selected;
    setState(() {
      _sensorRules[id]!.removeAt(index);
      _sensorRulesEdited.add(id);
    });
  }

  /// The push carries unit_id but not always unit_name; fill it from the home
  /// list (same as the valve).
  SensorReading _sensorForSave(SensorReading sensor) {
    if (sensor.unitName.isNotEmpty) return sensor;
    final String name =
        DeviceRepository.instance.deviceById(sensor.unitId)?.name ?? '';
    return sensor.copyWith(unitName: name);
  }

  /// Every base's current server setup, with [id] replaced by [control].
  Map<PlugBaseId, PlugBaseControl> _controlsWith(
    PlugBaseId id,
    PlugBaseControl control,
  ) {
    final Map<PlugBaseId, PlugBaseControl> all = {..._controls, id: control};
    return {
      for (final e in all.entries)
        e.key: e.value.sensor == null
            ? e.value
            : e.value.copyWith(sensor: _sensorForSave(e.value.sensor!)),
    };
  }

  PlugBaseControl _controlOf(PlugBaseId id) =>
      _controls[id] ?? PlugBaseControl.empty(id);

  Future<void> _saveSensorRules() async {
    final id = _selected;
    final control = _controlOf(id);
    if (control.sensor == null) {
      _showMessage('No sensor is linked to ${_plug.base(id).name}',
          color: GlassTokens.danger);
      return;
    }

    setState(() => _savingSensor.add(id));

    final updated = control.copyWith(sensorRules: List.of(_sensorRules[id]!));
    final result = await PlugControlApi.savePlugSensor(
      plug: _plug,
      controls: _controlsWith(id, updated),
    );

    if (!mounted) return;

    if (result.success) {
      // Saved — the server's copy is authoritative again for this base.
      setState(() {
        _controls[id] = updated;
        _sensorRulesEdited.remove(id);
      });
      _showMessage(
        '${_plug.base(id).name}: sensor rules saved',
        color: GlassTokens.success,
      );
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _savingSensor.remove(id));
  }

  /// "Choose a sensor" — fetch the account's units, run the two-step picker,
  /// then link the sensor to the selected socket with an EMPTY rule table
  /// (old ranges belonged to the previous sensor).
  Future<void> _addSensor() async {
    final id = _selected;
    setState(() => _loadingSensorUnits = true);

    final result = await PlugControlApi.getUserSensors(
      userId: AuthService.currentUser?['id'],
      deviceId: _plug.id,
    );

    if (!mounted) return;
    setState(() => _loadingSensorUnits = false);

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

    setState(() => _savingSensor.add(id));

    final linked =
        _controlOf(id).copyWith(sensor: picked, sensorRules: const []);
    final saved = await PlugControlApi.savePlugSensor(
      plug: _plug,
      controls: _controlsWith(id, linked),
    );

    if (!mounted) return;

    if (saved.success) {
      setState(() {
        _controls[id] = linked;
        _sensorRules[id] = [];
        _sensorRulesEdited.remove(id);
      });
      _showMessage('Sensor linked to ${_plug.base(id).name}',
          color: GlassTokens.success);
    } else {
      _showMessage(saved.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _savingSensor.remove(id));
  }

  /// "Remove" — unlinks the selected socket's sensor and drops its rules. The
  /// other socket is resent unchanged.
  Future<void> _removeSensor() async {
    final id = _selected;
    final bool? confirmed = await showRemoveSensorDialog(
      context,
      ruleCount: _sensorRules[id]!.length,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _savingSensor.add(id));

    final result = await PlugControlApi.clearBaseSensor(
      plug: _plug,
      base: id,
      controls: _controlsWith(id, _controlOf(id)),
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _controls[id] =
            _controlOf(id).copyWith(clearSensor: true, sensorRules: const []);
        _sensorRules[id] = [];
        _sensorRulesEdited.remove(id);
      });
      _showMessage('Sensor removed from ${_plug.base(id).name}',
          color: GlassTokens.success);
    } else {
      _showMessage(result.displayMessage, color: GlassTokens.danger);
    }

    setState(() => _savingSensor.remove(id));
  }

  // ===========================================================================
  // SECTION 6: RENAME (plug + base)
  // ===========================================================================

  Future<void> _editPlugName() async {
    if (_isDirectMode) {
      _showMessage('Renaming needs the plug online through your Wi-Fi',
          duration: const Duration(seconds: 2));
      return;
    }
    // set_plug_basic resends every base; until the first push we don't know
    // them yet (see SmartPlug.toBasicJson).
    if (!_hasDetail) {
      _showMessage('Loading plug details — try again in a moment',
          duration: const Duration(seconds: 2));
      return;
    }

    final newName = await showEditDeviceNameDialog(
      context,
      currentName: _plug.name,
      onSave: (name) async {
        final result =
            await PlugControlApi.renamePlug(plug: _plug, newName: name);
        if (!result.success) {
          _showMessage(result.displayMessage, color: GlassTokens.danger);
        }
        return result.success;
      },
    );
    if (newName == null || !mounted) return;

    setState(() => _plug = _plug.copyWith(name: newName.trim()));
    _showMessage('Plug name updated!', color: GlassTokens.success);
  }

  Future<void> _editBaseName() async {
    if (_isDirectMode) {
      _showMessage('Renaming needs the plug online through your Wi-Fi',
          duration: const Duration(seconds: 2));
      return;
    }
    final id = _selected;
    final newName = await showEditDeviceNameDialog(
      context,
      currentName: _plug.base(id).name,
      onSave: (name) async {
        final result = await PlugControlApi.renameBase(
          plug: _plug,
          base: id,
          newName: name,
        );
        if (!result.success) {
          _showMessage(result.displayMessage, color: GlassTokens.danger);
        }
        return result.success;
      },
    );
    if (newName == null || !mounted) return;

    setState(() {
      _plug = _plug.withBase(_plug.base(id).copyWith(name: newName.trim()));
    });
    _showMessage('Base name updated!', color: GlassTokens.success);
  }

  // ===========================================================================
  // SECTION 7: SNACKBAR HELPER
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
  // SECTION 8: BUILD  (UI v2)
  // ===========================================================================
  // Forest header (same band as the valve) → socket cards → "<socket> runs
  // on" (online only) → Control · Schedule · Sensor rules tabs → the card for
  // the active tab. A Save pill floats up when there is something to save.

  @override
  Widget build(BuildContext context) {
    final bool isOnline = _isOnline;
    final String? activeCard =
        _hasDetail && !_isDirectMode ? _activeCardOf(isOnline) : null;
    final PlugBaseId id = _selected;
    final double topInset = MediaQuery.paddingOf(context).top;

    // 8.7  Save pill — separate from the lists; floats up only while there is
    //      something to save on the active tab (per socket).
    final FloatingSavePill? savePill = activeCard == 'schedule'
        ? FloatingSavePill(
            hasUnsavedChanges: _schedulesEdited.contains(id),
            isSaving: _savingSchedule.contains(id),
            onSavePressed: _saveSchedule,
          )
        : activeCard == 'sensor' && _controlOf(id).sensor != null
            ? FloatingSavePill(
                hasUnsavedChanges: _sensorRulesEdited.contains(id),
                isSaving: _savingSensor.contains(id),
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
              // 8.1  Device header (replaces the app bar + DeviceInfoCard)
              ValveHeader(
                deviceName: _plug.name.isNotEmpty ? _plug.name : 'Unknown',
                deviceId: _plug.id,
                productType: _headerDetails(),
                isOnline: isOnline,
                isDirectMode: _isDirectMode,
                linkConnected: _wsConnected,
                onEditName: _editPlugName,
                productLine: 'Smart plug',
                imageAsset: 'assets/images/SP_1.jpeg',
                fallbackIcon: Icons.power_outlined,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isDirectMode)
                      ..._buildDirectSection()
                    else if (activeCard == null)
                      _buildLoading()
                    else
                      ..._buildBaseSection(isOnline, activeCard),
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

  /// "1.2 · 2 sockets" under the name in the header.
  String _headerDetails() {
    final String version =
        _plug.version.isNotEmpty ? _plug.version : 'Smart plug';
    if (!_hasDetail) return version;
    final int n = _plug.bases.length;
    return '$version · $n socket${n == 1 ? '' : 's'}';
  }

  /// Which card owns the bottom of the screen — same rule as before: the mode
  /// flags win, the tab choice only counts in manual mode, and an offline
  /// plug can't be driven manually.
  String _activeCardOf(bool isOnline) {
    final PlugBase base = _base;
    String activeCard = base.scheduleCtrl
        ? 'schedule'
        : base.sensorCtrl
            ? 'sensor'
            : _controlModeOf(base.id);
    if (!isOnline && activeCard == 'manual') activeCard = 'schedule';
    return activeCard;
  }

  // ---------------------------------------------------------------------------
  // Direct mode (UI only — see the header comment)
  // ---------------------------------------------------------------------------

  /// Sockets as the home-list row has them. A row without socket names still
  /// gets "Socket A" so the card reads well.
  List<PlugBase> get _directBases => [
        for (final b in _plug.bases)
          b.name.isNotEmpty ? b : b.copyWith(name: 'Socket ${b.id.letter}'),
      ];

  List<Widget> _buildDirectSection() {
    final bases = _directBases;
    final PlugBase base = bases.firstWhere(
      (b) => b.id == _selected,
      orElse: () => bases.first,
    );
    final bool linkUp = _wsConnected;

    return [
      PlugSocketCards(
        bases: bases,
        selected: base.id,
        isOffline: !linkUp,
        onSelected: (id) => setState(() => _selected = id),
        onEditName: _editBaseName,
      ),
      const SizedBox(height: 14),
      linkUp ? _directNote() : _linkLostNote(),
      const SizedBox(height: 14),
      // Locked while the link is down.
      IgnorePointer(
        ignoring: !linkUp,
        child: Opacity(
          opacity: linkUp ? 1 : 0.5,
          child: PlugManualCard(
            base: base,
            isUpdating: false,
            waitingForConfirmation: false,
            pendingState: null,
            confirmationCountdown: 0,
            onToggle: _switchBaseDirect,
          ),
        ),
      ),
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
                  showWifiCredentialsDialog(context, isSmartPlug: true),
              subtitle: 'Send your farm Wi-Fi to the plug',
            ),
          ],
        ),
      ),
    ];
  }

  // TODO(plug-direct): send the per-socket ON / OFF command over the ESP link
  // and wait for the plug's reply (same confirmation flow as the cloud).
  void _switchBaseDirect(bool on) {
    _showMessage(
      'Direct ON / OFF needs the plug firmware update',
      color: GlassTokens.warning,
      duration: const Duration(seconds: 3),
    );
  }

  Widget _directNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: GlassTokens.goldSoft,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: GlassTokens.onGold),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Direct link: only ON / OFF works here\n',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: 'Schedules and sensor rules need the plug online '
                        'through your Wi-Fi.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: GlassTokens.onGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkLostNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: GlassTokens.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: GlassTokens.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Direct link lost · ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: "reconnect to the plug's Wi-Fi hotspot to switch it.",
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: GlassTokens.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Until the first device_basic_detail push we don't know the sockets yet.
  Widget _buildLoading() {
    return const GlassCard(
      padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Loading plug details…',
              style: TextStyle(color: GlassTokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBaseSection(bool isOnline, String activeCard) {
    final PlugBase base = _base;
    final PlugBaseId id = base.id;
    final bool automate = _automateOf(base);

    // Same lock rules as the valve tabs: while an automation runs only its
    // card is reachable; offline, manual control is locked.
    final bool automated = base.isAutomated;
    final Set<String> lockedTabs = automated
        ? ({'manual', 'schedule', 'sensor'}..remove(activeCard))
        : (!isOnline ? {'manual'} : <String>{});

    return [
      // 8.2  Sockets: two cards on a dual plug, one on a single plug
      PlugSocketCards(
        bases: _plug.bases,
        selected: _selected,
        isOffline: !isOnline,
        onSelected: (id) => setState(() => _selected = id),
        onEditName: _editBaseName,
      ),
      const SizedBox(height: 14),

      if (!isOnline) ...[
        _offlineNote(),
        const SizedBox(height: 14),
      ],

      // 8.3  What the socket runs on (online only, like the valve)
      if (isOnline) ...[
        RunsOnCard(
          isAutomateMode: automate,
          isScheduleMode: base.scheduleCtrl,
          isSensorMode: base.sensorCtrl,
          isSwitching: _switchingMode.contains(id),
          onAutomateChanged: _onAutomateChanged,
          onScheduleChanged: _onScheduleChanged,
          onSensorChanged: _onSensorChanged,
          subject: base.name,
          manualSummary: 'You switch it ON / OFF',
        ),
        const SizedBox(height: 10),
      ],

      // 8.4  Control · Schedule · Sensor rules
      ControlTabs(
        selected: activeCard,
        locked: lockedTabs,
        onSelected: (mode) => setState(() => _controlMode[id] = mode),
        onLockedTap: (_) => _showMessage(
          automated
              ? 'Switch ${base.name} to Manual to use this'
              : 'Manual control needs the plug online',
          duration: const Duration(seconds: 2),
        ),
      ),
      const SizedBox(height: 14),

      // 8.5  Active card
      if (activeCard == 'manual')
        PlugManualCard(
          base: base,
          isUpdating: _updatingState.contains(id),
          waitingForConfirmation: _confirmation.isWaiting(id),
          pendingState: _confirmation.targetState(id),
          confirmationCountdown: _confirmation.countdown(id),
          onToggle: _switchBase,
        )
      else if (activeCard == 'schedule')
        PlugScheduleCard(
          baseName: base.name,
          schedules: _schedules[id]!,
          isSaving: _savingSchedule.contains(id),
          hasUnsavedChanges: _schedulesEdited.contains(id),
          onAddPressed: _showScheduleDialog,
          onRowTapped: (i) => _showScheduleDialog(editIndex: i),
          onRowDeleted: _deleteSchedule,
          onSavePressed: _saveSchedule,
        )
      else
        PlugSensorCard(
          baseName: base.name,
          reading: _controlOf(id).sensor,
          isUnitOnline: isDeviceOnline(_controlOf(id).sensor?.lastSeen),
          rules: _sensorRules[id]!,
          isSavingRules: _savingSensor.contains(id),
          isLoadingUnits: _loadingSensorUnits,
          onAddPressed: _showSensorRuleDialog,
          onAddSensorPressed: _addSensor,
          onRemoveSensor: _removeSensor,
          onRowTapped: (i) => _showSensorRuleDialog(editIndex: i),
          onRowDeleted: _deleteSensorRule,
          onSavePressed: _saveSensorRules,
        ),
    ];
  }

  Widget _offlineNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: GlassTokens.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: GlassTokens.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Plug offline · ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(
                    text: 'switching needs the plug online. Schedules and '
                        'sensor rules can still be edited and saved.',
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: GlassTokens.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
