import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// SEGMENTED PICKER
// =============================================================================
// Equal-width options in a recessed track; the selected one is a raised white
// chip in its own colour. Used for "Control by: Manual | Schedule | Sensor"
// and similar one-of-N switches.
//
// A segment with [SegmentOption.locked] shows a lock, is dimmed and does not
// call [onChanged] — the layout stays the same whether or not it is available
// (e.g. schedule / sensor in direct mode).
//
// View only: the caller owns [selected] and decides what a change does.
// =============================================================================

class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// Selected text/icon colour. Defaults to [GlassTokens.primary].
  final Color? color;

  final bool locked;

  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
    this.color,
    this.locked = false,
  });
}

class SegmentedPicker<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T>? onChanged;

  const SegmentedPicker({
    super.key,
    required this.options,
    required this.selected,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GlassTokens.sunk,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        border: Border.all(color: GlassTokens.border),
      ),
      child: Row(
        children: [
          for (int i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(child: _segment(options[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment(SegmentOption<T> o) {
    final bool isSelected = o.value == selected;
    final Color accent = o.color ?? GlassTokens.primary;
    final Color fg = isSelected ? accent : GlassTokens.textSecondary;
    final IconData? icon = o.locked ? Icons.lock_outline : o.icon;

    return Opacity(
      opacity: o.locked ? 0.5 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected ? GlassTokens.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
          boxShadow: isSelected ? GlassTokens.paneShadow() : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
            onTap: o.locked || onChanged == null || isSelected
                ? null
                : () => onChanged!(o.value),
            child: Semantics(
              selected: isSelected,
              button: true,
              enabled: !o.locked,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: fg),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        o.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
