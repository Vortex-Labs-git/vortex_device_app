import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/device_repository.dart';
import '../controllers/network_watcher.dart';
import '../services/auth_service.dart';
import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';
import 'login/login_screen.dart';
import 'main/main_screen.dart';

// =============================================================================
// APP GATE
// =============================================================================
// The app's real entry point. Nothing else renders until both gates pass:
//
//   1. SESSION     AuthService.isLoggedIn — no session, no app. Login is a
//                  full screen here, not the inline panel inside the User tab,
//                  so a logged-out user cannot browse Home/Manual/About.
//   2. PERMISSION  Every runtime permission the app needs must be granted.
//                  Currently that is location, which Android requires before
//                  it will reveal the connected Wi-Fi network name (see
//                  NetworkWatcher).
//
// Order matters: session first. Asking a stranger for location before they
// have proved they own a device reads as hostile, and Play expects the request
// to arrive in context.
//
// THE PERMISSION SCREEN IS ALSO THE DISCLOSURE. Play requires an in-app
// explanation before the system prompt whenever the reason for a sensitive
// permission is not self-evident. This screen states it plainly and only
// triggers the system prompt when the user presses Continue — which is why the
// old dialog in MainScreen.initState is gone.
//
// RE-CHECKS ON RESUME: the user may leave for Settings to flip a permanently
// denied permission. The observer re-evaluates when they return, so the app
// unblocks itself without a restart.
// =============================================================================

/// Rebuilds the gate after a login or logout anywhere in the app.
/// Bump this instead of pushing a fresh MainScreen.
final ValueNotifier<int> appGateRevision = ValueNotifier<int>(0);

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

enum _GateStage { checking, needsLogin, needsPermission, ready }

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  _GateStage _stage = _GateStage.checking;
  bool _permanentlyDenied = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appGateRevision.addListener(_evaluate);
    _evaluate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appGateRevision.removeListener(_evaluate);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from Settings, where the user may have granted what we asked
    // for. Only worth re-checking while actually blocked.
    if (state == AppLifecycleState.resumed && _stage != _GateStage.ready) {
      _evaluate();
    }
  }

  Future<void> _evaluate() async {
    if (!AuthService.isLoggedIn) {
      if (mounted) setState(() => _stage = _GateStage.needsLogin);
      return;
    }

    final granted = await NetworkWatcher.instance.hasLocationPermission;
    if (!mounted) return;
    setState(() {
      _stage = granted ? _GateStage.ready : _GateStage.needsPermission;
      if (granted) _permanentlyDenied = false;
    });
  }

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    final granted = await NetworkWatcher.instance.requestLocationPermission();
    if (!mounted) return;

    // "Permanently denied" means the system prompt will no longer appear, so
    // the only route left is the app's settings page.
    final permanent = !granted && await Permission.location.isPermanentlyDenied;
    if (!mounted) return;

    setState(() {
      _requesting = false;
      _permanentlyDenied = permanent;
      if (granted) _stage = _GateStage.ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _GateStage.checking:
        return const GlassScaffold(
          body: Center(child: CircularProgressIndicator()),
        );

      case _GateStage.needsLogin:
        return LoginScreen(
          onLoginSuccess: () {
            DeviceRepository.instance.reloadForLogin();
            _evaluate(); // straight on to the permission gate
          },
        );

      case _GateStage.needsPermission:
        return _PermissionGate(
          busy: _requesting,
          permanentlyDenied: _permanentlyDenied,
          onContinue: _requestPermission,
          onOpenSettings: openAppSettings,
        );

      case _GateStage.ready:
        return const MainScreen();
    }
  }
}

// -----------------------------------------------------------------------------
// The blocking permission screen, which doubles as the Play disclosure.
// -----------------------------------------------------------------------------

class _PermissionGate extends StatelessWidget {
  final bool busy;
  final bool permanentlyDenied;
  final VoidCallback onContinue;
  final VoidCallback onOpenSettings;

  const _PermissionGate({
    required this.busy,
    required this.permanentlyDenied,
    required this.onContinue,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    const body = TextStyle(fontSize: 15, color: GlassTokens.textSecondary);

    return GlassScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.wifi_find,
                      size: 44, color: GlassTokens.accent),
                  const SizedBox(height: 18),
                  const Text(
                    'One permission needed',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: GlassTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'To control a valve or sensor unit directly, the app needs '
                    'to recognise when your phone joins the device’s own '
                    'Wi-Fi hotspot.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Android only reveals the name of the connected Wi-Fi '
                    'network to apps holding location permission, so it will '
                    'ask for location next.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your location is never read, stored, or sent anywhere. '
                    'The app reads only the Wi-Fi network name.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: GlassTokens.textPrimary,
                    ),
                  ),
                  if (permanentlyDenied) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Android will no longer show the permission prompt for '
                      'this app. Please enable Location in the app settings, '
                      'then return here.',
                      style: TextStyle(
                          fontSize: 15, color: GlassTokens.danger),
                    ),
                  ],
                  const SizedBox(height: 26),
                  if (busy)
                    const Center(child: CircularProgressIndicator())
                  else
                    GlassButton(
                      label:
                          permanentlyDenied ? 'Open app settings' : 'Continue',
                      onPressed:
                          permanentlyDenied ? onOpenSettings : onContinue,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
