import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';

import '../services/esp_direct_service.dart';
import 'device_detail/widgets/sensor_type_style.dart';
import '../utils/app_log.dart';

/// Sensor Configuration Screen (ESP32 direct mode)
///
/// The unit has a FIXED set of 8 sensor slots (S00..S07), displayed as
/// "Sensor 01".."Sensor 08" (GUI index = slot index + 1; the wire always
/// uses S00..S07). The screen ALWAYS shows all 8 slots:
///   - S00 + S01 are the in-build sensors (temperature + humidity) —
///     read-only, always included in the save payload.
///   - S02..S07 are user-configurable: type dropdown (incl. "-- no type --")
///     and tag name field.
///
/// Architecture Doc v3 - Sensor Configuration Process:
///   - On open, send get_sensor_config → unit replies with the SAME event
///     containing no_sensors + sensor_data ({sensor_id, sensor_type,
///     sensor_name} — no values). Slots absent from the reply are shown
///     as "-- no type --".
///   - On Save, send set_sensor_config containing ONLY the configured
///     sensors: any slot whose type is "-- no type --" is EXCLUDED from
///     the message entirely (e.g. Sensor 03 with no type → no S02 entry),
///     and no_sensors counts only the included ones. sensor_data goes on
///     the wire as a RAW JSON ARRAY (firmware checks cJSON_IsArray).
///
/// ──────────────────────────────────────────────────────────────────────
/// IMPORTANT — Update rules (mirrors MotorCalibrationScreen):
/// ──────────────────────────────────────────────────────────────────────
///   - Fields populate ONLY from the FIRST get_sensor_config reply
///     (_initialConfigLoaded). Any later reply must not overwrite what
///     the user is editing.
///   - NOTE: firmware restarts the unit after a successful
///     set_sensor_config save — the WebSocket connection will drop.
class SensorConfigScreen extends StatefulWidget {
  /// Device data passed in from the detail screen (used for AppBar title etc).
  final Map<String, dynamic> deviceData;

  const SensorConfigScreen({super.key, required this.deviceData});

  @override
  State<SensorConfigScreen> createState() => _SensorConfigScreenState();
}

/// One row of the config form. Holds the wire fields plus a
/// TextEditingController for the name and a locked flag for in-build
/// sensors.
class _SensorConfigEntry {
  final String id;                       // sensor_id  e.g. "S03"
  String type;                           // sensor_type (dropdown value)
  final TextEditingController nameCtrl;  // sensor_name (tag name)
  final bool locked;                     // in-build → read-only

  _SensorConfigEntry({
    required this.id,
    required this.type,
    required String name,
    required this.locked,
  }) : nameCtrl = TextEditingController(text: name);

  Map<String, dynamic> toWireJson() => {
        'sensor_id': id,
        'sensor_type': type,
        'sensor_name': nameCtrl.text.trim(),
      };
}

class _SensorConfigScreenState extends State<SensorConfigScreen> {
  // ── Fixed slot layout ─────────────────────────────────────────────
  /// The unit always has 8 slots: S00..S07 → "Sensor 01".."Sensor 08".
  static const int _totalSlots = 8;

  /// First two slots (S00 temperature, S01 humidity) are in-build →
  /// read-only, always included in the save payload.
  static const int _inBuildCount = 2;

  /// Dropdown value meaning "this slot has no sensor configured".
  /// Slots with this type are EXCLUDED from the set_sensor_config message.
  static const String _noType = '-- no type --';

  // ── Config entries (8 fixed slots, populated from the first reply) ─
  final List<_SensorConfigEntry> _entries = [];

  // ── Sensor type dropdown options (spec: Temperature/Humidity/Moisture
  //    + "-- no type --"). Types reported by the device that aren't
  //    listed are added at parse time so the dropdown never shows an
  //    invalid value. ────────────────────────────────────────────────
  final List<String> _typeOptions = [
    _noType,
    'Temperature',
    'Humidity',
    'Moisture',
  ];

  // ── State flags ───────────────────────────────────────────────────
  /// True after the first get_sensor_config reply populated the form.
  /// Later replies are ignored (user owns the fields until save).
  bool _initialConfigLoaded = false;

  /// True while waiting for the very first reply (loading spinner).
  bool _isLoadingInitial = true;

  /// True while a save is in flight (debounces double-taps).
  bool _isSaving = false;

  // ── ESP stream subscription ───────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _configSub;

  // ── Re-request safety net (same as calibration screen) ───────────
  Timer? _initialRetryTimer;
  int _initialRetryCount = 0;
  static const int _maxInitialRetries = 3;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _setupEspListener();
    // Deferred one frame: _requestInitialConfig shows a snackbar when the
    // unit isn't authenticated, and ScaffoldMessenger.of(context) cannot be
    // called during initState. Post-frame, the context is fully wired and
    // the listener above is already subscribed, so no reply can be missed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestInitialConfig();
    });
  }

  @override
  void dispose() {
    _configSub?.cancel();
    _initialRetryTimer?.cancel();
    for (final e in _entries) {
      e.nameCtrl.dispose();
    }
    super.dispose();
  }

  // ============================================================
  // ESP32 COMMUNICATION
  // ============================================================

  /// Subscribe to the sensor config stream BEFORE sending the initial
  /// request, so we can't miss a fast reply.
  void _setupEspListener() {
    _configSub = EspDirectService.instance.sensorConfigStream.listen(
      _onConfigMessage,
    );
  }

  /// Send the very first get_sensor_config request. Repeats every 1.5s
  /// up to [_maxInitialRetries] until a reply arrives.
  void _requestInitialConfig() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      setState(() => _isLoadingInitial = false);
      _showSnack('Not connected to the sensor unit.', isError: true);
      return;
    }

    esp.requestSensorConfig();
    _initialRetryCount = 0;
    _initialRetryTimer?.cancel();
    _initialRetryTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (_initialConfigLoaded || !mounted) {
        t.cancel();
        return;
      }
      if (_initialRetryCount >= _maxInitialRetries) {
        t.cancel();
        if (mounted) {
          setState(() => _isLoadingInitial = false);
          _showSnack('No reply from sensor unit. Check connection.',
              isError: true);
        }
        return;
      }
      _initialRetryCount++;
      logD(
        '🔁 SensorConfig: retry get_sensor_config ($_initialRetryCount/$_maxInitialRetries)',
      );
      esp.requestSensorConfig();
    });
  }

  /// Create the 8 fixed slots (S00..S07) with placeholder values. The
  /// first reply overlay replaces these with the device-reported config;
  /// slots the device doesn't mention stay "-- no type --".
  void _buildFixedSlots() {
    for (final e in _entries) {
      e.nameCtrl.dispose();
    }
    _entries.clear();
    for (var i = 0; i < _totalSlots; i++) {
      final locked = i < _inBuildCount;
      _entries.add(_SensorConfigEntry(
        id: 'S${i.toString().padLeft(2, '0')}', // S00..S07
        // In-build placeholder types by convention (S00 temp, S01 hum) —
        // the reply overlay below replaces them with device values.
        type: locked ? (i == 0 ? 'Temperature' : 'Humidity') : _noType,
        name: '',
        locked: locked,
      ));
    }
  }

  /// Handle every get_sensor_config reply from the ESP32.
  ///
  /// Rule (see class doc): only the FIRST reply populates the form.
  /// The reply is merged onto the 8 fixed slots by sensor_id — the reply
  /// may contain fewer than 8 entries (unconfigured slots are omitted by
  /// the unit) and the screen must still show all 8.
  void _onConfigMessage(Map<String, dynamic> msg) {
    if (!mounted || _initialConfigLoaded) return;

    final parsed = _parseSensorData(msg['sensor_data']);
    if (parsed.isEmpty) {
      logD('⚠️ SensorConfig: reply had no parseable sensor_data: $msg');
      return;
    }

    setState(() {
      _buildFixedSlots();

      // Overlay the device-reported config onto the fixed slots by id.
      for (final m in parsed) {
        final id = m['sensor_id']?.toString() ?? '';
        final idx = _entries.indexWhere((e) => e.id == id);
        if (idx == -1) {
          logD('⚠️ SensorConfig: unknown sensor_id "$id" in reply — ignored');
          continue;
        }
        final type = m['sensor_type']?.toString() ?? '';
        // Keep the dropdown valid even for unknown device-reported types.
        if (type.isNotEmpty && !_typeOptions.contains(type)) {
          _typeOptions.add(type);
        }
        final entry = _entries[idx];
        entry.type = type.isNotEmpty ? type : _noType;
        entry.nameCtrl.text = m['sensor_name']?.toString() ?? '';
      }

      _initialConfigLoaded = true;
      _isLoadingInitial = false;
      _initialRetryTimer?.cancel();
      logD(
        '✅ SensorConfig: initial config loaded '
        '(${parsed.length} configured of $_totalSlots slots)',
      );
    });
  }

  /// sensor_data may arrive as an escaped JSON STRING (unit → app keeps
  /// the string convention) or a real List. Decode defensively —
  /// malformed input yields an empty list.
  List<Map<String, dynamic>> _parseSensorData(dynamic raw) {
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
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  // ============================================================
  // SAVE
  // ============================================================

  /// Send set_sensor_config with ONLY the configured sensors:
  ///   - in-build entries (S00/S01) always included, unchanged
  ///   - editable entries included only when a type is selected
  ///   - "-- no type --" slots are excluded from the message entirely,
  ///     and no_sensors (computed in EspDirectService from list length)
  ///     therefore counts only the included ones.
  /// The unit doesn't reply to this event — and firmware RESTARTS after
  /// a successful save — so mimic the WiFi dialog: brief sending state +
  /// confirmation snack.
  void _onSavePressed() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      _showSnack('Not connected to the sensor unit.', isError: true);
      return;
    }

    final included =
        _entries.where((e) => e.locked || e.type != _noType).toList();

    // Empty tag names on configured editable sensors would blank out the
    // device-side labels — block save. "-- no type --" slots are exempt
    // (they're not sent at all).
    final hasEmptyName =
        included.any((e) => !e.locked && e.nameCtrl.text.trim().isEmpty);
    if (hasEmptyName) {
      _showSnack('Sensor name cannot be empty.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    esp.setSensorConfig(
      sensors: included.map((e) => e.toWireJson()).toList(),
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('Sensor configuration sent to the unit.');
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? GlassTokens.danger : GlassTokens.success,
      ),
    );
  }

  // ============================================================
  // BUILD  (UI v2)
  // ============================================================
  // A short list of all 8 slots. Built-in slots are locked; tapping any
  // other slot opens an editor sheet for its type and tag name. Save is
  // pinned to the bottom, apart from the list. The entries, the first-reply
  // rule and the save payload are unchanged.

  @override
  Widget build(BuildContext context) {
    final deviceName = widget.deviceData['name']?.toString() ?? 'Sensor Unit';
    final bool ready = !_isLoadingInitial && _entries.isNotEmpty;

    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Sensor configuration',
        subtitle: '$deviceName · direct link',
      ),
      bottomNavigationBar: ready ? _buildSaveBar() : null,
      body: SafeArea(
        bottom: !ready,
        child: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? const Center(
                    child: Text(
                      'No sensor configuration received.',
                      style: TextStyle(color: GlassTokens.textMuted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      const Text(
                        'Sensor 01 and 02 are built in. Tap any other slot '
                        'to set its type and tag name.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: GlassTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── One row per slot (always all 8) ────────
                      GlassCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < _entries.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                    height: 1, color: GlassTokens.border),
                              _buildSlotRow(i, _entries[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  // ── One slot row: icon / "Sensor 03 · Moisture" / tag name ───────
  // Header "Sensor 01".."Sensor 08" (GUI index = slot index + 1; the
  // wire id stays S00..S07 — intentional off-by-one per the spec figure).
  Widget _buildSlotRow(int index, _SensorConfigEntry entry) {
    final String header = _slotLabel(index);
    final bool empty = entry.type == _noType;
    final style = SensorTypeStyle.of(entry.type);
    final String name = entry.nameCtrl.text.trim();

    final String subtitle = entry.locked
        ? '${name.isNotEmpty ? name : entry.type} · built in'
        : empty
            ? 'Tap to set up'
            : name.isNotEmpty
                ? name
                : 'No tag name yet';

    return InkWell(
      onTap: entry.locked ? null : () => _editSlot(index, entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: empty ? GlassTokens.sunk : style.background,
                borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
              ),
              child: Icon(
                entry.locked
                    ? Icons.lock_outline_rounded
                    : empty
                        ? Icons.add_rounded
                        : style.icon,
                size: 20,
                color: empty ? GlassTokens.textMuted : style.color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$header · ${empty ? 'Empty slot' : entry.type}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: empty
                          ? GlassTokens.textSecondary
                          : GlassTokens.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: !entry.locked && !empty && name.isEmpty
                          ? GlassTokens.danger
                          : GlassTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (!entry.locked)
              const Icon(Icons.chevron_right_rounded,
                  color: GlassTokens.textMuted),
          ],
        ),
      ),
    );
  }

  String _slotLabel(int index) =>
      'Sensor ${(index + 1).toString().padLeft(2, '0')}';

  /// Opens the editor sheet; Done writes the type and name back to the
  /// entry, Cancel leaves it as it was.
  Future<void> _editSlot(int index, _SensorConfigEntry entry) async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _SlotEditorSheet(
        title: _slotLabel(index),
        typeOptions: _typeOptions,
        noType: _noType,
        initialType: entry.type,
        initialName: entry.nameCtrl.text,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      entry.type = result.$1;
      entry.nameCtrl.text = result.$2;
    });
  }

  // ── Save bar: pinned to the bottom, apart from the list ──────────
  Widget _buildSaveBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: GlassTokens.surface,
        border: Border(top: BorderSide(color: GlassTokens.border)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Saving restarts the unit',
              style: TextStyle(fontSize: 12.5, color: GlassTokens.textMuted),
            ),
          ),
          const SizedBox(width: 10),
          // GlassButton fills its width; give it two thirds of the bar.
          Expanded(
            flex: 2,
            child: GlassButton(
              label: _isSaving ? 'Saving…' : 'Save to unit',
              icon: Icons.save_outlined,
              height: 48,
              isLoading: _isSaving,
              onPressed: _isSaving ? null : _onSavePressed,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SLOT EDITOR SHEET
// =============================================================================
// Type chips + tag name for one slot. Owns a copy of the values and pops
// (type, name) on Done; the screen applies them. The name field is disabled
// while the slot has no type, as before.
// =============================================================================

class _SlotEditorSheet extends StatefulWidget {
  final String title;
  final List<String> typeOptions;
  final String noType;
  final String initialType;
  final String initialName;

  const _SlotEditorSheet({
    required this.title,
    required this.typeOptions,
    required this.noType,
    required this.initialType,
    required this.initialName,
  });

  @override
  State<_SlotEditorSheet> createState() => _SlotEditorSheetState();
}

class _SlotEditorSheetState extends State<_SlotEditorSheet> {
  late String _type = widget.initialType;
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool empty = _type == widget.noType;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        18 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: GlassTokens.border,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: const TextStyle(
                fontFamily: GlassTokens.displayFont,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: GlassTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Type',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: GlassTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in widget.typeOptions)
                  ChoiceChip(
                    label: Text(t == widget.noType ? 'No type' : t),
                    selected: t == _type,
                    showCheckmark: false,
                    selectedColor: GlassTokens.textPrimary,
                    backgroundColor: GlassTokens.surface,
                    side: BorderSide(
                      color: t == _type
                          ? GlassTokens.textPrimary
                          : GlassTokens.border,
                      width: 1.5,
                    ),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: t == _type
                          ? GlassTokens.surface
                          : GlassTokens.textSecondary,
                    ),
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !empty,
              textInputAction: TextInputAction.done,
              decoration: glassInputDecoration(
                labelText: 'Tag name',
                hintText: empty ? 'Select a type first' : 'Enter tag name',
                prefixIcon: const Icon(Icons.label_outline_rounded),
              ),
            ),
            if (empty) ...[
              const SizedBox(height: 8),
              const Text(
                'An empty slot is left out when you save.',
                style: TextStyle(fontSize: 12, color: GlassTokens.textMuted),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GlassButton(
                    label: 'Done',
                    icon: Icons.check_rounded,
                    height: 48,
                    onPressed: () =>
                        Navigator.pop(context, (_type, _name.text)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
