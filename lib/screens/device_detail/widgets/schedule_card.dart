import 'package:flutter/material.dart';

import '../../../models/valve_device.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// SCHEDULE CARD  (UI v2)
// =============================================================================
// The valve's schedule as a week strip and slot cards:
//
//   All · Mo … Su   pick a day; a gold dot marks days that have slots.
//                   "Every day" slots appear on every day, tagged.
//   slot cards      "06:00:00 – 06:30:00", a bar for how far the valve
//                   opens, the angle, and a delete button. Tap to edit.
//   + Add slot      opens the add sheet.
//
// The valve stores hours and minutes; times are shown with ":00" seconds so
// they line up with the add/edit sheet.
//
// SAVING IS SEPARATE: this card never saves. Edits change the list in the
// parent only; [ScheduleSaveBar] (below) sends the whole list, and the parent
// pins it to the bottom of the screen. All dialogs and the REST call live in
// the parent and arrive as callbacks — same split as before. The selected day
// is the only state here, and it is view-only.
// =============================================================================

class ScheduleCard extends StatefulWidget {
  final List<ScheduleEntry> schedules;
  final bool isSavingSchedule;
  final bool readOnly;
  final VoidCallback onAddPressed;
  final ValueChanged<int> onRowTapped; // Tap a row to edit it
  final ValueChanged<int> onRowDeleted;
  final VoidCallback onSavePressed;

  const ScheduleCard({
    super.key,
    required this.schedules,
    required this.isSavingSchedule,
    this.readOnly = false,
    required this.onAddPressed,
    required this.onRowTapped,
    required this.onRowDeleted,
    required this.onSavePressed,
  });

  @override
  State<ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<ScheduleCard> {
  static const String _everyDay = 'Every day';
  static const List<(String, String)> _days = [
    ('Monday', 'Mo'),
    ('Tuesday', 'Tu'),
    ('Wednesday', 'We'),
    ('Thursday', 'Th'),
    ('Friday', 'Fr'),
    ('Saturday', 'Sa'),
    ('Sunday', 'Su'),
  ];

  /// null = All days.
  String? _day;

  bool _onDay(ScheduleEntry e, String day) =>
      e.day == day || e.day == _everyDay;

  @override
  Widget build(BuildContext context) {
    final schedules = widget.schedules;

    // Keep the original index: edit / delete callbacks use it.
    final visible = <(int, ScheduleEntry)>[
      for (int i = 0; i < schedules.length; i++)
        if (_day == null || _onDay(schedules[i], _day!)) (i, schedules[i]),
    ]..sort((a, b) => a.$2.start.compareTo(b.$2.start));

    final String title = _day ?? 'All days';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Week strip ──
        Row(
          children: [
            _DayChip(
              label: 'All',
              hasSlots: schedules.isNotEmpty,
              selected: _day == null,
              onTap: () => setState(() => _day = null),
            ),
            for (final (full, short) in _days) ...[
              const SizedBox(width: 4),
              _DayChip(
                label: short,
                hasSlots: schedules.any((e) => _onDay(e, full)),
                selected: _day == full,
                onTap: () => setState(() => _day = full),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),

        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: GlassTokens.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textPrimary,
                ),
              ),
            ),
            Text(
              '${visible.length} ${visible.length == 1 ? 'slot' : 'slots'}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GlassTokens.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (visible.isEmpty)
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            child: Text(
              _day == null
                  ? 'No watering times yet.'
                  : 'No watering on $title.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlassTokens.textMuted),
            ),
          ),

        for (final (index, entry) in visible)
          _SlotCard(
            entry: entry,
            showEveryDayTag: entry.day == _everyDay,
            showDay: _day == null && entry.day != _everyDay,
            readOnly: widget.readOnly,
            onTap: () => widget.onRowTapped(index),
            onDelete: () => widget.onRowDeleted(index),
          ),

        if (!widget.readOnly) ...[
          const SizedBox(height: 2),
          _AddSlotButton(onPressed: widget.onAddPressed),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Save bar — pinned to the bottom of the screen by the parent.
// -----------------------------------------------------------------------------

class ScheduleSaveBar extends StatelessWidget {
  final bool hasUnsavedChanges;
  final bool isSaving;
  final VoidCallback onSavePressed;

  /// Button label. The sensor rules tab reuses this bar.
  final String saveLabel;

  /// Shown when nothing is waiting to be saved. The plug screen reuses this
  /// bar.
  final String savedText;

  const ScheduleSaveBar({
    super.key,
    required this.hasUnsavedChanges,
    required this.isSaving,
    required this.onSavePressed,
    this.saveLabel = 'Save schedule',
    this.savedText = 'Saved on the valve',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 10, 14, 10 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: GlassTokens.surface,
        border: const Border(top: BorderSide(color: GlassTokens.border)),
        boxShadow: GlassTokens.paneShadow(y: -2, blurRadius: 6),
      ),
      child: Row(
        children: [
          Expanded(
            child: hasUnsavedChanges
                ? Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: 1,
                    // Shrinks rather than overflow beside a long button label
                    // on a narrow phone.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: StatusTag(
                        label: 'Unsaved changes',
                        color: GlassTokens.sun,
                        icon: Icons.edit_outlined,
                        background: GlassTokens.sunSoft,
                      ),
                    ),
                  )
                : Text(
                    savedText,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: GlassTokens.textMuted,
                    ),
                  ),
          ),
          GlassButton(
            label: isSaving ? 'Saving…' : saveLabel,
            icon: Icons.save_outlined,
            fullWidth: false,
            height: 48,
            isLoading: isSaving,
            onPressed: isSaving ? null : onSavePressed,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pieces
// -----------------------------------------------------------------------------

class _DayChip extends StatelessWidget {
  final String label;
  final bool hasSlots;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.label,
    required this.hasSlots,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? GlassTokens.ground : GlassTokens.textSecondary;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? GlassTokens.textPrimary : GlassTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected ? GlassTokens.textPrimary : GlassTokens.border,
              width: 1.5,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasSlots ? GlassTokens.sun : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  final ScheduleEntry entry;
  final bool showEveryDayTag;
  final bool showDay;
  final bool readOnly;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SlotCard({
    required this.entry,
    required this.showEveryDayTag,
    required this.showDay,
    required this.readOnly,
    required this.onTap,
    required this.onDelete,
  });

  /// "08:00" → "08:00:00". Leaves anything else as it came.
  static String _hms(String t) => RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t)
      ? '${t.padLeft(5, '0')}:00'
      : t;

  @override
  Widget build(BuildContext context) {
    final int a = entry.angle.clamp(0, 90);
    final String what = a == 90
        ? 'Fully open'
        : a == 0
            ? 'Closed'
            : '$a° open';

    return GlassSurface(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
      onTap: readOnly ? null : onTap,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_hms(entry.start)} – ${_hms(entry.end)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: GlassTokens.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    showDay ? '${entry.day} · $what' : what,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: GlassTokens.textMuted,
                    ),
                  ),
                  if (showEveryDayTag) ...[
                    const SizedBox(width: 6),
                    const StatusTag(
                      label: 'Every day',
                      color: GlassTokens.sun,
                      background: GlassTokens.sunSoft,
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: LinearProgressIndicator(
                value: a / 90,
                minHeight: 7,
                backgroundColor: GlassTokens.sunk,
                color: GlassTokens.water,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$a°',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: GlassTokens.water,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (!readOnly)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: GlassTokens.textMuted),
              onPressed: onDelete,
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _AddSlotButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddSlotButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
      child: Container(
        height: GlassTokens.touchTarget,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          border: Border.all(color: GlassTokens.border, width: 1.5),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: GlassTokens.primary, size: 20),
            SizedBox(width: 6),
            Text(
              'Add slot',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: GlassTokens.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
