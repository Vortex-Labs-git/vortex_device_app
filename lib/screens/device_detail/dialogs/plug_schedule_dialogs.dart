import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../utils/plug_utils.dart';
import '../utils/schedule_utils.dart' show kScheduleDayOptions;
import 'schedule_dialogs.dart'
    show HmsWheels, SheetChip, SheetLabel, SheetTimeBox;

// =============================================================================
// PLUG SCHEDULE DIALOGS  (UI v2)
// =============================================================================
// The plug's version of schedule_dialogs.dart:
//
//   showPlugScheduleEntryDialog   add / edit one time, as a bottom sheet:
//                                 day chips (one day, as before), From / To
//                                 with hours : minutes : SECONDS wheels, and
//                                 an "Advanced" fold for the ON / OFF cycle
//   showDeletePlugScheduleDialog  confirm a delete (unchanged)
//
// Same look as the valve's add-slot sheet (shared SheetLabel / SheetChip /
// SheetTimeBox / HmsWheels). Unlike the valve, the plug KEEPS the seconds.
//
// No ON/OFF choice: the socket is OFF outside every range and ON inside it.
//
// STEP ("advanced"): "<on seconds>:<off seconds>", cycled inside the range.
//   Off  → continuous, step = <range length>:0   (the default, e.g. "1200:0")
//   On   → the user picks ON and OFF seconds, e.g. 5:5
// Checks are unchanged; the message now shows inside the sheet.
// =============================================================================

/// Shows the add/edit sheet for one schedule row of [baseName].
/// Pass [initial] to edit. Returns the entry, or null if cancelled.
Future<PlugScheduleEntry?> showPlugScheduleEntryDialog(
  BuildContext context, {
  required String baseName,
  PlugScheduleEntry? initial,
}) {
  return showModalBottomSheet<PlugScheduleEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GlassTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _PlugScheduleSheet(baseName: baseName, initial: initial),
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

// -----------------------------------------------------------------------------
// Add / edit sheet
// -----------------------------------------------------------------------------

/// Starting values for the cycle fields when the user first turns it on.
const int _kDefaultCycleSeconds = 5;

class _PlugScheduleSheet extends StatefulWidget {
  final String baseName;
  final PlugScheduleEntry? initial;

  const _PlugScheduleSheet({required this.baseName, this.initial});

  @override
  State<_PlugScheduleSheet> createState() => _PlugScheduleSheetState();
}

class _PlugScheduleSheetState extends State<_PlugScheduleSheet> {
  late String _day;
  late int _start; // seconds since midnight
  late int _end;
  late bool _cycle;
  late final TextEditingController _onCtrl;
  late final TextEditingController _offCtrl;

  /// Which time box the wheels are editing.
  bool _editingFrom = true;

  /// Remounts the wheels when the target box changes, so they jump to it.
  int _wheelKey = 0;

  String? _error;

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

  /// Day chip labels: "Every day" stays long, weekdays are shortened.
  static String _short(String day) =>
      day == kScheduleDayOptions.first ? day : day.substring(0, 3);

  void _setPart({int? h, int? m, int? s}) {
    final int cur = _editingFrom ? _start : _end;
    final int next = (h ?? cur ~/ 3600) * 3600 +
        (m ?? (cur % 3600) ~/ 60) * 60 +
        (s ?? cur % 60);
    setState(() {
      _error = null;
      if (_editingFrom) {
        _start = next;
      } else {
        _end = next;
      }
    });
  }

  void _submit() {
    if (_start == _end) {
      setState(() => _error = 'Start and end time cannot be the same');
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
      setState(
          () => _error = 'ON and OFF time must both be at least 1 second');
      return;
    }
    if (on + off > _rangeSeconds) {
      setState(() => _error =
          'One ON + OFF cycle (${formatPlugSeconds(on + off)}) is longer '
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

  @override
  Widget build(BuildContext context) {
    final bool nextDay = _end <= _start && _start != _end;

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
              '${_isEditing ? 'Edit time' : 'Add time'} · ${widget.baseName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: GlassTokens.displayFont,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: GlassTokens.textPrimary,
              ),
            ),
            Text(
              '${widget.baseName} turns ON during this time',
              style: const TextStyle(
                fontSize: 12.5,
                color: GlassTokens.textMuted,
              ),
            ),
            const SizedBox(height: 14),

            // ── Day (one per time, as before) ──
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

            // ── Time (with seconds) ──
            const SheetLabel('Time'),
            Row(
              children: [
                Expanded(
                  child: SheetTimeBox(
                    label: 'From',
                    value: _startText,
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
                    value: _endText,
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
              seconds: _editingFrom ? _start : _end,
              onHour: (v) => _setPart(h: v),
              onMinute: (v) => _setPart(m: v),
              onSecond: (v) => _setPart(s: v),
            ),
            const SizedBox(height: 6),
            Text(
              'ON for ${formatPlugSeconds(_rangeSeconds)}'
              '${nextDay ? ' (ends next day)' : ''}',
              style: const TextStyle(fontSize: 12, color: GlassTokens.textMuted),
            ),
            const SizedBox(height: 12),

            // ── Advanced: ON / OFF cycle ──
            _cycleFold(),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 12.5,
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
                    label: _isEditing ? 'Update time' : 'Add time',
                    icon: Icons.check_rounded,
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

  /// "Advanced · cycle ON / OFF" — open means the cycle is used; closed means
  /// ON for the whole range (same meaning as the old switch).
  Widget _cycleFold() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: GlassTokens.border),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              _cycle = !_cycle;
              _error = null;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  const Icon(Icons.repeat_rounded,
                      size: 18, color: GlassTokens.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Advanced · cycle ON / OFF',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: GlassTokens.textPrimary,
                          ),
                        ),
                        Text(
                          _cycle
                              ? 'Repeats ON then OFF until the range ends'
                              : 'Off: stays ON for the whole range',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: GlassTokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _cycle,
                    activeTrackColor: GlassTokens.primary,
                    onChanged: (v) => setState(() {
                      _cycle = v;
                      _error = null;
                    }),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: !_cycle
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: _secondsField('ON (seconds)', _onCtrl)),
                            const SizedBox(width: 10),
                            Expanded(
                                child:
                                    _secondsField('OFF (seconds)', _offCtrl)),
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
                    ),
                  ),
          ),
        ],
      ),
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

  Widget _secondsField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: glassInputDecoration(labelText: label).copyWith(
        isDense: true,
      ),
      onChanged: (_) => setState(() => _error = null), // refresh the preview
    );
  }
}
