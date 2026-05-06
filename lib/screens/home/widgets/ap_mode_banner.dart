import 'package:flutter/material.dart';

// =============================================================================
// AP MODE BANNER
// =============================================================================
// Light-blue banner shown when the phone is connected to a Vortex_VA hotspot.
// Currently DISABLED in build() but kept here in case it's re-enabled.
//
// Reads ESP32 connection state through the parent (passed in via constructor)
// rather than calling EspDirectService.instance directly, so this widget stays
// pure and easy to test.
// =============================================================================

class ApModeBanner extends StatelessWidget {
  final bool espConnected;
  final String? espConnectedDeviceId;
  final bool isEspConnecting;

  const ApModeBanner({
    super.key,
    required this.espConnected,
    required this.espConnectedDeviceId,
    required this.isEspConnecting,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          // ─────────────────────────────────────────────────────────────
          // Left icon (check-circle when connected, remote when not)
          // ─────────────────────────────────────────────────────────────
          Icon(
            espConnected ? Icons.check_circle : Icons.settings_remote,
            color: espConnected ? Colors.green : const Color(0xFF3F51B5),
          ),

          const SizedBox(width: 12),

          // ─────────────────────────────────────────────────────────────
          // Title + subtitle
          // ─────────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  espConnected
                      ? 'Connected to valve directly'
                      : 'Valve WiFi detected',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  espConnected
                      ? 'Device: ${espConnectedDeviceId ?? "Identifying..."}'
                      : 'Tap a device to set up WiFi or control directly',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────────────────────────────
          // Spinner while connecting
          // ─────────────────────────────────────────────────────────────
          if (isEspConnecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}
