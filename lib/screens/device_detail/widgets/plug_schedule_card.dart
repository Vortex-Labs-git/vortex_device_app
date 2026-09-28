import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../utils/plug_utils.dart';

// =============================================================================
// PLUG SCHEDULE CARD
// =============================================================================
// The plug's version of ScheduleCard, for ONE base. Table of
// Day | Time (From – To, HH:mm:ss) | Mode (step) | delete, an "Add Schedule"
// button and a "Save Schedule" button. Dialogs and the REST call live in the
// parent screen.
//
// Every row is an ON period — the base is OFF outside all of them — so there
// is no ON/OFF column. "Mode" is the step: "Always ON" or "5 s / 5 s".
//
// [hasUnsavedChanges] shows a small "Unsaved changes" note so the user knows
// the table differs from what the plug has.
// =============================================================================

class PlugScheduleCard extends StatelessWidget {
  final String baseName;
  final List<PlugScheduleEntry> schedules;
  final bool isSaving;
  final bool hasUnsavedChanges;
  final VoidCallback onAddPressed;
  final ValueChanged<int> onRowTapped; // tap a row to edit it
  final ValueChanged<int> onRowDeleted;
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

  // Column widths, shared by the header and every row so they stay aligned.
  static const int _dayFlex = 3;
  static const int _timeFlex = 4;
  static const int _modeFlex = 3;
  static const double _deleteWidth = 40;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header: title + count ────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schedule — $baseName',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                '${schedules.length} entries',
                style: const TextStyle(
                  color: GlassTokens.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          if (hasUnsavedChanges) ...[
            const SizedBox(height: 4),
            const Text(
              'Unsaved changes — tap Save Schedule',
              style: TextStyle(
                color: GlassTokens.warning,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ─── Table header ─────────────────────────────────────────────
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
                  flex: _dayFlex,
                  child: Center(
                    child: Text('Day',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(
                  flex: _timeFlex,
                  child: Center(
                    child: Text('Time',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                Expanded(
                  flex: _modeFlex,
                  child: Center(
                    child: Text('Mode',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                SizedBox(width: _deleteWidth),
              ],
            ),
          ),

          // ─── Rows ─────────────────────────────────────────────────────
          if (schedules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No schedules added yet.\nTap + to add one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GlassTokens.textMuted),
                ),
              ),
            )
          else
            ...schedules.asMap().entries.map(
                  (e) => _buildRow(index: e.key, entry: e.value),
                ),

          const SizedBox(height: 12),

          // ─── Add ──────────────────────────────────────────────────────
          Center(
            child: TextButton.icon(
              onPressed: isSaving ? null : onAddPressed,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add Schedule'),
              style: TextButton.styleFrom(
                foregroundColor: GlassTokens.primary,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ─── Save ─────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isSaving ? null : onSavePressed,
              icon: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(isSaving ? 'Saving...' : 'Save Schedule'),
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
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // One row: Day | From – To | Mode | delete
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildRow({required int index, required PlugScheduleEntry entry}) {
    final bool cycling = !entry.isContinuous;

    return InkWell(
      onTap: isSaving ? null : () => onRowTapped(index),
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
              flex: _dayFlex,
              child: Center(
                child: Text(
                  entry.day,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // From over To, so HH:mm:ss fits on a phone.
            Expanded(
              flex: _timeFlex,
              child: Column(
                children: [
                  Text(
                    entry.start,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    entry.end,
                    style: const TextStyle(
                      fontSize: 12,
                      color: GlassTokens.textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: _modeFlex,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      cycling ? Icons.repeat : Icons.power,
                      size: 14,
                      color: cycling ? GlassTokens.info : GlassTokens.success,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        cycling
                            ? '${formatPlugSeconds(entry.onSeconds)} / '
                                '${formatPlugSeconds(entry.offSeconds)}'
                            : 'Always ON',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cycling
                              ? GlassTokens.info
                              : GlassTokens.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: _deleteWidth,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: GlassTokens.danger,
                onPressed: isSaving ? null : () => onRowDeleted(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
