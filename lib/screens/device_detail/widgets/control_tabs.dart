import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// CONTROL TABS  (UI v2 — valve screen)
// =============================================================================
// "Control · Schedule · Sensor rules". Picks which card is shown — a view
// only, like the old Control-by card it replaced (valve and plug screens).
// Tabs in [locked] show a lock and call [onLockedTap] instead, so the
// parent can explain why (e.g. a schedule is running, or the valve is
// offline).
//
// Values are the screen's existing mode strings: 'manual' | 'schedule' |
// 'sensor'.
// =============================================================================

class ControlTabs extends StatelessWidget {
  final String selected;
  final Set<String> locked;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onLockedTap;

  const ControlTabs({
    super.key,
    required this.selected,
    this.locked = const {},
    required this.onSelected,
    required this.onLockedTap,
  });

  static const List<(String, String)> _tabs = [
    ('manual', 'Control'),
    ('schedule', 'Schedule'),
    ('sensor', 'Sensor rules'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: GlassTokens.border)),
      ),
      // Shrinks a little rather than overflow on a narrow phone when the
      // lock icons are showing.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            for (final (value, label) in _tabs) ...[
              _Tab(
                label: label,
                isSelected: value == selected,
                isLocked: locked.contains(value),
                onTap: locked.contains(value)
                    ? () => onLockedTap(value)
                    : () => onSelected(value),
              ),
              const SizedBox(width: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isLocked;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.isSelected,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = isSelected
        ? GlassTokens.textPrimary
        : GlassTokens.textMuted;

    return Semantics(
      selected: isSelected,
      button: true,
      enabled: !isLocked,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Opacity(
          opacity: isLocked ? 0.5 : 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected ? GlassTokens.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLocked) ...[
                  Icon(Icons.lock_outline, size: 14, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
