import 'package:flutter/material.dart';

import '../../../widgets/glass/glass.dart';

// =============================================================================
// DEVICE INFO CARD
// =============================================================================
// Shows three rows: Product Type, Name (with Edit button), Connection Status.
// Receives all values + callbacks from the parent screen.
// =============================================================================

class DeviceInfoCard extends StatelessWidget {
  final String productType;
  final String deviceName;
  final bool isOnline;
  final bool isDirectMode;
  final VoidCallback onEditName;

  const DeviceInfoCard({
    super.key,
    required this.productType,
    required this.deviceName,
    required this.isOnline,
    required this.isDirectMode,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    final String statusText =
        isDirectMode ? 'Direct Connected' : (isOnline ? 'online' : 'offline');
    final Color statusColor = isOnline ? Colors.green : Colors.red;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ─────────────────────────────────────────────────────────────
            // Row 1: Product Type
            // ─────────────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Product Type', style: TextStyle(color: Colors.grey)),
                Text(
                  productType,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),

            const Divider(),

            // ─────────────────────────────────────────────────────────────
            // Row 2: Name with Edit button
            // ─────────────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Name', style: TextStyle(color: Colors.grey)),
                Row(
                  children: [
                    TextButton(
                      onPressed: onEditName,
                      child: const Text(
                        'Edit',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                    Text(
                      deviceName,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(),

            // ─────────────────────────────────────────────────────────────
            // Row 3: Connection Status (colored dot + label)
            // ─────────────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Connection Status',
                  style: TextStyle(color: Colors.grey),
                ),
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
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
