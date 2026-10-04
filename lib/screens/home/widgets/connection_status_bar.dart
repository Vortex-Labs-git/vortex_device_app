import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// CONNECTION STATUS BAR
// =============================================================================
// Tappable status card above the device list. Three possible states:
//   - GREEN  "Live updates on"                (server WS connected)
//   - GOLD   "Direct mode · <ssid>"           (phone is on a Vortex_VA AP)
//   - AMBER  "Offline · showing saved..."     (no server, no AP)
//
// The one-line summary rarely tells the user what a state actually means for
// them, so tapping expands an explanation of what works in that mode.
//
// The dot pulses for a few seconds when the connection comes up, then settles.
// It deliberately does NOT pulse forever: an animation that never ends keeps
// the whole app producing frames, and because BackdropFilter cannot be cached,
// the app bar and nav blurs are then recomputed on every one of those frames.
// Measured, that cost a full CPU core continuously while the screen just sat
// there. A pulse on the transition says "this just went live" — which is the
// moment the information is worth anything — and then the screen goes quiet.
//
// This widget is display-only: it takes the same three values from the parent
// as before and never talks to the services itself. Expansion is local state.
// =============================================================================

class ConnectionStatusBar extends StatefulWidget {
  final bool wsConnected;
  final bool isEspApMode;
  final String? connectedSsid;

  const ConnectionStatusBar({
    super.key,
    required this.wsConnected,
    required this.isEspApMode,
    required this.connectedSsid,
  });

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _pulse;
  Timer? _pulseStop;

  /// How long the "just went live" pulse runs before the screen goes idle.
  static const Duration _pulseWindow = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(ConnectionStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wsConnected != oldWidget.wsConnected) _syncPulse();
  }

  /// The halo runs only while updates are actually live — a pulsing dot on a
  /// stale or offline state would be a lie — and only for [_pulseWindow], so
  /// the app can go idle afterwards. See the note at the top of this file for
  /// why a permanent animation is expensive here specifically.
  void _syncPulse() {
    _pulseStop?.cancel();

    if (!widget.wsConnected) {
      _pulse.stop();
      _pulse.value = 0;
      return;
    }

    _pulse.repeat();
    _pulseStop = Timer(_pulseWindow, () {
      if (!mounted) return;
      _pulse.stop();
      // Rewinding notifies the listeners, so the halo clears without a
      // setState of its own.
      _pulse.value = 0;
    });
  }

  @override
  void dispose() {
    _pulseStop?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ─────────────────────────────────────────────────────────────
    // Resolve tint, label, icon and the expanded explanation
    // ─────────────────────────────────────────────────────────────
    final Color tint;
    final String label;
    final IconData icon;
    final String detail;

    if (widget.wsConnected) {
      tint = GlassTokens.success;
      label = 'Live updates on';
      icon = Icons.wifi;
      detail = 'Connected to the Vortex cloud.';
    } else if (widget.isEspApMode) {
      tint = GlassTokens.primary;
      label = 'Direct mode · ${widget.connectedSsid ?? 'Valve WiFi'}';
      icon = Icons.settings_remote;
      detail = 'Talking straight to the valve over its own WiFi. Manual '
          'control works; schedule and sensor features need a cloud '
          'connection.';
    } else {
      tint = GlassTokens.warning;
      label = 'Offline · showing saved devices';
      icon = Icons.wifi_off;
      detail = 'No connection to the Vortex cloud. This is the device list '
          'saved on your phone — pull down to retry.';
    }

    // Direct mode is the brand gold (a special link, not an error): gold
    // fill under dark text. Live and offline use their status colour.
    final bool gold = !widget.wsConnected && widget.isEspApMode;
    final Color fill = gold ? GlassTokens.goldSoft : Color.lerp(Colors.white, tint, 0.12)!;
    final Color foreground =
        gold ? GlassTokens.textPrimary : Color.lerp(tint, Colors.black, 0.20)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusDot(
                    tint: gold ? GlassTokens.gold : tint,
                    iconColor: gold ? GlassTokens.onGold : Colors.white,
                    icon: icon,
                    pulse: _pulse,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          // ── Explanation, revealed on tap ──
                          if (_expanded) ...[
                            const SizedBox(height: 6),
                            Text(
                              detail,
                              style: TextStyle(
                                color: foreground.withValues(alpha: 0.9),
                                fontSize: 12.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: AnimatedRotation(
                      turns: _expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
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

// -----------------------------------------------------------------------------
// STATUS DOT
// -----------------------------------------------------------------------------
// The state icon, with a halo that expands and fades while [pulse] runs.
// Isolated behind a RepaintBoundary so the animation repaints ~20px, not the
// whole capsule and the list behind it.
// -----------------------------------------------------------------------------

class _StatusDot extends StatelessWidget {
  final Color tint;
  final Color iconColor;
  final IconData icon;
  final Animation<double> pulse;

  const _StatusDot({
    required this.tint,
    required this.iconColor,
    required this.icon,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                final double t = pulse.value;
                if (t == 0) return const SizedBox.shrink();
                return Container(
                  width: 28 + 12 * t,
                  height: 28 + 12 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tint.withValues(alpha: 0.35 * (1 - t)),
                  ),
                );
              },
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
              child: Icon(icon, color: iconColor, size: 15),
            ),
          ],
        ),
      ),
    );
  }
}
