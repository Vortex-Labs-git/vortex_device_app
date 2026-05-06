import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/websocket_service.dart';
import '../../services/esp_direct_service.dart';

// Import newly extracted widgets
import 'widgets/device_app_bar.dart';
import 'widgets/device_info_card.dart';
import 'widgets/mode_toggle_card.dart';
import 'widgets/control_mode_card.dart';
import 'widgets/valve_control_card.dart';
import 'widgets/schedule_card.dart';
import 'widgets/sensor_card.dart';
import 'widgets/change_wifi_button.dart';
import 'widgets/motor_calibration_button.dart';

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
  late Map<String, dynamic> _device;
  bool _wsConnected = false;

  String _controlMode = 'manual';

  bool _isScheduleMode = false;
  bool _isSwitchingMode = false; 

  bool _isUpdating = false;
  bool _valveControlEnabled = true;

  bool _waitingForConfirmation = false;
  int? _pendingTargetAngle; 
  Timer? _confirmationTimer;
  int _confirmationCountdown = 0; 

  double _sliderAngle = 0; 
  bool _isAngleUpdating = false;
  bool _userIsEditingAngle = false; 
  Timer? _angleEditDebounce; 

  List<Map<String, dynamic>> _schedules = [];
  bool _isSavingSchedule = false;
  bool _schedulesLoadedFromServer = false; 
  bool _schedulesLocallyEdited = false; 

  StreamSubscription<Map<String, dynamic>>? _detailSub;
  StreamSubscription<Map<String, dynamic>>? _scheduleSub;
  StreamSubscription<bool>? _connectionSub;

  StreamSubscription<Map<String, dynamic>>? _espValveDataSub;
  StreamSubscription<bool>? _espConnectionSub;
  Timer? _espPollTimer;

  static const List<String> _dayOptions = [
    'Every day', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  bool get _isDirectMode => widget.isDirectMode;

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.deviceData);

    final scheduleCtrl = _device['user_schedule_ctrl'];
    _isScheduleMode = (scheduleCtrl == 1 || scheduleCtrl == '1' || scheduleCtrl == true);

    if (_isDirectMode) {
      _controlMode = 'manual';
      _isScheduleMode = false;
      _device['vwv_pos'] = null;
      _device['vwv_is_open'] = null;
      _device['vwv_is_close'] = null;
    } else {
      _controlMode = _isScheduleMode ? 'schedule' : 'manual';
    }

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
    if (!_isDirectMode) {
      WebSocketService.subscribeTo('device_list');
    }
    super.dispose();
  }

  // ============================================================
  // Websocket & Direct Services Logic
  // ============================================================
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

        if (_waitingForConfirmation && _pendingTargetAngle != null) {
          final actualPos = int.tryParse((_device['vwv_pos'] ?? '').toString()) ?? -1;
          if (actualPos == _pendingTargetAngle) {
            _onConfirmationSuccess();
          }
        }

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

    _scheduleSub = WebSocketService.scheduleStream.listen((data) {
      if (mounted && data['device_id']?.toString() == _device['id']?.toString() && !_schedulesLocallyEdited) {
        _loadScheduleFromServer(data);
      }
    });

    WebSocketService.subscribeTo('device_detail', deviceId: _device['id']?.toString());
  }

  void _setupEspDirect() {
    final esp = EspDirectService.instance;
    _wsConnected = esp.isConnected;

    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _espValveDataSub = esp.valveDataStream.listen((data) {
      if (!mounted) return;

      final valveData = data['get_valvedata'] ?? {};
      final angle = valveData['angle'];
      final isOpen = valveData['is_open'];
      final isClose = valveData['is_close'];

      if (angle != null) {
        final angleInt = angle is int ? angle : int.tryParse(angle.toString()) ?? 0;
        setState(() {
          _device['vwv_pos'] = angleInt.toString();
          _device['vwv_is_open'] = (isOpen == true) ? 1 : 0;
          _device['vwv_is_close'] = (isClose == true) ? 1 : 0;
          if (!_userIsEditingAngle) {
            _sliderAngle = angleInt.toDouble();
          }
        });
      }

      if (_waitingForConfirmation && _pendingTargetAngle != null) {
        final actualPos = _getActualPosition();
        if (actualPos == _pendingTargetAngle) {
          _onConfirmationSuccess();
        }
      }
    });

    _requestEspValveData();

    _espPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && esp.isAuthenticated) {
        _requestEspValveData();
      }
    });
  }

  void _requestEspValveData() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) return;

    final userId = _device['user_id']?.toString() ?? 'app_user';
    final deviceId = _device['id']?.toString() ?? '';
    final deviceName = _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
    esp.requestValveData(userId: userId, deviceId: deviceId, deviceName: deviceName);
  }

  bool _isDeviceOnline(String? lastSeen) {
    if (lastSeen == null || lastSeen.isEmpty || lastSeen == 'NULL') return false;
    try {
      final lastSeenTime = DateTime.parse(lastSeen);
      final now = DateTime.now();
      return now.difference(lastSeenTime).inSeconds <= 30;
    } catch (e) {
      return false;
    }
  }

  int _getActualPosition() {
    return int.tryParse((_device['vwv_pos'] ?? '0').toString()) ?? 0;
  }

  bool _isValveOpen() {
    if (_waitingForConfirmation && _pendingTargetAngle != null) {
      return _pendingTargetAngle! >= 45;
    }
    return _getActualPosition() >= 45;
  }

  // ============================================================
  // API Calls and Operations Logic
  // ============================================================

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
        'set_controller': { 'schedule': scheduleMode, 'sensor': false },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': currentAngle,
        },
        'ota_update': false,
      };

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $token' },
        body: jsonEncode(requestBody),
      );

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          setState(() {
            _isScheduleMode = scheduleMode;
            _controlMode = scheduleMode ? 'schedule' : 'manual';
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(scheduleMode ? 'Switched to Schedule mode' : 'Switched to Manual mode'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSwitchingMode = false);
    }
  }

  Future<void> _sendControlCommand(String command) async {
    setState(() => _isUpdating = true);
    int targetAngle = (command == "Open") ? 90 : 0;

    if (_isDirectMode) {
      final deviceName = _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
      EspDirectService.instance.setValveAngle(angle: targetAngle, deviceName: deviceName);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _requestEspValveData();
      });

      if (mounted) {
        _startConfirmationWait(targetAngle);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Direct command sent!'), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)));
        setState(() => _isUpdating = false);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'device_id': _device['id'],
        'set_controller': { 'schedule': false, 'sensor': false },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': targetAngle,
        }
      };

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $token' },
        body: jsonEncode(requestBody),
      );

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          _startConfirmationWait(targetAngle);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Command sent!'), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _sendAngleCommand(int angle) async {
    setState(() => _isAngleUpdating = true);

    if (_isDirectMode) {
      final deviceName = _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
      EspDirectService.instance.setValveAngle(angle: angle, deviceName: deviceName);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _requestEspValveData();
      });

      if (mounted) {
        _startConfirmationWait(angle);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Direct command sent!'), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)));
        setState(() => _isAngleUpdating = false);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'device_id': _device['id'],
        'set_controller': { 'schedule': false, 'sensor': false },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': angle,
        }
      };

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $token' },
        body: jsonEncode(requestBody),
      );

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          _startConfirmationWait(angle);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Command sent!'), backgroundColor: Colors.blue, duration: const Duration(seconds: 2)));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isAngleUpdating = false);
    }
  }

  void _startConfirmationWait(int targetAngle) {
    _confirmationTimer?.cancel();
    setState(() {
      _waitingForConfirmation = true;
      _pendingTargetAngle = targetAngle;
      _confirmationCountdown = 20;
    });

    _confirmationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _confirmationCountdown--);
      if (_confirmationCountdown <= 0) {
        timer.cancel();
        _onConfirmationTimeout();
      }
    });
  }

  void _onConfirmationSuccess() {
    _confirmationTimer?.cancel();
    setState(() {
      _waitingForConfirmation = false;
      _pendingTargetAngle = null;
      _confirmationCountdown = 0;
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Valve position confirmed!'), backgroundColor: Colors.green, duration: Duration(seconds: 2)));
  }

  void _onConfirmationTimeout() {
    final actualPos = _getActualPosition();
    final targetWas = _pendingTargetAngle;

    setState(() {
      _waitingForConfirmation = false;
      _pendingTargetAngle = null;
      _confirmationCountdown = 0;
    });

    if (targetWas != null && actualPos == targetWas) {
      _onConfirmationSuccess();
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⏳ Valve is still responding. Position will update shortly.'), backgroundColor: Colors.orange, duration: Duration(seconds: 3)));
    }
  }

  // Schedule Logic
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

      List<dynamic> parsed;
      if (scheduleJson is String) {
        parsed = jsonDecode(scheduleJson);
      } else if (scheduleJson is List) {
        parsed = scheduleJson;
      } else {
        return;
      }

      setState(() {
        _schedules = parsed.map((e) => Map<String, dynamic>.from(e)).toList();
        _schedulesLoadedFromServer = true;
      });
    } catch (e) {
      print("❌ Error parsing schedule data: $e");
    }
  }

  Future<void> _saveSchedule() async {
    setState(() => _isSavingSchedule = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $token' },
        body: jsonEncode({
          'event': 'set_valve_control',
          'device_id': _device['id'],
          'set_scheduledata': { 'set_schedule': _schedules.isNotEmpty, 'schedule_info': _schedules },
        }),
      );

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          setState(() => _schedulesLocallyEdited = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule saved successfully!'), backgroundColor: Colors.green));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSavingSchedule = false);
    }
  }

  // ============================================================
  // Helper / Time Methods
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
  // DIALOGS
  // ============================================================

  void _showAddScheduleDialog({int? editIndex}) {
    String selectedDay = editIndex != null ? _schedules[editIndex]['day'] : 'Every day';
    TimeOfDay openTime = editIndex != null ? _parseTime(_schedules[editIndex]['open'] ?? '08:00') : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay closeTime = editIndex != null ? _parseTime(_schedules[editIndex]['close'] ?? '08:20') : const TimeOfDay(hour: 8, minute: 20);

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
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: const InputDecoration(labelText: 'Day', border: OutlineInputBorder(), isDense: true),
                    items: _dayOptions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                    onChanged: (val) { setDialogState(() => selectedDay = val!); },
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: openTime);
                      if (picked != null) setDialogState(() => openTime = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Open Time', border: OutlineInputBorder(), isDense: true),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatTime(openTime), style: const TextStyle(fontSize: 16)),
                          Icon(Icons.access_time, color: Colors.green[600]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: closeTime);
                      if (picked != null) setDialogState(() => closeTime = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Close Time', border: OutlineInputBorder(), isDense: true),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatTime(closeTime), style: const TextStyle(fontSize: 16)),
                          Icon(Icons.access_time, color: Colors.red[600]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    final entry = {'day': selectedDay, 'open': _formatTime(openTime), 'close': _formatTime(closeTime)};
                    setState(() {
                      _schedulesLocallyEdited = true;
                      if (editIndex != null) _schedules[editIndex] = entry;
                      else _schedules.add(entry);
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F51B5), foregroundColor: Colors.white),
                  child: Text(editIndex != null ? 'Update' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteSchedule(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text('Delete "${_schedules[index]['day']} — Open: ${_schedules[index]['open']}, Close: ${_schedules[index]['close']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _schedulesLocallyEdited = true;
                _schedules.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showWifiCredentialsDialog() {
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Row(children: [Icon(Icons.wifi, color: Color(0xFF3F51B5)), SizedBox(width: 10), Text('Set Home WiFi')]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter your home WiFi credentials. The valve will restart and connect to this network.', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              TextField(controller: ssidController, autofocus: true, decoration: const InputDecoration(labelText: 'WiFi Name (SSID)', hintText: 'Enter your home WiFi name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.wifi))),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'WiFi Password', hintText: 'Enter WiFi password', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off), onPressed: () => setDialogState(() => obscurePassword = !obscurePassword)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: isSending ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: isSending ? null : () {
                final ssid = ssidController.text.trim();
                final password = passwordController.text;
                if (ssid.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter WiFi name'))); return; }
                if (!EspDirectService.instance.isAuthenticated) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not connected to valve. Go back and reconnect.'), backgroundColor: Colors.red)); return; }
                
                setDialogState(() => isSending = true);
                EspDirectService.instance.setWifiCredentials(ssid: ssid, password: password);
                
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WiFi credentials sent! Valve will restart and connect to your home WiFi.'), backgroundColor: Colors.green, duration: Duration(seconds: 5)));
                  }
                });
              },
              icon: isSending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
              label: Text(isSending ? 'Sending...' : 'Save & Connect'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNameDialog() {
    final controller = TextEditingController(text: _device['vwv_name'] ?? _device['device_name']);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Device Name'),
          content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Device Name', border: OutlineInputBorder())),
          actions: [
            TextButton(onPressed: isSaving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                final newName = controller.text.trim();
                if (newName.isEmpty) return;
                setDialogState(() => isSaving = true);
                
                final success = await _saveDeviceName(newName);
                if (success && mounted) {
                  setState(() {
                    _device['vwv_name'] = newName;
                    _device['device_name'] = newName;
                  });
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device name updated!'), backgroundColor: Colors.green));
                } else {
                  setDialogState(() => isSaving = false);
                }
              },
              child: isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _saveDeviceName(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_id': _device['id'],
        'set_controller': { 'schedule': _isScheduleMode, 'sensor': false },
        'valve_data': { 'name': newName, 'set_angle': true, 'angle': _getActualPosition() },
        'ota_update': false,
      };

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $token' },
        body: jsonEncode(requestBody),
      );

      final result = jsonDecode(response.body);
      if (result['success'] == true) return true;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${result['message']}'), backgroundColor: Colors.red));
      return false;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e'), backgroundColor: Colors.red));
      return false;
    }
  }

  // ============================================================
  // BUILD UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: DeviceAppBar(
        isDirectMode: _isDirectMode,
        wsConnected: _wsConnected,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeviceInfoCard(
              device: _device,
              isDirectMode: _isDirectMode,
              isOnline: _isDirectMode ? true : _isDeviceOnline(_device['vwv_last_seen']?.toString()),
              onEditName: _showEditNameDialog,
            ),
            const SizedBox(height: 16),
            
            if (!_isDirectMode) 
              ModeToggleCard(
                isScheduleMode: _isScheduleMode,
                isSwitchingMode: _isSwitchingMode,
                onToggle: _sendModeSwitch,
              ),
              
            if (!_isDirectMode) const SizedBox(height: 16),
            
            if (!_isScheduleMode && !_isDirectMode) ...[
              ControlModeCard(
                controlMode: _controlMode,
                isDirectMode: _isDirectMode,
                onModeSelected: (mode) => setState(() => _controlMode = mode),
              ),
              const SizedBox(height: 16),
            ],

            if (_isScheduleMode) 
              ScheduleCard(
                schedules: _schedules,
                isSavingSchedule: _isSavingSchedule,
                onAddSchedule: () => _showAddScheduleDialog(),
                onSaveSchedule: _saveSchedule,
                onEditSchedule: (index) => _showAddScheduleDialog(editIndex: index),
                onDeleteSchedule: _deleteSchedule,
              ),
              
            if (!_isScheduleMode && _controlMode == 'manual') 
              ValveControlCard(
                valveControlEnabled: _valveControlEnabled,
                onValveControlEnabledChanged: (value) => setState(() => _valveControlEnabled = value),
                waitingForConfirmation: _waitingForConfirmation,
                confirmationCountdown: _confirmationCountdown,
                pendingTargetAngle: _pendingTargetAngle,
                isOpen: _isValveOpen(),
                actualPos: _getActualPosition(),
                isUpdating: _isUpdating,
                onStateControlChanged: (value) => _sendControlCommand(value ? "Open" : "Closed"),
                sliderAngle: _sliderAngle,
                isAngleUpdating: _isAngleUpdating,
                onSliderChanged: _waitingForConfirmation ? null : (value) => setState(() => _sliderAngle = value),
                onSliderChangeStart: _waitingForConfirmation ? null : (_) {
                  _userIsEditingAngle = true;
                  _angleEditDebounce?.cancel();
                },
                onSliderChangeEnd: _waitingForConfirmation ? null : (_) {
                  _angleEditDebounce?.cancel();
                  _angleEditDebounce = Timer(const Duration(seconds: 3), () {
                    if (mounted) setState(() => _userIsEditingAngle = false);
                  });
                },
                onSetAngle: () {
                  _angleEditDebounce?.cancel();
                  _userIsEditingAngle = false;
                  _sendAngleCommand(_sliderAngle.round());
                },
              ),
              
            if (!_isScheduleMode && _controlMode == 'schedule') 
              ScheduleCard(
                schedules: _schedules,
                isSavingSchedule: _isSavingSchedule,
                onAddSchedule: () => _showAddScheduleDialog(),
                onSaveSchedule: _saveSchedule,
                onEditSchedule: (index) => _showAddScheduleDialog(editIndex: index),
                onDeleteSchedule: _deleteSchedule,
              ),
              
            if (!_isScheduleMode && _controlMode == 'sensor') 
              SensorCard(
                onSave: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sensor settings saved!'))),
              ),
              
            const SizedBox(height: 16),
            
            if (_isDirectMode) ...[
              ChangeWifiButton(onPressed: _showWifiCredentialsDialog),
              const SizedBox(height: 12),
              MotorCalibrationButton(deviceData: _device),
            ],
          ],
        ),
      ),
    );
  }
}