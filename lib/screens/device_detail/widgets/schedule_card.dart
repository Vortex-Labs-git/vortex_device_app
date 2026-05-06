import 'package:flutter/material.dart';

// =============================================================================
// SCHEDULE CARD
// =============================================================================
// Shows the schedule table (Day | Open | Close | delete), an "Add Schedule"
// button, and a "Save Schedule" button. All add/edit/delete dialogs and the
// REST save call live in the parent screen and are invoked through callbacks.
// =============================================================================

class ScheduleCard extends StatelessWidget {
  final List<Map<String, dynamic>> schedules;
  final bool isSavingSchedule;
  final VoidCallback onAddPressed;
  final ValueChanged<int> onRowTapped; // Tap a row to edit it
  final ValueChanged<int> onRowDeleted;
  final VoidCallback onSavePressed;

  const ScheduleCard({
    super.key,
    required this.schedules,
    required this.isSavingSchedule,
    required this.onAddPressed,
    required this.onRowTapped,
    required this.onRowDeleted,
    required this.onSavePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =========================================================
            // SECTION 1: HEADER ROW (title + entry count)
            // =========================================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${schedules.length} entries',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // =========================================================
            // SECTION 2: TABLE HEADER (Day | Open | Close | _)
            // =========================================================
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        'Day',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        'Open',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SizedBox(width: 40), // Space for delete button column
                ],
              ),
            ),

            // =========================================================
            // SECTION 3: SCHEDULE ROWS (or empty placeholder)
            // =========================================================
            if (schedules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No schedules added yet.\nTap + to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ...schedules.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return _buildRow(
                  index: i,
                  day: s['day'] ?? '',
                  openTime: s['open'] ?? '',
                  closeTime: s['close'] ?? '',
                );
              }),

            const SizedBox(height: 12),

            // =========================================================
            // SECTION 4: ADD SCHEDULE BUTTON
            // =========================================================
            Center(
              child: TextButton.icon(
                onPressed: onAddPressed,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Schedule'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3F51B5),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // =========================================================
            // SECTION 5: SAVE SCHEDULE BUTTON
            // =========================================================
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSavingSchedule ? null : onSavePressed,
                icon: isSavingSchedule
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(isSavingSchedule ? 'Saving...' : 'Save Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF3F51B5).withOpacity(0.6),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: single schedule row (Day | Open | Close | delete-icon)
  // Tapping the row body calls onRowTapped (edit). The delete icon calls
  // onRowDeleted independently.
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildRow({
    required int index,
    required String day,
    required String openTime,
    required String closeTime,
  }) {
    return InkWell(
      onTap: () => onRowTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  day,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  openTime,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.green[700],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  closeTime,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.red[700],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red[300],
                onPressed: () => onRowDeleted(index),
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
