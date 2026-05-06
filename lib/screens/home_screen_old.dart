import 'package:flutter/material.dart';
import 'dart:async';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import '../services/local_storage_service.dart';
import '../services/esp_direct_service.dart';
import 'device_detail/device_detail_screen.dart';
import 'wifi_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // State
  List<dynamic> _devices = [];
  bool _isLoading = true;
  bool _wsConnected = false;
  String? _errorMessage;

  // ── Offline / ESP32 AP mode state ──
  bool _isOfflineMode = false;
  bool _isEspApMode = false;
  String? _connectedSsid;
  String? _espConnectedDeviceId;
  bool _isEspConnecting = false;

  // ── Debug terminal ──
  bool _showDebugPanel = false;
  final List<String> _debugLogs = [];
  final ScrollController _debugScrollController = ScrollController();
  final TextEditingController _espIpController = TextEditingController(text: '192.168.137.1');
  final TextEditingController _espPortController = TextEditingController(text: '80');
  final TextEditingController _espPasskeyController = TextEditingController(text: '12345');

  // Stream subscriptions
  StreamSubscription<List<dynamic>>? _deviceListSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<bool>? _espConnectionSub;
  StreamSubscription<Map<String, dynamic>>? _espDeviceInfoSub;
  StreamSubscription<Map<String, dynamic>>? _espValveDataSub;
  StreamSubscription<Map<String, dynamic>>? _espErrorSub;

  // WiFi info
  final NetworkInfo _networkInfo = NetworkInfo();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deviceListSub?.cancel();
    _connectionSub?.cancel();
    _espConnectionSub?.cancel();
    _espDeviceInfoSub?.cancel();
    _espValveDataSub?.cancel();
    _espErrorSub?.cancel();
    _debugScrollController.dispose();
    _espIpController.dispose();
    _espPortController.dispose();
    _espPasskeyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWifiConnection();
      if (_isOfflineMode && !_isEspApMode) {
        WebSocketService.resetReconnectAttempts();
        WebSocketService.connect().then((connected) {
          if (connected) {
            WebSocketService.subscribeTo('device_list');
          }
        });
      }
    }
  }

  // ============================================================
  // DEBUG LOG HELPER
  // ============================================================
  void _log(String message) {
    final time = DateTime.now().toString().substring(11, 19);
    if (mounted) {
      setState(() {
        _debugLogs.add("[$time] $message");
        // Keep last 200 lines
        if (_debugLogs.length > 200) {
          _debugLogs.removeAt(0);
        }
      });
      // Auto-scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_debugScrollController.hasClients) {
          _debugScrollController.animateTo(
            _debugScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================
  Future<void> _initialize() async {
    _log("App initializing...");

    // Step 1: Load cached devices
    final cachedDevices = await LocalStorageService.getDeviceList();
    if (cachedDevices.isNotEmpty && mounted) {
      setState(() {
        _devices = cachedDevices;
        _isLoading = false;
        _isOfflineMode = true;
      });
      _log("Loaded ${cachedDevices.length} cached devices");
    } else {
      _log("No cached devices found");
    }

    // Step 2: Setup WebSocket listeners
    _setupWebSocket();

    // Step 3: Check WiFi
    await _checkWifiConnection();

    // Step 4: Setup ESP32 listeners
    _setupEspListeners();

    // Step 5: Restore ESP32 direct connection state if already connected
    // This handles the case where user switches tabs and comes back
    _restoreEspState();
  }

  /// If EspDirectService is already connected and authenticated,
  /// restore the device status flags so the UI shows "Direct Connected"
  void _restoreEspState() {
    final esp = EspDirectService.instance;
    if (esp.isConnected && esp.isAuthenticated && esp.connectedDeviceId != null) {
      final deviceId = esp.connectedDeviceId!;
      _log("ESP32: Restoring connection state for $deviceId");

      setState(() {
        _espConnectedDeviceId = deviceId;
        _isEspConnecting = false;

        for (int i = 0; i < _devices.length; i++) {
          if (_devices[i]['id']?.toString() == deviceId) {
            _devices[i] = Map<String, dynamic>.from(_devices[i]);
            _devices[i]['_esp_connected'] = true;
            _devices[i]['_esp_is_user_device'] = true;
          }
        }
      });
    }
  }

  // ============================================================
  // SERVER WEBSOCKET
  // ============================================================
  void _setupWebSocket() {
    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _wsConnected = connected;
          if (connected) _isOfflineMode = false;
        });
        _log("Server WS: ${connected ? 'CONNECTED' : 'DISCONNECTED'}");
      }
    });

    _deviceListSub = WebSocketService.deviceListStream.listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
          _isOfflineMode = false;
          _errorMessage = null;
        });
        _log("Server WS: Received ${devices.length} devices");
        LocalStorageService.saveDeviceList(devices);
      }
    });

    _wsConnected = WebSocketService.isConnected;

    if (WebSocketService.isConnected) {
      WebSocketService.subscribeTo('device_list');
      setState(() => _isOfflineMode = false);
      _log("Server WS: Already connected, subscribed to device_list");
    } else {
      _log("Server WS: Not connected, waiting...");
      _waitForConnection();
    }
  }

  void _waitForConnection() async {
    await Future.delayed(const Duration(seconds: 3));

    if (WebSocketService.isConnected) {
      WebSocketService.subscribeTo('device_list');
      _log("Server WS: Connected after wait");
    } else {
      if (_isEspApMode) {
        _log("Server WS: In AP mode, skipping server");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isOfflineMode = true;
          });
        }
        return;
      }

      _log("Server WS: Trying one more connect...");
      final connected = await WebSocketService.connect();
      if (connected) {
        WebSocketService.subscribeTo('device_list');
        _log("Server WS: Connected!");
      } else {
        _log("Server WS: Failed — offline mode");
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isOfflineMode = true;
            if (_devices.isEmpty) {
              _errorMessage = "No server connection and no cached devices.\nPlease connect to the internet and login first.";
            }
          });
        }
      }
    }
  }

  // ============================================================
  // WIFI CHECK
  // ============================================================
  Future<void> _checkWifiConnection() async {
    try {
      final locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        final result = await Permission.location.request();
        if (!result.isGranted) {
          _log("WiFi: Location permission DENIED");
          return;
        }
      }

      final ssid = await _networkInfo.getWifiName();
      final cleanSsid = ssid?.replaceAll('"', '');

      if (mounted) {
        setState(() {
          _connectedSsid = cleanSsid;
          _isEspApMode = cleanSsid != null &&
              cleanSsid.startsWith('Vortex_VA');
        });
      }

      _log("WiFi SSID: ${cleanSsid ?? 'null'} | AP Mode: $_isEspApMode");

      if (_isEspApMode && !EspDirectService.instance.isConnected) {
        _connectToEsp32();
      }

      // If we're on normal WiFi (not AP mode) and server is NOT connected,
      // try reconnecting — user likely switched back from valve hotspot to internet
      if (!_isEspApMode && !WebSocketService.isConnected) {
        _log("WiFi: Normal WiFi detected, trying server reconnect...");
        WebSocketService.resetReconnectAttempts();
        WebSocketService.connect().then((connected) {
          if (connected) {
            WebSocketService.subscribeTo('device_list');
            _log("Server WS: Reconnected after WiFi switch!");
          } else {
            _log("Server WS: Still can't reach server");
          }
        });
      }
    } catch (e) {
      _log("WiFi check error: $e");
    }
  }

  // ============================================================
  // ESP32 DIRECT CONNECTION
  // ============================================================
  void _setupEspListeners() {
    final esp = EspDirectService.instance;

    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {});
        _log("ESP32 WS: ${connected ? 'CONNECTED' : 'DISCONNECTED'}");
        if (connected) {
          final userId = AuthService.currentUser?['id']?.toString() ?? 'app_user';
          _log("ESP32: Sending request_device_info (passkey: '${_espPasskeyController.text}', user: $userId)");
          esp.authenticate(
            passkey: _espPasskeyController.text,
            userId: userId,
          );
        }
      }
    });

    _espDeviceInfoSub = esp.deviceInfoStream.listen((data) async {
      if (!mounted) return;

      final deviceId = data['device_id']?.toString();
      _log("ESP32: device_info received → ID: $deviceId");

      if (deviceId != null) {
        final isUserDevice = await LocalStorageService.isUserDevice(deviceId);
        _log("ESP32: Device '$deviceId' belongs to user: $isUserDevice");

        setState(() {
          _espConnectedDeviceId = deviceId;
          _isEspConnecting = false;

          for (int i = 0; i < _devices.length; i++) {
            if (_devices[i]['id']?.toString() == deviceId) {
              _devices[i] = Map<String, dynamic>.from(_devices[i]);
              _devices[i]['_esp_connected'] = true;
              _devices[i]['_esp_is_user_device'] = isUserDevice;
            }
          }
        });

        if (isUserDevice) {
          _showSnackBar('✅ Connected to your valve: $deviceId');
        } else {
          _showSnackBar('⚠️ This valve ($deviceId) is not assigned to your account');
        }
      }
    });

    // Listen for valve data (debug display)
    _espValveDataSub = esp.valveDataStream.listen((data) {
      if (!mounted) return;
      final angle = data['get_valvedata']?['angle'] ?? '?';
      final isOpen = data['get_valvedata']?['is_open'] ?? false;
      _log("ESP32: valve_data → angle=${angle}°, open=$isOpen");
    });

    // Listen for errors
    _espErrorSub = esp.errorStream.listen((data) {
      if (!mounted) return;
      _log("ESP32 ERROR: ${data['error'] ?? data['message'] ?? 'unknown'}");
    });
  }

  /// Connect to ESP32 using IP/port from debug panel
  Future<void> _connectToEsp32({String? overrideIp, int? overridePort}) async {
    if (_isEspConnecting) return;

    final ip = overrideIp ?? EspDirectService.defaultApIp;
    final port = overridePort ?? EspDirectService.defaultPort;

    setState(() => _isEspConnecting = true);
    _log("ESP32: Connecting to ws://$ip:$port/ws ...");

    final success = await EspDirectService.instance.connect(ip: ip, port: port);

    if (mounted) {
      if (!success) {
        setState(() => _isEspConnecting = false);
        _log("ESP32: Connection FAILED");
      }
    }
  }

  // ============================================================
  // DEVICE STATUS
  // ============================================================
  /// Check if device is online based on vwv_last_seen.
  /// If the time gap between now and vwv_last_seen > 30 seconds → offline.
  /// NOTE: Server and phone must be in the same timezone for accuracy.
  String _getDeviceStatus(Map<String, dynamic> device) {
    if (device['_esp_connected'] == true) return 'esp_connected';

    final lastSeen = device['vwv_last_seen'];
    if (lastSeen == null || lastSeen.toString().isEmpty || lastSeen == 'NULL') {
      return 'offline';
    }
    try {
      final lastSeenTime = DateTime.parse(lastSeen.toString());
      final now = DateTime.now();
      final difference = now.difference(lastSeenTime).inSeconds;
      return difference <= 30 ? 'online' : 'offline';
    } catch (e) {
      return 'offline';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'online':
      case 'esp_connected':
        return Colors.green;
      default:
        return Colors.red;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'online':
        return 'Online';
      case 'esp_connected':
        return 'Direct Connected';
      default:
        return 'Offline';
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  // ============================================================
  // NAVIGATION
  // ============================================================
  void _onDeviceTap(Map<String, dynamic> device) {
    final status = _getDeviceStatus(device);

    if (status == 'esp_connected') {
      // Open DeviceDetailScreen in direct ESP32 mode
      // Valve control works, schedule/sensor are restricted
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceDetailScreen(
            deviceData: device,
            isDirectMode: true,
          ),
        ),
      );
    } else if (status == 'online') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceDetailScreen(deviceData: device),
        ),
      );
    } else {
      _showSnackBar(
        'Device is offline. Connect to its hotspot or use the debug panel below.',
      );
    }
  }

  // ============================================================
  // BUILD UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Main content area ──
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("Loading devices...",
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : _errorMessage != null && _devices.isEmpty
                    ? _buildErrorView()
                    : _devices.isEmpty
                        ? _buildEmptyView()
                        : _buildDeviceListView(),
          ),

          // Debug terminal hidden (toggle bar and panel removed from UI)
          // _buildDebugToggleBar(),
          // if (_showDebugPanel) _buildDebugPanel(),
        ],
      ),
    );
  }

  // ============================================================
  // ERROR / EMPTY VIEWS (unchanged)
  // ============================================================
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 60, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() { _isLoading = true; _errorMessage = null; });
                _initialize();
              },
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text("No devices found", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text("Please contact Vortex Labs to get devices assigned to your account.",
                style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DEVICE LIST VIEW
  // ============================================================
  Widget _buildDeviceListView() {
    return Column(
      children: [
        _buildConnectionStatusBar(),
        // AP mode banner hidden
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _checkWifiConnection();
              if (!_wsConnected) {
                final connected = await WebSocketService.connect();
                if (connected) WebSocketService.subscribeTo('device_list');
              }
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, index) => _buildDeviceCard(_devices[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionStatusBar() {
    Color barColor;
    String barText;
    IconData barIcon;

    if (_wsConnected) {
      barColor = Colors.green;
      barText = "Live updates active";
      barIcon = Icons.wifi;
    } else if (_isEspApMode) {
      barColor = const Color(0xFF3F51B5);
      barText = "Direct mode — ${_connectedSsid ?? 'Valve WiFi'}";
      barIcon = Icons.settings_remote;
    } else {
      barColor = Colors.orange;
      barText = "Offline — showing cached devices";
      barIcon = Icons.wifi_off;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      color: barColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(barIcon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(barText,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildApModeBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(
            EspDirectService.instance.isConnected ? Icons.check_circle : Icons.settings_remote,
            color: EspDirectService.instance.isConnected ? Colors.green : const Color(0xFF3F51B5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  EspDirectService.instance.isConnected
                      ? 'Connected to valve directly'
                      : 'Valve WiFi detected',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  EspDirectService.instance.isConnected
                      ? 'Device: ${_espConnectedDeviceId ?? "Identifying..."}'
                      : 'Tap a device to set up WiFi or control directly',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          if (_isEspConnecting)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(dynamic device) {
    final deviceMap = Map<String, dynamic>.from(device);
    final status = _getDeviceStatus(deviceMap);
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onDeviceTap(deviceMap),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[200],
          ),
          child: Row(
            children: [
              Container(
                width: 80, height: 80,
                margin: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Center(
                  child: Icon(Icons.settings_remote, size: 40,
                      color: status == 'esp_connected' ? Colors.green : Colors.indigo),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceMap['vwv_name'] ?? deviceMap['device_name'] ?? 'Unknown Device',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text("ID: ${deviceMap['id']}",
                        style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(statusText,
                            style: TextStyle(fontWeight: FontWeight.w500, color: statusColor, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                width: 12, height: 104,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // DEBUG TERMINAL
  // ============================================================

  Widget _buildDebugToggleBar() {
    return GestureDetector(
      onTap: () => setState(() => _showDebugPanel = !_showDebugPanel),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        color: const Color(0xFF1E1E1E),
        child: Row(
          children: [
            const Icon(Icons.bug_report, color: Colors.greenAccent, size: 16),
            const SizedBox(width: 8),
            const Text(
              'Debug Terminal',
              style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'monospace'),
            ),
            const Spacer(),
            // ESP32 connection status dot
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: EspDirectService.instance.isConnected ? Colors.greenAccent : Colors.red,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              EspDirectService.instance.isConnected ? 'ESP' : 'ESP OFF',
              style: TextStyle(
                color: EspDirectService.instance.isConnected ? Colors.greenAccent : Colors.red,
                fontSize: 10, fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              _showDebugPanel ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: Colors.greenAccent, size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    return Container(
      height: 280,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // ── ESP32 Connection Controls ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                // IP input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _espIpController,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: 'IP Address',
                        hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey[700]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey[700]!),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF3C3C3C),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Port input
                SizedBox(
                  width: 50,
                  height: 32,
                  child: TextField(
                    controller: _espPortController,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Port',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF3C3C3C),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Connect button
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: _isEspConnecting
                        ? null
                        : () {
                            final ip = _espIpController.text.trim();
                            final port = int.tryParse(_espPortController.text.trim()) ?? 80;
                            _connectToEsp32(overrideIp: ip, overridePort: port);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EspDirectService.instance.isConnected
                          ? Colors.red[700]
                          : Colors.green[700],
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      EspDirectService.instance.isConnected ? 'Disconnect' : 'Connect ESP',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Quick action buttons ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                _debugActionButton('📡 Request Info', () {
                  if (!EspDirectService.instance.isAuthenticated) {
                    _log("⚠️ Not authenticated yet");
                    return;
                  }
                  final userId = AuthService.currentUser?['id']?.toString() ?? 'test';
                  final deviceId = _espConnectedDeviceId ?? 'VA202601001';
                  _log("→ Requesting valve data for $deviceId");
                  EspDirectService.instance.requestValveData(
                    userId: userId, deviceId: deviceId, deviceName: 'Valve',
                  );
                }),
                const SizedBox(width: 6),
                _debugActionButton('🔓 Open Valve', () {
                  if (!EspDirectService.instance.isAuthenticated) {
                    _log("⚠️ Not authenticated yet");
                    return;
                  }
                  _log("→ set_valve_basic angle=90 (OPEN)");
                  EspDirectService.instance.openValve(deviceName: 'Valve');
                }),
                const SizedBox(width: 6),
                _debugActionButton('🔒 Close Valve', () {
                  if (!EspDirectService.instance.isAuthenticated) {
                    _log("⚠️ Not authenticated yet");
                    return;
                  }
                  _log("→ set_valve_basic angle=0 (CLOSE)");
                  EspDirectService.instance.closeValve(deviceName: 'Valve');
                }),
                const SizedBox(width: 6),
                _debugActionButton('🗑️ Clear', () {
                  setState(() => _debugLogs.clear());
                }),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF444444)),

          // ── Log output area ──
          Expanded(
            child: ListView.builder(
              controller: _debugScrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _debugLogs.length,
              itemBuilder: (context, index) {
                final log = _debugLogs[index];
                Color textColor = Colors.grey[400]!;
                if (log.contains('ERROR') || log.contains('FAILED') || log.contains('❌')) {
                  textColor = Colors.red[300]!;
                } else if (log.contains('CONNECTED') || log.contains('✅') || log.contains('Received')) {
                  textColor = Colors.greenAccent;
                } else if (log.contains('ESP32')) {
                  textColor = Colors.cyanAccent;
                } else if (log.contains('→')) {
                  textColor = Colors.amberAccent;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _debugActionButton(String label, VoidCallback onTap) {
    return Expanded(
      child: SizedBox(
        height: 28,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            side: BorderSide(color: Colors.grey[700]!),
            foregroundColor: Colors.grey[300],
          ),
          child: Text(label, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}