import 'package:flutter/material.dart';

// =============================================================================
// DEBUG TOGGLE BAR
// =============================================================================
// Black bar at the bottom of the screen showing "Debug Terminal" label, an
// ESP connection indicator dot, and an arrow. Tapping it expands/collapses
// the full debug panel.
//
// Currently DISABLED in build() but kept here in case it's re-enabled.
// =============================================================================

class DebugToggleBar extends StatelessWidget {
  final bool showDebugPanel;
  final bool espConnected;
  final VoidCallback onTap;

  const DebugToggleBar({
    super.key,
    required this.showDebugPanel,
    required this.espConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        color: const Color(0xFF1E1E1E),
        child: Row(
          children: [
            // ─────────────────────────────────────────────────────────
            // Bug icon + "Debug Terminal" label
            // ─────────────────────────────────────────────────────────
            const Icon(Icons.bug_report, color: Colors.greenAccent, size: 16),
            const SizedBox(width: 8),
            const Text(
              'Debug Terminal',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),

            const Spacer(),

            // ─────────────────────────────────────────────────────────
            // ESP32 connection status dot
            // ─────────────────────────────────────────────────────────
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: espConnected ? Colors.greenAccent : Colors.red,
              ),
            ),
            const SizedBox(width: 6),

            // ESP / ESP OFF label
            Text(
              espConnected ? 'ESP' : 'ESP OFF',
              style: TextStyle(
                color: espConnected ? Colors.greenAccent : Colors.red,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),

            const SizedBox(width: 12),

            // Expand / collapse arrow
            Icon(
              showDebugPanel
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_up,
              color: Colors.greenAccent,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
