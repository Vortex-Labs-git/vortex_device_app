import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../models/valve_device.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// SENSOR CARD
// =============================================================================
// "Control by → sensor". Two halves, both fed by the "Sensor" block of the
// device_schedule push:
//
//   1. IDENTITY PANEL  which sensor drives this valve, whether its unit is
//                      online (last_seen, same 30 s window as the valve), and
//                      its latest reading. Offline blurs the reading — a stale
//                      number that looks live is worse than no number.
//
//   2. RULE TABLE      "sensor range → valve angle", laid out exactly like
//                      ScheduleCard's table so the two read as one system.
//
// View only. Dialogs, validation and the save call live in DeviceDetailScreen
// and arrive as callbacks — same split as ScheduleCard.
// =============================================================================

class SensorCard extends StatelessWidget {
  /// The bound sensor, or null when this valve has none yet.
  final SensorReading? reading;

  /// True when [reading]'s unit counts as online (isDeviceOnline on last_seen).
  final bool isUnitOnline;

  final List<SensorRule> rules;
  final bool isSavingRules;

  final VoidCallback onAddPressed;
  /// "+ Add sensor" / the swap button — picks WHICH sensor drives this valve.
  /// A different operation from adding a rule, hence its own callback.
  final VoidCallback onAddSensorPressed;

  /// Unbind the sensor entirely. Destructive — the screen confirms first.
  final VoidCallback onRemoveSensor;

  /// True while get_user_sensors is in flight.
  final bool isLoadingUnits;

  final ValueChanged<int> onRowTapped;   // tap a row to edit it
  final ValueChanged<int> onRowDeleted;
  final VoidCallback onSavePressed;

  const SensorCard({
    super.key,
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

  // Column widths, shared by the header and every row so they stay aligned.
  // Mirrors ScheduleCard's _dayFlex / _timeFlex / _angleFlex / _deleteWidth.
  static const int _rangeFlex = 5;
  static const int _angleFlex = 3;
  static const double _deleteWidth = 40;

  @override
  Widget build(BuildContext context) {
    final SensorReading? sensor = reading;

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =========================================================
            // SECTION 1: HEADER (title + rule count)
            // =========================================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sensor Settings',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${rules.length} ${rules.length == 1 ? 'rule' : 'rules'}',
                  style: TextStyle(color: GlassTokens.textMuted, fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // =========================================================
            // SECTION 2: THE SENSOR
            // =========================================================
            if (sensor == null) _buildAddSensorBox() else _buildSensor(sensor),

            const SizedBox(height: 18),

            // =========================================================
            // SECTION 3: TABLE HEADER (Sensor range | Valve angle | _)
            // =========================================================
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: GlassTokens.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: _rangeFlex,
                    child: Center(
                      child: Text('Sensor range',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Expanded(
                    flex: _angleFlex,
                    child: Center(
                      child: Text('Valve angle',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(width: _deleteWidth), // delete button column
                ],
              ),
            ),

            // =========================================================
            // SECTION 4: RULE ROWS (or empty placeholder)
            // =========================================================
            if (rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No sensor rules yet.\nTap + to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GlassTokens.textMuted),
                  ),
                ),
              )
            else
              ...rules.asMap().entries.map(
                    (e) => _buildRow(index: e.key, rule: e.value),
                  ),

            const SizedBox(height: 12),

            // =========================================================
            // SECTION 5: ADD RULE
            // =========================================================
            Center(
              child: TextButton.icon(
                onPressed: onAddPressed,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Sensor Rule'),
                style: TextButton.styleFrom(
                  foregroundColor: GlassTokens.primary,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // =========================================================
            // SECTION 6: SAVE
            // =========================================================
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSavingRules ? null : onSavePressed,
                icon: isSavingRules
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(isSavingRules ? 'Saving...' : 'Save Sensor Rules'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTokens.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      GlassTokens.primary.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Empty state — no sensor bound to this valve yet
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildAddSensorBox() {
    return InkWell(
      onTap: isLoadingUnits ? null : onAddSensorPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.35),
          border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: isLoadingUnits
              ? [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GlassTokens.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Loading sensor units...',
                    style: TextStyle(color: GlassTokens.textMuted),
                  ),
                ]
              : const [
                  Icon(Icons.add_circle_outline,
                      color: GlassTokens.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Add sensor',
                    style: TextStyle(
                      color: GlassTokens.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Identity panel — unit, state, sensor, type, live reading
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildSensor(SensorReading sensor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // Violet = sensor mode, the same hue ModeToggleCard gives it.
        color: GlassTokens.info.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- Unit id + name + online pill --
          //    Actions deliberately NOT in this row: badge + id + pill + an
          //    icon squeezes "SU200001001" down to an ellipsis on a 360dp
          //    phone. Remove lives on its own row at the bottom instead.
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.sensors,
                    color: GlassTokens.info, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sensor.unitId.isEmpty ? 'Unknown unit' : sensor.unitId,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: GlassTokens.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sensor.unitName.isNotEmpty)
                      Text(
                        sensor.unitName,
                        style: TextStyle(
                            fontSize: 12, color: GlassTokens.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _buildStatePill(),
            ],
          ),

          const SizedBox(height: 12),

          // -- Sensor name | type | reading --
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _field(
                  'Sensor',
                  sensor.sensorName.isEmpty
                      ? sensor.sensorId
                      : sensor.sensorName,
                ),
              ),
              Expanded(
                child: _field(
                  'Type',
                  sensor.sensorType.isEmpty ? '—' : sensor.sensorType,
                ),
              ),
              _buildReading(sensor),
            ],
          ),

          // -- Offline: say WHY the reading is greyed out --
          if (!isUnitOnline) ...[
            const SizedBox(height: 8),
            Text(
              sensor.lastSeen == null
                  ? 'Unit has not reported yet.'
                  : 'Last seen ${sensor.lastSeen} — reading is stale.',
              style: TextStyle(fontSize: 11, color: GlassTokens.textMuted),
            ),
          ],

          // -- Remove --
          //    No "change" affordance on purpose: removing drops back to the
          //    "+ Add sensor" box, which is the one way in. One path in, one
          //    path out — and it makes the rule wipe explicit instead of
          //    hiding it behind a swap.
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: isSavingRules ? null : onRemoveSensor,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove'),
              style: TextButton.styleFrom(
                foregroundColor: GlassTokens.danger,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatePill() {
    final Color tint = isUnitOnline ? GlassTokens.success : GlassTokens.danger;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
          ),
          const SizedBox(width: 6),
          Text(
            isUnitOnline ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: tint,
            ),
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
    final Widget value = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          // Trimmed to one decimal — see SensorReading.displayValue. The raw
          // 33.45692475692 pushed this box wide enough to squeeze the Sensor
          // and Type columns out of the row entirely.
          sensor.displayValue,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            height: 1.1,
            fontWeight: FontWeight.bold,
            color: GlassTokens.info,
          ),
        ),
        Text(
          'reading',
          style: TextStyle(fontSize: 11, color: GlassTokens.textMuted),
        ),
      ],
    );

    return Container(
      // maxWidth as well as minWidth: this box is the only unbounded child of
      // its Row, so without a ceiling ANY long value starves the two Expanded
      // columns beside it and overflows the card. The formatting above should
      // keep it well under 110, but the cap means a surprise value degrades
      // to an ellipsis instead of breaking the layout.
      constraints: const BoxConstraints(minWidth: 78, maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
      ),
      child: isUnitOnline
          ? value
          : ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Opacity(opacity: 0.55, child: value),
            ),
    );
  }

  Widget _field(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: GlassTokens.textMuted),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: GlassTokens.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // One rule row (range | angle | delete). Tapping the body edits it; the
  // delete icon deletes independently — identical to ScheduleCard._buildRow.
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildRow({required int index, required SensorRule rule}) {
    return InkWell(
      onTap: () => onRowTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: _rangeFlex,
              child: Center(
                child: Text(
                  rule.rangeLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: _angleFlex,
              child: Center(
                child: Text(
                  '${rule.angle}°',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _angleColor(rule.angle),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: _deleteWidth,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => onRowDeleted(index),
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: GlassTokens.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Same red / amber / green ramp the schedule table uses, so an angle reads
  /// the same in both tables.
  Color _angleColor(int angle) {
    if (angle <= 0) return GlassTokens.danger;
    if (angle >= 90) return GlassTokens.success;
    return GlassTokens.warning;
  }
}