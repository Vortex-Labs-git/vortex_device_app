import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/device_repository.dart';
import '../../models/smart_plug.dart';
import '../../models/valve_device.dart' show SensorReading;
import '../../services/auth_service.dart';
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
import 'dialogs/sensor_dialogs.dart'
    show showAddSensorFlow, showPlugSensorRuleDialog, showRemoveSensorDialog;

// Pure helpers
import 'utils/valve_utils.dart' show isDeviceOnline;

// Card widgets
import 'widgets/control_tabs.dart';
import 'widgets/plug_manual_card.dart';
import 'widgets/plug_schedule_card.dart';
import 'widgets/plug_sensor_card.dart';
import 'widgets/plug_socket_cards.dart';
import 'widgets/runs_on_card.dart';
import 'widgets/schedule_card.dart' show ScheduleSaveBar;
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
//                            Save bar is pinned to the bottom
//      PlugSensorCard        the socket's own sensor + ON/OFF rules; the
//                            Save bar is pinned to the bottom
//
// Everything from 3 down belongs to the SELECTED base. Each base keeps its own
// UI state (automate switch, control-by choice, pending command).
//
// Cloud only: live data via PlugServerFeed, commands via PlugControlApi.
// =============================================================================

class PlugDetailScreen extends StatefulWidget {
  /// The home-list row (Device.raw): id, name, version, last_seen. Enough to
  /// draw the info card until the first device_basic_detail push lands.
  final Map<String, dynamic> deviceData;

  const PlugDetailScreen({super.key, required this.deviceData});

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
  late final PlugServerFeed _feed;

  // -- Shortcuts --
  PlugBase get _base => _plug.base(_selected);
  bool get _isOnline => isDeviceOnline(_plug.lastSeen);

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

    _feed = PlugServerFeed(
      deviceId: _plug.id,
      onConnectionChanged: (connected) {
        if (mounted) setState(() => _wsConnected = connected);
      },
      onPlugUpdate: _onPlugUpdate,
      onControlUpdate: _onControlUpdate,
    );
    _wsConnected = _feed.isConnected;
    _feed.start();
  }

  @override
  void dispose() {
    _feed.dispose();
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
  // the active tab. The schedule's Save bar is pinned to the bottom.

  @override
  Widget build(BuildContext context) {
    final bool isOnline = _isOnline;
    final String? activeCard = _hasDetail ? _activeCardOf(isOnline) : null;
    final PlugBaseId id = _selected;
    final double topInset = MediaQuery.paddingOf(context).top;

    return GlassScaffold(
      // The forest header draws behind the status bar itself.
      useSafeArea: false,

      // 8.7  Save bars — separate from the lists, pinned to the bottom
      bottomNavigationBar: activeCard == 'schedule'
          ? ScheduleSaveBar(
              hasUnsavedChanges: _schedulesEdited.contains(id),
              isSaving: _savingSchedule.contains(id),
              onSavePressed: _saveSchedule,
              savedText: 'Saved on the plug',
            )
          : activeCard == 'sensor' && _controlOf(id).sensor != null
              ? ScheduleSaveBar(
                  hasUnsavedChanges: _sensorRulesEdited.contains(id),
                  isSaving: _savingSensor.contains(id),
                  onSavePressed: _saveSensorRules,
                  saveLabel: 'Save sensor rules',
                  savedText: 'Saved on the plug',
                )
              : null,

      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              // 8.1  Device header (replaces the app bar + DeviceInfoCard)
              ValveHeader(
                deviceName: _plug.name.isNotEmpty ? _plug.name : 'Unknown',
                deviceId: _plug.id,
                productType: _headerDetails(),
                isOnline: isOnline,
                isDirectMode: false,
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
                    if (activeCard == null)
                      _buildLoading()
                    else
                      ..._buildBaseSection(isOnline, activeCard),
                  ],
                ),
              ),
            ],
          ),

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
