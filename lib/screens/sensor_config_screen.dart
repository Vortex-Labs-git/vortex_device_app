import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/esp_direct_service.dart';

/// Sensor Configuration Screen (ESP32 direct mode)
///
/// Allows the user to:
///   1. View each sensor's type and tag name as stored on the unit
///   2. Change the sensor type (dropdown) and tag name (text field)
///      for the EDITABLE sensors
///   3. Save the full configuration back to the Sensor Unit
///
/// Architecture Doc v3 - Sensor Configuration Process:
///   - On open, send get_sensor_config → unit replies with the SAME event
///     containing no_sensors + sensor_data (ESCAPED JSON STRING of
///     {sensor_id, sensor_type, sensor_name} — no values).
///   - On Save, send set_sensor_config with the SAME payload shape,
///     including the unchanged in-build entries.
///
/// ──────────────────────────────────────────────────────────────────────
/// IMPORTANT — Update rules (mirrors MotorCalibrationScreen):
/// ──────────────────────────────────────────────────────────────────────
///   - Fields populate ONLY from the FIRST get_sensor_config reply
///     (_initialConfigLoaded). Any later reply must not overwrite what
///     the user is editing.
///   - Per spec, the FIRST TWO sensors are in-build sensors and are NOT
///     editable — rendered read-only, but still included unchanged in
///     the set_sensor_config payload.
class SensorConfigScreen extends StatefulWidget {
  /// Device data passed in from the detail screen (used for AppBar title etc).
  final Map<String, dynamic> deviceData;

  const SensorConfigScreen({super.key, required this.deviceData});

  @override
  State<SensorConfigScreen> createState() => _SensorConfigScreenState();
}

/// One editable row of the config form. Holds the wire fields plus a
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
  // ── Config entries (populated once from the first reply) ──────────
  final List<_SensorConfigEntry> _entries = [];

  // ── Sensor type dropdown options (spec: Temperature/Humidity/Moisture).
  //    Types reported by the device that aren't listed are added at
  //    parse time so the dropdown never shows an invalid value. ──────
  final List<String> _typeOptions = ['Temperature', 'Humidity', 'Moisture'];

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
    _requestInitialConfig();
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
      print(
        '🔁 SensorConfig: retry get_sensor_config ($_initialRetryCount/$_maxInitialRetries)',
      );
      esp.requestSensorConfig();
    });
  }

  /// Handle every get_sensor_config reply from the ESP32.
  ///
  /// Rule (see class doc): only the FIRST reply populates the form.
  void _onConfigMessage(Map<String, dynamic> msg) {
    if (!mounted || _initialConfigLoaded) return;

    final parsed = _parseSensorData(msg['sensor_data']);
    if (parsed.isEmpty) {
      print('⚠️ SensorConfig: reply had no parseable sensor_data: $msg');
      return;
    }

    setState(() {
      _entries.clear();
      for (var i = 0; i < parsed.length; i++) {
        final m = parsed[i];
        final type = m['sensor_type']?.toString() ?? '';
        // Keep the dropdown valid even for unknown device-reported types.
        if (type.isNotEmpty && !_typeOptions.contains(type)) {
          _typeOptions.add(type);
        }
        _entries.add(_SensorConfigEntry(
          id: m['sensor_id']?.toString() ?? '',
          type: type.isNotEmpty ? type : _typeOptions.first,
          name: m['sensor_name']?.toString() ?? '',
          locked: i < 2, // spec: first 2 are in-build → read-only
        ));
      }
      _initialConfigLoaded = true;
      _isLoadingInitial = false;
      _initialRetryTimer?.cancel();
      print('✅ SensorConfig: initial config loaded (${_entries.length} sensors)');
    });
  }

  /// sensor_data arrives as an ESCAPED JSON STRING (same convention as
  /// sensor_unit_info). Decode defensively — malformed input yields an
  /// empty list. Also tolerates a real List.
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

  /// Send set_sensor_config with the FULL entry list (in-build entries
  /// included unchanged). The unit doesn't send a reply for this event,
  /// so mimic the WiFi dialog: brief sending state + confirmation snack.
  void _onSavePressed() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      _showSnack('Not connected to the sensor unit.', isError: true);
      return;
    }

    // Empty tag names would blank out the device-side labels — block save.
    final hasEmptyName =
        _entries.any((e) => !e.locked && e.nameCtrl.text.trim().isEmpty);
    if (hasEmptyName) {
      _showSnack('Sensor name cannot be empty.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    esp.setSensorConfig(
      sensors: _entries.map((e) => e.toWireJson()).toList(),
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
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final deviceName = widget.deviceData['name']?.toString() ?? 'Sensor Unit';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Configuration'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? Center(
                    child: Text(
                      'No sensor configuration received.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Device name header
                        Text(
                          deviceName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 16),

                        // ── One card per sensor ─────────────────────
                        for (var i = 0; i < _entries.length; i++) ...[
                          _buildSensorCard(i, _entries[i]),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 4),

                        // ── Save button ─────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _onSavePressed,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isSaving ? 'Saving...' : 'save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── One sensor card: header / type dropdown / name field ─────────
  Widget _buildSensorCard(int index, _SensorConfigEntry entry) {
    final String header =
        'Sensor ${(index + 1).toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (entry.locked)
                  Row(
                    children: [
                      Icon(Icons.lock, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        'In-build',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Sensor type ─────────────────────────────────
            Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text('Sensor type',
                      style: TextStyle(color: Colors.grey)),
                ),
                Expanded(
                  child: entry.locked
                      ? _buildReadOnlyBox(entry.type)
                      : DropdownButtonFormField<String>(
                          value: entry.type,
                          isDense: true,
                          decoration: _fieldDecoration(),
                          items: _typeOptions
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => entry.type = v);
                            }
                          },
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Sensor name (tag) ───────────────────────────
            Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text('Sensor name',
                      style: TextStyle(color: Colors.grey)),
                ),
                Expanded(
                  child: entry.locked
                      ? _buildReadOnlyBox(entry.nameCtrl.text)
                      : TextField(
                          controller: entry.nameCtrl,
                          decoration: _fieldDecoration(
                            hint: 'Enter tag name',
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Small UI helpers ────────────────────────────────────────────

  Widget _buildReadOnlyBox(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Text(
        value.isNotEmpty ? value : '—',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.green[700]!, width: 2),
      ),
    );
  }
}
