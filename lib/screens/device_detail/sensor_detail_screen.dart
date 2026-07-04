import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/websocket_service.dart';
import '../../models/sensor_unit.dart';

// =============================================================================
// SENSOR DETAIL SCREEN
// =============================================================================
// Screen for one WiFi sensor unit (device id starts with "SU"). Server mode
// only. Subscribes to the unit over WebSocket, parses each device_basic_detail
// push into a SensorUnit, and renders the unit info + each sensor reading.
//
// Mirrors the valve screen's WebSocket lifecycle: listen to deviceDetailStream
// filtered by this unit's id, subscribe to 'device_detail', and on dispose go
// back to 'device_list' so the home list resumes. Read-only for now — the two
// bottom buttons are stubs until the sensor edit/config REST is defined.
// =============================================================================

class SensorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData; // from the home list: id, name, ...

  const SensorDetailScreen({super.key, required this.deviceData});

  @override
  State<SensorDetailScreen> createState() => _SensorDetailScreenState();
}

class _SensorDetailScreenState extends State<SensorDetailScreen> {
  late final String _deviceId; // id we subscribe with / filter pushes against
  SensorUnit? _unit;           // latest push; null until the first one arrives
  bool _wsConnected = false;

  StreamSubscription? _detailSub;
  StreamSubscription? _connectionSub;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.deviceData['id']?.toString() ?? '';
    _setupWebSocket();
  }

  @override
  void dispose() {
    _detailSub?.cancel();
    _connectionSub?.cancel();
    WebSocketService.subscribeTo('device_list'); // resume home list updates
    super.dispose();
  }

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

  // Online if reported within 30s. Depends on the server sending a parseable
  // unit_last_seen (same dependency the valve has). Unparseable -> offline.
  bool _isDeviceOnline(String? lastSeen) {
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
        title: const Text('Vortex Labs'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _wsConnected ? Icons.wifi : Icons.wifi_off,
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
            Text(online ? 'online' : 'offline',
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w500)),
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

  // ----- Bottom buttons (stubs until sensor edit/config REST is defined) -----
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
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  // ----- Action stubs — wire up when the sensor edit/config REST is ready -----
  void _onEditName() => _todo('Rename sensor unit');
  void _onEditTag(Sensor sensor) => _todo('Rename "${sensor.name}"');
  void _onChangeWifi() => _todo('Change WiFi connection');
  void _onSensorConfig() => _todo('Sensor configuration');

  void _todo(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — not wired up yet')),
    );
  }
}