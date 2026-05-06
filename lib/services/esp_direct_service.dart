import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// ESP32 Direct Communication Service
/// 
/// Aligned with actual ESP32 firmware implementation:
///   - websocket_server_fn.c: Server lifecycle, async broadcast, URI /ws
///   - websocket_state_fn.c: Event processing, authentication, state updates
///   - WEBSOCKET_MSG_FLOW.md: Message formats and flow
///
/// Connection Flow:
///   1. Connect to ws://<ip>:<port>/ws
///   2. Authenticate with request_device_info + passkey
///   3. ESP32 responds with device_info (device_id)
///   4. Request valve data with device_basic_info
///   5. Control valve with set_valve_basic
///   6. Configure WiFi with set_valve_wifi
class EspDirectService {
  static EspDirectService? _instance;
  static EspDirectService get instance => _instance ??= EspDirectService._();
  
  EspDirectService._();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isAuthenticated = false; // ESP32 requires auth before processing commands
  String? _connectedDeviceIp;
  String? _connectedDeviceId;
  
  // Stream controllers for different event types
  final _connectionStateController = StreamController<bool>.broadcast();
  final _deviceInfoController = StreamController<Map<String, dynamic>>.broadcast();
  final _valveDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _motorCalibrationController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Public streams
  Stream<bool> get connectionStream => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get deviceInfoStream => _deviceInfoController.stream;
  Stream<Map<String, dynamic>> get valveDataStream => _valveDataController.stream;
  Stream<Map<String, dynamic>> get motorCalibrationStream => _motorCalibrationController.stream;
  Stream<Map<String, dynamic>> get errorStream => _errorController.stream;
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  String? get connectedDeviceIp => _connectedDeviceIp;
  String? get connectedDeviceId => _connectedDeviceId;

  // Default ESP32 AP mode settings
  // ESP32 httpd server runs on port 80, WebSocket URI is /ws
  static const String defaultApIp = '192.168.4.1';
  static const int defaultPort = 80;
  static const String wsPath = '/ws';

  // ============================================================
  // CONNECTION MANAGEMENT
  // ============================================================

  /// Connect to ESP32 WebSocket server
  /// 
  /// ESP32 registers WebSocket handler at URI: /ws
  /// Server runs on default HTTP port 80
  /// See: websocket_server_fn.c → start_webserver()
  Future<bool> connect({
    String ip = defaultApIp,
    int port = defaultPort,
  }) async {
    try {
      print('🔄 ESP32: Connecting to ws://$ip:$port$wsPath');
      
      await disconnect();
      
      final wsUri = Uri(
        scheme: 'ws',
        host: ip,
        port: port,
        path: wsPath,
      );
      
      _channel = WebSocketChannel.connect(wsUri);
      
      await _channel!.ready;
      
      _isConnected = true;
      _isAuthenticated = false; // Must authenticate after connect
      _connectedDeviceIp = ip;
      _connectionStateController.add(true);
      
      print('✅ ESP32: WebSocket connected!');
      
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('❌ ESP32: WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('🔌 ESP32: WebSocket closed');
          _handleDisconnect();
        },
      );
      
      return true;
    } catch (e) {
      print('❌ ESP32: Connection failed: $e');
      _handleDisconnect();
      return false;
    }
  }

  /// Disconnect from ESP32
  Future<void> disconnect() async {
    if (_channel != null) {
      await _channel!.sink.close(status.goingAway);
      _channel = null;
    }
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isAuthenticated = false;
    _connectedDeviceIp = null;
    _connectedDeviceId = null;
    _connectionStateController.add(false);
  }

  // ============================================================
  // INCOMING MESSAGE HANDLER
  // ============================================================

  /// Handle incoming WebSocket messages from ESP32
  /// 
  /// ESP32 sends these event types:
  ///   - device_info: After successful authentication
  ///   - valve_data: Full valve state (controller, position, limits, error)
  ///   - valve_error: Error notification broadcast
  /// 
  /// See: websocket_state_fn.c → send_device_info(), send_device_data()
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      final event = data['event'] as String?;
      
      print('📨 ESP32 Event: $event');
      print('📨 Full message: $message');
      
      switch (event) {
        // ── Authentication response ──
        // ESP32 sends this after valid passkey
        // Format: {"event":"device_info","timestamp":"...","device_id":"DEVICE_ID"}
        // See: websocket_state_fn.c → send_device_info()
        case 'device_info':
          _isAuthenticated = true;
          _connectedDeviceId = data['device_id'];
          _deviceInfoController.add(Map<String, dynamic>.from(data));
          print('✅ ESP32: Authenticated! Device ID: $_connectedDeviceId');
          break;
        
        // ── Full valve state data ──
        // ESP32 sends this in response to device_basic_info request
        // Format: {"event":"valve_data","timestamp":"...","device_id":"...",
        //          "get_controller":{...},"get_valvedata":{...},
        //          "get_limitdata":{...},"Error":"..."}
        // See: websocket_state_fn.c → send_device_data()
        case 'valve_data':
          _valveDataController.add(Map<String, dynamic>.from(data));
          break;
        
        // ── Motor calibration data ──
        // ESP32 sends this in response to:
        //   - get_motor_calibration request (initial load)
        //   - set_motor_rotation clockwise/anticlockwise (real-time encoder updates)
        // Format: {"event":"get_motor_calibration","timestamp":"...","device_id":"...",
        //          "encoder_data":{"value":2500,"Close_limit":2000,"Open_limit":3500}}
        // The app screen decides whether to use Close_limit/Open_limit (only on first reply)
        // or just the real-time `value` (on subsequent replies).
        case 'get_motor_calibration':
          _motorCalibrationController.add(Map<String, dynamic>.from(data));
          break;
        
        // ── Error broadcast ──
        // ESP32 can broadcast errors to all connected clients
        // Format: {"event":"valve_error","timestamp":"...","device_id":"...","error":"..."}
        case 'valve_error':
          _errorController.add(Map<String, dynamic>.from(data));
          break;
        
        default:
          print('⚠️ ESP32: Unknown event type: $event');
      }
    } catch (e) {
      print('❌ ESP32: Parse error: $e');
    }
  }

  /// Send JSON message to ESP32
  void _send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      print('⚠️ ESP32: Not connected');
      return;
    }
    final message = jsonEncode(data);
    print('📤 ESP32 Sending: $message');
    _channel!.sink.add(message);
  }

  // ============================================================
  // AUTHENTICATION
  // ============================================================

  /// Authenticate with ESP32 using passkey
  /// 
  /// This MUST be called first after connecting.
  /// ESP32 will not process any other events until authenticated.
  /// 
  /// Real ESP32 expects (confirmed via Postman):
  /// ```json
  /// {
  ///   "event": "request_device_info",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "user_id": "user_id",
  ///   "passkey": "12345"
  /// }
  /// ```
  /// 
  /// ESP32 responds with:
  /// ```json
  /// {
  ///   "event": "device_info",
  ///   "timestamp": "1970-01-01T00:13:09",
  ///   "device_id": "VA202601001"
  /// }
  /// ```
  void authenticate({required String passkey, String? userId}) {
    _send({
      'event': 'request_device_info',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'user_id': userId ?? 'app_user',
      'passkey': passkey,
    });
  }

  // ============================================================
  // REQUEST VALVE DATA
  // ============================================================

  /// Request full valve state from ESP32
  /// 
  /// Architecture Doc Page 11:
  /// ```json
  /// {
  ///   "event": "device_basic_info",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "data": {
  ///     "user_id": "user001",
  ///     "device_id": "dev0016",
  ///     "device_name": "home valve"
  ///   }
  /// }
  /// ```
  void requestValveData({
    required String userId,
    required String deviceId,
    String? deviceName,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'device_basic_info',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'data': {
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName ?? 'Valve',
      },
    });
  }

  // ============================================================
  // VALVE CONTROL
  // ============================================================

  /// Set valve angle (manual control)
  /// 
  /// Architecture Doc Page 12 - exact format ESP32 expects:
  /// ```json
  /// {
  ///   "event": "set_valve_basic",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "dev0016",
  ///   "set_controller": { "schedule": false, "sensor": false },
  ///   "valve_data": { "name": "MainValve01", "set_angle": true, "angle": 45 },
  ///   "ota_update": false
  /// }
  /// ```
  void setValveAngle({required int angle, String? deviceName}) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_valve_basic',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'set_controller': {
        'schedule': false,
        'sensor': false,
      },
      'valve_data': {
        'name': deviceName ?? 'Valve',
        'set_angle': true,
        'angle': angle.clamp(0, 90),
      },
      'ota_update': false,
    });
  }

  /// Open valve fully (angle = 90)
  void openValve({String? deviceName}) {
    setValveAngle(angle: 90, deviceName: deviceName);
  }

  /// Close valve fully (angle = 0)
  void closeValve({String? deviceName}) {
    setValveAngle(angle: 0, deviceName: deviceName);
  }

  // ============================================================
  // MOTOR CALIBRATION
  // ============================================================

  /// Request motor calibration data from ESP32 (initial load)
  /// 
  /// Called once when MotorCalibrationScreen opens.
  /// ESP32 responds with `get_motor_calibration` event containing
  /// encoder_data { value, Close_limit, Open_limit }.
  /// 
  /// edit.pdf - Motor Calibration process:
  /// ```json
  /// {
  ///   "event": "get_motor_calibration",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "VA202604001"
  /// }
  /// ```
  void requestMotorCalibration() {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'get_motor_calibration',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
    });
  }

  /// Turn motor clockwise or anti-clockwise (called per-tap)
  /// 
  /// User taps "Turn motor Clockwise" or "Turn motor Anticlockwise"
  /// continuously. Each tap sends one rotation command. ESP32 replies
  /// with a `get_motor_calibration` message containing the updated
  /// real-time encoder value.
  /// 
  /// edit.pdf - Motor Calibration process:
  /// ```json
  /// {
  ///   "event": "set_motor_rotation",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "VA202604001",
  ///   "set_motor": {
  ///     "turn_clkwise": true,
  ///     "Turn_anticlkwise": false
  ///   }
  /// }
  /// ```
  void setMotorRotation({required bool clockwise}) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_motor_rotation',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'set_motor': {
        'turn_clkwise': clockwise,
        'Turn_anticlkwise': !clockwise,
      },
    });
  }

  /// Save calibration limits to ESP32
  /// 
  /// Called when user taps "save" on MotorCalibrationScreen, after
  /// they have set close value / open value. Sends only the limits
  /// (no `value` field — that's sensor data, not user-set).
  /// 
  /// edit.pdf - Motor Calibration process:
  /// ```json
  /// {
  ///   "event": "set_motor_calibration",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "VA202604001",
  ///   "encoder_data": {
  ///     "Close_limit": 2000,
  ///     "Open_limit": 3500
  ///   }
  /// }
  /// ```
  void setMotorCalibration({
    required int closeLimit,
    required int openLimit,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_motor_calibration',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'encoder_data': {
        'Close_limit': closeLimit,
        'Open_limit': openLimit,
      },
    });
  }

  // ============================================================
  // WIFI CONFIGURATION
  // ============================================================

  /// Set WiFi credentials for ESP32 STA mode
  /// 
  /// Architecture Doc Page 13:
  /// ```json
  /// {
  ///   "event": "set_valve_wifi",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "dev0016",
  ///   "wifi_data": {
  ///     "ssid": "myNetWork",
  ///     "password": "1234"
  ///   }
  /// }
  /// ```
  /// 
  /// WARNING: ESP32 will restart after saving new credentials!
  ///          The WebSocket connection will be lost.
  void setWifiCredentials({
    required String ssid,
    required String password,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_valve_wifi',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'wifi_data': {
        'ssid': ssid,
        'password': password,
      },
    });
  }

  // ============================================================
  // CONVENIENCE METHODS
  // ============================================================

  /// Connect and authenticate in one step
  /// Returns true if both connection and authentication message were sent
  /// Listen to deviceInfoStream to confirm authentication success
  Future<bool> connectAndAuthenticate({
    String ip = defaultApIp,
    int port = defaultPort,
    required String passkey,
  }) async {
    final connected = await connect(ip: ip, port: port);
    if (connected) {
      authenticate(passkey: passkey);
      return true;
    }
    return false;
  }

  /// Request valve data using the connected device ID
  /// Call this after authentication (when connectedDeviceId is available)
  void requestCurrentValveData({required String userId}) {
    if (_connectedDeviceId != null) {
      requestValveData(
        userId: userId,
        deviceId: _connectedDeviceId!,
      );
    } else {
      print('⚠️ ESP32: No device ID available. Authenticate first.');
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  /// Dispose all resources
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _deviceInfoController.close();
    _valveDataController.close();
    _motorCalibrationController.close();
    _errorController.close();
  }
}