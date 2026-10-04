import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../models/valve_device.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import 'tinted_add_button.dart';

// =============================================================================
// PLUG SENSOR CARD  (UI v2)
// =============================================================================
// The plug's Sensor rules tab, for ONE socket — same layout as the valve's
// SensorCard, fed by that socket's "Sensor" block of the device_schedule push:
//
//   1. SENSOR      which sensor drives this socket, whether its unit is
//                  online, the latest reading and Remove. Offline blurs the
//                  reading. No sensor yet → "Choose a sensor".
//   2. RULES       one card per "reading range → Turn ON / Turn OFF". The rule
//                  that matches the current reading is marked "In use now".
//
// Each socket of a dual plug has its own sensor and rules; the parent passes
// the selected socket's. Saving is separate: the parent floats a Save pill
// (FloatingSavePill) at the bottom of the screen. View only — dialogs, validation and the save call live
// in PlugDetailScreen and arrive as callbacks.
// =============================================================================

class PlugSensorCard extends StatelessWidget {
  /// Socket name, used in the empty state.
  final String baseName;

  /// The bound sensor, or null when this socket has none yet.
  final SensorReading? reading;

  /// True when [reading]'s unit counts as online (isDeviceOnline on last_seen).
  final bool isUnitOnline;

  final List<PlugSensorRule> rules;
  final bool isSavingRules;
  final VoidCallback onAddPressed;

  /// "Choose a sensor" — picks WHICH sensor drives this socket. A different
  /// operation from adding a rule, hence its own callback.
  final VoidCallback onAddSensorPressed;

  /// Unbind the sensor entirely. Destructive — the screen confirms first.
  final VoidCallback onRemoveSensor;

  /// True while get_user_sensors is in flight.
  final bool isLoadingUnits;

  final ValueChanged<int> onRowTapped; // tap a rule to edit it
  final ValueChanged<int> onRowDeleted;
  final VoidCallback onSavePressed;

  const PlugSensorCard({
    super.key,
    required this.baseName,
    required this.reading,
    required this.isUnitOnline,
    required this.rules,
    required this.isSavingRules,
    required this.onAddPressed,
    required this.onAddSensorPressed,
    required this.onRemoveSensor,
    this.isLoadingUnits = false,
    required this.onRowTapped,
    required this.onRowDeleted,
    required this.onSavePressed,
  });

  /// Index of the rule the current reading falls in, or null (offline,
  /// unreadable value, or no match).
  int? get _activeRule {
    final SensorReading? sensor = reading;
    if (sensor == null || !isUnitOnline) return null;
    final double? v = double.tryParse(sensor.value.trim());
    if (v == null) return null;
    for (int i = 0; i < rules.length; i++) {
      if (v >= rules[i].from && v <= rules[i].to) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final SensorReading? sensor = reading;
    if (sensor == null) return _buildNoSensor();

    final int? active = _activeRule;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSensor(sensor),
        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(
              child: Text(
                'Rules',
                style: TextStyle(
                  fontFamily: GlassTokens.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textPrimary,
                ),
              ),
            ),
            Text(
              '${rules.length} ${rules.length == 1 ? 'rule' : 'rules'} · '
              'reading → socket',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GlassTokens.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (rules.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Text(
              'No rules yet. Add one for when $baseName turns ON or OFF.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlassTokens.textMuted, height: 1.4),
            ),
          ),

        for (int i = 0; i < rules.length; i++)
          _RuleCard(
            rule: rules[i],
            inUse: i == active,
            onTap: () => onRowTapped(i),
            onDelete: () => onRowDeleted(i),
          ),

        const SizedBox(height: 2),
        TintedAddButton(label: 'Add rule', onPressed: onAddPressed),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // No sensor bound yet
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildNoSensor() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: GlassTokens.infoSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.sensors, color: GlassTokens.info, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            'No sensor linked to $baseName',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: GlassTokens.displayFont,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: GlassTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pick a sensor from one of your sensor units. Then add rules for '
            'when $baseName turns ON or OFF.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: GlassTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          GlassButton(
            label: isLoadingUnits ? 'Loading sensor units…' : 'Choose a sensor',
            icon: Icons.add_rounded,
            fullWidth: false,
            height: 48,
            isLoading: isLoadingUnits,
            onPressed: isLoadingUnits ? null : onAddSensorPressed,
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // The bound sensor
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildSensor(SensorReading sensor) {
    final String name =
        sensor.sensorName.isEmpty ? sensor.sensorId : sensor.sensorName;
    final String title =
        sensor.sensorType.isEmpty ? name : '$name · ${sensor.sensorType}';
    final String unit = [
      if (sensor.unitName.isNotEmpty) sensor.unitName,
      if (sensor.unitId.isNotEmpty) sensor.unitId,
      if (sensor.sensorId.isNotEmpty) sensor.sensorId,
    ].join(' · ');

    final String status = isUnitOnline
        ? 'Reading now'
        : sensor.lastSeen == null
            ? 'Unit has not reported yet'
            : 'Last seen ${sensor.lastSeen} · reading is stale';

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -- Icon · name / type / unit · online tag --
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: GlassTokens.infoSoft,
                  borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
                ),
                child: const Icon(Icons.sensors,
                    color: GlassTokens.info, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: GlassTokens.textPrimary,
                      ),
                    ),
                    if (unit.isNotEmpty)
                      Text(
                        unit,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: GlassTokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              isUnitOnline
                  ? StatusTag.online()
                  : StatusTag.offline(),
              const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 10),

          // -- Reading · status text (takes the rest, wraps) · Remove --
          //    The text is Expanded and may wrap to a second or third line,
          //    so the Remove button never gets pushed out of the card.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildReading(sensor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: GlassTokens.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: isSavingRules ? null : onRemoveSensor,
                style: TextButton.styleFrom(
                  foregroundColor: GlassTokens.danger,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
                    side: BorderSide(
                      color: GlassTokens.danger.withValues(alpha: 0.30),
                    ),
                  ),
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The live value. Offline, it is blurred rather than hidden: the user can
  /// see a reading exists without being able to misread a stale one as current.
  ///
  /// ImageFiltered, NOT BackdropFilter — this blurs its own child, so it costs
  /// one small filter instead of re-blurring the backdrop every frame.
  Widget _buildReading(SensorReading sensor) {
    final Widget value = ConstrainedBox(
      // A ceiling so a surprise long value ellipsizes instead of starving
      // the status text and the Remove button.
      constraints: const BoxConstraints(maxWidth: 120),
      child: Text(
        sensor.displayValue,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: GlassTokens.displayFont,
          fontSize: 38,
          height: 1.0,
          fontWeight: FontWeight.w800,
          color: GlassTokens.info,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
    return isUnitOnline
        ? value
        : ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Opacity(opacity: 0.55, child: value),
          );
  }
}

// -----------------------------------------------------------------------------
// One rule: swatch · range / when · Turn ON / OFF · delete. Tap to edit.
// -----------------------------------------------------------------------------

class _RuleCard extends StatelessWidget {
  final PlugSensorRule rule;
  final bool inUse;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RuleCard({
    required this.rule,
    required this.inUse,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bool on = rule.state;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        boxShadow: inUse
            ? [
                BoxShadow(
                  color: GlassTokens.info.withValues(alpha: 0.18),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: Material(
        color: GlassTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          side: BorderSide(
            color: inUse ? GlassTokens.info : GlassTokens.border,
            width: inUse ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 32,
                  decoration: BoxDecoration(
                    color: on ? GlassTokens.primary : GlassTokens.border,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            rule.rangeLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: GlassTokens.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (inUse)
                            const StatusTag(
                              label: 'In use now',
                              color: Colors.white,
                              background: GlassTokens.info,
                              foreground: Colors.white,
                            ),
                        ],
                      ),
                      const Text(
                        'When the reading is in this range',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: GlassTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                StatusTag(
                  label: on ? 'Turn ON' : 'Turn OFF',
                  color: on ? GlassTokens.success : GlassTokens.textSecondary,
                  background: on ? GlassTokens.leafSoft : GlassTokens.sunk,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: GlassTokens.textMuted),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
