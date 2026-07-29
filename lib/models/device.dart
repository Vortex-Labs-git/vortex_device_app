// =============================================================================
// DEVICE (list-level model)
// =============================================================================
// One row in the home device list. This is the SUMMARY model — just enough to
// render a DeviceCard and route a tap. Detail payloads keep their own models:
//
//   Device      → home list row            (this file)
//   SensorUnit  → sensor detail payload    (models/sensor_unit.dart)
//   valve map   → valve detail payload     (device_detail_screen works on the
//                                           raw map; typed model may come later)
//
// SOURCES — all three produce the same map shape:
//   1. Cloud push    'device_list' via Ratchet server (WebSocketService)
//   2. Cache         LocalStorageService.getDeviceList() (verbatim copy of 1)
//   3. ESP overlay   _esp_connected / _esp_is_user_device injected by the app
//                    at runtime while direct-connected. SESSION-ONLY: these
//                    flags must never be persisted. When caching, always cache
//                    [raw] (which never contains them fresh from the server),
//                    never a re-serialized Device.  ← this is why there is
//                    deliberately NO toJson() on this class.
//
// KEY FALLBACK CHAINS (mirrors DeviceCard + home_screen exactly):
//   name      name → vwv_name → device_name → 'Unknown Device'
//   lastSeen  last_seen → vwv_last_seen; null / '' / literal 'NULL' /
//             unparseable all collapse to null (PHP serializes SQL NULL as
//             the string 'NULL' — that gotcha is load-bearing, keep it)
//
// STATUS IS DERIVED, NEVER STORED:
//   espConnected                          → DeviceStatus.espConnected
//   lastSeen within the last 30 seconds   → DeviceStatus.online
//   otherwise                             → DeviceStatus.offline
//   The comparison uses .inSeconds (truncation), NOT a Duration compare, so
//   30.9 s still counts as online — identical to the legacy
//   _getDeviceStatus() behavior. Server and phone must share a timezone.
//
// [raw] keeps the untouched payload so navigation stays map-based for now:
//   DeviceDetailScreen / SensorDetailScreen still receive deviceData: d.raw.
// =============================================================================

/// Derived connection status of a device row.
enum DeviceStatus {
  online('Online'),
  offline('Offline'),
  espConnected('Direct Connected');

  /// UI label, replicating the legacy _getStatusText(). Colors stay in the
  /// widget layer — this model is pure Dart on purpose (no Flutter imports).
  final String label;
  const DeviceStatus(this.label);
}

class Device {
  /// "VA202601001" (WiFi valve) / "SU202601003" (sensor unit)
  final String id;

  /// Display name after the fallback chain (see header).
  final String name;

  /// Parsed last_seen, or null when the server sent nothing usable.
  final DateTime? lastSeen;

  /// True while EspDirectService has an authenticated direct link to THIS
  /// device. App-injected, session-only — never comes from the server.
  final bool espConnected;

  /// True when the direct-connected device is assigned to the logged-in user
  /// (LocalStorageService.isUserDevice). App-injected, session-only.
  final bool espIsUserDevice;

  /// The original payload map, untouched. Passed to detail screens so their
  /// existing Map contract (vwv_pos, user_vwv_pos, sensor_data, …) keeps
  /// working without changes.
  final Map<String, dynamic> raw;

  /// Online window in seconds (legacy magic number, now named).
  static const int onlineWindowSeconds = 30;

  const Device({
    required this.id,
    required this.name,
    required this.lastSeen,
    this.espConnected = false,
    this.espIsUserDevice = false,
    required this.raw,
  });

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id']?.toString() ?? '',
      name: (json['name'] ??
              json['vwv_name'] ??
              json['device_name'] ??
              'Unknown Device')
          .toString(),
      lastSeen: _parseLastSeen(json['last_seen'] ?? json['vwv_last_seen']),
      // `== true` keeps the exact legacy semantics: anything that isn't the
      // bool true (missing, null, 1, "true") reads as false.
      espConnected: json['_esp_connected'] == true,
      espIsUserDevice: json['_esp_is_user_device'] == true,
      raw: Map<String, dynamic>.from(json),
    );
  }

  /// Parse a whole device_list payload (server push or cache).
  /// Entries may be Map<dynamic, dynamic> straight out of jsonDecode,
  /// so each one is normalized first. Defensive: a non-map entry is skipped
  /// rather than crashing the list.
  static List<Device> listFromJson(List<dynamic> list) {
    return list
        .whereType<Map>()
        .map((e) => Device.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static DateTime? _parseLastSeen(dynamic value) {
    if (value == null) return null;
    final s = value.toString();
    if (s.isEmpty || s == 'NULL') return null;
    return DateTime.tryParse(s); // bad format → null → offline
  }

  // ---------------------------------------------------------------------------
  // Derived properties
  // ---------------------------------------------------------------------------

  /// Device category by ID prefix — same rule DeviceCard and _onDeviceTap use.
  bool get isSensor => id.toUpperCase().startsWith('SU');
  bool get isValve => id.toUpperCase().startsWith('VA');

  /// Derived status. Recomputed on every read so a device naturally falls to
  /// offline once last_seen ages past the window (evaluated at build time,
  /// exactly like the legacy per-build _getDeviceStatus call).
  DeviceStatus get status {
    if (espConnected) return DeviceStatus.espConnected;
    final seen = lastSeen;
    if (seen == null) return DeviceStatus.offline;
    final diff = DateTime.now().difference(seen).inSeconds;
    return diff <= onlineWindowSeconds
        ? DeviceStatus.online
        : DeviceStatus.offline;
  }

  // ---------------------------------------------------------------------------
  // Copy
  // ---------------------------------------------------------------------------

  /// Used by DeviceRepository to overlay / clear the session-only ESP flags
  /// without touching the server-sourced fields or [raw].
  Device copyWith({
    String? id,
    String? name,
    DateTime? lastSeen,
    bool? espConnected,
    bool? espIsUserDevice,
    Map<String, dynamic>? raw,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      lastSeen: lastSeen ?? this.lastSeen,
      espConnected: espConnected ?? this.espConnected,
      espIsUserDevice: espIsUserDevice ?? this.espIsUserDevice,
      raw: raw ?? this.raw,
    );
  }

  @override
  String toString() =>
      'Device($id "$name" ${status.name}${espConnected ? ' [direct]' : ''})';
}
