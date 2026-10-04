import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../models/valve_device.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../utils/sensor_utils.dart';
import '../utils/valve_utils.dart';
import '../widgets/valve_angle_picker.dart';

// UI v2: the rule editor and both sensor pickers are bottom sheets (same
// pattern as the add-slot sheet). Validation, the two-step flow and the
// remove confirmation are unchanged.

/// Opens a rounded bottom sheet with the drag handle, the shared shell for
/// every sheet in this file.
Future<T?> _showSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GlassTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        18 +
            MediaQuery.viewInsetsOf(sheetContext).bottom +
            MediaQuery.paddingOf(sheetContext).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: GlassTokens.border,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Flexible(child: builder(sheetContext)),
        ],
      ),
    ),
  );
}

/// Sheet title (+ optional line under it), with an optional back button.
Widget _sheetTitle(String title, {String? subtitle, VoidCallback? onBack}) {
  return Row(
    children: [
      if (onBack != null) ...[
        Material(
          color: GlassTokens.sunk,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(12),
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.chevron_left_rounded,
                  color: GlassTokens.textPrimary),
            ),
          ),
        ),
        const SizedBox(width: 10),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: GlassTokens.displayFont,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: GlassTokens.textPrimary,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: GlassTokens.textMuted,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

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
  return _showSheet<SensorRule>(
    context,
    (_) => _SensorRuleSheet(initial: initial, existingRules: existingRules),
  );
}

class _SensorRuleSheet extends StatefulWidget {
  final SensorRule? initial;
  final List<SensorRule> existingRules;

  const _SensorRuleSheet({this.initial, required this.existingRules});

  @override
  State<_SensorRuleSheet> createState() => _SensorRuleSheetState();
}

class _SensorRuleSheetState extends State<_SensorRuleSheet> {
  late final TextEditingController _from;
  late final TextEditingController _to;
  late double _angle;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _from = TextEditingController(text: (e?.from ?? 0).toString());
    _to = TextEditingController(text: (e?.to ?? 30).toString());
    _angle = (e?.angle ?? 0).toDouble();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _submit() {
    final int? from = int.tryParse(_from.text.trim());
    final int? to = int.tryParse(_to.text.trim());
    if (from == null || to == null) {
      setState(() => _error = 'Enter both ends of the range as numbers');
      return;
    }
    if (from < 0 || to < 0) {
      setState(() => _error = 'Range cannot be negative');
      return;
    }
    if (from > to) {
      setState(() => _error = '"From" must be less than or equal to "To"');
      return;
    }
    final candidate = SensorRule(from: from, to: to, angle: _angle.round());
    // Two rules covering the same reading would leave the angle undefined, so
    // reject the overlap instead of guessing.
    final clash = widget.existingRules
        .any((r) => !identical(r, widget.initial) && r.overlaps(candidate));
    if (clash) {
      setState(() => _error = 'This range overlaps a rule you already have');
      return;
    }
    Navigator.pop(context, candidate);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: GlassTokens.textMuted,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initial != null;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetTitle(isEditing ? 'Edit rule' : 'Add rule'),
          const SizedBox(height: 14),
          _label('When the reading is'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _from,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: glassInputDecoration(labelText: 'From'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('–',
                    style: TextStyle(
                        fontSize: 18, color: GlassTokens.textMuted)),
              ),
              Expanded(
                child: TextField(
                  controller: _to,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: glassInputDecoration(labelText: 'To'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _label('Set the valve to'),
          ValveAnglePicker(
            angle: _angle,
            min: kSensorAngleMin,
            max: kSensorAngleMax,
            onChanged: (v) => setState(() => _angle = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: GlassTokens.danger,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GlassButton(
                  label: isEditing ? 'Update rule' : 'Add rule',
                  height: 48,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Add / edit one PLUG sensor rule: the same sheet as [showSensorRuleDialog],
/// but the action is Turn ON / Turn OFF for the socket instead of an angle.
/// Same checks: numbers, not negative, From ≤ To, no overlap with
/// [existingRules] (which includes [initial] when editing).
Future<PlugSensorRule?> showPlugSensorRuleDialog(
  BuildContext context, {
  required String baseName,
  PlugSensorRule? initial,
  List<PlugSensorRule> existingRules = const [],
}) {
  return _showSheet<PlugSensorRule>(
    context,
    (_) => _PlugSensorRuleSheet(
      baseName: baseName,
      initial: initial,
      existingRules: existingRules,
    ),
  );
}

class _PlugSensorRuleSheet extends StatefulWidget {
  final String baseName;
  final PlugSensorRule? initial;
  final List<PlugSensorRule> existingRules;

  const _PlugSensorRuleSheet({
    required this.baseName,
    this.initial,
    required this.existingRules,
  });

  @override
  State<_PlugSensorRuleSheet> createState() => _PlugSensorRuleSheetState();
}

class _PlugSensorRuleSheetState extends State<_PlugSensorRuleSheet> {
  late final TextEditingController _from;
  late final TextEditingController _to;
  late bool _on;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _from = TextEditingController(text: (e?.from ?? 0).toString());
    _to = TextEditingController(text: (e?.to ?? 30).toString());
    _on = e?.state ?? true;
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _submit() {
    final int? from = int.tryParse(_from.text.trim());
    final int? to = int.tryParse(_to.text.trim());
    if (from == null || to == null) {
      setState(() => _error = 'Enter both ends of the range as numbers');
      return;
    }
    if (from < 0 || to < 0) {
      setState(() => _error = 'Range cannot be negative');
      return;
    }
    if (from > to) {
      setState(() => _error = '"From" must be less than or equal to "To"');
      return;
    }
    final candidate = PlugSensorRule(from: from, to: to, state: _on);
    final clash = widget.existingRules
        .any((r) => !identical(r, widget.initial) && r.overlaps(candidate));
    if (clash) {
      setState(() => _error = 'This range overlaps a rule you already have');
      return;
    }
    Navigator.pop(context, candidate);
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: GlassTokens.textMuted,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initial != null;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetTitle(
            '${isEditing ? 'Edit rule' : 'Add rule'} · ${widget.baseName}',
          ),
          const SizedBox(height: 14),
          _label('When the reading is'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _from,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: glassInputDecoration(labelText: 'From'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('–',
                    style: TextStyle(
                        fontSize: 18, color: GlassTokens.textMuted)),
              ),
              Expanded(
                child: TextField(
                  controller: _to,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: glassInputDecoration(labelText: 'To'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _label('Then ${widget.baseName} should'),
          SegmentedPicker<bool>(
            selected: _on,
            onChanged: (v) => setState(() => _on = v),
            options: const [
              SegmentOption(
                value: true,
                label: 'Turn ON',
                icon: Icons.power_settings_new_rounded,
                color: GlassTokens.primary,
              ),
              SegmentOption(
                value: false,
                label: 'Turn OFF',
                icon: Icons.power_off_outlined,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: GlassTokens.danger,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: GlassButton(
                  label: isEditing ? 'Update rule' : 'Add rule',
                  height: 48,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
  return _showSheet<SensorUnitOption>(
    context,
    (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetTitle('Choose a sensor unit', subtitle: 'Step 1 of 2'),
        const SizedBox(height: 10),
        if (units.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No sensor units found on this account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: units.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: GlassTokens.border),
              itemBuilder: (_, i) => _unitTile(sheetContext, units[i]),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

Widget _unitTile(BuildContext sheetContext, SensorUnitOption unit) {
  final bool online = isDeviceOnline(unit.lastSeen);
  return InkWell(
    onTap: () => Navigator.pop(sheetContext, unit),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _iconTile(Icons.developer_board),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.name.isEmpty ? 'Unnamed unit' : unit.name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: GlassTokens.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${unit.id} · ${unit.sensors.length} '
                  '${unit.sensors.length == 1 ? 'sensor' : 'sensors'}',
                  style: const TextStyle(
                      fontSize: 12, color: GlassTokens.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          online ? StatusTag.online() : StatusTag.offline(),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: GlassTokens.textMuted),
        ],
      ),
    ),
  );
}

/// STEP 2 — the sensors inside one unit. Title is the unit's name, subtitle
/// its id. Back (or the back arrow) returns to step 1.
Future<SensorOption?> showUnitSensorPickerDialog(
  BuildContext context, {
  required SensorUnitOption unit,
}) {
  return _showSheet<SensorOption>(
    context,
    (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetTitle(
          unit.name.isEmpty ? unit.id : unit.name,
          subtitle: '${unit.id} · step 2 of 2',
          onBack: () => Navigator.pop(sheetContext),
        ),
        const SizedBox(height: 10),
        if (unit.sensors.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'This unit has not reported any sensors.',
              textAlign: TextAlign.center,
              style: TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: unit.sensors.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: GlassTokens.border),
              itemBuilder: (_, i) => _sensorTile(sheetContext, unit.sensors[i]),
            ),
          ),
      ],
    ),
  );
}

Widget _sensorTile(BuildContext sheetContext, SensorOption sensor) {
  return InkWell(
    onTap: () => Navigator.pop(sheetContext, sensor),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          _iconTile(Icons.sensors),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sensor.name.isEmpty ? sensor.id : sensor.name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: GlassTokens.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${sensor.type} · ${sensor.id}',
                  style: const TextStyle(
                      fontSize: 12, color: GlassTokens.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (sensor.value.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                sensor.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: GlassTokens.info,
                ),
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: GlassTokens.textMuted),
        ],
      ),
    ),
  );
}

Widget _iconTile(IconData icon) {
  return Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: GlassTokens.info.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
    ),
    child: Icon(icon, color: GlassTokens.info, size: 20),
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