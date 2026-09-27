import 'package:flutter/material.dart';

import '../../models/smart_plug.dart';
import '../../services/plug_control_api.dart';
import '../../theme/glass_theme.dart';
import '../../utils/app_log.dart';
import '../../widgets/glass/glass.dart';

// Controllers (live data + confirmation wait)
import 'controllers/plug_confirmation_controller.dart';
import 'controllers/plug_feed.dart';

// Dialogs
import 'dialogs/edit_device_name_dialog.dart';

// Pure helpers
import 'utils/valve_utils.dart' show isDeviceOnline;

// Card widgets
import 'widgets/control_mode_card.dart';
import 'widgets/device_app_bar.dart';
import 'widgets/device_info_card.dart';
import 'widgets/mode_toggle_card.dart';
import 'widgets/plug_base_header_card.dart';
import 'widgets/plug_base_selector.dart';
import 'widgets/plug_manual_card.dart';

// =============================================================================
// PLUG DETAIL SCREEN
// =============================================================================
// Screen for one smart plug (id "SP…"). Sibling of DeviceDetailScreen (valve)
// and SensorDetailScreen, built from the same cards where it can be:
//
//   1  DeviceInfoCard        product type, plug name + Edit, online state
//   2  PlugBaseSelector      Base A | Base B (Base B locked on a single plug)
//   3  PlugBaseHeaderCard    selected base: name + Edit, wattage, ON/OFF
//   4  ModeToggleCard        Manual / Automate → Schedule, Sensor (per base)
//   5  ControlModeCard       Control by: manual / schedule / sensor (manual only)
//   6  PlugManualCard        current state + ON/OFF button
//      schedule / sensor     placeholders — next step
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

  /// Per-base schedule + sensor setup from device_schedule. Parsed and kept
  /// now so the schedule / sensor cards (next step) have it ready.
  final Map<PlugBaseId, PlugBaseControl> _controls = {
    PlugBaseId.a: const PlugBaseControl.empty(PlugBaseId.a),
    PlugBaseId.b: const PlugBaseControl.empty(PlugBaseId.b),
  };

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
        if (c != null) _controls[id] = c;
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
  // SECTION 6: RENAME (plug + base)
  // ===========================================================================

  Future<void> _editPlugName() async {
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
  // SECTION 8: BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final bool isOnline = _isOnline;

    return GlassScaffold(
      appBar: DeviceAppBar(isDirectMode: false, wsConnected: _wsConnected),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 8.1  Device info card (same as the valve)
            DeviceInfoCard(
              productType: _plug.version.isNotEmpty ? _plug.version : 'Smart Plug',
              deviceName: _plug.name.isNotEmpty ? _plug.name : 'Unknown',
              isOnline: isOnline,
              isDirectMode: false,
              onEditName: _editPlugName,
            ),

            const SizedBox(height: 16),

            if (!_hasDetail)
              _buildLoading()
            else
              ..._buildBaseSection(isOnline),
          ],
        ),
      ),
    );
  }

  /// Until the first device_basic_detail push we don't know the bases yet.
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

  List<Widget> _buildBaseSection(bool isOnline) {
    final PlugBase base = _base;
    final PlugBaseId id = base.id;
    final bool automate = _automateOf(base);

    // Which card owns the bottom of the screen — same rule as the valve:
    // the mode flags win, the Control-by choice only counts in manual mode,
    // and an offline plug can't be driven manually.
    String activeCard = base.scheduleCtrl
        ? 'schedule'
        : base.sensorCtrl
            ? 'sensor'
            : _controlModeOf(id);
    if (!isOnline && activeCard == 'manual') activeCard = 'schedule';

    return [
      // 8.2  Base A | Base B
      PlugBaseSelector(
        selected: _selected,
        baseA: _plug.baseA,
        baseB: _plug.baseB,
        onSelected: (id) => setState(() => _selected = id),
      ),

      const SizedBox(height: 16),

      // 8.3  Selected base: name + state
      PlugBaseHeaderCard(base: base, onEditName: _editBaseName),

      const SizedBox(height: 16),

      // 8.4  Control method (online only, like the valve)
      if (isOnline) ...[
        ModeToggleCard(
          isAutomateMode: automate,
          isScheduleMode: base.scheduleCtrl,
          isSensorMode: base.sensorCtrl,
          isSwitching: _switchingMode.contains(id),
          onAutomateChanged: _onAutomateChanged,
          onScheduleChanged: _onScheduleChanged,
          onSensorChanged: _onSensorChanged,
          subject: 'base',
          manualSummary: 'You switch the base ON / OFF',
          scheduleDescription: 'Turn ON / OFF at set times',
        ),
        const SizedBox(height: 16),
      ],

      // 8.5  Control by — manual only
      if (!base.isAutomated) ...[
        ControlModeCard(
          controlMode: activeCard,
          isDirectMode: false,
          isOffline: !isOnline,
          onModeSelected: (mode) => setState(() => _controlMode[id] = mode),
          onDisabledTap: (_) => _showMessage(
            'Manual control needs the plug online',
            duration: const Duration(seconds: 2),
          ),
        ),
        const SizedBox(height: 16),
      ],

      // 8.6  Active card
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
        _placeholder(
          'Schedule for ${base.name}',
          '${_controls[id]?.schedules.length ?? 0} entries · editor coming next',
        )
      else
        _placeholder(
          'Sensor for ${base.name}',
          _controls[id]?.sensor == null
              ? 'No sensor linked · editor coming next'
              : '${_controls[id]!.sensor!.sensorName} · editor coming next',
        ),
    ];
  }

  // TODO(plug): replace with PlugScheduleCard / PlugSensorCard.
  Widget _placeholder(String title, String subtitle) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: GlassTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: GlassTokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
