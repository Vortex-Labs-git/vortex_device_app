import 'package:flutter/material.dart';
import 'dart:math' as math;

class ValveControlCard extends StatelessWidget {
  final bool valveControlEnabled;
  final ValueChanged<bool>? onValveControlEnabledChanged;
  final bool waitingForConfirmation;
  final int confirmationCountdown;
  final int? pendingTargetAngle;
  final bool isOpen;
  final int actualPos;
  final bool isUpdating;
  final ValueChanged<bool> onStateControlChanged;
  final double sliderAngle;
  final bool isAngleUpdating;
  final ValueChanged<double>? onSliderChanged;
  final ValueChanged<double>? onSliderChangeStart;
  final ValueChanged<double>? onSliderChangeEnd;
  final VoidCallback onSetAngle;

  const ValveControlCard({
    super.key,
    required this.valveControlEnabled,
    required this.onValveControlEnabledChanged,
    required this.waitingForConfirmation,
    required this.confirmationCountdown,
    this.pendingTargetAngle,
    required this.isOpen,
    required this.actualPos,
    required this.isUpdating,
    required this.onStateControlChanged,
    required this.sliderAngle,
    required this.isAngleUpdating,
    required this.onSliderChanged,
    required this.onSliderChangeStart,
    required this.onSliderChangeEnd,
    required this.onSetAngle,
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
                  'Valve control',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Transform.scale(
                  scale: 1.2,
                  child: Switch(
                    value: valveControlEnabled,
                    onChanged: waitingForConfirmation ? null : onValveControlEnabledChanged,
                    activeColor: const Color(0xFF3F51B5),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                valveControlEnabled ? 'Mode: Open / Close' : 'Mode: Angle control',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // STATE MODE
            if (valveControlEnabled) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('By state', style: TextStyle(color: Colors.grey)),
                  Row(
                    children: [
                      Text(
                        isOpen ? 'Open' : 'Close',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isOpen ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                      const SizedBox(width: 8),
                      (isUpdating || waitingForConfirmation)
                          ? SizedBox(
                              width: 48,
                              height: 28,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: waitingForConfirmation ? Colors.blue : null,
                                  ),
                                ),
                              ),
                            )
                          : Switch(
                              value: isOpen,
                              onChanged: onStateControlChanged,
                              activeColor: Colors.green,
                              inactiveTrackColor: Colors.red.shade200,
                              inactiveThumbColor: Colors.red,
                            ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildActualPositionInfo(),
            ],

            // ANGLE MODE
            if (!valveControlEnabled) ...[
              const Text('By angle', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              if (waitingForConfirmation) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Waiting for valve... ${confirmationCountdown}s',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        'Target: ${pendingTargetAngle}°',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[300]!, width: 8),
                        ),
                      ),
                      Transform.rotate(
                        angle: (sliderAngle / 90) * (math.pi / 2),
                        child: Container(
                          width: 4,
                          height: 50,
                          decoration: BoxDecoration(
                            color: waitingForConfirmation ? Colors.blue : const Color(0xFF3F51B5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: waitingForConfirmation ? Colors.blue : const Color(0xFF3F51B5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${sliderAngle.round()}°',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: waitingForConfirmation ? Colors.blue : const Color(0xFF3F51B5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('0°', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: sliderAngle,
                      min: 0,
                      max: 90,
                      divisions: 90,
                      activeColor: waitingForConfirmation ? Colors.grey : const Color(0xFF3F51B5),
                      inactiveColor: Colors.grey[300],
                      label: '${sliderAngle.round()}°',
                      onChanged: onSliderChanged,
                      onChangeStart: onSliderChangeStart,
                      onChangeEnd: onSliderChangeEnd,
                    ),
                  ),
                  const Text('90°', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (isAngleUpdating || waitingForConfirmation) ? null : onSetAngle,
                  icon: (isAngleUpdating || waitingForConfirmation)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(waitingForConfirmation
                      ? 'Waiting... ${confirmationCountdown}s'
                      : isAngleUpdating
                          ? 'Sending...'
                          : 'Set Angle to ${sliderAngle.round()}°'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF3F51B5).withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildActualPositionInfo(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActualPositionInfo() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Actual position',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          Text(
            '$actualPos°',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: actualPos >= 45 ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}