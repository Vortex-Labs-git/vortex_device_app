import 'package:flutter/material.dart';

class ScheduleCard extends StatelessWidget {
  final List<Map<String, dynamic>> schedules;
  final bool isSavingSchedule;
  final VoidCallback onAddSchedule;
  final VoidCallback onSaveSchedule;
  final void Function(int) onEditSchedule;
  final void Function(int) onDeleteSchedule;

  const ScheduleCard({
    super.key,
    required this.schedules,
    required this.isSavingSchedule,
    required this.onAddSchedule,
    required this.onSaveSchedule,
    required this.onEditSchedule,
    required this.onDeleteSchedule,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

            // Table Header
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
                          child: Text('Day',
                              style: TextStyle(fontWeight: FontWeight.bold)))),
                  Expanded(
                      flex: 2,
                      child: Center(
                          child: Text('Open',
                              style: TextStyle(fontWeight: FontWeight.bold)))),
                  Expanded(
                      flex: 2,
                      child: Center(
                          child: Text('Close',
                              style: TextStyle(fontWeight: FontWeight.bold)))),
                  SizedBox(width: 40), // Space for delete button
                ],
              ),
            ),

            // Schedule Rows
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
                return _buildScheduleRowInteractive(
                  i,
                  s['day'] ?? '',
                  s['open'] ?? '',
                  s['close'] ?? '',
                );
              }),

            const SizedBox(height: 12),

            // Add Schedule Button
            Center(
              child: TextButton.icon(
                onPressed: onAddSchedule,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Schedule'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3F51B5),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSavingSchedule ? null : onSaveSchedule,
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
                  disabledBackgroundColor: const Color(0xFF3F51B5).withOpacity(0.6),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRowInteractive(int index, String day, String openTime, String closeTime) {
    return InkWell(
      onTap: () => onEditSchedule(index),
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
                      color: Colors.green[700]),
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
                      color: Colors.red[700]),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red[300],
                onPressed: () => onDeleteSchedule(index),
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