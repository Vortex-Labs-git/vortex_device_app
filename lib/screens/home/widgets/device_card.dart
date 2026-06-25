import 'package:flutter/material.dart';

// =============================================================================
// DEVICE CARD
// =============================================================================
// One device row in the home device list. Shows avatar, name, ID,
// status dot + label, and a colored side bar. The whole card is tappable —
// the parent decides what to do based on device status.
//
// Avatar logic (driven by the device ID prefix):
//   - VA*  → valve product image (assets/images/valve_v2.jpeg)
//   - SU*  → sensor icon
//   - else → neutral unknown-device icon
//
// All status logic (online / offline / esp_connected) lives in the parent;
// this widget just receives the resolved [statusText] / [statusColor] values
// and the icon color override for the avatar.
// =============================================================================

class DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final String statusText;     // "Online" | "Offline" | "Direct Connected"
  final Color statusColor;     // Green or red
  final bool isEspConnected;   // Drives the avatar icon color
  final VoidCallback onTap;

  const DeviceCard({
    super.key,
    required this.device,
    required this.statusText,
    required this.statusColor,
    required this.isEspConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String name =
        device['vwv_name'] ?? device['device_name'] ?? 'Unknown Device';
    final String id = device['id']?.toString() ?? '';
    final String idPrefix = id.toUpperCase();
    final bool isValve = idPrefix.startsWith('VA');    // valve image
    final bool isSensor = idPrefix.startsWith('SU');   // sensor icon

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[200],
          ),
          child: Row(
            children: [
              // ─────────────────────────────────────────────────────────
              // Avatar: valve image for VA-*, sensor icon for SU-*,
              // neutral icon otherwise
              // ─────────────────────────────────────────────────────────
              Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isEspConnected ? Colors.green : Colors.indigo,
                    width: 2,
                  ),
                ),
                child: isValve
                    ? ClipOval(
                        child: Image.asset(
                          'assets/images/valve_v2.jpeg',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      )
                    : isSensor
                        ? Center(
                            child: Icon(
                              Icons.sensors,
                              size: 40,
                              color:
                                  isEspConnected ? Colors.green : Colors.indigo,
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.device_unknown,
                              size: 40,
                              color:
                                  isEspConnected ? Colors.green : Colors.indigo,
                            ),
                          ),
              ),

              // ─────────────────────────────────────────────────────────
              // Name + ID + status row
              // ─────────────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Device name
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    // Device ID
                    Text(
                      "ID: $id",
                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                    ),

                    const SizedBox(height: 4),

                    // Status dot + label
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: statusColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ─────────────────────────────────────────────────────────
              // Right colored side bar
              // ─────────────────────────────────────────────────────────
              Container(
                width: 12,
                height: 104,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}