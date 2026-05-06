import 'package:flutter/material.dart';

// =============================================================================
// DEBUG PANEL
// =============================================================================
// Full debug terminal that appears below the toggle bar when expanded. Has:
//   1. ESP32 connection controls (IP / Port + Connect button)
//   2. Quick action buttons (Request Info / Open / Close / Clear)
//   3. Color-coded log output area
//
// All ESP32 service calls and state live in the parent. This widget receives
// the values it needs and raises callbacks for every user action.
//
// Currently DISABLED in build() but kept here in case it's re-enabled.
// =============================================================================

class DebugPanel extends StatelessWidget {
  // ── Inputs ──
  final TextEditingController ipController;
  final TextEditingController portController;
  final List<String> logs;
  final ScrollController scrollController;
  final bool isEspConnecting;
  final bool espConnected;

  // ── Callbacks ──
  final VoidCallback onConnectPressed;
  final VoidCallback onRequestInfoPressed;
  final VoidCallback onOpenValvePressed;
  final VoidCallback onCloseValvePressed;
  final VoidCallback onClearLogsPressed;

  const DebugPanel({
    super.key,
    required this.ipController,
    required this.portController,
    required this.logs,
    required this.scrollController,
    required this.isEspConnecting,
    required this.espConnected,
    required this.onConnectPressed,
    required this.onRequestInfoPressed,
    required this.onOpenValvePressed,
    required this.onCloseValvePressed,
    required this.onClearLogsPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // =====================================================
          // SECTION 1: ESP32 CONNECTION CONTROLS (IP / Port / Btn)
          // =====================================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                // 1.1  IP input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: ipController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText: 'IP Address',
                        hintStyle:
                            TextStyle(color: Colors.grey[600], fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey[700]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey[700]!),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF3C3C3C),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // 1.2  Port input
                SizedBox(
                  width: 50,
                  height: 32,
                  child: TextField(
                    controller: portController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Port',
                      hintStyle:
                          TextStyle(color: Colors.grey[600], fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: Colors.grey[700]!),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF3C3C3C),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // 1.3  Connect / Disconnect button
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: isEspConnecting ? null : onConnectPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          espConnected ? Colors.red[700] : Colors.green[700],
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: Size.zero,
                    ),
                    child: Text(
                      espConnected ? 'Disconnect' : 'Connect ESP',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // =====================================================
          // SECTION 2: QUICK ACTION BUTTONS
          // =====================================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0xFF2D2D2D),
            child: Row(
              children: [
                _actionButton('📡 Request Info', onRequestInfoPressed),
                const SizedBox(width: 6),
                _actionButton('🔓 Open Valve', onOpenValvePressed),
                const SizedBox(width: 6),
                _actionButton('🔒 Close Valve', onCloseValvePressed),
                const SizedBox(width: 6),
                _actionButton('🗑️ Clear', onClearLogsPressed),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF444444)),

          // =====================================================
          // SECTION 3: LOG OUTPUT AREA (color-coded by content)
          // =====================================================
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];

                // Color rules:
                //   red    → ERROR / FAILED / ❌
                //   green  → CONNECTED / ✅ / Received
                //   cyan   → ESP32 …
                //   amber  → outgoing → arrows
                //   grey   → everything else
                Color textColor = Colors.grey[400]!;
                if (log.contains('ERROR') ||
                    log.contains('FAILED') ||
                    log.contains('❌')) {
                  textColor = Colors.red[300]!;
                } else if (log.contains('CONNECTED') ||
                    log.contains('✅') ||
                    log.contains('Received')) {
                  textColor = Colors.greenAccent;
                } else if (log.contains('ESP32')) {
                  textColor = Colors.cyanAccent;
                } else if (log.contains('→')) {
                  textColor = Colors.amberAccent;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: a single quick-action button (used 4× above)
  // Inline because it's only used here and has no business logic.
  // ───────────────────────────────────────────────────────────────────────
  Widget _actionButton(String label, VoidCallback onTap) {
    return Expanded(
      child: SizedBox(
        height: 28,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            side: BorderSide(color: Colors.grey[700]!),
            foregroundColor: Colors.grey[300],
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
