import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/websocket_service.dart';
import '../../services/esp_direct_service.dart';
import '../../models/sensor_unit.dart';
import '../sensor_config_screen.dart';

// =============================================================================
// SENSOR DETAIL SCREEN
// =============================================================================
// Screen for one WiFi sensor unit (device id starts with "SU"). Two modes,
// mirroring DeviceDetailScreen:
//
//   - Server mode (isDirectMode = false): WebSocket through the cloud.
//     Subscribes to 'device_detail'; parses each device_basic_detail push
//     into a SensorUnit via SensorUnit.fromJson (keys: id / unit_name /
//     unit_version / unit_last_seen / no_sensors / sensor_data).
//
//   - Direct mode (isDirectMode = true): Talks straight to the ESP32 over
//     its AP via EspDirectService. Sends device_basic_info (initial +
//     2-second poll, same cadence as the valve screen); listens on
//     sensorUnitInfoStream for the sensor_unit_info reply and parses it via
//     SensorUnit.fromDirectJson (keys: device_id / device_name / no_sensors
//     / data). No lastSeen in this payload, so online status is simply the
//     ESP32 connection state.
//
// On dispose, server mode resubscribes to 'device_list' so the home list
// resumes; direct mode must NOT touch the cloud WebSocket. Both bottom
// buttons are wired for direct mode only ("Change WiFi connection" →
// set_device_wifi popup; "Sensor configuration" → SensorConfigScreen).
// Name/tag Edit remains a stub until the sensor edit REST is defined.
// =============================================================================

class SensorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData; // from the home list: id, name, ...
  final bool isDirectMode;

  const SensorDetailScreen({
    super.key,
    required this.deviceData,
    this.isDirectMode = false,
  });

  @override
  State<SensorDetailScreen> createState() => _SensorDetailScreenState();
}

class _SensorDetailScreenState extends State<SensorDetailScreen> {
  late final String _deviceId; // id we subscribe with / filter pushes against
  SensorUnit? _unit;           // latest push; null until the first one arrives
  bool _wsConnected = false;   // cloud WS (server mode) or ESP32 WS (direct)

  // -- Stream subscriptions (server mode) --
  StreamSubscription? _detailSub;
  StreamSubscription? _connectionSub;

  // -- Stream subscriptions (direct mode) --
  StreamSubscription? _espUnitInfoSub;
  StreamSubscription? _espConnectionSub;
  Timer? _espPollTimer;

  // -- Shortcut --
  bool get _isDirectMode => widget.isDirectMode;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.deviceData['id']?.toString() ?? '';
    // _unit starts null in BOTH modes, so no stale cloud state can leak into
    // direct mode — the first sensor_unit_info reply is the source of truth.
    if (_isDirectMode) {
      _setupEspDirect();
    } else {
      _setupWebSocket();
    }
  }

  @override
  void dispose() {
    _detailSub?.cancel();
    _connectionSub?.cancel();
    _espUnitInfoSub?.cancel();
    _espConnectionSub?.cancel();
    _espPollTimer?.cancel();
    if (!_isDirectMode) {
      WebSocketService.subscribeTo('device_list'); // resume home list updates
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // WebSocket setup (server mode)
  // ---------------------------------------------------------------------------
  void _setupWebSocket() {
    _wsConnected = WebSocketService.isConnected;

    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _detailSub = WebSocketService.deviceDetailStream.listen((data) {
      if (!mounted) return;
      if (data['id']?.toString() != _deviceId) return; // only THIS unit
      setState(() => _unit = SensorUnit.fromJson(data));
    });

    WebSocketService.subscribeTo('device_detail', deviceId: _deviceId);
  }

  // ---------------------------------------------------------------------------
  // ESP32 direct setup (direct mode)
  // ---------------------------------------------------------------------------
  void _setupEspDirect() {
    final esp = EspDirectService.instance;
    _wsConnected = esp.isConnected;

    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _espUnitInfoSub = esp.sensorUnitInfoStream.listen((data) {
      if (!mounted) return;
      if (data['device_id']?.toString() != _deviceId) return; // only THIS unit
      setState(() => _unit = SensorUnit.fromDirectJson(data));
      print('📱 ESP32 Direct: sensor_unit_info, '
          '${data['no_sensors']} sensors');
    });

    // Initial request, then poll every 2 seconds (same cadence as the
    // valve screen — the ESP32 replies per-request, it doesn't push).
    _requestEspSensorData();
    _espPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && esp.isAuthenticated) {
        _requestEspSensorData();
      }
    });
  }

  void _requestEspSensorData() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) return;

    final userId = widget.deviceData['user_id']?.toString() ?? 'app_user';
    final deviceName =
        widget.deviceData['name']?.toString() ?? 'Sensor Unit';
    esp.requestSensorUnitData(
      userId: userId,
      deviceId: _deviceId,
      deviceName: deviceName,
    );
  }

  // Online if reported within 30s (server mode only). Direct mode has no
  // lastSeen field — being connected to the ESP32 IS the online signal.
  bool _isDeviceOnline(String? lastSeen) {
    if (_isDirectMode) return _wsConnected;
    if (lastSeen == null || lastSeen.isEmpty || lastSeen.toUpperCase() == 'NULL') {
      return false;
    }
    try {
      return DateTime.now().difference(DateTime.parse(lastSeen)).inSeconds <= 30;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final unit = _unit;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isDirectMode ? 'Direct Control' : 'Vortex Labs'),
        backgroundColor:
            _isDirectMode ? Colors.green[700] : const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _wsConnected
                  ? (_isDirectMode ? Icons.settings_remote : Icons.wifi)
                  : Icons.wifi_off,
              color: _wsConnected ? Colors.greenAccent : Colors.red,
            ),
          ),
        ],
      ),
      body: unit == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildUnitInfoCard(unit),
                  const SizedBox(height: 16),
                  ...unit.sensors.map(_buildSensorCard),
                  if (unit.sensors.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No sensors reported',
                            style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _buildBottomButtons(),
                ],
              ),
            ),
    );
  }

  // ----- Unit info: Product Type / Name (Edit) / Status / Active Sensors -----
  Widget _buildUnitInfoCard(SensorUnit unit) {
    final bool online = _isDeviceOnline(unit.lastSeen);
    final Color statusColor = online ? Colors.green : Colors.red;
    final String displayName = unit.name.isNotEmpty
        ? unit.name
        : (widget.deviceData['name']?.toString() ?? 'Sensor Unit');

    return Container(
      // Highlighted so the unit summary stands apart from the sensor cards:
      // light indigo tint + indigo border + soft shadow (a "lifted" look).
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3F51B5), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E3F51B5),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _infoRow('Product Type', Text(
            unit.version.isNotEmpty ? unit.version : 'Sensor unit',
            style: const TextStyle(fontWeight: FontWeight.w500),
          )),
          const Divider(),
          _infoRow('Name', Row(children: [
            TextButton(
              onPressed: _onEditName,
              child: const Text('Edit', style: TextStyle(color: Colors.blue)),
            ),
            Text(displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
          ])),
          const Divider(),
          _infoRow('Connection Status', Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              online
                  ? (_isDirectMode ? 'direct' : 'online')
                  : 'offline',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w500),
            ),
          ])),
          const Divider(),
          _infoRow('Active Sensors', Text(
            '${unit.sensorCount}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          )),
        ],
      ),
    );
  }

  // ----- One sensor: Sensor Type / Tag name (Edit) / Sensor value -----
  Widget _buildSensorCard(Sensor sensor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _infoRow('Sensor Type', Text(
              sensor.type.isNotEmpty ? sensor.type : '—',
              style: const TextStyle(fontWeight: FontWeight.w500),
            )),
            const Divider(),
            _infoRow('Tag name', Row(children: [
              TextButton(
                onPressed: () => _onEditTag(sensor),
                child: const Text('Edit', style: TextStyle(color: Colors.blue)),
              ),
              Text(sensor.name.isNotEmpty ? sensor.name : '—',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ])),
            const Divider(),
            _infoRow('Sensor value', Text(
              sensor.value.isNotEmpty ? sensor.value : '—',
              style: const TextStyle(fontWeight: FontWeight.w600),
            )),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, Widget trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        trailing,
      ],
    );
  }

  // ----- Bottom buttons (stubs until WiFi popup / config screen are wired) -----
  Widget _buildBottomButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _onChangeWifi,
            icon: const Icon(Icons.wifi),
            label: const Text('Change WiFi connection'),
            style: _buttonStyle(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _onSensorConfig,
            icon: const Icon(Icons.tune),
            label: const Text('Sensor configuration'),
            style: _buttonStyle(),
          ),
        ),
      ],
    );
  }

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
        backgroundColor:
            _isDirectMode ? Colors.green[700] : const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  // ----- Action stubs — name/tag editing needs the sensor edit REST
  //       endpoint (server side, not defined yet). -----
  void _onEditName() => _todo('Rename sensor unit');
  void _onEditTag(Sensor sensor) => _todo('Rename "${sensor.name}"');

  /// get/set_sensor_config are AP-mode operations — direct mode only.
  /// In server mode, tell the user to connect to the unit's hotspot.
  void _onSensorConfig() {
    if (!_isDirectMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Connect to the sensor unit\'s hotspot to configure sensors.'),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SensorConfigScreen(deviceData: widget.deviceData),
      ),
    );
  }

  void _todo(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — not wired up yet')),
    );
  }

  // -------------------------------------------------------------------------
  // WiFi Credentials Dialog (Direct mode)
  // -------------------------------------------------------------------------
  /// set_device_wifi is an AP-mode operation — the sensor unit must be the
  /// connected WiFi network. In server mode, tell the user to connect to
  /// the unit's hotspot instead of showing the dialog.
  void _onChangeWifi() {
    if (!_isDirectMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Connect to the sensor unit\'s hotspot to change its WiFi.'),
        ),
      );
      return;
    }
    _showWifiCredentialsDialog();
  }

  /// Shows a popup to enter home WiFi SSID and password, then sends
  /// set_device_wifi (sensor unit event — NOT the valve's set_valve_wifi)
  /// to the connected ESP32. Architecture Doc v3 - Sensor Unit /
  /// Details Screen - Data editing.
  void _showWifiCredentialsDialog() {
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi, color: Color(0xFF3F51B5)),
              SizedBox(width: 10),
              Text('Set Home WiFi'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your home WiFi credentials. The sensor unit will restart and connect to this network.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ssidController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'WiFi Name (SSID)',
                  hintText: 'Enter your home WiFi name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'WiFi Password',
                  hintText: 'Enter WiFi password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () {
                      setDialogState(
                          () => obscurePassword = !obscurePassword);
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isSending
                  ? null
                  : () {
                      final ssid = ssidController.text.trim();
                      final password = passwordController.text;

                      if (ssid.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter WiFi name'),
                          ),
                        );
                        return;
                      }

                      if (!EspDirectService.instance.isAuthenticated) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Not connected to sensor unit. Go back and reconnect.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);

                      EspDirectService.instance.setSensorUnitWifi(
                        ssid: ssid,
                        password: password,
                      );

                      print("📤 ESP32: set_device_wifi ssid=$ssid");

                      // ESP32 will restart — connection will be lost
                      Future.delayed(const Duration(seconds: 3), () {
                        if (mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'WiFi credentials sent! Sensor unit will restart and connect to your home WiFi.',
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 5),
                            ),
                          );
                        }
                      });
                    },
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(isSending ? 'Sending...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}