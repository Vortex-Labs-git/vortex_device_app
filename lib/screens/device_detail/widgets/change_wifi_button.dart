import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import 'tool_row.dart';

// =============================================================================
// CHANGE WIFI BUTTON
// =============================================================================
// Direct-mode-only button at the bottom of the screen. Tapping it opens the
// WiFi credentials dialog (handled in the parent screen via [onPressed]) so
// the user can push home WiFi credentials to the connected ESP32.
// UI v2: a row in the direct-mode "Device tools" card (see ToolRow).
// =============================================================================

class ChangeWifiButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ChangeWifiButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ToolRow(
      icon: Icons.wifi,
      iconColor: GlassTokens.water,
      iconBackground: GlassTokens.waterSoft,
      title: 'Change Wi-Fi',
      subtitle: 'Send your farm Wi-Fi to the valve',
      onPressed: onPressed,
    );
  }
}
