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

  // -- Resume re-check (see _resumeWifiRecheck) --
  Timer? _wifiRecheckTimer;
  int _wifiRecheckCount = 0;

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
    _wifiRecheckTimer?.cancel();
    _debugScrollController.dispose();
    _espIpController.dispose();
    _espPortController.dispose();
    _espPasskeyController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeWifiRecheck();
    }
  }

  /// Runs after every app resume (phone woke up / came back from another
  /// app). Two problems this solves:
  ///
  ///   1. ZOMBIE SOCKET — while the phone slept, Android usually killed
  ///      the TCP link to the ESP32 but no close event ever reached us,
  ///      so EspDirectService.isConnected still says true. The old
  ///      "reconnect only if !isConnected" check was fooled by this and
  ///      the app kept talking into a dead socket. Fix: FORCE a clean
  ///      reconnect whenever we're on a Vortex hotspot at resume.
  ///
  ///   2. SSID RACE — WiFi takes a few seconds to re-associate after
  ///      sleep, so the first check often reads SSID null and gave up
  ///      (the check was strictly one-shot). Fix: retry every 3 s, up
  ///      to 4 times, stopping early once either connection path is up.
  void _resumeWifiRecheck() {
    _wifiRecheckTimer?.cancel();
    _wifiRecheckCount = 0;

    _checkWifiConnection(forceEspReconnect: true);

    _wifiRecheckTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (!mounted ||
          _isEspApMode || // Vortex AP detected → check already handled it
          WebSocketService.isConnected || // normal WiFi path is back up
          _wifiRecheckCount >= 4) {
        t.cancel();
        return;
      }
      _wifiRecheckCount++;
      _log("WiFi: resume re-check $_wifiRecheckCount/4 ...");
      _checkWifiConnection(forceEspReconnect: true);
    });
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

  /// [forceEspReconnect] is passed true from the resume path: after phone
  /// sleep, EspDirectService.isConnected often reports true for a socket
  /// that is actually dead (Android killed the TCP link without a close
  /// event), so "already connected" cannot be trusted at resume time.
  Future<void> _checkWifiConnection({bool forceEspReconnect = false}) async {
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

      // Step 6.2: Read SSID and detect a Vortex device hotspot.
      // Valves broadcast "Vortex_VA…", sensor units "Vortex_SU…" — match
      // the shared "Vortex_" prefix so BOTH device types trigger direct
      // mode. (Was startsWith('Vortex_VA'), which silently ignored
      // sensor unit hotspots — nothing ever showed as direct connected.)
      final ssid = await _networkInfo.getWifiName();
      final cleanSsid = ssid?.replaceAll('"', '');

      if (mounted) {
        setState(() {
          _connectedSsid = cleanSsid;
          _isEspApMode =
              cleanSsid != null && cleanSsid.startsWith('Vortex_');
        });
      }

      _log("WiFi SSID: ${cleanSsid ?? 'null'} | AP Mode: $_isEspApMode");

      // Step 6.3: If on a Vortex device AP, make sure the direct link is
      // genuinely alive. Normal path: connect when not connected. Resume
      // path (forceEspReconnect): reconnect EVEN IF isConnected says true,
      // because after sleep that flag routinely lies (zombie socket).
      // connect() internally disconnects first, so this is always clean.
      if (_isEspApMode) {
        if (!EspDirectService.instance.isConnected) {
          _connectToEsp32();
        } else if (forceEspReconnect) {
          _log("ESP32: Resume on Vortex AP — forcing reconnect "
              "(old socket may be dead)");
          _connectToEsp32();
        }
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

    // 7.1  Connection state stream — auto-authenticate on connect,
    //      clear ALL stale direct-mode state on disconnect
    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) {
        _log("ESP32 WS: ${connected ? 'CONNECTED' : 'DISCONNECTED'}");
        if (connected) {
          setState(() {});
          final userId =
              AuthService.currentUser?['id']?.toString() ?? 'app_user';
          _log(
              "ESP32: Sending request_device_info (passkey: '${_espPasskeyController.text}', user: $userId)");
          esp.authenticate(
            passkey: _espPasskeyController.text,
            userId: userId,
          );
        } else {
          // Connection died (phone sleep, WiFi drop, ESP32 restart).
          // Clear EVERYTHING the last session left behind, otherwise:
          //   - _isEspConnecting can stay locked true forever (it was
          //     only reset on device_info arrival), making every future
          //     _connectToEsp32() call return immediately
          //   - devices keep their green _esp_connected flag for a link
          //     that no longer exists
          setState(() {
            _isEspConnecting = false;
            _espConnectedDeviceId = null;
            for (int i = 0; i < _devices.length; i++) {
              if (_devices[i]['_esp_connected'] == true) {
                _devices[i] = Map<String, dynamic>.from(_devices[i]);
                _devices[i]['_esp_connected'] = false;
                _devices[i]['_esp_is_user_device'] = false;
              }
            }
          });
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
          _showSnackBar('✅ Connected to your device: $deviceId');
        } else {
          _showSnackBar(
              '⚠️ This device ($deviceId) is not assigned to your account');
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

    final lastSeen = device['last_seen'];
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

    // Device category by id prefix: VA- = WiFi valve, SU- = sensor unit.
    // Used by BOTH branches — direct mode must also route SU- devices to
    // the sensor screen (previously they always opened the valve screen).
    final bool isSensor =
        device['id']?.toString().toUpperCase().startsWith('SU') ?? false;

    if (status == 'esp_connected') {
      // Open in direct ESP32 mode (valve: manual control only;
      // sensor unit: read-only data view)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => isSensor
              ? SensorDetailScreen(deviceData: device, isDirectMode: true)
              : DeviceDetailScreen(deviceData: device, isDirectMode: true),
        ),
      );
    } else if (status == 'online') {
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