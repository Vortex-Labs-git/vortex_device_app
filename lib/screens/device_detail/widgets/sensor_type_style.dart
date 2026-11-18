import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// SENSOR TYPE STYLE  (UI v2)
// =============================================================================
// Icon and colours for a sensor type string, shared by the sensor unit screen
// and Sensor configuration. Matching is loose (contains, any case) because the
// type comes from the unit as free text; anything unknown gets a neutral look.
// =============================================================================

class SensorTypeStyle {
  final IconData icon;
  final Color color;
  final Color background;

  const SensorTypeStyle(this.icon, this.color, this.background);

  static SensorTypeStyle of(String type) {
    final String t = type.toLowerCase();
    if (t.contains('temp')) {
      return const SensorTypeStyle(
          Icons.thermostat_rounded, GlassTokens.sun, GlassTokens.sunSoft);
    }
    if (t.contains('humid')) {
      return const SensorTypeStyle(
          Icons.water_drop_outlined, GlassTokens.water, GlassTokens.waterSoft);
    }
    if (t.contains('moist')) {
      return const SensorTypeStyle(
          Icons.grass_rounded, GlassTokens.primary, GlassTokens.leafSoft);
    }
    return const SensorTypeStyle(
        Icons.sensors_rounded, GlassTokens.textSecondary, GlassTokens.sunk);
  }
}
