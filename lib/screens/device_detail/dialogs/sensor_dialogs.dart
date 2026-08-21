import 'package:flutter/material.dart';

import '../../../models/valve_device.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../utils/sensor_utils.dart';

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