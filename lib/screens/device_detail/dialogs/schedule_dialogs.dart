import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../../../models/valve_device.dart';
import '../utils/schedule_utils.dart';
import '../widgets/valve_angle_picker.dart';

// =============================================================================
// SCHEDULE DIALOGS  (UI v2)
// =============================================================================
// showScheduleEntryDialog   add / edit one slot, as a bottom sheet:
//                           day chips, From / To with an hours : minutes :
//                           seconds wheel, Close / Open, and an "Advanced"
//                           fold with a 0–90° slider (5° steps).
// showDeleteScheduleDialog  confirm a delete (unchanged).
//
// The sheet pieces (SheetLabel, SheetChip, SheetTimeBox, HmsWheels) are public
// so the plug's add-time sheet looks the same.
//
// SECONDS ARE SHOWN, NOT SAVED: the valve stores "HH:mm", so the returned
// entry is built with formatScheduleTime() and the seconds are dropped. No
// change to the model, the parser or the save call.
// =============================================================================

/// Shows the add/edit slot sheet.
///
/// Pass the existing entry as [initial] to edit it; omit it to add a new one.
/// Returns the entry, or null if the user cancelled.
Future<ScheduleEntry?> showScheduleEntryDialog(
  BuildContext context, {
  ScheduleEntry? initial,
}) {
  return showModalBottomSheet<ScheduleEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GlassTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ScheduleEntrySheet(initial: initial),
  );
}

class _ScheduleEntrySheet extends StatefulWidget {
  final ScheduleEntry? initial;

  const _ScheduleEntrySheet({this.initial});

  @override
  State<_ScheduleEntrySheet> createState() => _ScheduleEntrySheetState();
}

class _ScheduleEntrySheetState extends State<_ScheduleEntrySheet> {
  late String _day;

  /// Seconds since midnight for each end (seconds are display-only).
  late int _from;
  late int _to;

  /// Which time box the wheel is editing.
  bool _editingFrom = true;

  late double _angle;
  String? _error;

  /// Remounts the wheels when the target box changes, so they jump to it.
  int _wheelKey = 0;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _day = e?.day ?? kScheduleDayOptions.first;
    _from = _secondsOf(e != null
        ? parseScheduleTime(e.start)
        : const TimeOfDay(hour: 8, minute: 0));
    _to = _secondsOf(e != null
        ? parseScheduleTime(e.end)
        : const TimeOfDay(hour: 8, minute: 20));
    _angle = (e?.angle ?? 90).toDouble();
  }

  static int _secondsOf(TimeOfDay t) => t.hour * 3600 + t.minute * 60;

  static TimeOfDay _timeOf(int seconds) =>
      TimeOfDay(hour: seconds ~/ 3600, minute: (seconds % 3600) ~/ 60);

  static String _hms(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 3600)}:${two((seconds % 3600) ~/ 60)}:'
        '${two(seconds % 60)}';
  }

  /// Day chip labels: "Every day" stays long, weekdays are shortened.
  static String _short(String day) =>
      day == kScheduleDayOptions.first ? day : day.substring(0, 3);

  void _setPart({int? h, int? m, int? s}) {
    final int cur = _editingFrom ? _from : _to;
    final int next = (h ?? cur ~/ 3600) * 3600 +
        (m ?? (cur % 3600) ~/ 60) * 60 +
        (s ?? cur % 60);
    setState(() {
      _error = null;
      if (_editingFrom) {
        _from = next;
      } else {
        _to = next;
      }
    });
  }

  void _submit() {
    // Saved as HH:mm — compare what will actually be stored.
    final start = formatScheduleTime(_timeOf(_from));
    final end = formatScheduleTime(_timeOf(_to));
    if (start == end) {
      setState(() => _error = 'Start and end time cannot be the same');
      return;
    }
    Navigator.pop(
      context,
      ScheduleEntry(day: _day, start: start, end: end, angle: _angle.round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        10,
        18,
        18 +
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.paddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
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
            Text(
              isEditing ? 'Edit slot' : 'Add slot',
              style: const TextStyle(
                fontFamily: GlassTokens.displayFont,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: GlassTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 14),

            // ── Day ──
            const SheetLabel('Day'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in kScheduleDayOptions)
                  SheetChip(
                    label: _short(d),
                    selected: d == _day,
                    onTap: () => setState(() => _day = d),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Time ──
            const SheetLabel('Time'),
            Row(
              children: [
                Expanded(
                  child: SheetTimeBox(
                    label: 'From',
                    value: _hms(_from),
                    active: _editingFrom,
                    onTap: () => setState(() {
                      _editingFrom = true;
                      _wheelKey++;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SheetTimeBox(
                    label: 'To',
                    value: _hms(_to),
                    active: !_editingFrom,
                    onTap: () => setState(() {
                      _editingFrom = false;
                      _wheelKey++;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            HmsWheels(
              key: ValueKey(_wheelKey),
              seconds: _editingFrom ? _from : _to,
              onHour: (v) => _setPart(h: v),
              onMinute: (v) => _setPart(m: v),
              onSecond: (v) => _setPart(s: v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.danger,
                ),
              ),
            ],
            const SizedBox(height: 14),

            // ── Valve ──
            const SheetLabel('Valve'),
            ValveAnglePicker(
              angle: _angle,
              onChanged: (v) => setState(() => _angle = v),
            ),
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
                    label: isEditing ? 'Update slot' : 'Add slot',
                    height: 48,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sheet pieces
// -----------------------------------------------------------------------------

class SheetLabel extends StatelessWidget {
  final String text;

  const SheetLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
  }
}

class SheetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SheetChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? GlassTokens.textPrimary : GlassTokens.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? GlassTokens.textPrimary : GlassTokens.border,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? GlassTokens.ground : GlassTokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class SheetTimeBox extends StatelessWidget {
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  const SheetTimeBox({
    super.key,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlassTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
        side: BorderSide(
          color: active ? GlassTokens.primary : GlassTokens.border,
          width: active ? 2 : 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: GlassTokens.textMuted,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontFamily: GlassTokens.displayFont,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hours : minutes : seconds wheels for the selected time box. Owns its
/// scroll controllers; the parent remounts it (new key) to jump to the other
/// box.
class HmsWheels extends StatefulWidget {
  final int seconds;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;
  final ValueChanged<int> onSecond;

  const HmsWheels({
    super.key,
    required this.seconds,
    required this.onHour,
    required this.onMinute,
    required this.onSecond,
  });

  @override
  State<HmsWheels> createState() => HmsWheelsState();
}

class HmsWheelsState extends State<HmsWheels> {
  late final FixedExtentScrollController _h;
  late final FixedExtentScrollController _m;
  late final FixedExtentScrollController _s;

  @override
  void initState() {
    super.initState();
    final int t = widget.seconds;
    _h = FixedExtentScrollController(initialItem: t ~/ 3600);
    _m = FixedExtentScrollController(initialItem: (t % 3600) ~/ 60);
    _s = FixedExtentScrollController(initialItem: t % 60);
  }

  @override
  void dispose() {
    _h.dispose();
    _m.dispose();
    _s.dispose();
    super.dispose();
  }

  Widget _wheel(String label, int count, FixedExtentScrollController ctrl,
      ValueChanged<int> onPick) {
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 112,
            child: CupertinoPicker(
              scrollController: ctrl,
              itemExtent: 36,
              looping: true,
              selectionOverlay: Container(
                decoration: BoxDecoration(
                  color: GlassTokens.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onSelectedItemChanged: onPick,
              children: [
                for (int i = 0; i < count; i++)
                  Center(
                    child: Text(
                      i.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontFamily: GlassTokens.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: GlassTokens.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: GlassTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const sep = Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Text(
        ':',
        style: TextStyle(
          fontFamily: GlassTokens.displayFont,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      decoration: BoxDecoration(
        color: GlassTokens.sunk,
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
      ),
      child: Row(
        children: [
          _wheel('HOURS', 24, _h, widget.onHour),
          sep,
          _wheel('MINUTES', 60, _m, widget.onMinute),
          sep,
          _wheel('SECONDS', 60, _s, widget.onSecond),
        ],
      ),
    );
  }
}

/// Asks the user to confirm deleting [entry]. Returns true when confirmed.
Future<bool> showDeleteScheduleDialog(
  BuildContext context,
  ScheduleEntry entry,
) async {
  final confirmed = await showGlassDialog<bool>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: 'Delete Schedule',
      icon: Icons.delete_outline,
      tint: GlassTokens.danger,
      content: Text(
        'Delete "${entry.day} — ${entry.timeRange} at ${entry.angle}°"?',
        style: const TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        GlassButton(
          label: 'Delete',
          color: GlassTokens.danger,
          fullWidth: false,
          height: 44,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
