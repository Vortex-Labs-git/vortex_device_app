import 'package:flutter/material.dart';

// =============================================================================
// ERROR VIEW
// =============================================================================
// Shown when there's an error message AND no cached devices to display.
// Shows the error icon, message, and a Retry button that re-runs initialization.
// =============================================================================

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error icon
            Icon(Icons.wifi_off, size: 60, color: Colors.red[300]),

            const SizedBox(height: 16),

            // Error message text
            Text(
              message,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Retry button
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}
