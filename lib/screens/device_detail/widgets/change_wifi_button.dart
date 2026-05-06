import 'package:flutter/material.dart';

// =============================================================================
// CHANGE WIFI BUTTON
// =============================================================================
// Direct-mode-only button at the bottom of the screen. Tapping it opens the
// WiFi credentials dialog (handled in the parent screen via [onPressed]) so
// the user can push home WiFi credentials to the connected ESP32.
// =============================================================================

class ChangeWifiButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ChangeWifiButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.wifi),
        label: const Text('Change WiFi connection'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3F51B5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
