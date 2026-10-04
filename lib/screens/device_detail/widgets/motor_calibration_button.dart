import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import 'tool_row.dart';

// =============================================================================
// MOTOR CALIBRATION BUTTON
// =============================================================================
// Direct-mode-only button shown under the Change WiFi button. Tapping it
// opens MotorCalibrationScreen — that navigation is handled in the parent
// screen via [onPressed].
// UI v2: a row in the direct-mode "Device tools" card (see ToolRow).
// =============================================================================

class MotorCalibrationButton extends StatelessWidget {
  final VoidCallback onPressed;

  const MotorCalibrationButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ToolRow(
      icon: Icons.track_changes_rounded,
      iconColor: GlassTokens.onGold,
      iconBackground: GlassTokens.goldSoft,
      title: 'Motor calibration',
      subtitle: 'Set the fully closed and open points',
      onPressed: onPressed,
    );
  }
}
