import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import 'tinted_add_button.dart';
import '../utils/plug_utils.dart';

// =============================================================================
// PLUG SCHEDULE CARD  (UI v2)
// =============================================================================
// The plug's version of ScheduleCard, for ONE socket — same week strip and
// time cards as the valve:
//
//   All · Mo … Su   pick a day; a gold dot marks days that have times.
//   time cards      "06:00:00 – 06:20:30" (plugs keep seconds), the day,
//                   and "Always ON" or the ON / OFF cycle. Tap to edit.
//   + Add time      opens the add sheet.
//
// Every card is an ON period — the socket is OFF outside all of them — so
// there is no ON/OFF column.
//
// SAVING IS SEPARATE: the parent floats a Save pill (FloatingSavePill) at the
// bottom of the screen and passes it [isSaving] / [hasUnsavedChanges] / [onSavePressed];
// this card only edits the list through the callbacks. The selected day is
// the only state here, and it is view-only.
// =============================================================================

class PlugScheduleCard extends StatefulWidget {
  final String baseName;
  final List<PlugScheduleEntry> schedules;
  final bool isSaving;

  /// Shown by the Save pill, not here; kept so the parent wiring is unchanged.
  final bool hasUnsavedChanges;
  final VoidCallback onAddPressed;
  final ValueChanged<int> onRowTapped; // tap a row to edit it
  final ValueChanged<int> onRowDeleted;

  /// Used by the Save pill the parent floats at the bottom of the screen.
  final VoidCallback onSavePressed;

  const PlugScheduleCard({
    super.key,
    required this.baseName,
    required this.schedules,
    required this.isSaving,
    required this.hasUnsavedChanges,
    required this.onAddPressed,
    required this.onRowTapped,
    required this.onRowDeleted,
    required this.onSavePressed,
  });

  @override
  State<PlugScheduleCard> createState() => _PlugScheduleCardState();
}

class _PlugScheduleCardState extends State<PlugScheduleCard> {
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

  bool _onDay(PlugScheduleEntry e, String day) =>
      e.day == day || e.day == _everyDay;

  @override
  Widget build(BuildContext context) {
    final schedules = widget.schedules;
    final bool locked = widget.isSaving;

    // Keep the original index: edit / delete callbacks use it.
    final visible = <(int, PlugScheduleEntry)>[
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
              '${visible.length} ${visible.length == 1 ? 'time' : 'times'}',
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
                  ? 'No ON times for ${widget.baseName} yet.'
                  : 'Nothing on $title.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlassTokens.textMuted),
            ),
          ),

        for (final (index, entry) in visible)
          _TimeCard(
            entry: entry,
            showDay: _day == null || entry.day == _everyDay,
            locked: locked,
            onTap: () => widget.onRowTapped(index),
            onDelete: () => widget.onRowDeleted(index),
          ),

        const SizedBox(height: 2),
        TintedAddButton(
          label: 'Add time',
          onPressed: locked ? null : widget.onAddPressed,
        ),
      ],
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

class _TimeCard extends StatelessWidget {
  final PlugScheduleEntry entry;
  final bool showDay;
  final bool locked;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TimeCard({
    required this.entry,
    required this.showDay,
    required this.locked,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bool nextDay = (PlugScheduleEntry.secondsOfDay(entry.end) ?? 0) <=
        (PlugScheduleEntry.secondsOfDay(entry.start) ?? 0);

    return GlassSurface(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
      onTap: locked ? null : onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.timeRange,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: GlassTokens.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showDay)
                      Text(
                        entry.day,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: GlassTokens.textSecondary,
                        ),
                      ),
                    entry.isContinuous
                        ? Text(
                            'Always ON · '
                            '${formatPlugSeconds(entry.durationSeconds)}'
                            '${nextDay ? ' · ends next day' : ''}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: GlassTokens.textMuted,
                            ),
                          )
                        : StatusTag(
                            label:
                                '${formatPlugSeconds(entry.onSeconds)} on / '
                                '${formatPlugSeconds(entry.offSeconds)} off',
                            color: GlassTokens.water,
                            icon: Icons.repeat_rounded,
                            background: GlassTokens.waterSoft,
                          ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline,
                size: 20, color: GlassTokens.textMuted),
            onPressed: locked ? null : onDelete,
          ),
        ],
      ),
    );
  }
}
