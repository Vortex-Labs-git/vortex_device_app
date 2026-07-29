import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/websocket_service.dart';

// =============================================================================
// NETWORK WATCHER  (controller — sensing only)
// =============================================================================
// App-lifetime singleton that owns everything about *knowing* which network
// the phone is on. It NEVER connects to anything — it only senses and emits.
//
//   OWNS (moved out of _HomeScreenState):
//     - Location permission check/request  (needed to read SSID on Android)
//     - SSID read + quote cleanup          (network_info_plus)
//     - Vortex AP detection                (SSID startsWith 'Vortex_' — the
//                                           shared prefix, so BOTH valve
//                                           "Vortex_VA…" and sensor unit
//                                           "Vortex_SU…" hotspots count)
//     - App-resume re-check loop           (WidgetsBindingObserver lives HERE
//                                           now; the screen no longer needs it)
//
//   WHY THE RESUME LOOP EXISTS (legacy _resumeWifiRecheck):
//     After phone sleep, WiFi takes a few seconds to re-associate, so a
//     one-shot SSID read often returns null and the app wrongly concluded
//     "not on a Vortex AP". Fix: re-check every 3 s, up to 4 extra times,
//     stopping early once a Vortex AP is detected or the server WebSocket
//     is back up.
//
//   TRIGGER SEMANTICS — this is the important contract:
//     Every emitted NetworkState carries the trigger that produced it.
//     trigger == resume is the zombie-socket signal: EspSession must FORCE
//     a reconnect on a resume-triggered Vortex-AP state even if
//     EspDirectService.isConnected still says true, because after sleep that
//     flag routinely lies (Android killed the TCP link without a close event).
//     The watcher only *reports* the trigger — the force policy lives in
//     EspSession, keeping this class free of orchestration.
//
//   SUBSCRIBER CONTRACT (wired up in later steps):
//     EspSession       → isVortexAp true            → ensure direct link
//                        isVortexAp + resume trigger → force clean reconnect
//     DeviceRepository → isVortexAp false + server WS down → nudge reconnect
//     HomeScreen       → ssid / isVortexAp for ConnectionStatusBar,
//                        checkNow(trigger: manual) on pull-to-refresh
//
//   EXTERNAL DEPENDENCIES:
//     WebSocketService.isConnected — READ-ONLY, used solely as the resume
//     loop's early-stop condition (same as legacy). No connect calls here.
//
//   Dropped from legacy on purpose: all `if (mounted)` guards — this object
//   lives for the whole app session, there is no unmount.
// =============================================================================

/// Why a NetworkState was emitted. See "TRIGGER SEMANTICS" above.
enum NetworkCheckTrigger {
  /// First check when the watcher starts (app launch).
  initial,

  /// Explicit call — pull-to-refresh, retry buttons, etc.
  manual,

  /// Emitted by the app-resume re-check loop. Downstream must treat a
  /// Vortex-AP state with this trigger as "socket may be a zombie".
  resume,
}

/// Immutable snapshot of what the watcher currently knows.
class NetworkState {
  /// Cleaned SSID (surrounding quotes stripped), or null when unknown /
  /// not connected / permission denied.
  final String? ssid;

  /// True when [ssid] starts with [NetworkWatcher.vortexSsidPrefix].
  final bool isVortexAp;

  /// False only after the user has explicitly denied location permission.
  /// Starts optimistic (true) to mirror legacy behavior, which assumed
  /// nothing until a denial actually happened.
  final bool permissionGranted;

  /// What caused this emission.
  final NetworkCheckTrigger trigger;

  const NetworkState({
    required this.ssid,
    required this.isVortexAp,
    required this.permissionGranted,
    required this.trigger,
  });

  const NetworkState.initial()
      : ssid = null,
        isVortexAp = false,
        permissionGranted = true,
        trigger = NetworkCheckTrigger.initial;

  @override
  String toString() =>
      'NetworkState(ssid: ${ssid ?? 'null'}, vortexAp: $isVortexAp, '
      'permission: $permissionGranted, trigger: ${trigger.name})';
}

class NetworkWatcher with WidgetsBindingObserver {
  // -- Singleton (same lazy pattern as EspDirectService) --
  static NetworkWatcher? _instance;
  static NetworkWatcher get instance => _instance ??= NetworkWatcher._();
  NetworkWatcher._();

  // -- Tuning constants (legacy magic numbers, now named) --
  static const String vortexSsidPrefix = 'Vortex_';
  static const Duration resumeRecheckInterval = Duration(seconds: 3);
  static const int maxResumeRechecks = 4;

  // -- Internals --
  final NetworkInfo _networkInfo = NetworkInfo();
  final StreamController<NetworkState> _stateController =
      StreamController<NetworkState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  NetworkState _current = const NetworkState.initial();
  Timer? _resumeTimer;
  int _resumeCount = 0;
  bool _started = false;

  // -- Public surface --

  /// Every sensing result, in order. Broadcast: late subscribers should read
  /// [current] first, then listen.
  Stream<NetworkState> get stateStream => _stateController.stream;

  /// Human-readable log lines for the debug terminal (mirrors the lines the
  /// legacy code pushed into _debugLogs).
  Stream<String> get logStream => _logController.stream;

  NetworkState get current => _current;
  String? get ssid => _current.ssid;
  bool get isVortexAp => _current.isVortexAp;

  /// Call once at app start (e.g. from main() or MainScreen.initState).
  /// Idempotent. Registers the lifecycle observer and runs the first check.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _log('NetworkWatcher started');
    checkNow(trigger: NetworkCheckTrigger.initial);
  }

  /// Normally never called — the watcher lives as long as the app. Provided
  /// for completeness/tests, mirroring EspDirectService.dispose().
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    _resumeTimer = null;
  }

  // -- App lifecycle → resume re-check loop --

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startResumeLoop();
    }
  }

  /// Legacy _resumeWifiRecheck, verbatim in behavior:
  ///   - immediate check with the resume trigger
  ///   - then every 3 s, up to 4 more checks
  ///   - early stop when a Vortex AP is detected (the immediate check or a
  ///     retry already handled it) or the server WebSocket path is back up
  void _startResumeLoop() {
    _resumeTimer?.cancel();
    _resumeCount = 0;

    checkNow(trigger: NetworkCheckTrigger.resume);

    _resumeTimer = Timer.periodic(resumeRecheckInterval, (t) {
      if (_current.isVortexAp || // Vortex AP detected → already handled
          WebSocketService.isConnected || // normal WiFi path is back up
          _resumeCount >= maxResumeRechecks) {
        t.cancel();
        return;
      }
      _resumeCount++;
      _log('WiFi: resume re-check $_resumeCount/$maxResumeRechecks ...');
      checkNow(trigger: NetworkCheckTrigger.resume);
    });
  }

  // -- The actual sensing (legacy _checkWifiConnection, steps 6.1 + 6.2) --

  /// Reads permission + SSID and emits a NetworkState. Returns the emitted
  /// (or, on permission denial, the preserved) state so imperative callers
  /// can `await` a fresh answer — e.g. pull-to-refresh.
  Future<NetworkState> checkNow(
      {NetworkCheckTrigger trigger = NetworkCheckTrigger.manual}) async {
    try {
      // 1. Location permission (required to read SSID on Android).
      //    Same as legacy: silently request if missing — this may pop the
      //    system dialog on a manual refresh, which is existing behavior.
      final locationStatus = await Permission.location.status;
      if (!locationStatus.isGranted) {
        final result = await Permission.location.request();
        if (!result.isGranted) {
          _log('WiFi: Location permission DENIED');
          // Legacy just returned here without touching SSID state — preserve
          // that: keep prior ssid/isVortexAp, only record the denial.
          _emit(NetworkState(
            ssid: _current.ssid,
            isVortexAp: _current.isVortexAp,
            permissionGranted: false,
            trigger: trigger,
          ));
          return _current;
        }
      }

      // 2. Read SSID and detect a Vortex device hotspot ("Vortex_" prefix
      //    so both valve and sensor-unit APs match).
      final rawSsid = await _networkInfo.getWifiName();
      final cleanSsid = rawSsid?.replaceAll('"', '');
      final isAp =
          cleanSsid != null && cleanSsid.startsWith(vortexSsidPrefix);

      _log('WiFi SSID: ${cleanSsid ?? 'null'} | AP Mode: $isAp');

      _emit(NetworkState(
        ssid: cleanSsid,
        isVortexAp: isAp,
        permissionGranted: true,
        trigger: trigger,
      ));
    } catch (e) {
      _log('WiFi check error: $e');
    }
    return _current;
  }

  // -- Helpers --

  void _emit(NetworkState state) {
    _current = state;
    _stateController.add(state);
  }

  void _log(String message) {
    // ignore: avoid_print
    print('📶 $message'); // console, matching service style
    _logController.add(message); // debug terminal, when re-enabled
  }
}
