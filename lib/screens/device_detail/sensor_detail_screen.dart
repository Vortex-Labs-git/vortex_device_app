import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import '../../services/websocket_service.dart';
import '../../services/esp_direct_service.dart';
import '../../models/sensor_unit.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass/glass.dart';
import '../sensor_config_screen.dart';
import 'dialogs/wifi_credentials_dialog.dart';
import 'widgets/change_wifi_button.dart';
import 'widgets/sensor_type_style.dart';
import 'widgets/tool_row.dart';
import 'widgets/valve_header.dart';
import '../../utils/app_log.dart';

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
// Preview mode (previewMode = true): used ONLY by the @Preview builders at
// the bottom of this file for the VS Code Flutter Widget Preview panel.
// Skips ALL networking (no WebSocketService, no EspDirectService, no poll
// timer) and seeds _unit directly from deviceData so the GUI renders with
// dummy data. Defaults to false — production behavior is unchanged.
//
// On dispose, server mode resubscribes to 'device_list' so the home list
// resumes; direct mode must NOT touch the cloud WebSocket. The Device tools
// card ("Change Wi-Fi" → set_device_wifi sheet; "Sensor configuration"
// → SensorConfigScreen) renders in DIRECT MODE ONLY — both are AP-mode
// operations, so server (online) mode shows no tools at all.
// Unit name Edit remains a stub until the sensor edit REST is defined.
// Sensor tag names are read-only.
// =============================================================================

class SensorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData; // from the home list: id, name, ...
  final bool isDirectMode;
  final bool previewMode; // widget-preview only — bypasses all networking

  const SensorDetailScreen({
    super.key,
    required this.deviceData,
    this.isDirectMode = false,
    this.previewMode = false,
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

  // -- Shortcuts --
  bool get _isDirectMode => widget.isDirectMode;
  bool get _isPreviewMode => widget.previewMode;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.deviceData['id']?.toString() ?? '';

    // Preview mode: no WebSocket, no ESP32, no polling. Seed the unit
    // straight from deviceData (cloud-style keys) so the UI renders.
    if (_isPreviewMode) {
      _unit = SensorUnit.fromJson(widget.deviceData);
      _wsConnected = true; // green connection icon in the app bar
      return;
    }

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
    // Preview mode never subscribed, so it must not touch the singleton here.
    if (!_isDirectMode && !_isPreviewMode) {
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
      logD('📱 ESP32 Direct: sensor_unit_info, '
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
  // Build  (UI v2)
  // ---------------------------------------------------------------------------
  // Forest header (same band as the valve) → sensor tiles, two per row →
  // direct-mode Device tools. Offline, a red note says when the unit was last
  // heard from and the values blur, so an old reading never looks live.
  @override
  Widget build(BuildContext context) {
    final unit = _unit;
    final bool online = unit != null && _isDeviceOnline(unit.lastSeen);
    final String fallbackName =
        widget.deviceData['name']?.toString() ?? 'Sensor Unit';
    final String displayName =
        unit != null && unit.name.isNotEmpty ? unit.name : fallbackName;
    final double topInset = MediaQuery.paddingOf(context).top;

    return GlassScaffold(
      // The forest header draws behind the status bar itself.
      useSafeArea: false,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              ValveHeader(
                deviceName: displayName,
                deviceId: _deviceId,
                productType: _headerDetails(unit),
                isOnline: online,
                isDirectMode: _isDirectMode,
                linkConnected: _wsConnected,
                onEditName: _onEditName,
                productLine: 'Sensor unit',
                imageAsset: 'assets/images/SU_1.jpeg',
                fallbackIcon: Icons.sensors_rounded,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (unit == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      if (!online) ...[
                        _offlineNote(unit),
                        const SizedBox(height: 14),
                      ],
                      _sensorsTitle(online),
                      const SizedBox(height: 10),
                      if (unit.sensors.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text('No sensors reported',
                                style:
                                    TextStyle(color: GlassTokens.textMuted)),
                          ),
                        )
                      else
                        _sensorGrid(unit.sensors, online),
                    ],

                    // Direct-mode device tools. Both are AP-mode operations,
                    // so in server (online) mode this card does not exist.
                    if (_isDirectMode) ...[
                      const SizedBox(height: 14),
                      _deviceTools(),
                    ],
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

  /// "1.0.0 · 4 sensors" under the name in the header.
  String _headerDetails(SensorUnit? unit) {
    if (unit == null) return 'Sensor unit';
    final String count =
        '${unit.sensorCount} sensor${unit.sensorCount == 1 ? '' : 's'}';
    return unit.version.isNotEmpty ? '${unit.version} · $count' : count;
  }

  Widget _offlineNote(SensorUnit unit) {
    final String lastSeen = unit.lastSeen ?? '';
    final String detail = _isDirectMode
        ? 'Direct link lost. Values are the last ones received.'
        : lastSeen.isEmpty || lastSeen.toUpperCase() == 'NULL'
            ? 'No recent data. Values are the last ones received.'
            : 'Last seen $lastSeen. Values are the last ones received.';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: GlassTokens.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 18, color: GlassTokens.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Unit offline · ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: detail),
                ],
              ),
              style: const TextStyle(
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

  Widget _sensorsTitle(bool online) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Sensors',
            style: TextStyle(
              fontFamily: GlassTokens.displayFont,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: GlassTokens.textPrimary,
            ),
          ),
        ),
        Text(
          online ? 'Live' : 'Last values',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: GlassTokens.textMuted,
          ),
        ),
      ],
    );
  }

  /// Two tiles per row.
  Widget _sensorGrid(List<Sensor> sensors, bool online) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double gap = 10;
        final double w = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in sensors)
              SizedBox(width: w, child: _sensorTile(s, online)),
          ],
        );
      },
    );
  }

  // ----- One sensor: type icon / tag name / value / type · slot -----
  Widget _sensorTile(Sensor sensor, bool online) {
    final style = SensorTypeStyle.of(sensor.type);
    final String type = sensor.type.isNotEmpty ? sensor.type : 'Sensor';

    Widget value = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _formatSensorNumber(sensor),
            style: TextStyle(
              fontFamily: GlassTokens.displayFont,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1,
              color: online ? style.color : GlassTokens.textMuted,
            ),
          ),
          if (_unitSuffix(sensor).isNotEmpty)
            TextSpan(
              text: ' ${_unitSuffix(sensor)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: GlassTokens.textMuted,
              ),
            ),
        ],
      ),
      maxLines: 1,
    );
    value = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: value,
    );
    if (!online) {
      // ImageFiltered blurs its own child only — cheap, unlike a backdrop.
      value = Opacity(
        opacity: 0.6,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: value,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GlassTokens.surface,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        border: Border.all(color: GlassTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(style.icon, size: 19, color: style.color),
          ),
          const SizedBox(height: 8),
          Text(
            sensor.name.isNotEmpty ? sensor.name : '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: GlassTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: online ? null : 'Last value, unit offline',
            child: value,
          ),
          const SizedBox(height: 6),
          Text(
            '$type · ${_displaySensorId(sensor)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: GlassTokens.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _deviceTools() {
    return GlassCard(
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
            onPressed: _onChangeWifi,
            subtitle: 'Send your farm Wi-Fi to the unit',
          ),
          const Divider(height: 1, color: GlassTokens.border),
          ToolRow(
            icon: Icons.tune_rounded,
            iconColor: GlassTokens.info,
            iconBackground: GlassTokens.info.withValues(alpha: 0.1),
            title: 'Sensor configuration',
            subtitle: 'Set the type and name of each sensor',
            onPressed: _onSensorConfig,
          ),
        ],
      ),
    );
  }

  // ----- Sensor id display formatting -----
  // Backend sensor ids are 0-based (S00..S07) but the GUI shows them
  // 1-based (S01..S08) — same convention as the config screen headers.
  // Handles both bare "S00" and prefixed "SU202601003_S00" formats;
  // anything unrecognized is shown as-is.
  String _displaySensorId(Sensor sensor) {
    final raw = sensor.id.trim();
    final tail =
        raw.contains('_') ? raw.substring(raw.lastIndexOf('_') + 1) : raw;
    final match = RegExp(r'^[Ss](\d+)$').firstMatch(tail);
    if (match == null) return raw;
    final n = int.parse(match.group(1)!) + 1;
    return 'S${n.toString().padLeft(2, '0')}';
  }

  // ----- Sensor value display formatting -----
  // Numeric readings are shown with exactly 2 decimal places ("24.5" →
  // "24.50", "61" → "61.00"). Non-numeric values pass through unchanged
  // (the format varies per sensor, so don't break anything exotic).
  String _formatSensorNumber(Sensor sensor) {
    final raw = sensor.value.trim();
    if (raw.isEmpty) return '—';
    final parsed = double.tryParse(raw);
    return parsed != null ? parsed.toStringAsFixed(2) : raw;
  }

  // Unit suffix by sensor type: temperature → °C, humidity → %.
  String _unitSuffix(Sensor sensor) {
    if (sensor.value.trim().isEmpty) return '';
    final type = sensor.type.toLowerCase();
    if (type.contains('temp')) return '°C';
    if (type.contains('humid')) return '%';
    return '';
  }

  // ----- Action stubs — unit name editing needs the sensor edit REST
  //       endpoint (server side, not defined yet). Sensor tag names are
  //       read-only in this screen. -----
  void _onEditName() => _todo('Rename sensor unit');

  /// get/set_sensor_config are AP-mode operations. The row that reaches
  /// this only renders in direct mode, so no server-mode guard is needed.
  /// Preview mode never navigates — SensorConfigScreen would try to talk
  /// to EspDirectService.
  void _onSensorConfig() {
    if (_isPreviewMode) {
      _todo('Sensor configuration (preview)');
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

  /// Direct mode only (the row lives in Device tools). Same sheet as the
  /// valve, but it sends the sensor unit's own event, set_device_wifi — NOT
  /// the valve's set_valve_wifi. In preview mode nothing is ever sent: the
  /// sheet checks isAuthenticated, which is false there.
  void _onChangeWifi() {
    showWifiCredentialsDialog(context, isSensorUnit: true);
  }
}

// =============================================================================
// WIDGET PREVIEWS (VS Code Flutter Widget Preview panel only)
// =============================================================================
// previewMode: true bypasses all networking and seeds the unit straight from
// deviceData. last_seen is set to "now" at build time so the status dot shows
// online/green — a hardcoded timestamp would fail the 30-second check.
// =============================================================================

@Preview(
  name: 'Sensor Detail — Server mode',
  size: Size(390, 844),
)
Widget sensorDetailScreenPreview() {
  final now = DateTime.now().toUtc().toIso8601String();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SensorDetailScreen(
      previewMode: true,
      deviceData: {
        'id': 'SU202601003',
        'unit_name': 'Greenhouse Sensor',
        'unit_version': '1.0.0',
        'unit_last_seen': now,
        'last_seen': now,
        'no_sensors': '2',
        'sensor_data':
            '[{"sensor_id":"S00","sensor_type":"Temperature","sensor_name":"Temperature","sensor_value":"24.5"},{"sensor_id":"S01","sensor_type":"Humidity","sensor_name":"Humidity","sensor_value":"61"}]',
      },
    ),
  );
}

@Preview(
  name: 'Sensor Detail — Direct mode',
  size: Size(390, 844),
)
Widget sensorDetailScreenDirectPreview() {
  final now = DateTime.now().toUtc().toIso8601String();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SensorDetailScreen(
      previewMode: true,
      isDirectMode: true,
      deviceData: {
        'id': 'SU202601003',
        'unit_name': 'Greenhouse Sensor',
        'unit_version': '1.0.0',
        'unit_last_seen': now,
        'last_seen': now,
        'no_sensors': '2',
        'sensor_data':
            '[{"sensor_id":"S00","sensor_type":"Temperature","sensor_name":"Temperature","sensor_value":"24.5"},{"sensor_id":"S01","sensor_type":"Humidity","sensor_name":"Humidity","sensor_value":"61"}]',
      },
    ),
  );
}