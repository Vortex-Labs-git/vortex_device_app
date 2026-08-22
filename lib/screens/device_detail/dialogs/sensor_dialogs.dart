import 'package:flutter/material.dart';

import '../../../models/valve_device.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../utils/sensor_utils.dart';
import '../utils/valve_utils.dart';

/// Add / edit one sensor rule — the sensor twin of showScheduleEntryDialog.
///
/// Pass the existing rule as [initial] to edit it; omit it to add a new one.
/// [existingRules] is everything currently in the table (INCLUDING [initial]
/// when editing — it is excluded internally), used to reject a range that
/// overlaps another rule: two rules claiming the same reading would leave the
/// valve angle undefined.
///
/// Returns the rule, or null if the user cancelled.
Future<SensorRule?> showSensorRuleDialog(
  BuildContext context, {
  SensorRule? initial,
  List<SensorRule> existingRules = const [],
}) {
  final SensorRule? existing = initial;
  final bool isEditing = existing != null;

  final TextEditingController fromController =
      TextEditingController(text: (existing?.from ?? 0).toString());
  final TextEditingController toController =
      TextEditingController(text: (existing?.to ?? 30).toString());

  double angle = (existing?.angle ?? 0).toDouble();
  String? errorText;

  return showGlassDialog<SensorRule>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return GlassDialog(
            title: isEditing ? 'Edit Sensor Rule' : 'Add Sensor Rule',
            icon: Icons.sensors,
            tint: GlassTokens.info,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ───────────────────────────────────────────────────────
                // Reading range
                // ───────────────────────────────────────────────────────
                Text(
                  'Sensor range',
                  style: TextStyle(fontSize: 12, color: GlassTokens.textMuted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fromController,
                        keyboardType: TextInputType.number,
                        decoration: glassInputDecoration(labelText: 'From')
                            .copyWith(isDense: true),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('–'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: toController,
                        keyboardType: TextInputType.number,
                        decoration: glassInputDecoration(labelText: 'To')
                            .copyWith(isDense: true),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ───────────────────────────────────────────────────────
                // Valve angle
                // ───────────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Valve angle',
                      style: TextStyle(
                          fontSize: 12, color: GlassTokens.textMuted),
                    ),
                    Text(
                      '${angle.round()}°',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: GlassTokens.primary,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: angle,
                  min: kSensorAngleMin.toDouble(),
                  max: kSensorAngleMax.toDouble(),
                  divisions: (kSensorAngleMax - kSensorAngleMin) ~/ 5,
                  label: '${angle.round()}°',
                  onChanged: (v) => setDialogState(() => angle = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('closed',
                        style: TextStyle(
                            fontSize: 11, color: GlassTokens.textMuted)),
                    Text('open',
                        style: TextStyle(
                            fontSize: 11, color: GlassTokens.textMuted)),
                  ],
                ),

                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: TextStyle(
                      color: Color.lerp(GlassTokens.danger, Colors.black, 0.25),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              GlassButton(
                label: isEditing ? 'Update' : 'Add',
                fullWidth: false,
                height: 44,
                onPressed: () {
                  final int? from = int.tryParse(fromController.text.trim());
                  final int? to = int.tryParse(toController.text.trim());

                  if (from == null || to == null) {
                    setDialogState(() =>
                        errorText = 'Enter both ends of the range as numbers');
                    return;
                  }
                  if (from < 0 || to < 0) {
                    setDialogState(
                        () => errorText = 'Range cannot be negative');
                    return;
                  }
                  if (from > to) {
                    setDialogState(() =>
                        errorText = '"From" must be less than or equal to "To"');
                    return;
                  }

                  final candidate =
                      SensorRule(from: from, to: to, angle: angle.round());

                  // Two rules covering the same reading would leave the angle
                  // undefined, so reject the overlap instead of guessing.
                  final clash = existingRules.any((r) =>
                      !identical(r, existing) && r.overlaps(candidate));
                  if (clash) {
                    setDialogState(() => errorText =
                        'This range overlaps a rule you already have');
                    return;
                  }

                  Navigator.pop(dialogContext, candidate);
                },
              ),
            ],
          );
        },
      );
    },
  );
}


// =============================================================================
// ADD-SENSOR FLOW  (two steps)
// =============================================================================
//   1. "Available Sensor Units"  → every unit on the account
//   2. "<unit name>"             → the sensors inside the one they picked
//
// Backing out of step 2 returns to step 1 rather than cancelling the whole
// flow — picking the wrong unit is the easiest mistake to make here.
// =============================================================================

/// Runs both steps and returns the chosen sensor as a SensorReading ready for
/// the card, or null if the user backed all the way out.
Future<SensorReading?> showAddSensorFlow(
  BuildContext context, {
  required List<SensorUnitOption> units,
}) async {
  while (true) {
    final SensorUnitOption? unit = await showSensorUnitPickerDialog(
      context,
      units: units,
    );
    if (unit == null || !context.mounted) return null;

    final SensorOption? sensor = await showUnitSensorPickerDialog(
      context,
      unit: unit,
    );
    if (!context.mounted) return null;
    if (sensor == null) continue; // Back → unit list

    return SensorReading(
      unitId: unit.id,
      unitName: unit.name,
      sensorId: sensor.id,
      sensorName: sensor.name,
      sensorType: sensor.type,
      value: sensor.value,
      // Online state belongs to the UNIT, so the card's dot keeps working
      // until the next device_schedule push replaces this whole object.
      lastSeen: unit.lastSeen,
      status: '',
    );
  }
}

/// STEP 1 — "Available Sensor Units".
Future<SensorUnitOption?> showSensorUnitPickerDialog(
  BuildContext context, {
  required List<SensorUnitOption> units,
}) {
  return showGlassDialog<SensorUnitOption>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: 'Available Sensor Units',
      icon: Icons.developer_board,
      tint: GlassTokens.info,
      content: units.isEmpty
          ? const Text(
              'No sensor units found on this account.',
              style: TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
            )
          : SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                // Cap the height so ten units scroll instead of overflowing.
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: units.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _unitTile(dialogContext, units[i]),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

Widget _unitTile(BuildContext dialogContext, SensorUnitOption unit) {
  final bool online = isDeviceOnline(unit.lastSeen);
  final Color tint = online ? GlassTokens.success : GlassTokens.danger;

  return InkWell(
    onTap: () => Navigator.pop(dialogContext, unit),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.id,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: GlassTokens.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  unit.name.isEmpty ? 'Unnamed unit' : unit.name,
                  style: TextStyle(fontSize: 12, color: GlassTokens.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            online ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: tint,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: GlassTokens.textMuted),
        ],
      ),
    ),
  );
}

/// STEP 2 — the sensors inside one unit. Title is the unit's name, subtitle
/// its id, as specified.
Future<SensorOption?> showUnitSensorPickerDialog(
  BuildContext context, {
  required SensorUnitOption unit,
}) {
  return showGlassDialog<SensorOption>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: unit.name.isEmpty ? unit.id : unit.name,
      icon: Icons.sensors,
      tint: GlassTokens.info,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            unit.id,
            style: TextStyle(fontSize: 12, color: GlassTokens.textMuted),
          ),
          const SizedBox(height: 14),
          if (unit.sensors.isEmpty)
            const Text(
              'This unit has not reported any sensors.',
              style: TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
            )
          else
            SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: unit.sensors.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _sensorTile(dialogContext, unit.sensors[i]),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Back'),
        ),
      ],
    ),
  );
}

Widget _sensorTile(BuildContext dialogContext, SensorOption sensor) {
  return InkWell(
    onTap: () => Navigator.pop(dialogContext, sensor),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sensor.name.isEmpty ? sensor.id : sensor.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GlassTokens.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${sensor.id}  ·  ${sensor.type}',
                  style: TextStyle(fontSize: 12, color: GlassTokens.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: GlassTokens.textMuted),
        ],
      ),
    ),
  );
}

/// Confirms unbinding the sensor. Returns true only on an explicit Remove —
/// a barrier tap or Cancel both come back null/false.
///
/// [ruleCount] is named in the message because removing the sensor takes the
/// rule table with it, and that is not obvious from a button labelled Remove.
Future<bool?> showRemoveSensorDialog(
  BuildContext context, {
  int ruleCount = 0,
}) {
  return showGlassDialog<bool>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: 'Remove sensor?',
      icon: Icons.link_off,
      tint: GlassTokens.danger,
      content: Text(
        ruleCount == 0
            ? 'This valve will stop following a sensor.'
            : 'This valve will stop following a sensor, and its $ruleCount '
                'sensor ${ruleCount == 1 ? 'rule' : 'rules'} will be deleted.',
        style: const TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        GlassButton(
          label: 'Remove',
          color: GlassTokens.danger,
          fullWidth: false,
          height: 44,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );
}