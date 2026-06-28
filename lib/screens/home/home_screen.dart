import 'package:flutter/material.dart';
import 'dart:async';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/auth_service.dart';
import '../../services/websocket_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/esp_direct_service.dart';
import '../device_detail/device_detail_screen.dart';
import '../device_detail/sensor_detail_screen.dart';
// Local card widgets
import 'widgets/error_view.dart';
import 'widgets/empty_view.dart';
import 'widgets/connection_status_bar.dart';
import 'widgets/device_card.dart';
// Imports kept ready for when the debug terminal & AP banner are re-enabled
// in build(). Marked unused-ignore to silence linter until they're wired up.
// ignore: unused_import
import 'widgets/ap_mode_banner.dart';
// ignore: unused_import
import 'widgets/debug_toggle_bar.dart';
// ignore: unused_import
import 'widgets/debug_panel.dart';

// =============================================================================
// HOME SCREEN
// =============================================================================
// Top-level screen showing the user's devices. Owns ALL state, WebSocket
// subscriptions, ESP32-direct subscriptions, WiFi-permission handling,
// debug logging, and navigation. The build method composes the widgets in
// widgets/ and wires them up via callbacks.
//
// Two source-of-truth modes for the device list:
//   - Server mode  → WebSocketService.deviceListStream (online, fresh data)
//   - Cached mode  → LocalStorageService.getDeviceList() (offline fallback)
//
// Plus a parallel ESP32 direct connection that can mark a single device as
// "_esp_connected" so it can be opened in DeviceDetailScreen direct mode.
// =============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ===========================================================================
  // SECTION 1: STATE VARIABLES
  // ===========================================================================

  // -- Device list & loading state --
  List<dynamic> _devices = [];
  bool _isLoading = true;
  bool _wsConnected = false;
  String? _errorMessage;

  // -- Offline / ESP32 AP mode --
  bool _isOfflineMode = false;
  bool _isEspApMode = false;
  String? _connectedSsid;
  String? _espConnectedDeviceId;
  bool _isEspConnecting = false;

  // -- Debug terminal --
  bool _showDebugPanel = false;
  final List<String> _debugLogs = [];
  final ScrollController _debugScrollController = ScrollController();
  final TextEditingController _espIpController =
      TextEditingController(text: '192.168.137.1');
  final TextEditingController _espPortController =
      TextEditingController(text: '80');
  final TextEditingController _espPasskeyController =
      TextEditingController(text: '12345');

  // -- Stream subscriptions --
  StreamSubscription<List<dynamic>>? _deviceListSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<bool>? _espConnectionSub;
  StreamSubscription<Map<String, dynamic>>? _espDeviceInfoSub;
  StreamSubscription<Map<String, dynamic>>? _espValveDataSub;
  StreamSubscription<Map<String, dynamic>>? _espErrorSub;

  // -- WiFi info --
  final NetworkInfo _networkInfo = NetworkInfo();

  // ===========================================================================
  // SECTION 2: LIFECYCLE METHODS
  // ===========================================================================

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
      // If we were offline and we're not on a valve hotspot, try to
      // reconnect to the server WebSocket
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

  // ===========================================================================
  // SECTION 3: DEBUG LOG HELPER
  // ===========================================================================
  // Adds a timestamped line to _debugLogs and auto-scrolls the panel to the
  // bottom. Caps the buffer at 200 lines.

  void _log(String message) {
    final time = DateTime.now().toString().substring(11, 19);
    if (mounted) {
      setState(() {
        _debugLogs.add("[$time] $message");
        if (_debugLogs.length > 200) {
          _debugLogs.removeAt(0);
        }
      });
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

  // ===========================================================================
  // SECTION 4: INITIALIZATION FLOW
  // ===========================================================================

  Future<void> _initialize() async {
    _log("App initializing...");

    // Step 4.1: Load cached devices first so the UI isn't blank
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

    // Step 4.2: Setup WebSocket listeners
    _setupWebSocket();

    // Step 4.3: Check WiFi (permission + SSID + AP detection)
    await _checkWifiConnection();

    // Step 4.4: Setup ESP32 listeners
    _setupEspListeners();

    // Step 4.5: Restore ESP32 direct connection state if already connected
    // (handles the case where user switches tabs and comes back)
    _restoreEspState();
  }

  /// If EspDirectService is already connected and authenticated, restore the
  /// device flags so the UI shows "Direct Connected".
  void _restoreEspState() {
    final esp = EspDirectService.instance;
    if (esp.isConnected &&
        esp.isAuthenticated &&
        esp.connectedDeviceId != null) {
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

  // ===========================================================================
  // SECTION 5: SERVER WEBSOCKET SETUP
  // ===========================================================================

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
        // Cache for offline use
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

  /// Wait briefly for an in-flight connect to finish, otherwise retry once.
  /// If it still fails, fall back to offline mode.
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
              _errorMessage =
                  "No server connection and no cached devices.\nPlease connect to the internet and login first.";
            }
          });
        }
      }
    }
  }

  // ===========================================================================
  // SECTION 6: WIFI CHECK
  // ===========================================================================

  Future<void> _checkWifiConnection() async {
    try {
      // Step 6.1: Make sure we have location permission (needed to read SSID)
      final locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        final result = await Permission.location.request();
        if (!result.isGranted) {
          _log("WiFi: Location permission DENIED");
          return;
        }
      }

      // Step 6.2: Read SSID and detect "Vortex_VA…" hotspot
      final ssid = await _networkInfo.getWifiName();
      final cleanSsid = ssid?.replaceAll('"', '');

      if (mounted) {
        setState(() {
          _connectedSsid = cleanSsid;
          _isEspApMode =
              cleanSsid != null && cleanSsid.startsWith('Vortex_VA');
        });
      }

      _log("WiFi SSID: ${cleanSsid ?? 'null'} | AP Mode: $_isEspApMode");

      // Step 6.3: If on a valve AP, kick off ESP32 direct connect
      if (_isEspApMode && !EspDirectService.instance.isConnected) {
        _connectToEsp32();
      }

      // Step 6.4: If on normal WiFi but server still isn't connected,
      // try a reconnect (user may have just left the valve hotspot)
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

  // ===========================================================================
  // SECTION 7: ESP32 DIRECT CONNECTION
  // ===========================================================================

  void _setupEspListeners() {
    final esp = EspDirectService.instance;

    // 7.1  Connection state stream — auto-authenticate on connect
    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {});
        _log("ESP32 WS: ${connected ? 'CONNECTED' : 'DISCONNECTED'}");
        if (connected) {
          final userId =
              AuthService.currentUser?['id']?.toString() ?? 'app_user';
          _log(
              "ESP32: Sending request_device_info (passkey: '${_espPasskeyController.text}', user: $userId)");
          esp.authenticate(
            passkey: _espPasskeyController.text,
            userId: userId,
          );
        }
      }
    });

    // 7.2  Device info — mark the device as direct-connected and tag
    //      whether it belongs to the current user
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
          _showSnackBar(
              '⚠️ This valve ($deviceId) is not assigned to your account');
        }
      }
    });

    // 7.3  Valve data (debug log only — DeviceDetailScreen handles its own)
    _espValveDataSub = esp.valveDataStream.listen((data) {
      if (!mounted) return;
      final angle = data['get_valvedata']?['angle'] ?? '?';
      final isOpen = data['get_valvedata']?['is_open'] ?? false;
      _log("ESP32: valve_data → angle=${angle}°, open=$isOpen");
    });

    // 7.4  Errors
    _espErrorSub = esp.errorStream.listen((data) {
      if (!mounted) return;
      _log("ESP32 ERROR: ${data['error'] ?? data['message'] ?? 'unknown'}");
    });
  }

  /// Connect to ESP32. Optional override IP/port come from the debug panel.
  Future<void> _connectToEsp32({String? overrideIp, int? overridePort}) async {
    if (_isEspConnecting) return;

    final ip = overrideIp ?? EspDirectService.defaultApIp;
    final port = overridePort ?? EspDirectService.defaultPort;

    setState(() => _isEspConnecting = true);
    _log("ESP32: Connecting to ws://$ip:$port/ws ...");

    final success =
        await EspDirectService.instance.connect(ip: ip, port: port);

    if (mounted) {
      if (!success) {
        setState(() => _isEspConnecting = false);
        _log("ESP32: Connection FAILED");
      }
    }
  }

  // ===========================================================================
  // SECTION 8: DEVICE STATUS HELPERS
  // ===========================================================================

  /// Returns 'esp_connected' | 'online' | 'offline'.
  /// Online = vwv_last_seen within the last 30 seconds.
  /// (Server and phone must share a timezone for this to be accurate.)
  String _getDeviceStatus(Map<String, dynamic> device) {
    if (device['_esp_connected'] == true) return 'esp_connected';

    final lastSeen = device['vwv_last_seen'];
    if (lastSeen == null ||
        lastSeen.toString().isEmpty ||
        lastSeen == 'NULL') {
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

  // ===========================================================================
  // SECTION 9: NAVIGATION
  // ===========================================================================

  void _onDeviceTap(Map<String, dynamic> device) {
    final status = _getDeviceStatus(device);

    if (status == 'esp_connected') {
      // Open in direct ESP32 mode (manual control only)
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
      final bool isSensor =
          device['id']?.toString().toUpperCase().startsWith('SU') ?? false;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => isSensor
              ? SensorDetailScreen(deviceData: device)
              : DeviceDetailScreen(deviceData: device),
        ),
      );
    } else {
      _showSnackBar(
        'Device is offline. Connect to its hotspot or use the debug panel below.',
      );
    }
  }

  // ===========================================================================
  // SECTION 10: BUILD METHOD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ─── Main content area ─────────────────────────────────────────
          Expanded(
            child: _isLoading
                // 10.1  Loading spinner
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          "Loading devices...",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                // 10.2  Error view (no cached + error)
                : _errorMessage != null && _devices.isEmpty
                    ? ErrorView(
                        message: _errorMessage!,
                        onRetry: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          _initialize();
                        },
                      )
                    // 10.3  Empty view (no devices assigned)
                    : _devices.isEmpty
                        ? const EmptyView()
                        // 10.4  Device list with status bar + pull-to-refresh
                        : _buildDeviceList(),
          ),

          // ─── Debug terminal (currently disabled) ───────────────────────
          // To re-enable, uncomment these two lines:
          //
          // DebugToggleBar(
          //   showDebugPanel: _showDebugPanel,
          //   espConnected: EspDirectService.instance.isConnected,
          //   onTap: () => setState(() => _showDebugPanel = !_showDebugPanel),
          // ),
          // if (_showDebugPanel)
          //   DebugPanel(
          //     ipController: _espIpController,
          //     portController: _espPortController,
          //     logs: _debugLogs,
          //     scrollController: _debugScrollController,
          //     isEspConnecting: _isEspConnecting,
          //     espConnected: EspDirectService.instance.isConnected,
          //     onConnectPressed: () {
          //       final ip = _espIpController.text.trim();
          //       final port =
          //           int.tryParse(_espPortController.text.trim()) ?? 80;
          //       _connectToEsp32(overrideIp: ip, overridePort: port);
          //     },
          //     onRequestInfoPressed: _onDebugRequestInfo,
          //     onOpenValvePressed: _onDebugOpenValve,
          //     onCloseValvePressed: _onDebugCloseValve,
          //     onClearLogsPressed: () => setState(() => _debugLogs.clear()),
          //   ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // 10.4  Device list (status bar + RefreshIndicator + ListView)
  // Kept as a private method here because it composes several pieces and
  // doesn't carry its own state — it's just a layout helper.
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildDeviceList() {
    return Column(
      children: [
        // Connection status bar (top)
        ConnectionStatusBar(
          wsConnected: _wsConnected,
          isEspApMode: _isEspApMode,
          connectedSsid: _connectedSsid,
        ),

        // AP mode banner currently disabled. To re-enable:
        //
        // if (_isEspApMode)
        //   ApModeBanner(
        //     espConnected: EspDirectService.instance.isConnected,
        //     espConnectedDeviceId: _espConnectedDeviceId,
        //     isEspConnecting: _isEspConnecting,
        //   ),

        // Device list with pull-to-refresh
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _checkWifiConnection();
              if (!_wsConnected) {
                final connected = await WebSocketService.connect();
                if (connected) {
                  WebSocketService.subscribeTo('device_list');
                }
              }
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final deviceMap =
                    Map<String, dynamic>.from(_devices[index]);
                final status = _getDeviceStatus(deviceMap);
                return DeviceCard(
                  device: deviceMap,
                  statusText: _getStatusText(status),
                  statusColor: _getStatusColor(status),
                  isEspConnected: status == 'esp_connected',
                  onTap: () => _onDeviceTap(deviceMap),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION 11: DEBUG ACTION HANDLERS (used by DebugPanel when re-enabled)
  // ===========================================================================
  // These are referenced from the commented-out DebugPanel block in build().
  // Marked unused-ignore until the panel is re-enabled.

  // ignore: unused_element
  void _onDebugRequestInfo() {
    if (!EspDirectService.instance.isAuthenticated) {
      _log("⚠️ Not authenticated yet");
      return;
    }
    final userId = AuthService.currentUser?['id']?.toString() ?? 'test';
    final deviceId = _espConnectedDeviceId ?? 'VA202601001';
    _log("→ Requesting valve data for $deviceId");
    EspDirectService.instance.requestValveData(
      userId: userId,
      deviceId: deviceId,
      deviceName: 'Valve',
    );
  }

  // ignore: unused_element
  void _onDebugOpenValve() {
    if (!EspDirectService.instance.isAuthenticated) {
      _log("⚠️ Not authenticated yet");
      return;
    }
    _log("→ set_valve_basic angle=90 (OPEN)");
    EspDirectService.instance.openValve(deviceName: 'Valve');
  }

  // ignore: unused_element
  void _onDebugCloseValve() {
    if (!EspDirectService.instance.isAuthenticated) {
      _log("⚠️ Not authenticated yet");
      return;
    }
    _log("→ set_valve_basic angle=0 (CLOSE)");
    EspDirectService.instance.closeValve(deviceName: 'Valve');
  }
}
