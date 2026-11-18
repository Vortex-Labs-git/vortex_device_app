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
// UI v2 layout: an illustration of the phone reaching a device hotspot, then
// the same three facts as a checklist — why, why location, and the privacy
// promise — so the disclosure is skimmable without losing any of its wording.

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
    return GlassScaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: _HotspotArt()),
                const SizedBox(height: 20),
                const Text(
                  'One permission to talk to your devices',
                  style: TextStyle(
                    fontFamily: GlassTokens.displayFont,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: GlassTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                const GlassCard(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    children: [
                      _Reason(
                        icon: Icons.wifi_rounded,
                        color: GlassTokens.water,
                        background: GlassTokens.waterSoft,
                        title: 'Find the device hotspot',
                        body: 'To control a valve or sensor unit directly, the '
                            'app needs to recognise when your phone joins the '
                            'device’s own Wi-Fi hotspot.',
                      ),
                      _ReasonDivider(),
                      _Reason(
                        icon: Icons.location_on_outlined,
                        color: GlassTokens.sun,
                        background: GlassTokens.sunSoft,
                        title: 'Why Android asks for location',
                        body: 'Android only reveals the name of the connected '
                            'Wi-Fi network to apps holding location '
                            'permission, so it will ask for location next.',
                      ),
                      _ReasonDivider(),
                      _Reason(
                        icon: Icons.verified_user_outlined,
                        color: GlassTokens.success,
                        background: GlassTokens.leafSoft,
                        title: 'Your location is never read',
                        body: 'Your location is never read, stored, or sent '
                            'anywhere. The app reads only the Wi-Fi network '
                            'name.',
                      ),
                    ],
                  ),
                ),
                if (permanentlyDenied) ...[
                  const SizedBox(height: 14),
                  GlassCard(
                    tint: GlassTokens.danger,
                    tintStrength: 0.12,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: GlassTokens.danger, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Android will no longer show the permission '
                            'prompt for this app. Please enable Location in '
                            'the app settings, then return here.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: Color.lerp(
                                  GlassTokens.danger, Colors.black, 0.25),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (busy)
                  const Center(child: CircularProgressIndicator())
                else
                  GlassButton(
                    label: permanentlyDenied ? 'Open app settings' : 'Continue',
                    onPressed: permanentlyDenied ? onOpenSettings : onContinue,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String body;

  const _Reason({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: GlassTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: GlassTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReasonDivider extends StatelessWidget {
  const _ReasonDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Divider(height: 1, color: GlassTokens.border),
    );
  }
}

// Phone on the left, a valve on the right, gold Wi-Fi arcs between them.
class _HotspotArt extends StatelessWidget {
  const _HotspotArt();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 210,
        height: 130,
        child: CustomPaint(painter: _HotspotPainter()),
      ),
    );
  }
}

class _HotspotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Soft disc behind everything.
    canvas.drawCircle(const Offset(105, 65), 62,
        Paint()..color = GlassTokens.leafSoft);

    // Phone.
    final RRect phone = RRect.fromRectAndRadius(
        const Rect.fromLTWH(40, 30, 44, 76), const Radius.circular(9));
    canvas.drawRRect(phone, Paint()..color = GlassTokens.surface);
    canvas.drawRRect(
        phone,
        Paint()
          ..color = GlassTokens.textPrimary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(47, 40, 30, 40), const Radius.circular(4)),
        Paint()..color = GlassTokens.primary);

    // Valve: actuator box on a stem, gold indicator.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(128, 52, 40, 34), const Radius.circular(6)),
        Paint()..color = GlassTokens.forest);
    canvas.drawRect(const Rect.fromLTWH(142, 86, 12, 20),
        Paint()..color = GlassTokens.textSecondary);
    canvas.drawCircle(
        const Offset(148, 68), 6, Paint()..color = GlassTokens.gold);

    // Wi-Fi arcs.
    final Paint arc = Paint()
      ..color = GlassTokens.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: const Offset(106, 72), radius: 16),
        3.6, 2.2, false, arc);
    canvas.drawArc(Rect.fromCircle(center: const Offset(106, 72), radius: 8),
        3.6, 2.2, false, arc);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
