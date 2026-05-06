import 'package:flutter/material.dart';
import 'dart:math' as math;

// =============================================================================
// VALVE CONTROL CARD
// =============================================================================
// Manual-mode valve control. Has two sub-modes selected by [valveControlEnabled]:
//   ON  → State mode: Open / Close switch with confirmation tracking
//   OFF → Angle mode: 0–90° slider + dial visualization + Set Angle button
//
// All state lives in the parent screen. This widget just renders + raises
// callbacks for every user action.
// =============================================================================

class ValveControlCard extends StatelessWidget {
  // ── Mode toggle ──
  final bool valveControlEnabled; // true = state mode, false = angle mode
  final ValueChanged<bool> onValveControlEnabledChanged;

  // ── State mode ──
  final bool isOpen;
  final int actualPosition;
  final bool isUpdating;
  final ValueChanged<bool> onOpenCloseToggled; // true=open, false=close

  // ── Angle mode ──
  final double sliderAngle;
  final bool isAngleUpdating;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onSliderEditStart;
  final VoidCallback onSliderEditEnd;
  final ValueChanged<int> onSetAnglePressed;

  // ── Confirmation tracking (shared across both sub-modes) ──
  final bool waitingForConfirmation;
  final int? pendingTargetAngle;
  final int confirmationCountdown;

  const ValveControlCard({
    super.key,
    required this.valveControlEnabled,
    required this.onValveControlEnabledChanged,
    required this.isOpen,
    required this.actualPosition,
    required this.isUpdating,
    required this.onOpenCloseToggled,
    required this.sliderAngle,
    required this.isAngleUpdating,
    required this.onSliderChanged,
    required this.onSliderEditStart,
    required this.onSliderEditEnd,
    required this.onSetAnglePressed,
    required this.waitingForConfirmation,
    required this.pendingTargetAngle,
    required this.confirmationCountdown,
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
            // SECTION 1: HEADER + MODE TOGGLE
            // =========================================================
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
                    // Disable mode switch while waiting for confirmation
                    onChanged: waitingForConfirmation
                        ? null
                        : onValveControlEnabledChanged,
                    activeColor: const Color(0xFF3F51B5),
                  ),
                ),
              ],
            ),

            // =========================================================
            // SECTION 2: MODE INDICATOR LABEL
            // =========================================================
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                valveControlEnabled
                    ? 'Mode: Open / Close'
                    : 'Mode: Angle control',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // =========================================================
            // SECTION 3: STATE MODE (toggle ON)
            // =========================================================
            if (valveControlEnabled) ...[
              // 3.1  "By state" row with Open/Close switch
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'By state',
                    style: TextStyle(color: Colors.grey),
                  ),
                  Row(
                    children: [
                      Text(
                        isOpen ? 'Open' : 'Close',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color:
                              isOpen ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Spinner while sending OR waiting; Switch otherwise
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
                                    color: waitingForConfirmation
                                        ? Colors.blue
                                        : null,
                                  ),
                                ),
                              ),
                            )
                          : Switch(
                              value: isOpen,
                              onChanged: onOpenCloseToggled,
                              activeColor: Colors.green,
                              inactiveTrackColor: Colors.red.shade200,
                              inactiveThumbColor: Colors.red,
                            ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 3.2  Actual position display
              _buildActualPositionRow(),
            ],

            // =========================================================
            // SECTION 4: ANGLE MODE (toggle OFF)
            // =========================================================
            if (!valveControlEnabled) ...[
              const Text('By angle', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),

              // 4.1  Waiting indicator banner (only while waiting)
              if (waitingForConfirmation) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                        'Target: $pendingTargetAngle°',
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

              // 4.2  Angle dial (ring + needle + center dot)
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.grey[300]!,
                            width: 8,
                          ),
                        ),
                      ),
                      // Needle (rotated by current slider angle)
                      Transform.rotate(
                        angle: (sliderAngle / 90) * (math.pi / 2),
                        child: Container(
                          width: 4,
                          height: 50,
                          decoration: BoxDecoration(
                            color: waitingForConfirmation
                                ? Colors.blue
                                : const Color(0xFF3F51B5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Center dot
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: waitingForConfirmation
                              ? Colors.blue
                              : const Color(0xFF3F51B5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 4.3  Big angle value text
              Center(
                child: Text(
                  '${sliderAngle.round()}°',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: waitingForConfirmation
                        ? Colors.blue
                        : const Color(0xFF3F51B5),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 4.4  Slider 0° ─────●───── 90°
              Row(
                children: [
                  const Text(
                    '0°',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      value: sliderAngle,
                      min: 0,
                      max: 90,
                      divisions: 90,
                      activeColor: waitingForConfirmation
                          ? Colors.grey
                          : const Color(0xFF3F51B5),
                      inactiveColor: Colors.grey[300],
                      label: '${sliderAngle.round()}°',
                      onChanged: waitingForConfirmation ? null : onSliderChanged,
                      onChangeStart: waitingForConfirmation
                          ? null
                          : (_) => onSliderEditStart(),
                      onChangeEnd: waitingForConfirmation
                          ? null
                          : (_) => onSliderEditEnd(),
                    ),
                  ),
                  const Text(
                    '90°',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // 4.5  "Set Angle" button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (isAngleUpdating || waitingForConfirmation)
                      ? null
                      : () => onSetAnglePressed(sliderAngle.round()),
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
                  label: Text(
                    waitingForConfirmation
                        ? 'Waiting... ${confirmationCountdown}s'
                        : isAngleUpdating
                            ? 'Sending...'
                            : 'Set Angle to ${sliderAngle.round()}°',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF3F51B5).withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 4.6  Actual position display
              _buildActualPositionRow(),
            ],
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: actual-position info row (used by both state and angle modes)
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildActualPositionRow() {
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
            '$actualPosition°',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: actualPosition >= 45 ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}
