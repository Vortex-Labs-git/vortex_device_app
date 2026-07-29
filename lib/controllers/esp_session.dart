import 'dart:async';

import '../services/auth_service.dart';
import '../services/esp_direct_service.dart';
import '../services/local_storage_service.dart';
import 'network_watcher.dart';

// =============================================================================
// ESP SESSION  (controller — direct-connection policy state machine)
// =============================================================================
// App-lifetime singleton that owns *when and how* the app talks to an ESP32
// over its AP, wrapping EspDirectService. Strict division of truth:
//
//   EspDirectService  → MECHANISM. Raw socket + protocol. Sole owner of
//                       isConnected / isAuthenticated / connectedDeviceId
//                       at the socket level. Untouched by this refactor.
//   EspSession        → POLICY. When to connect, auth passkey/user, the
//                       connecting lock, the resume force-reconnect, session
//                       establishment, and stale-state cleanup on disconnect.
//                       This class NEVER caches its own "isConnected" — that
//                       is exactly how the zombie-flag bug happened once.
//
// STATE MACHINE:
//
//     idle ──connect()──▶ connecting ──socket up──▶ authenticating
//      ▲                      │        (auto-sends request_device_info) │
//      │                      │ connect() returned false                │
//      │◀─────────────────────┘                          device_info ▼
//      │◀─────────── disconnect event ────────────────────────── active
//      │◀─────────── establish timeout (lock release only) ◀──┘
//
//   isConnecting == (connecting || authenticating) — this reproduces the
//   legacy _isEspConnecting lock exactly: taken before connect(), released
//   on connect failure, on device_info arrival, or on a disconnect event.
//
// NEW vs LEGACY — THE ESTABLISH TIMEOUT:
//   Legacy could hold the lock forever if connect() succeeded but neither
//   device_info nor a disconnect event ever arrived (rare, but it bricked
//   every future _connectToEsp32() call). Now a 15 s timer covers the whole
//   connecting→active journey. On expiry it ONLY releases the lock and
//   reverts to idle — it deliberately does NOT touch the socket, because
//   EspDirectService.connect() always disconnects first anyway, so the next
//   attempt is guaranteed clean.
//
// NETWORK REACTIONS (moved from home_screen Step 6.3):
//   NetworkWatcher.stateStream drives connects:
//     - Vortex AP + not connected                  → connect()
//     - Vortex AP + trigger == resume              → connect() EVEN IF the
//       service says connected: after phone sleep, Android routinely kills
//       the TCP link without a close event, so isConnected lies (zombie
//       socket). connect() disconnects first, so forcing is always clean.
//     - Leaving the AP → nothing, same as legacy. The socket dies on its
//       own and the disconnect event runs the cleanup.
//
// SUBSCRIBER CONTRACT (wired in later steps):
//   DeviceRepository → stateStream: overlays / clears _esp flags on devices
//                      (deviceId + isUserDevice while active, cleared on idle)
//   HomeScreen       → activationStream: one event per received device_info,
//                      carrying isUserDevice → shows the ✅ / ⚠️ snackbar
//                      isConnecting → ApModeBanner (when re-enabled)
//
// START ORDER: start EspSession (and DeviceRepository) BEFORE
// NetworkWatcher.start(), so the watcher's initial emission is not missed.
// As a belt-and-braces measure, start() also acts on NetworkWatcher.current,
// making the session resilient to ordering mistakes.
// =============================================================================

enum EspSessionPhase {
  /// No direct link and nothing in flight.
  idle,

  /// EspDirectService.connect() in flight. Lock held.
  connecting,

  /// Socket is up, request_device_info sent, waiting for device_info.
  /// Lock still held (legacy semantics).
  authenticating,

  /// device_info received — session established.
  active,
}

/// Immutable snapshot of the session.
class EspSessionState {
  final EspSessionPhase phase;

  /// Device ID from device_info; non-null only while [phase] == active.
  final String? deviceId;

  /// Whether [deviceId] is assigned to the logged-in user
  /// (LocalStorageService.isUserDevice). Meaningful only while active.
  final bool isUserDevice;

  const EspSessionState({
    required this.phase,
    this.deviceId,
    this.isUserDevice = false,
  });

  const EspSessionState.idle()
      : phase = EspSessionPhase.idle,
        deviceId = null,
        isUserDevice = false;

  bool get isActive => phase == EspSessionPhase.active;

  @override
  String toString() =>
      'EspSessionState(${phase.name}'
      '${deviceId != null ? ', $deviceId, userDevice: $isUserDevice' : ''})';
}

class EspSession {
  // -- Singleton (same lazy pattern as EspDirectService) --
  static EspSession? _instance;
  static EspSession get instance => _instance ??= EspSession._();
  EspSession._();

  // -- Tuning --
  static const String defaultPasskey = '12345';
  static const Duration sessionEstablishTimeout = Duration(seconds: 15);

  /// Auth passkey sent with request_device_info. Mutable so the debug panel
  /// can override it (legacy _espPasskeyController); everything else uses
  /// the default.
  String passkey = defaultPasskey;

  // -- Internals --
  final StreamController<EspSessionState> _stateController =
      StreamController<EspSessionState>.broadcast();
  final StreamController<EspSessionState> _activationController =
      StreamController<EspSessionState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  EspSessionState _current = const EspSessionState.idle();
  Timer? _establishTimer;
  bool _started = false;

  StreamSubscription<bool>? _espConnectionSub;
  StreamSubscription<Map<String, dynamic>>? _espDeviceInfoSub;
  StreamSubscription<Map<String, dynamic>>? _espValveDataSub;
  StreamSubscription<Map<String, dynamic>>? _espErrorSub;
  StreamSubscription<NetworkState>? _networkSub;

  // -- Public surface --

  /// Every state change, in order. Late subscribers read [current] first.
  Stream<EspSessionState> get stateStream => _stateController.stream;

  /// Exactly one event per received device_info — i.e. per (re)established
  /// session. Drives the ✅ / ⚠️ snackbar, matching legacy behavior of
  /// showing it on every device_info.
  Stream<EspSessionState> get activationStream => _activationController.stream;

  /// Debug-terminal log lines (legacy _log texts preserved).
  Stream<String> get logStream => _logController.stream;

  EspSessionState get current => _current;

  /// Reproduces the legacy _isEspConnecting lock (see header).
  bool get isConnecting =>
      _current.phase == EspSessionPhase.connecting ||
      _current.phase == EspSessionPhase.authenticating;

  /// Call once at app start, BEFORE NetworkWatcher.start(). Idempotent.
  void start() {
    if (_started) return;
    _started = true;

    _subscribeEspStreams();

    // React to network sensing (replaces home_screen Step 6.3).
    _networkSub =
        NetworkWatcher.instance.stateStream.listen(_onNetworkState);

    // Legacy _restoreEspState: if the service is already connected and
    // authenticated (session outlived a screen), rebuild the active state.
    _restoreFromService();

    // Belt-and-braces for start-order mistakes: act on what the watcher
    // already knows (a non-resume state can never force, so this is safe).
    _onNetworkState(NetworkWatcher.instance.current);
  }

  /// Normally never called — app-lifetime object. For completeness/tests.
  void stop() {
    if (!_started) return;
    _started = false;
    _espConnectionSub?.cancel();
    _espDeviceInfoSub?.cancel();
    _espValveDataSub?.cancel();
    _espErrorSub?.cancel();
    _networkSub?.cancel();
    _establishTimer?.cancel();
    _establishTimer = null;
  }

  /// Connect to the ESP32. Optional IP/port overrides come from the debug
  /// panel; everything else uses the service defaults (192.168.4.1:80).
  /// Legacy _connectToEsp32, plus the establish timeout.
  Future<void> connect({String? overrideIp, int? overridePort}) async {
    if (isConnecting) return; // legacy lock

    final ip = overrideIp ?? EspDirectService.defaultApIp;
    final port = overridePort ?? EspDirectService.defaultPort;

    _emit(const EspSessionState(phase: EspSessionPhase.connecting));
    _armEstablishTimeout();
    _log('ESP32: Connecting to ws://$ip:$port${EspDirectService.wsPath} ...');

    final success =
        await EspDirectService.instance.connect(ip: ip, port: port);

    if (!success) {
      _log('ESP32: Connection FAILED');
      _cancelEstablishTimeout();
      _emit(const EspSessionState.idle());
    }
    // success → wait for the connection event (→ authenticating) and then
    // device_info (→ active). The timeout covers this whole journey.
  }

  // -- Network reactions --

  void _onNetworkState(NetworkState net) {
    if (!net.isVortexAp) return; // leaving the AP: do nothing (see header)

    final force = net.trigger == NetworkCheckTrigger.resume;

    if (!EspDirectService.instance.isConnected) {
      connect();
    } else if (force) {
      _log('ESP32: Resume on Vortex AP — forcing reconnect '
          '(old socket may be dead)');
      connect();
    }
  }

  // -- EspDirectService stream handlers (legacy Section 7, minus UI) --

  void _subscribeEspStreams() {
    final esp = EspDirectService.instance;

    // 7.1  Connection state — auto-authenticate on connect, clear ALL
    //      session state on disconnect.
    _espConnectionSub = esp.connectionStream.listen((connected) {
      _log('ESP32 WS: ${connected ? 'CONNECTED' : 'DISCONNECTED'}');
      if (connected) {
        final userId =
            AuthService.currentUser?['id']?.toString() ?? 'app_user';
        _log("ESP32: Sending request_device_info "
            "(passkey: '$passkey', user: $userId)");
        _emit(const EspSessionState(phase: EspSessionPhase.authenticating));
        esp.authenticate(passkey: passkey, userId: userId);
      } else {
        // Connection died (phone sleep, WiFi drop, ESP32 restart). Clear
        // everything the session held — the legacy bug where the lock and
        // the device flags survived a dead link is impossible now, because
        // idle releases the lock and DeviceRepository clears flags off this
        // same emission.
        _cancelEstablishTimeout();
        _emit(const EspSessionState.idle());
      }
    });

    // 7.2  Device info — session established.
    _espDeviceInfoSub = esp.deviceInfoStream.listen((data) async {
      final deviceId = data['device_id']?.toString();
      _log('ESP32: device_info received → ID: $deviceId');
      if (deviceId == null) return;

      final isUserDevice = await LocalStorageService.isUserDevice(deviceId);
      _log("ESP32: Device '$deviceId' belongs to user: $isUserDevice");

      _cancelEstablishTimeout();
      final state = EspSessionState(
        phase: EspSessionPhase.active,
        deviceId: deviceId,
        isUserDevice: isUserDevice,
      );
      _emit(state);
      _activationController.add(state); // → snackbar in HomeScreen
    });

    // 7.3  Valve data — debug log only (DeviceDetailScreen has its own sub).
    _espValveDataSub = esp.valveDataStream.listen((data) {
      final angle = data['get_valvedata']?['angle'] ?? '?';
      final isOpen = data['get_valvedata']?['is_open'] ?? false;
      _log('ESP32: valve_data → angle=$angle°, open=$isOpen');
    });

    // 7.4  Errors — debug log only.
    _espErrorSub = esp.errorStream.listen((data) {
      _log("ESP32 ERROR: ${data['error'] ?? data['message'] ?? 'unknown'}");
    });
  }

  /// Legacy _restoreEspState, with one fix: isUserDevice is actually looked
  /// up instead of hardcoded true (the legacy restore assumed true, which
  /// could mislabel a stranger's device after a tab switch).
  void _restoreFromService() {
    final esp = EspDirectService.instance;
    if (esp.isConnected &&
        esp.isAuthenticated &&
        esp.connectedDeviceId != null) {
      final deviceId = esp.connectedDeviceId!;
      _log('ESP32: Restoring connection state for $deviceId');
      LocalStorageService.isUserDevice(deviceId).then((isUserDevice) {
        // Guard: a disconnect may have raced the lookup.
        if (EspDirectService.instance.isConnected) {
          _emit(EspSessionState(
            phase: EspSessionPhase.active,
            deviceId: deviceId,
            isUserDevice: isUserDevice,
          ));
        }
      });
    }
  }

  // -- Establish timeout --

  void _armEstablishTimeout() {
    _establishTimer?.cancel();
    _establishTimer = Timer(sessionEstablishTimeout, () {
      if (isConnecting) {
        _log('ESP32: session establish timeout '
            '(${sessionEstablishTimeout.inSeconds}s) — releasing connect lock');
        _emit(const EspSessionState.idle());
      }
    });
  }

  void _cancelEstablishTimeout() {
    _establishTimer?.cancel();
    _establishTimer = null;
  }

  // -- Helpers --

  void _emit(EspSessionState state) {
    _current = state;
    _stateController.add(state);
  }

  void _log(String message) {
    // ignore: avoid_print
    print('🔌 $message'); // console, matching service style
    _logController.add(message); // debug terminal, when re-enabled
  }
}
