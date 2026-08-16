import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// CONNECTION STATUS BAR
// =============================================================================
// Status capsule above the device list. Three possible states:
//   - GREEN  "Live updates active"            (server WS connected)
//   - INDIGO "Direct mode — <ssid>"           (phone is on a Vortex_VA AP)
//   - ORANGE "Offline — showing cached..."    (no server, no AP)
//
// Drawn as a tinted glass pill rather than a full-bleed bar: it floats over
// the backdrop with the rest of the UI instead of cutting the screen in two.
//
// All values are derived in the parent and passed in.
// =============================================================================

class ConnectionStatusBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // ─────────────────────────────────────────────────────────────
    // Decide tint, text, and icon based on connection state
    // ─────────────────────────────────────────────────────────────
    Color tint;
    String barText;
    IconData barIcon;

    if (wsConnected) {
      tint = GlassTokens.success;
      barText = "Live updates active";
      barIcon = Icons.wifi;
    } else if (isEspApMode) {
      tint = GlassTokens.primary;
      barText = "Direct mode — ${connectedSsid ?? 'Valve WiFi'}";
      barIcon = Icons.settings_remote;
    } else {
      tint = GlassTokens.warning;
      barText = "Offline — showing cached devices";
      barIcon = Icons.wifi_off;
    }

    final Color foreground = Color.lerp(tint, Colors.black, 0.35)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GlassPill(
        tint: tint,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Pulsing-looking dot: a glow ring around the state icon
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint.withValues(alpha: 0.18),
              ),
              child: Icon(barIcon, color: foreground, size: 13),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                barText,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
