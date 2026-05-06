import 'package:flutter/material.dart';

class ModeToggleCard extends StatelessWidget {
  final bool isScheduleMode;
  final bool isSwitchingMode;
  final ValueChanged<bool> onToggle;

  const ModeToggleCard({
    super.key,
    required this.isScheduleMode,
    required this.isSwitchingMode,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Control method',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isScheduleMode
                        ? Colors.orange.shade50
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isScheduleMode ? Icons.schedule : Icons.pan_tool,
                    color: isScheduleMode ? Colors.orange : const Color(0xFF3F51B5),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Manual',
                            style: TextStyle(
                              fontWeight: !isScheduleMode ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                              color: !isScheduleMode ? const Color(0xFF3F51B5) : Colors.grey,
                            ),
                          ),
                          Text(
                            '  /  ',
                            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
                          ),
                          Text(
                            'Schedule',
                            style: TextStyle(
                              fontWeight: isScheduleMode ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                              color: isScheduleMode ? Colors.orange : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isScheduleMode
                            ? 'Valve follows the schedule automatically'
                            : 'You control the valve position',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                if (isSwitchingMode)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: isScheduleMode,
                    activeColor: Colors.orange,
                    inactiveThumbColor: const Color(0xFF3F51B5),
                    inactiveTrackColor: const Color(0xFF3F51B5).withOpacity(0.3),
                    onChanged: onToggle,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}