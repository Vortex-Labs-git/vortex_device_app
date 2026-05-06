import 'package:flutter/material.dart';

class ControlModeCard extends StatelessWidget {
  final String controlMode;
  final bool isDirectMode;
  final ValueChanged<String> onModeSelected;

  const ControlModeCard({
    super.key,
    required this.controlMode,
    required this.isDirectMode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Control by',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModeButton(context, 'manual', Icons.pan_tool, 'manual'),
                _buildModeButton(context, 'schedule', Icons.schedule, 'schedule'),
                _buildModeButton(context, 'sensor', Icons.sensors, 'sensor'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(BuildContext context, String mode, IconData icon, String label) {
    bool isSelected = controlMode == mode;
    bool isDisabled = isDirectMode && (mode == 'schedule' || mode == 'sensor');

    return GestureDetector(
      onTap: isDisabled
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Schedule & Sensor require server connection'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          : () => onModeSelected(mode),
      child: Opacity(
        opacity: isDisabled ? 0.35 : 1.0,
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3F51B5) : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                isDisabled ? Icons.lock_outline : icon,
                color: isSelected ? Colors.white : Colors.grey[600],
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}