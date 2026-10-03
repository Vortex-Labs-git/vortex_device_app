import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// RUNS ON CARD  (UI v2 — valve screen)
// =============================================================================
// "Valve runs on: Manual | Automatic". Replaces ModeToggleCard on the valve
// screen (the plug screen still uses ModeToggleCard), with the same three
// callbacks and the same rules:
//
//   Manual / Automatic   → onAutomateChanged(false / true)
//                          Automatic alone sends nothing until a source is on.
//   Schedule / Sensor    → onScheduleChanged / onSensorChanged — each sends the
//                          control method to the server; both can be on.
//
// While [isSwitching] the server hasn't confirmed yet: every control is locked
// and a spinner shows in the corner.
// =============================================================================

class RunsOnCard extends StatelessWidget {
  final bool isAutomateMode;
  final bool isScheduleMode;
  final bool isSensorMode;
  final bool isSwitching;
  final ValueChanged<bool> onAutomateChanged;
  final ValueChanged<bool> onScheduleChanged;
  final ValueChanged<bool> onSensorChanged;

  const RunsOnCard({
    super.key,
    required this.isAutomateMode,
    required this.isScheduleMode,
    required this.isSensorMode,
    required this.isSwitching,
    required this.onAutomateChanged,
    required this.onScheduleChanged,
    required this.onSensorChanged,
  });

  /// One line on what the switches add up to (same wording as before).
  String get _summary {
    if (!isAutomateMode) return 'You control the valve';
    if (isScheduleMode && isSensorMode) return 'Schedule, with sensor override';
    if (isScheduleMode) return 'Valve follows the schedule';
    if (isSensorMode) return 'Valve follows sensor readings';
    return 'Pick Schedule, Sensor or both';
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Valve runs on',
                  style: TextStyle(
                    fontFamily: GlassTokens.displayFont,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: GlassTokens.textPrimary,
                  ),
                ),
              ),
              if (isSwitching)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Flexible(
                  child: Text(
                    _summary,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      color: GlassTokens.textMuted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedPicker<bool>(
            selected: isAutomateMode,
            onChanged: isSwitching ? null : onAutomateChanged,
            options: const [
              SegmentOption(
                value: false,
                label: 'Manual',
                icon: Icons.pan_tool_outlined,
              ),
              SegmentOption(
                value: true,
                label: 'Automatic',
                icon: Icons.autorenew_rounded,
                color: GlassTokens.sun,
              ),
            ],
          ),

          // ── Sources, only while Automatic ──
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isAutomateMode
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _SourceChip(
                            label: 'Schedule',
                            icon: Icons.calendar_month_outlined,
                            color: GlassTokens.sun,
                            on: isScheduleMode,
                            enabled: !isSwitching,
                            onTap: () => onScheduleChanged(!isScheduleMode),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SourceChip(
                            label: 'Sensor',
                            icon: Icons.sensors,
                            color: GlassTokens.info,
                            on: isSensorMode,
                            enabled: !isSwitching,
                            onTap: () => onSensorChanged(!isSensorMode),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// One automation source: a tappable chip that reads "Schedule · ON / OFF".
class _SourceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool on;
  final bool enabled;
  final VoidCallback onTap;

  const _SourceChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.on,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = on ? color : GlassTokens.textMuted;
    return Semantics(
      toggled: on,
      button: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Material(
          color: on ? Color.lerp(Colors.white, color, 0.10) : GlassTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
            side: BorderSide(
              color: on ? color : GlassTokens.border,
              width: 1.5,
            ),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: on ? fg : GlassTokens.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    on ? 'ON' : 'OFF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: fg,
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
