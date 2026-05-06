import 'package:flutter/material.dart';

// =============================================================================
// MOTOR CALIBRATION BUTTON
// =============================================================================
// Direct-mode-only button shown under the Change WiFi button. Tapping it
// opens MotorCalibrationScreen — that navigation is handled in the parent
// screen via [onPressed].
// =============================================================================

class MotorCalibrationButton extends StatelessWidget {
  final VoidCallback onPressed;

  const MotorCalibrationButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.tune),
        label: const Text('Motor Calibration'),
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
