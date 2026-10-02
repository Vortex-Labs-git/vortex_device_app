import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/device_repository.dart';
import '../../controllers/esp_session.dart';
import '../../controllers/network_watcher.dart';
import '../../models/device.dart';
import '../../services/auth_service.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass/glass.dart';
import '../device_detail/device_detail_screen.dart';
import '../device_detail/plug_detail_screen.dart';
import '../device_detail/sensor_detail_screen.dart';
import 'widgets/connection_status_bar.dart';
import 'widgets/device_card.dart';
import 'widgets/empty_view.dart';
import 'widgets/error_view.dart';

// =============================================================================
// HOME SCREEN  (view only)
// =============================================================================
// Renders the device list. ALL logic lives in the app-lifetime controllers
// (started once in main.dart, in this order):
//
//   NetworkWatcher    → permission / SSID / Vortex AP detect / resume loop
//   EspSession        → direct-connect policy, auth, zombie-socket handling
//   DeviceRepository  → server + cache + ESP overlay → one snapshot stream
//
// This widget only: subscribes, setState-mirrors the snapshots, shows the
// session snackbar, and navigates. It owns no timers, no lifecycle observer,
// no WiFi code, and no ESP streams — do not add logic back here.
// (UI v2 adds one piece of view-only state, the device type filter; the
// header summary is counted from the same snapshot.)
//
// Debug terminal: removed from this screen. The controllers each expose a
// logStream; a future standalone debug screen can merge those, use
// EspSession.instance.passkey / connect(overrideIp:, overridePort:) for the
// old panel's inputs, and call EspDirectService directly for the test
// buttons — nothing was lost, it just no longer lives in the view.
// =============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Mirrored controller snapshots — the only state this screen holds.
  DeviceRepositoryState _repo = DeviceRepository.instance.current;
  NetworkState _network = NetworkWatcher.instance.current;

  // View-only state: which device types the list shows.
  _DeviceFilter _filter = _DeviceFilter.all;

  StreamSubscription<DeviceRepositoryState>? _repoSub;
  StreamSubscription<NetworkState>? _networkSub;
  StreamSubscription<EspSessionState>? _activationSub;

  @override
  void initState() {
    super.initState();

    _repoSub = DeviceRepository.instance.stateStream.listen((s) {
      if (mounted) setState(() => _repo = s);
    });

    _networkSub = NetworkWatcher.instance.stateStream.listen((s) {
      if (mounted) setState(() => _network = s);
    });

    // One event per established direct session → legacy ✅ / ⚠️ snackbar.
    _activationSub = EspSession.instance.activationStream.listen((s) {
      if (!mounted || s.deviceId == null) return;
      _showSnackBar(s.isUserDevice
          ? '✅ Connected to your device: ${s.deviceId}'
          : '⚠️ This device (${s.deviceId}) is not assigned to your account');
    });
  }

  @override
  void dispose() {
    _repoSub?.cancel();
    _networkSub?.cancel();
    _activationSub?.cancel();
    super.dispose();
  }

  // -- Helpers --

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// Colors stay in the view layer — the model is pure Dart on purpose.
  Color _statusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online:
      case DeviceStatus.espConnected:
        return GlassTokens.success;
      case DeviceStatus.offline:
        return GlassTokens.danger;
    }
  }

  void _onDeviceTap(Device device) {
    // Smart plugs are cloud-only for now: no direct (AP) screen, and the same
    // screen for online and offline (it locks manual control when offline).
    if (device.isPlug) {
      if (device.status == DeviceStatus.espConnected) {
        _showSnackBar('Direct control is not available for smart plugs yet');
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlugDetailScreen(deviceData: device.raw),
        ),
      );
      return;
    }

    switch (device.status) {
      case DeviceStatus.espConnected:
        // Direct ESP32 mode (valve: manual control only; sensor: read-only).
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => device.isSensor
                ? SensorDetailScreen(deviceData: device.raw, isDirectMode: true)
                : DeviceDetailScreen(deviceData: device.raw, isDirectMode: true),
          ),
        );
        break;
      case DeviceStatus.online:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => device.isSensor
                ? SensorDetailScreen(deviceData: device.raw)
                : DeviceDetailScreen(deviceData: device.raw),
          ),
        );
        break;
      case DeviceStatus.offline:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => device.isSensor
                ? SensorDetailScreen(deviceData: device.raw)
                : DeviceDetailScreen(deviceData: device.raw),
          ),
        );
        break;
    }
  }

  // -- View helpers (pure: derived from the snapshot, no state) --

  bool _matchesFilter(Device d) {
    switch (_filter) {
      case _DeviceFilter.all:
        return true;
      case _DeviceFilter.valves:
        return d.isValve;
      case _DeviceFilter.sensors:
        return d.isSensor;
      case _DeviceFilter.plugs:
        return d.isPlug;
    }
  }

  /// "Updated 3 s ago" / "Last seen 2 h ago" from the same lastSeen the
  /// status rule uses. Refreshes whenever a new snapshot arrives.
  String _seenText(Device d) {
    if (d.status == DeviceStatus.espConnected) return 'Phone joined its hotspot';
    final DateTime? seen = d.lastSeen;
    if (seen == null) return 'Not seen yet';

    final Duration diff = DateTime.now().difference(seen);
    final int s = diff.inSeconds < 0 ? 0 : diff.inSeconds;
    final String ago = s < 60
        ? '$s s'
        : s < 3600
            ? '${diff.inMinutes} min'
            : s < 86400
                ? '${diff.inHours} h'
                : '${diff.inDays} d';
    return d.status == DeviceStatus.online
        ? 'Updated $ago ago'
        : 'Last seen $ago ago';
  }

  String get _greeting {
    final int h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    // No Scaffold: this is a tab inside MainScreen's GlassScaffold. Home gets
    // no app bar and no top SafeArea there — the forest header below draws
    // behind the status bar itself.
    if (_repo.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading devices...',
              style: TextStyle(color: GlassTokens.textSecondary),
            ),
          ],
        ),
      );
    }

    final double topInset = MediaQuery.paddingOf(context).top;
    // With extendBody on the shell Scaffold, the bottom inset already covers
    // the floating nav bar — add it so the last card clears the bar while the
    // list still scrolls underneath it.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    final List<Widget> children = [_buildHeader()];

    if (_repo.errorMessage != null && _repo.devices.isEmpty) {
      children.add(ErrorView(
        message: _repo.errorMessage!,
        onRetry: () => DeviceRepository.instance.retry(),
      ));
    } else if (_repo.devices.isEmpty) {
      children.add(const EmptyView());
    } else {
      children.addAll(_buildDeviceList());
    }

    return Stack(
      children: [
        RefreshIndicator(
          color: GlassTokens.primary,
          backgroundColor: GlassTokens.surface,
          edgeOffset: topInset,
          onRefresh: () async {
            // WiFi half first (may trigger EspSession via the watcher),
            // then the server half.
            await NetworkWatcher.instance.checkNow();
            await DeviceRepository.instance.refresh();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: 16 + bottomInset),
            children: children,
          ),
        ),

        // Forest strip behind the status bar, so the clock and battery stay
        // on green (with light icons) after the header scrolls away.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topInset,
          child: const AnnotatedRegion<SystemUiOverlayStyle>(
            value: GlassTokens.systemOverlayOnForest,
            child: ColoredBox(color: GlassTokens.forest),
          ),
        ),
      ],
    );
  }

  /// Forest header: logo, greeting, and a farm summary counted from the
  /// device list (no extra data needed from the server).
  Widget _buildHeader() {
    final devices = _repo.devices;
    final int online =
        devices.where((d) => d.status != DeviceStatus.offline).length;
    final int valves = devices.where((d) => d.isValve).length;
    final int others = devices.where((d) => d.isSensor || d.isPlug).length;
    final String name =
        (AuthService.currentUser?['name'] ?? '').toString().trim();

    return ForestHeader(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/logo.jpeg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.eco_rounded,
                    color: GlassTokens.forest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    Text(
                      name.isEmpty ? 'Your farm' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: GlassTokens.displayFont,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ForestStat(
                  value: '$online/${devices.length}',
                  label: 'devices online',
                  highlight: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ForestStat(
                  value: '$valves',
                  label: valves == 1 ? 'valve' : 'valves',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ForestStat(
                  value: '$others',
                  label: 'sensors & plugs',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDeviceList() {
    final devices = _repo.devices;
    final visible = devices.where(_matchesFilter).toList();
    final bool live = _repo.wsConnected;

    int count(bool Function(Device) test) => devices.where(test).length;

    return [
      ConnectionStatusBar(
        wsConnected: _repo.wsConnected,
        isEspApMode: _network.isVortexAp,
        connectedSsid: _network.ssid,
      ),

      // Filter chips — by the ID prefix the app already routes on.
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Row(
          children: [
            _FilterChip(
              label: 'All',
              count: devices.length,
              selected: _filter == _DeviceFilter.all,
              onTap: () => setState(() => _filter = _DeviceFilter.all),
            ),
            _FilterChip(
              label: 'Valves',
              count: count((d) => d.isValve),
              selected: _filter == _DeviceFilter.valves,
              onTap: () => setState(() => _filter = _DeviceFilter.valves),
            ),
            _FilterChip(
              label: 'Sensors',
              count: count((d) => d.isSensor),
              selected: _filter == _DeviceFilter.sensors,
              onTap: () => setState(() => _filter = _DeviceFilter.sensors),
            ),
            _FilterChip(
              label: 'Plugs',
              count: count((d) => d.isPlug),
              selected: _filter == _DeviceFilter.plugs,
              onTap: () => setState(() => _filter = _DeviceFilter.plugs),
            ),
          ],
        ),
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                live ? 'Your devices' : 'Saved devices',
                style: const TextStyle(
                  fontFamily: GlassTokens.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textPrimary,
                ),
              ),
            ),
            Text(
              live ? 'Pull down to refresh' : 'From your phone',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GlassTokens.textMuted,
              ),
            ),
          ],
        ),
      ),

      if (visible.isEmpty)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Text(
            'No devices of this type.',
            textAlign: TextAlign.center,
            style: TextStyle(color: GlassTokens.textMuted),
          ),
        ),

      for (final device in visible)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DeviceCard(
            device: device.raw,
            statusText: device.status.label,
            statusColor: _statusColor(device.status),
            isEspConnected: device.status == DeviceStatus.espConnected,
            isOffline: device.status == DeviceStatus.offline,
            subtitle: _seenText(device),
            onTap: () => _onDeviceTap(device),
          ),
        ),
    ];
  }
}

enum _DeviceFilter { all, valves, sensors, plugs }

// -----------------------------------------------------------------------------
// One filter pill: label + count. Selected is a dark filled pill.
// -----------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? GlassTokens.ground : GlassTokens.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? GlassTokens.textPrimary : GlassTokens.surface,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? GlassTokens.textPrimary : GlassTokens.border,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: label),
                  TextSpan(
                    text: '  $count',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
