import 'package:flutter/material.dart';

// =============================================================================
// CONNECTION STATUS BAR
// =============================================================================
// Thin colored bar at the top of the device list. Three possible states:
//   - GREEN  "Live updates active"            (server WS connected)
//   - INDIGO "Direct mode — <ssid>"           (phone is on a Vortex_VA AP)
//   - ORANGE "Offline — showing cached..."    (no server, no AP)
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
    // Decide bar color, text, and icon based on connection state
    // ─────────────────────────────────────────────────────────────
    Color barColor;
    String barText;
    IconData barIcon;

    if (wsConnected) {
      barColor = Colors.green;
      barText = "Live updates active";
      barIcon = Icons.wifi;
    } else if (isEspApMode) {
      barColor = const Color(0xFF3F51B5);
      barText = "Direct mode — ${connectedSsid ?? 'Valve WiFi'}";
      barIcon = Icons.settings_remote;
    } else {
      barColor = Colors.orange;
      barText = "Offline — showing cached devices";
      barIcon = Icons.wifi_off;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      color: barColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(barIcon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              barText,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
