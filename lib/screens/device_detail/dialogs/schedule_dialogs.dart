import 'package:flutter/material.dart';

import '../../../models/valve_device.dart';
import '../utils/schedule_utils.dart';

/// Shows the add/edit schedule dialog.
///
/// Pass the existing entry as [initial] to edit it; omit it to add a new one.
/// Returns the entry, or null if the user cancelled.
Future<ScheduleEntry?> showScheduleEntryDialog(
  BuildContext context, {
  ScheduleEntry? initial,
}) {
  final existing = initial;
  final isEditing = existing != null;

  String selectedDay = existing?.day ?? kScheduleDayOptions.first;
  TimeOfDay startTime = existing != null
      ? parseScheduleTime(existing.start)
      : const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = existing != null
      ? parseScheduleTime(existing.end)
      : const TimeOfDay(hour: 8, minute: 20);
  double angle = (existing?.angle ?? 90).toDouble();

  return showDialog<ScheduleEntry>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // ───────────────────────────────────────────────────────────────
          // Helper: one tappable time field
          // ───────────────────────────────────────────────────────────────
          Widget timeField({
            required String label,
            required TimeOfDay value,
            required Color iconColor,
            required ValueChanged<TimeOfDay> onPicked,
          }) {
            return InkWell(
              onTap: () async {
                final picked = await showTimePicker(
                  context: dialogContext,
                  initialTime: value,
                );
                if (picked != null) onPicked(picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatScheduleTime(value),
                        style: const TextStyle(fontSize: 16)),
                    Icon(Icons.access_time, color: iconColor),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(isEditing ? 'Edit Schedule' : 'Add Schedule'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: kScheduleDayOptions
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedDay = val);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Time range
                  Row(
                    children: [
                      Expanded(
                        child: timeField(
                          label: 'From',
                          value: startTime,
                          iconColor: Colors.green[600]!,
                          onPicked: (v) => setDialogState(() => startTime = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: timeField(
                          label: 'To',
                          value: endTime,
                          iconColor: Colors.red[600]!,
                          onPicked: (v) => setDialogState(() => endTime = v),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Angle held during the range
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Valve angle: ${angle.round()}°',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Slider(
                    value: angle,
                    min: 0,
                    max: 90,
                    divisions: 18,              // 5° steps
                    label: '${angle.round()}°',
                    activeColor: const Color(0xFF3F51B5),
                    onChanged: (v) => setDialogState(() => angle = v),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0° closed',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      Text('90° open',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final start = formatScheduleTime(startTime);
                  final end = formatScheduleTime(endTime);

                  if (start == end) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Start and end time cannot be the same'),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    ScheduleEntry(
                      day: selectedDay,
                      start: start,
                      end: end,
                      angle: angle.round(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                ),
                child: Text(isEditing ? 'Update' : 'Add'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Asks the user to confirm deleting [entry]. Returns true when confirmed.
Future<bool> showDeleteScheduleDialog(
  BuildContext context,
  ScheduleEntry entry,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete Schedule'),
      content: Text(
          'Delete "${entry.day} — ${entry.timeRange} at ${entry.angle}°"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}