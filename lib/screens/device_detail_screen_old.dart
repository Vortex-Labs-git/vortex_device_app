import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';
import '../services/esp_direct_service.dart';
import 'manual_control_screen.dart';
import 'wifi_setup_screen.dart';
import 'motor_calibration_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData;
  final bool isDirectMode; // true = ESP32 direct, false = server mode

  const DeviceDetailScreen({
    super.key,
    required this.deviceData,
    this.isDirectMode = false,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Map<String, dynamic> _device;
  bool _wsConnected = false;

  // Control mode: 'manual', 'schedule', 'sensor'
  String _controlMode = 'manual';

  // ── Schedule/Manual mode toggle ──
  // This tells the ESP32 whether to follow schedule or user commands
  // Synced with user_schedule_ctrl from DB
  bool _isScheduleMode = false;
  bool _isSwitchingMode = false; // True while sending mode change to server

  // Valve control
  bool _isUpdating = false;
  bool _valveControlEnabled = true; // Toggle: ON = state mode, OFF = angle mode

  // ── Valve state confirmation tracking ──
  // When user sends a command, we track the expected angle
  // and wait for vwv_pos in the DB to match within ~10 seconds.
  bool _waitingForConfirmation = false;
  int? _pendingTargetAngle; // 0 or 90
  Timer? _confirmationTimer;
  int _confirmationCountdown = 0; // seconds remaining

  // Angle control (for angle mode)
  double _sliderAngle = 0; // 0-90
  bool _isAngleUpdating = false;
  bool _userIsEditingAngle = false; // True while user is dragging slider
  Timer? _angleEditDebounce; // Debounce timer to reset editing flag

  // Schedule data - format per architecture doc: {day, open, close}
  List<Map<String, dynamic>> _schedules = [];
  bool _isSavingSchedule = false;
  bool _schedulesLoadedFromServer = false; // Track if we've loaded initial data
  bool _schedulesLocallyEdited = false; // Don't overwrite user's local edits

  // Stream subscriptions
  StreamSubscription<Map<String, dynamic>>? _detailSub;
  StreamSubscription<Map<String, dynamic>>? _scheduleSub;
  StreamSubscription<bool>? _connectionSub;

  // ── ESP32 Direct Mode subscriptions ──
  StreamSubscription<Map<String, dynamic>>? _espValveDataSub;
  StreamSubscription<bool>? _espConnectionSub;
  Timer? _espPollTimer; // Periodic polling for valve state in direct mode

  // Day options
  static const List<String> _dayOptions = [
    'Every day',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // Shortcut for direct mode check
  bool get _isDirectMode => widget.isDirectMode;

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.deviceData);

    // Initialize schedule mode from DB field user_schedule_ctrl
    final scheduleCtrl = _device['user_schedule_ctrl'];
    _isScheduleMode = (scheduleCtrl == 1 || scheduleCtrl == '1' || scheduleCtrl == true);

    // In direct mode, force manual control only
    // Otherwise, set control mode based on schedule state
    if (_isDirectMode) {
      _controlMode = 'manual';
      _isScheduleMode = false;
      // Clear cached valve state — ESP32 will provide the real state
      // on first poll response. Without this, stale DB data shows wrong open/close.
      _device['vwv_pos'] = null;
      _device['vwv_is_open'] = null;
      _device['vwv_is_close'] = null;
    } else {
      _controlMode = _isScheduleMode ? 'schedule' : 'manual';
    }

    // Initialize slider angle from DB
    final vwvPos = _device['vwv_pos'];
    if (vwvPos != null) {
      _sliderAngle = (int.tryParse(vwvPos.toString()) ?? 0).toDouble();
    }

    if (_isDirectMode) {
      _setupEspDirect();
    } else {
      _setupWebSocket();
    }
  }

  @override
  void dispose() {
    _detailSub?.cancel();
    _scheduleSub?.cancel();
    _connectionSub?.cancel();
    _espValveDataSub?.cancel();
    _espConnectionSub?.cancel();
    _espPollTimer?.cancel();
    _confirmationTimer?.cancel();
    _angleEditDebounce?.cancel();
    // Switch back to device_list when leaving (server mode only)
    if (!_isDirectMode) {
      WebSocketService.subscribeTo('device_list');
    }
    super.dispose();
  }

  void _setupWebSocket() {
    _wsConnected = WebSocketService.isConnected;

    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _detailSub = WebSocketService.deviceDetailStream.listen((data) {
      if (mounted && data['id']?.toString() == _device['id']?.toString()) {
        setState(() {
          _device = {..._device, ...data};
        });

        // Sync schedule mode from server data (if not currently switching)
        if (!_isSwitchingMode) {
          final scheduleCtrl = _device['user_schedule_ctrl'];
          final serverScheduleMode = (scheduleCtrl == 1 || scheduleCtrl == '1' || scheduleCtrl == true);
          if (serverScheduleMode != _isScheduleMode) {
            setState(() {
              _isScheduleMode = serverScheduleMode;
              _controlMode = serverScheduleMode ? 'schedule' : 'manual';
            });
          }
        }

        // ── Check confirmation: compare vwv_pos with pending target ──
        if (_waitingForConfirmation && _pendingTargetAngle != null) {
          final actualPos = int.tryParse(
              (_device['vwv_pos'] ?? '').toString()) ?? -1;

          if (actualPos == _pendingTargetAngle) {
            // ✅ Valve reached target position - confirmed!
            _onConfirmationSuccess();
          }
        }

        // Update slider angle from actual position when user is NOT editing
        // and NOT waiting for angle confirmation
        if (!_userIsEditingAngle && !(_waitingForConfirmation && !_valveControlEnabled)) {
          final vwvPos = _device['vwv_pos'];
          if (vwvPos != null) {
            final parsed = int.tryParse(vwvPos.toString());
            if (parsed != null) {
              setState(() => _sliderAngle = parsed.toDouble());
            }
          }
        }
      }
    });

    // Listen to schedule updates from WebSocket
    _scheduleSub = WebSocketService.scheduleStream.listen((data) {
      if (mounted &&
          data['device_id']?.toString() == _device['id']?.toString() &&
          !_schedulesLocallyEdited) {
        _loadScheduleFromServer(data);
      }
    });

    // Subscribe to this device's detail
    WebSocketService.subscribeTo('device_detail',
        deviceId: _device['id']?.toString());
  }

  // ============================================================
  // ESP32 DIRECT MODE: Listen for valve data from ESP32
  // ============================================================
  void _setupEspDirect() {
    final esp = EspDirectService.instance;
    _wsConnected = esp.isConnected; // reuse the flag for UI

    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    // Listen for valve_data from ESP32
    // Update _device fields so all existing UI logic (open/close button,
    // confirmation, slider) works the same as server mode
    _espValveDataSub = esp.valveDataStream.listen((data) {
      if (!mounted) return;

      final valveData = data['get_valvedata'] ?? {};
      final angle = valveData['angle'];
      final isOpen = valveData['is_open'];
      final isClose = valveData['is_close'];

      // Map ESP32 valve_data fields → server DB field equivalents
      // so _getActualPosition(), _isValveOpen(), confirmation all work
      if (angle != null) {
        final angleInt = angle is int ? angle : int.tryParse(angle.toString()) ?? 0;
        setState(() {
          _device['vwv_pos'] = angleInt.toString();
          _device['vwv_is_open'] = (isOpen == true) ? 1 : 0;
          _device['vwv_is_close'] = (isClose == true) ? 1 : 0;
          // Update slider only if user is not dragging
          if (!_userIsEditingAngle) {
            _sliderAngle = angleInt.toDouble();
          }
        });
      }

      // Check confirmation (same logic as server mode)
      if (_waitingForConfirmation && _pendingTargetAngle != null) {
        final actualPos = _getActualPosition();
        if (actualPos == _pendingTargetAngle) {
          _onConfirmationSuccess();
        }
      }

      print("📱 ESP32 Direct: valve angle=$angle, open=$isOpen, close=$isClose");
    });

    // Request initial valve data from ESP32
    _requestEspValveData();

    // Poll valve data every 2 seconds (ESP32 doesn't push like server WebSocket)
    // This keeps the UI updated with the real valve state
    _espPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && esp.isAuthenticated) {
        _requestEspValveData();
      }
    });
  }

  /// Helper to request valve data from ESP32
  void _requestEspValveData() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) return;

    final userId = _device['user_id']?.toString() ?? 'app_user';
    final deviceId = _device['id']?.toString() ?? '';
    final deviceName = _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
    esp.requestValveData(
      userId: userId,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  // ============================================================
  // MODE SWITCH: Toggle between Manual and Schedule mode
  // ============================================================
  /// Send mode change to server via REST API.
  /// This tells the ESP32 (via MQTT) whether to follow
  /// schedule timings or user manual commands.
  ///
  /// Sends to control_device.php:
  /// {
  ///   "event": "set_valve_basic",
  ///   "device_id": "VA202601001",
  ///   "set_controller": { "schedule": true/false, "sensor": false },
  ///   "valve_data": { "set_angle": false, "angle": <current> },
  ///   "ota_update": false
  /// }
  Future<void> _sendModeSwitch(bool scheduleMode) async {
    setState(() => _isSwitchingMode = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final currentAngle = _getActualPosition();
      final requestBody = {
        'event': 'set_valve_basic',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_id': _device['id'],
        'set_controller': {
          'schedule': scheduleMode,
          'sensor': false,
        },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': currentAngle,
        },
        'ota_update': false,
      };

      print("📤 Mode Switch: schedule=$scheduleMode → ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      print("Mode Switch Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            _isScheduleMode = scheduleMode;
            _controlMode = scheduleMode ? 'schedule' : 'manual';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(scheduleMode
                  ? 'Switched to Schedule mode — valve follows schedule'
                  : 'Switched to Manual mode — you control the valve'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("Mode Switch Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSwitchingMode = false);
    }
  }

  // ============================================================
  // VALVE: Get current state from DB fields
  // ============================================================

  /// Check if device is online: compare vwv_last_seen with phone time.
  /// If gap > 30 seconds → offline.
  bool _isDeviceOnline(String? lastSeen) {
    if (lastSeen == null || lastSeen.isEmpty || lastSeen == 'NULL') {
      return false;
    }
    try {
      final lastSeenTime = DateTime.parse(lastSeen);
      final now = DateTime.now();
      return now.difference(lastSeenTime).inSeconds <= 30;
    } catch (e) {
      print("⚠️ Error parsing vwv_last_seen: $e");
      return false;
    }
  }

  /// Get the ACTUAL valve position from vwv_pos (physical position)
  int _getActualPosition() {
    return int.tryParse((_device['vwv_pos'] ?? '0').toString()) ?? 0;
  }

  // ============================================================
  // SCHEDULE: Load from WebSocket server data
  // ============================================================
  /// Parse schedule data from WebSocket device_schedule event
  /// Server sends: {"event":"device_schedule","device_id":"...","schedule":{...}}
  /// The schedule field contains: {"device_id":"...","schedule":"[JSON string]","set_schedule":1}
  void _loadScheduleFromServer(Map<String, dynamic> data) {
    try {
      final scheduleData = data['schedule'];
      if (scheduleData == null) return;

      final scheduleJson = scheduleData['schedule'];
      if (scheduleJson == null || scheduleJson.toString().isEmpty) {
        setState(() {
          _schedules = [];
          _schedulesLoadedFromServer = true;
        });
        return;
      }

      // Parse JSON string — could be a String or already a List
      List<dynamic> parsed;
      if (scheduleJson is String) {
        parsed = jsonDecode(scheduleJson);
      } else if (scheduleJson is List) {
        parsed = scheduleJson;
      } else {
        print("⚠️ Unexpected schedule format: ${scheduleJson.runtimeType}");
        return;
      }

      setState(() {
        _schedules = parsed
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _schedulesLoadedFromServer = true;
      });

      print("📅 Loaded ${_schedules.length} schedule entries from server");
    } catch (e) {
      print("❌ Error parsing schedule data: $e");
    }
  }

  /// Get the USER-REQUESTED position from user_vwv_pos
  int _getUserRequestedPosition() {
    return int.tryParse((_device['user_vwv_pos'] ?? '0').toString()) ?? 0;
  }

  /// Determine if valve is open based on actual position
  bool _isValveOpen() {
    if (_waitingForConfirmation && _pendingTargetAngle != null) {
      // While waiting, show the pending state
      return _pendingTargetAngle! >= 45;
    }
    return _getActualPosition() >= 45;
  }

  // ============================================================
  // VALVE: Send Open/Close command via REST API or ESP32 Direct
  // ============================================================
  Future<void> _sendControlCommand(String command) async {
    setState(() => _isUpdating = true);

    int targetAngle = (command == "Open") ? 90 : 0;

    // ── ESP32 DIRECT MODE: Send directly to ESP32 ──
    if (_isDirectMode) {
      final deviceName = _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
      print("📤 ESP32 Direct: set_valve_basic angle=$targetAngle");
      EspDirectService.instance.setValveAngle(
        angle: targetAngle,
        deviceName: deviceName,
      );

      // Request valve data back so ESP32 sends its updated state
      // The polling timer also does this, but this ensures a quick response
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _requestEspValveData();
      });

      if (mounted) {
        _startConfirmationWait(targetAngle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Direct command sent! Valve ${command == "Open" ? "opening" : "closing"}...'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() => _isUpdating = false);
      }
      return;
    }

    // ── SERVER MODE: Send via REST API ──
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'device_id': _device['id'],
        'set_controller': {
          'schedule': false,
          'sensor': false,
        },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': targetAngle,
        }
      };

      print("📤 State Request Body: ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      print("Control Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          // ── Start confirmation wait ──
          _startConfirmationWait(targetAngle);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Command sent! Waiting for valve to ${command == "Open" ? "open" : "close"}...'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("Control Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ============================================================
  // VALVE: Confirmation Wait Logic
  // ============================================================

  /// Start waiting for vwv_pos to match targetAngle (up to 20 seconds)
  void _startConfirmationWait(int targetAngle) {
    _confirmationTimer?.cancel();

    setState(() {
      _waitingForConfirmation = true;
      _pendingTargetAngle = targetAngle;
      _confirmationCountdown = 20;
    });

    // Check every second
    _confirmationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _confirmationCountdown--);

      if (_confirmationCountdown <= 0) {
        // ⏰ Timeout - revert to actual DB position
        timer.cancel();
        _onConfirmationTimeout();
      }
    });
  }

  /// Valve confirmed - position matches target
  void _onConfirmationSuccess() {
    _confirmationTimer?.cancel();
    setState(() {
      _waitingForConfirmation = false;
      _pendingTargetAngle = null;
      _confirmationCountdown = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Valve position confirmed!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Timeout - DON'T revert the UI. Just stop the countdown spinner
  /// and let WebSocket naturally update the UI when DB catches up.
  ///
  /// Why: The valve may have physically moved but the DB update
  /// arrived just after our 20-second window. The next WebSocket
  /// push (within ~2 seconds) will deliver the correct vwv_pos
  /// and the UI will update smoothly via _detailSub / _espValveDataSub.
  void _onConfirmationTimeout() {
    final actualPos = _getActualPosition();
    final targetWas = _pendingTargetAngle;

    setState(() {
      _waitingForConfirmation = false;
      _pendingTargetAngle = null;
      _confirmationCountdown = 0;
      // ✅ DON'T revert _sliderAngle here — let WebSocket update it naturally
      // The next device_detail push will set the real position
    });

    // Check if it actually reached in the last moment
    if (targetWas != null && actualPos == targetWas) {
      _onConfirmationSuccess();
    } else {
      // Valve hasn't confirmed yet — show a gentle message
      // The UI will self-correct within 2-4 seconds when
      // the next WebSocket push arrives with the updated vwv_pos
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⏳ Valve is still responding. Position will update shortly.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ============================================================
  // VALVE: Send Angle command via REST API (angle mode)
  // Uses same confirmation logic as state mode
  // ============================================================
  Future<void> _sendAngleCommand(int angle) async {
    setState(() => _isAngleUpdating = true);

    // ── ESP32 DIRECT MODE: Send directly to ESP32 ──
    if (_isDirectMode) {
      final deviceName = _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
      print("📤 ESP32 Direct: set_valve_basic angle=$angle");
      EspDirectService.instance.setValveAngle(
        angle: angle,
        deviceName: deviceName,
      );

      // Request valve data back so ESP32 sends its updated state
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _requestEspValveData();
      });

      if (mounted) {
        _startConfirmationWait(angle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Direct command sent! Setting angle to $angle°...'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() => _isAngleUpdating = false);
      }
      return;
    }

    // ── SERVER MODE: Send via REST API ──
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'device_id': _device['id'],
        'set_controller': {
          'schedule': false,
          'sensor': false,
        },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': angle,
        }
      };

      print("📤 Angle Request Body: ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      print("Angle Control Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          // ── Start confirmation wait (same as state mode) ──
          _startConfirmationWait(angle);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Command sent! Waiting for valve to reach $angle°...'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("Angle Control Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAngleUpdating = false);
    }
  }

  // ============================================================
  // SCHEDULE: Add Entry Dialog (Architecture doc format)
  // Each entry: { "day": "Monday", "open": "08:00", "close": "08:20" }
  // ============================================================
  void _showAddScheduleDialog({int? editIndex}) {
    // Pre-fill if editing
    String selectedDay =
        editIndex != null ? _schedules[editIndex]['day'] : 'Every day';
    TimeOfDay openTime = editIndex != null
        ? _parseTime(_schedules[editIndex]['open'] ?? '08:00')
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay closeTime = editIndex != null
        ? _parseTime(_schedules[editIndex]['close'] ?? '08:20')
        : const TimeOfDay(hour: 8, minute: 20);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(editIndex != null ? 'Edit Schedule' : 'Add Schedule'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day Picker
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _dayOptions
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedDay = val!);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Open Time Picker
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: openTime,
                      );
                      if (picked != null) {
                        setDialogState(() => openTime = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Open Time',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(openTime),
                            style: const TextStyle(fontSize: 16),
                          ),
                          Icon(Icons.access_time, color: Colors.green[600]),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Close Time Picker
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: closeTime,
                      );
                      if (picked != null) {
                        setDialogState(() => closeTime = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Close Time',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(closeTime),
                            style: const TextStyle(fontSize: 16),
                          ),
                          Icon(Icons.access_time, color: Colors.red[600]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final entry = {
                      'day': selectedDay,
                      'open': _formatTime(openTime),
                      'close': _formatTime(closeTime),
                    };

                    setState(() {
                      _schedulesLocallyEdited = true;
                      if (editIndex != null) {
                        _schedules[editIndex] = entry;
                      } else {
                        _schedules.add(entry);
                      }
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(editIndex != null ? 'Update' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // SCHEDULE: Delete Entry
  // ============================================================
  void _deleteSchedule(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text(
            'Delete "${_schedules[index]['day']} — Open: ${_schedules[index]['open']}, Close: ${_schedules[index]['close']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _schedulesLocallyEdited = true;
                _schedules.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SCHEDULE: Save to Server via REST API
  // ============================================================
  Future<void> _saveSchedule() async {
    setState(() => _isSavingSchedule = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final response = await http.post(
        Uri.parse(
            'https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': 'set_valve_control',
          'device_id': _device['id'],
          'set_scheduledata': {
            'set_schedule': _schedules.isNotEmpty,
            'schedule_info': _schedules,
          },
        }),
      );

      print("📅 Schedule Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          setState(() => _schedulesLocallyEdited = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Schedule saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("📅 Schedule Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSchedule = false);
    }
  }

  // ============================================================
  // Time Helpers
  // ============================================================
  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  // ============================================================
  // BUILD UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_isDirectMode ? 'Direct Control' : 'Vortex Labs'),
        backgroundColor: _isDirectMode ? Colors.green[700] : const Color(0xFF3F51B5),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Direct mode banner hidden
            _buildInfoCard(),
            const SizedBox(height: 16),
            // ── Mode toggle: Manual ↔ Schedule ──
            if (!_isDirectMode) _buildModeToggleCard(),
            if (!_isDirectMode) const SizedBox(height: 16),
            // Show control mode selector and valve/schedule cards based on mode
            if (!_isScheduleMode && !_isDirectMode) ...[
              _buildControlModeCard(),
              const SizedBox(height: 16),
            ],
            if (_isScheduleMode) _buildScheduleCard(),
            if (!_isScheduleMode && _controlMode == 'manual') _buildValveControlCard(),
            if (!_isScheduleMode && _controlMode == 'schedule') _buildScheduleCard(),
            if (!_isScheduleMode && _controlMode == 'sensor') _buildSensorCard(),
            const SizedBox(height: 16),
            // ── Direct-mode-only action buttons ──
            // Shown only when the user is connected straight to the
            // ESP32 over its AP (Vortex_VA<deviceId>). In server mode
            // these actions don't apply.
            if (_isDirectMode) ...[
              _buildChangeWifiButton(),
              const SizedBox(height: 12),
              _buildMotorCalibrationButton(),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MODE TOGGLE CARD: Manual ↔ Schedule
  // ============================================================
  Widget _buildModeToggleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Control method',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            // Toggle row
            Row(
              children: [
                // Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isScheduleMode
                        ? Colors.orange.shade50
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _isScheduleMode ? Icons.schedule : Icons.pan_tool,
                    color: _isScheduleMode ? Colors.orange : const Color(0xFF3F51B5),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Labels
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Manual',
                            style: TextStyle(
                              fontWeight: !_isScheduleMode ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                              color: !_isScheduleMode ? const Color(0xFF3F51B5) : Colors.grey,
                            ),
                          ),
                          Text(
                            '  /  ',
                            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                          ),
                          Text(
                            'Schedule',
                            style: TextStyle(
                              fontWeight: _isScheduleMode ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                              color: _isScheduleMode ? Colors.orange : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isScheduleMode
                            ? 'Valve follows the schedule automatically'
                            : 'You control the valve position',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                // Switch
                if (_isSwitchingMode)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: _isScheduleMode,
                    activeColor: Colors.orange,
                    inactiveThumbColor: const Color(0xFF3F51B5),
                    inactiveTrackColor: const Color(0xFF3F51B5).withOpacity(0.3),
                    onChanged: (value) {
                      _sendModeSwitch(value);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO CARD
  // ============================================================
  Widget _buildInfoCard() {
    bool isOnline = _isDirectMode ? true : _isDeviceOnline(_device['vwv_last_seen']?.toString());
    String statusText = _isDirectMode ? 'Direct Connected' : (isOnline ? 'online' : 'offline');
    Color statusColor = isOnline ? Colors.green : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow(
                'Product Type', _device['type'] ?? 'WiFi Valve v1'),
            const Divider(),
            _buildInfoRowWithEdit(
                'Name',
                _device['vwv_name'] ??
                    _device['device_name'] ??
                    'Unknown'),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Connection Status',
                    style: TextStyle(color: Colors.grey)),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildInfoRowWithEdit(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Row(
          children: [
            TextButton(
              onPressed: () => _showEditNameDialog(),
              child:
                  const Text('Edit', style: TextStyle(color: Colors.blue)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // CONTROL MODE CARD
  // ============================================================
  Widget _buildControlModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Control by',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModeButton('manual', Icons.pan_tool, 'manual'),
                _buildModeButton('schedule', Icons.schedule, 'schedule'),
                _buildModeButton('sensor', Icons.sensors, 'sensor'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(String mode, IconData icon, String label) {
    bool isSelected = _controlMode == mode;
    // In direct mode, only manual control is allowed
    bool isDisabled = _isDirectMode && (mode == 'schedule' || mode == 'sensor');

    return GestureDetector(
      onTap: isDisabled
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Schedule & Sensor require server connection'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          : () {
              setState(() => _controlMode = mode);
            },
      child: Opacity(
        opacity: isDisabled ? 0.35 : 1.0,
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3F51B5) : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                isDisabled ? Icons.lock_outline : icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // VALVE CONTROL CARD (Manual Mode)
  // Toggle ON  → State mode (Open/Close with DB confirmation)
  // Toggle OFF → Angle mode (Slider 0-90°)
  // ============================================================
  Widget _buildValveControlCard() {
    bool isOpen = _isValveOpen();
    int actualPos = _getActualPosition();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: "Valve control" + enable toggle ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Valve control',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Transform.scale(
                  scale: 1.2,
                  child: Switch(
                    value: _valveControlEnabled,
                    onChanged: _waitingForConfirmation
                        ? null // Disable mode switch while waiting
                        : (value) {
                            setState(() => _valveControlEnabled = value);
                          },
                    activeColor: const Color(0xFF3F51B5),
                  ),
                ),
              ],
            ),

            // ── Mode indicator ──
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _valveControlEnabled
                    ? 'Mode: Open / Close'
                    : 'Mode: Angle control',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── STATE MODE (when toggle is ON) ──
            if (_valveControlEnabled) ...[
              // Waiting indicator hidden in state mode
              // if (_waitingForConfirmation) ...[
              // ],

              // By state row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('By state', style: TextStyle(color: Colors.grey)),
                  Row(
                    children: [
                      Text(
                        isOpen ? 'Open' : 'Close',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isOpen
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                      const SizedBox(width: 8),
                      (_isUpdating || _waitingForConfirmation)
                          ? SizedBox(
                              width: 48,
                              height: 28,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _waitingForConfirmation
                                        ? Colors.blue
                                        : null,
                                  ),
                                ),
                              ),
                            )
                          : Switch(
                              value: isOpen,
                              onChanged: (value) {
                                _sendControlCommand(
                                    value ? "Open" : "Closed");
                              },
                              activeColor: Colors.green,
                              inactiveTrackColor: Colors.red.shade200,
                              inactiveThumbColor: Colors.red,
                            ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Show actual position info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Actual position',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '$actualPos°',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: actualPos >= 45
                            ? Colors.green[700]
                            : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── ANGLE MODE (when toggle is OFF) ──
            if (!_valveControlEnabled) ...[
              const Text('By angle', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),

              // Waiting indicator (same style as state mode)
              if (_waitingForConfirmation) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Waiting for valve... ${_confirmationCountdown}s',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        'Target: ${_pendingTargetAngle}°',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Angle dial visualization
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.grey[300]!, width: 8),
                        ),
                      ),
                      // Angle indicator needle
                      Transform.rotate(
                        angle: (_sliderAngle / 90) * (math.pi / 2),
                        child: Container(
                          width: 4,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _waitingForConfirmation
                                ? Colors.blue
                                : const Color(0xFF3F51B5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Center dot
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _waitingForConfirmation
                              ? Colors.blue
                              : const Color(0xFF3F51B5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Angle value display
              Center(
                child: Text(
                  '${_sliderAngle.round()}°',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _waitingForConfirmation
                        ? Colors.blue
                        : const Color(0xFF3F51B5),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Angle slider - disabled during confirmation wait
              Row(
                children: [
                  const Text('0°',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _sliderAngle,
                      min: 0,
                      max: 90,
                      divisions: 90,
                      activeColor: _waitingForConfirmation
                          ? Colors.grey
                          : const Color(0xFF3F51B5),
                      inactiveColor: Colors.grey[300],
                      label: '${_sliderAngle.round()}°',
                      // Disable slider while waiting for confirmation
                      onChanged: _waitingForConfirmation
                          ? null
                          : (value) {
                              setState(() => _sliderAngle = value);
                            },
                      onChangeStart: _waitingForConfirmation
                          ? null
                          : (_) {
                              // User started dragging - stop WebSocket from
                              // overwriting slider value
                              _userIsEditingAngle = true;
                              _angleEditDebounce?.cancel();
                            },
                      onChangeEnd: _waitingForConfirmation
                          ? null
                          : (_) {
                              // User stopped dragging - keep editing flag
                              // for 3 seconds so WebSocket doesn't snap it
                              // back before user taps "Set Angle"
                              _angleEditDebounce?.cancel();
                              _angleEditDebounce = Timer(
                                const Duration(seconds: 3),
                                () {
                                  if (mounted) {
                                    setState(
                                        () => _userIsEditingAngle = false);
                                  }
                                },
                              );
                            },
                    ),
                  ),
                  const Text('90°',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),

              const SizedBox(height: 8),

              // Set angle button - disabled during confirmation wait
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_isAngleUpdating || _waitingForConfirmation)
                      ? null
                      : () {
                          // Cancel the debounce so editing flag resets
                          _angleEditDebounce?.cancel();
                          _userIsEditingAngle = false;
                          _sendAngleCommand(_sliderAngle.round());
                        },
                  icon: (_isAngleUpdating || _waitingForConfirmation)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_waitingForConfirmation
                      ? 'Waiting... ${_confirmationCountdown}s'
                      : _isAngleUpdating
                          ? 'Sending...'
                          : 'Set Angle to ${_sliderAngle.round()}°'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF3F51B5).withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Actual position info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Actual position',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '$actualPos°',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: actualPos >= 45
                            ? Colors.green[700]
                            : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SCHEDULE CARD (Working version)
  // ============================================================
  Widget _buildScheduleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${_schedules.length} entries',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Table Header: Day | Open | Close
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Center(
                          child: Text('Day',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)))),
                  Expanded(
                      flex: 2,
                      child: Center(
                          child: Text('Open',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)))),
                  Expanded(
                      flex: 2,
                      child: Center(
                          child: Text('Close',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)))),
                  SizedBox(width: 40), // Space for delete button
                ],
              ),
            ),

            // Schedule Rows
            if (_schedules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No schedules added yet.\nTap + to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ..._schedules.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return _buildScheduleRowInteractive(
                  i,
                  s['day'] ?? '',
                  s['open'] ?? '',
                  s['close'] ?? '',
                );
              }),

            const SizedBox(height: 12),

            // Add Schedule Button
            Center(
              child: TextButton.icon(
                onPressed: () => _showAddScheduleDialog(),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Schedule'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3F51B5),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingSchedule ? null : _saveSchedule,
                icon: _isSavingSchedule
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label:
                    Text(_isSavingSchedule ? 'Saving...' : 'Save Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF3F51B5).withOpacity(0.6),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRowInteractive(
      int index, String day, String openTime, String closeTime) {
    return InkWell(
      onTap: () => _showAddScheduleDialog(editIndex: index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  day,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  openTime,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.green[700]),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  closeTime,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.red[700]),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red[300],
                onPressed: () => _deleteSchedule(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SENSOR CARD (placeholder - unchanged)
  // ============================================================
  Widget _buildSensorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sensor Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '+ Add sensor',
                  style: TextStyle(color: Color(0xFF3F51B5)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Upper limit')),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '80',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Lower limit')),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '60',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Sensor settings saved!')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WIFI BUTTON
  // ============================================================
  Widget _buildWifiButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          if (_isDirectMode) {
            // In direct mode, ESP32 is already connected — show simple dialog
            _showWifiCredentialsDialog();
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const WifiSetupScreen()),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3F51B5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text('WiFi Only Direct'),
      ),
    );
  }

  // ============================================================
  // CHANGE WIFI CONNECTION BUTTON (direct mode bottom of screen)
  // ============================================================
  /// Shown at the bottom of the screen when in direct mode.
  /// Opens the same dialog that lets the user enter home WiFi credentials
  /// and pushes them to the ESP32 via set_valve_wifi.
  Widget _buildChangeWifiButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showWifiCredentialsDialog,
        icon: const Icon(Icons.wifi),
        label: const Text('Change WiFi connection'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3F51B5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MOTOR CALIBRATION BUTTON (direct mode, sits under Change WiFi)
  // ============================================================
  /// Opens the MotorCalibrationScreen, where the user can rotate
  /// the motor and set close/open encoder limits on the ESP32.
  Widget _buildMotorCalibrationButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MotorCalibrationScreen(deviceData: _device),
            ),
          );
        },
        icon: const Icon(Icons.tune),
        label: const Text('Motor Calibration'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3F51B5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // WIFI CREDENTIALS DIALOG (Direct Mode)
  // ============================================================
  /// Shows a popup to enter home WiFi SSID and password.
  /// Sends set_valve_wifi to the already-connected ESP32.
  /// Architecture Doc Page 13.
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
                'Enter your home WiFi credentials. The valve will restart and connect to this network.',
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
                              content: Text('Please enter WiFi name')),
                        );
                        return;
                      }

                      if (!EspDirectService.instance.isAuthenticated) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Not connected to valve. Go back and reconnect.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);

                      // Send to ESP32 per Architecture Doc Page 13
                      EspDirectService.instance.setWifiCredentials(
                        ssid: ssid,
                        password: password,
                      );

                      print("📤 ESP32: set_valve_wifi ssid=$ssid");

                      // ESP32 will restart — connection will be lost
                      Future.delayed(const Duration(seconds: 3), () {
                        if (mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'WiFi credentials sent! Valve will restart and connect to your home WiFi.',
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
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(isSending ? 'Sending...' : 'Save & Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // EDIT NAME DIALOG
  // ============================================================
  void _showEditNameDialog() {
    final controller = TextEditingController(
        text: _device['vwv_name'] ?? _device['device_name']);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Device Name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Device Name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final newName = controller.text.trim();
                      if (newName.isEmpty) return;

                      setDialogState(() => isSaving = true);

                      // Send to server via REST API
                      final success = await _saveDeviceName(newName);

                      if (success && mounted) {
                        setState(() {
                          _device['vwv_name'] = newName;
                          _device['device_name'] = newName;
                        });
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Device name updated!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        setDialogState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Save device name to backend via control_device.php
  /// Architecture Doc Page 8: set_valve_basic with valve_data.name
  Future<bool> _saveDeviceName(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_id': _device['id'],
        'set_controller': {
          'schedule': _isScheduleMode,
          'sensor': false,
        },
        'valve_data': {
          'name': newName,
          'set_angle': true,
          'angle': _getActualPosition(),
        },
        'ota_update': false,
      };

      print("📤 Name Update: ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      print("Name Update Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        return true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      print("Name Update Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }
}