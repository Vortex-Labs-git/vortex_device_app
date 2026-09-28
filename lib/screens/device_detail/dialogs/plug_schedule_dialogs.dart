import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../utils/plug_utils.dart';
import '../utils/schedule_utils.dart' show kScheduleDayOptions;

// =============================================================================
// PLUG SCHEDULE DIALOGS
// =============================================================================
// The plug's version of schedule_dialogs.dart:
//
//   showPlugScheduleEntryDialog   add / edit one row: day, From–To (with
//                                 SECONDS), and the ADVANCED step cycle
//   showDeletePlugScheduleDialog  confirm a delete
//   showPlugTimePicker            HH : mm : ss wheel picker (Flutter's
//                                 showTimePicker has no seconds)
//
// No ON/OFF choice: the base is OFF outside every range and ON inside it.
//
// STEP ("advanced"): "<on seconds>:<off seconds>", cycled inside the range.
//   Off  → continuous, step = <range length>:0   (the default, e.g. "1200:0")
//   On   → the user picks ON and OFF seconds, e.g. 5:5
//
// The dialogs are StatefulWidgets so they own (and dispose) their
// controllers — same reason as edit_device_name_dialog.dart.
// =============================================================================

/// Shows the add/edit dialog for one schedule row of [baseName].
/// Pass [initial] to edit. Returns the entry, or null if cancelled.
Future<PlugScheduleEntry?> showPlugScheduleEntryDialog(
  BuildContext context, {
  required String baseName,
  PlugScheduleEntry? initial,
}) {
  return showGlassDialog<PlugScheduleEntry>(
    context: context,
    builder: (_) => _PlugScheduleEntryDialog(
      baseName: baseName,
      initial: initial,
    ),
  );
}

/// Asks the user to confirm deleting [entry]. Returns true when confirmed.
Future<bool> showDeletePlugScheduleDialog(
  BuildContext context,
  PlugScheduleEntry entry,
) async {
  final confirmed = await showGlassDialog<bool>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: 'Delete Schedule',
      icon: Icons.delete_outline,
      tint: GlassTokens.danger,
      content: Text(
        'Delete "${entry.day} — ${entry.timeRange}, '
        '${describePlugStep(entry)}"?',
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

/// HH : mm : ss picker. [initialSeconds] is seconds since midnight; returns
/// the picked seconds since midnight, or null if cancelled.
Future<int?> showPlugTimePicker(
  BuildContext context, {
  required String title,
  required int initialSeconds,
}) {
  return showGlassDialog<int>(
    context: context,
    builder: (_) => _PlugTimePickerDialog(
      title: title,
      initialSeconds: initialSeconds,
    ),
  );
}

// -----------------------------------------------------------------------------
// Add / edit dialog
// -----------------------------------------------------------------------------

/// Starting values for the cycle fields when the user first turns it on.
const int _kDefaultCycleSeconds = 5;

class _PlugScheduleEntryDialog extends StatefulWidget {
  final String baseName;
  final PlugScheduleEntry? initial;

  const _PlugScheduleEntryDialog({required this.baseName, this.initial});

  @override
  State<_PlugScheduleEntryDialog> createState() =>
      _PlugScheduleEntryDialogState();
}

class _PlugScheduleEntryDialogState extends State<_PlugScheduleEntryDialog> {
  late String _day;
  late int _start; // seconds since midnight
  late int _end;
  late bool _cycle;
  late final TextEditingController _onCtrl;
  late final TextEditingController _offCtrl;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;

    _day = e?.day ?? kScheduleDayOptions.first;
    if (!kScheduleDayOptions.contains(_day)) _day = kScheduleDayOptions.first;

    _start = (e != null ? PlugScheduleEntry.secondsOfDay(e.start) : null) ??
        8 * 3600; // 08:00:00
    _end = (e != null ? PlugScheduleEntry.secondsOfDay(e.end) : null) ??
        8 * 3600 + 20 * 60; // 08:20:00

    _cycle = e != null && !e.isContinuous;
    _onCtrl = TextEditingController(
      text: '${_cycle ? e!.onSeconds : _kDefaultCycleSeconds}',
    );
    _offCtrl = TextEditingController(
      text: '${_cycle ? e!.offSeconds : _kDefaultCycleSeconds}',
    );
  }

  @override
  void dispose() {
    _onCtrl.dispose();
    _offCtrl.dispose();
    super.dispose();
  }

  String get _startText => PlugScheduleEntry.formatSecondsOfDay(_start);
  String get _endText => PlugScheduleEntry.formatSecondsOfDay(_end);

  int get _rangeSeconds =>
      PlugScheduleEntry.durationSecondsOf(_startText, _endText);

  int? get _onSeconds => int.tryParse(_onCtrl.text.trim());
  int? get _offSeconds => int.tryParse(_offCtrl.text.trim());

  void _error(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _submit() {
    if (_start == _end) {
      _error('Start and end time cannot be the same');
      return;
    }

    // Default: ON for the whole range, step = <range>:0.
    if (!_cycle) {
      Navigator.pop(
        context,
        PlugScheduleEntry.continuous(
          day: _day,
          start: _startText,
          end: _endText,
        ),
      );
      return;
    }

    // Advanced: ON / OFF cycle.
    final on = _onSeconds;
    final off = _offSeconds;
    if (on == null || on <= 0 || off == null || off <= 0) {
      _error('ON and OFF time must both be at least 1 second');
      return;
    }
    if (on + off > _rangeSeconds) {
      _error('One ON + OFF cycle (${formatPlugSeconds(on + off)}) is longer '
          'than the time range (${formatPlugSeconds(_rangeSeconds)})');
      return;
    }

    Navigator.pop(
      context,
      PlugScheduleEntry(
        day: _day,
        start: _startText,
        end: _endText,
        onSeconds: on,
        offSeconds: off,
      ),
    );
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showPlugTimePicker(
      context,
      title: isStart ? 'From' : 'To',
      initialSeconds: isStart ? _start : _end,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: _isEditing ? 'Edit Schedule' : 'Add Schedule',
      icon: Icons.schedule,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.baseName} turns ON during this time',
              style: const TextStyle(
                fontSize: 12,
                color: GlassTokens.textMuted,
              ),
            ),
            const SizedBox(height: 12),

            // ─── Day ────────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _day,
              decoration:
                  glassInputDecoration(labelText: 'Day').copyWith(isDense: true),
              items: kScheduleDayOptions
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _day = v);
              },
            ),

            const SizedBox(height: 16),

            // ─── Time range (HH:mm:ss) ──────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _timeField(
                    label: 'From',
                    text: _startText,
                    iconColor: GlassTokens.success,
                    onTap: () => _pickTime(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _timeField(
                    label: 'To',
                    text: _endText,
                    iconColor: GlassTokens.danger,
                    onTap: () => _pickTime(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'ON for ${formatPlugSeconds(_rangeSeconds)}'
              '${_end <= _start && _start != _end ? ' (ends next day)' : ''}',
              style: const TextStyle(fontSize: 12, color: GlassTokens.textMuted),
            ),

            // ─── Advanced: step cycle ───────────────────────────────────
            const SizedBox(height: 12),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Advanced: cycle ON / OFF',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                _cycle
                    ? 'Repeats ON then OFF until the range ends'
                    : 'Off: stays ON for the whole range',
                style: const TextStyle(
                  fontSize: 11,
                  color: GlassTokens.textMuted,
                ),
              ),
              value: _cycle,
              activeColor: GlassTokens.primary,
              onChanged: (v) => setState(() => _cycle = v),
            ),
            if (_cycle) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: _secondsField('ON (seconds)', _onCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: _secondsField('OFF (seconds)', _offCtrl)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _cyclePreview(),
                style: const TextStyle(
                  fontSize: 12,
                  color: GlassTokens.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        GlassButton(
          label: _isEditing ? 'Update' : 'Add',
          fullWidth: false,
          height: 44,
          onPressed: _submit,
        ),
      ],
    );
  }

  /// "5 s ON / 5 s OFF → about 3 cycles" under the step fields.
  String _cyclePreview() {
    final on = _onSeconds ?? 0;
    final off = _offSeconds ?? 0;
    if (on <= 0 || off <= 0) return 'Enter ON and OFF time in seconds';
    final cycles = _rangeSeconds ~/ (on + off);
    return '${formatPlugSeconds(on)} ON / ${formatPlugSeconds(off)} OFF'
        ' → about $cycles cycle${cycles == 1 ? '' : 's'}';
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helpers
  // ───────────────────────────────────────────────────────────────────────

  Widget _timeField({
    required String label,
    required String text,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: glassInputDecoration(labelText: label).copyWith(
          isDense: true,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Icon(Icons.access_time, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _secondsField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: glassInputDecoration(labelText: label).copyWith(
        isDense: true,
      ),
      onChanged: (_) => setState(() {}), // refresh the preview line
    );
  }
}

// -----------------------------------------------------------------------------
// HH : mm : ss picker
// -----------------------------------------------------------------------------

class _PlugTimePickerDialog extends StatefulWidget {
  final String title;
  final int initialSeconds;

  const _PlugTimePickerDialog({
    required this.title,
    required this.initialSeconds,
  });

  @override
  State<_PlugTimePickerDialog> createState() => _PlugTimePickerDialogState();
}

class _PlugTimePickerDialogState extends State<_PlugTimePickerDialog> {
  late int _h;
  late int _m;
  late int _s;
  late final FixedExtentScrollController _hCtrl;
  late final FixedExtentScrollController _mCtrl;
  late final FixedExtentScrollController _sCtrl;

  @override
  void initState() {
    super.initState();
    final t = widget.initialSeconds % (24 * 3600);
    _h = t ~/ 3600;
    _m = (t % 3600) ~/ 60;
    _s = t % 60;
    _hCtrl = FixedExtentScrollController(initialItem: _h);
    _mCtrl = FixedExtentScrollController(initialItem: _m);
    _sCtrl = FixedExtentScrollController(initialItem: _s);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    _sCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: widget.title,
      icon: Icons.access_time,
      content: SizedBox(
        height: 180,
        child: Row(
          children: [
            Expanded(child: _wheel(_hCtrl, 24, (v) => _h = v)),
            _colon(),
            Expanded(child: _wheel(_mCtrl, 60, (v) => _m = v)),
            _colon(),
            Expanded(child: _wheel(_sCtrl, 60, (v) => _s = v)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        GlassButton(
          label: 'OK',
          fullWidth: false,
          height: 44,
          onPressed: () => Navigator.pop(context, _h * 3600 + _m * 60 + _s),
        ),
      ],
    );
  }

  Widget _colon() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          ':',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      );

  Widget _wheel(
    FixedExtentScrollController controller,
    int count,
    ValueChanged<int> onChanged,
  ) {
    return CupertinoPicker(
      scrollController: controller,
      itemExtent: 40,
      looping: true,
      selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
        background: GlassTokens.primary.withValues(alpha: 0.08),
      ),
      onSelectedItemChanged: onChanged,
      children: List.generate(
        count,
        (i) => Center(
          child: Text(
            i.toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: 22,
              color: GlassTokens.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
