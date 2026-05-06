import 'package:flutter/material.dart';

// =============================================================================
// EMPTY VIEW
// =============================================================================
// Shown when device loading is complete but the user has no devices assigned.
// Static, no callbacks needed — just a hint to contact Vortex Labs.
// =============================================================================

class EmptyView extends StatelessWidget {
  const EmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Devices icon
            Icon(Icons.devices_other, size: 60, color: Colors.grey[400]),

            const SizedBox(height: 16),

            // Title
            const Text(
              "No devices found",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),

            const SizedBox(height: 8),

            // Subtitle
            Text(
              "Please contact Vortex Labs to get devices assigned to your account.",
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
