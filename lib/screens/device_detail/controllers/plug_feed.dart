import 'dart:async';

import '../../../models/smart_plug.dart';
import '../../../services/websocket_service.dart';
import '../../../utils/app_log.dart';

// =============================================================================
// PLUG FEED
// =============================================================================
// Live-data plumbing for the smart plug detail screen — the plug's version of
// ServerDeviceFeed (screens/device_detail/controllers/device_feeds.dart).
//
// The plug uses the SAME WebSocket events as the valve, so WebSocketService
// needs no changes:
//
//   subscribe {"process":"device_detail","device_id":"SP…"}
//     → device_basic_detail every ~2 s  → SmartPlug     → onPlugUpdate
//     → device_schedule                 → PlugControl   → onControlUpdate
//
// What this adds over the valve feed is PARSING: the screen receives typed
// models, never raw maps. Events for other devices are dropped here.
//
// Cloud only — there is no direct (ESP32 AP) plug feed yet.
// =============================================================================

class PlugServerFeed {
  final String deviceId;
  final void Function(bool connected) onConnectionChanged;
  final void Function(SmartPlug plug) onPlugUpdate;
  final void Function(PlugControl control) onControlUpdate;

  PlugServerFeed({
    required this.deviceId,
    required this.onConnectionChanged,
    required this.onPlugUpdate,
    required this.onControlUpdate,
  });

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _detailSub;
  StreamSubscription<Map<String, dynamic>>? _scheduleSub;

  bool get isConnected => WebSocketService.isConnected;

  void start() {
    _connectionSub =
        WebSocketService.connectionStream.listen(onConnectionChanged);

    // device_basic_detail — WebSocketService already unwrapped `data`, so the
    // id sits at the top level.
    _detailSub = WebSocketService.deviceDetailStream.listen((data) {
      if (data['id']?.toString() != deviceId) return;
      try {
        onPlugUpdate(SmartPlug.fromJson(data));
      } catch (e) {
        logD("❌ Plug feed: bad device_basic_detail: $e");
      }
    });

    // device_schedule — the full message, device_id at the top level.
    _scheduleSub = WebSocketService.scheduleStream.listen((data) {
      if (data['device_id']?.toString() != deviceId) return;
      try {
        onControlUpdate(PlugControl.fromJson(data));
      } catch (e) {
        logD("❌ Plug feed: bad device_schedule: $e");
      }
    });

    WebSocketService.subscribeTo('device_detail', deviceId: deviceId);
  }

  void dispose() {
    _connectionSub?.cancel();
    _detailSub?.cancel();
    _scheduleSub?.cancel();
    // Hand the socket back to the device list screen.
    WebSocketService.subscribeTo('device_list');
  }
}