import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// PLUG BASE SELECTOR
// =============================================================================
// "Base A | Base B" segmented bar under the info card. Everything below it on
// the plug screen shows the selected base only.
//
// Each tab carries a small dot for that base's live state (green = ON).
// On a single plug base_B is not valid, so its tab is locked (lock icon,
// dimmed, not tappable) rather than hidden — the layout stays the same for
// both plug versions.
// =============================================================================

class PlugBaseSelector extends StatelessWidget {
  final PlugBaseId selected;
  final PlugBase baseA;
  final PlugBase baseB;
  final ValueChanged<PlugBaseId> onSelected;

  const PlugBaseSelector({
    super.key,
    required this.selected,
    required this.baseA,
    required this.baseB,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(4),
      borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
      child: Row(
        children: [
          Expanded(child: _tab(baseA, 'Base A')),
          const SizedBox(width: 4),
          Expanded(child: _tab(baseB, 'Base B')),
        ],
      ),
    );
  }

  Widget _tab(PlugBase base, String label) {
    final bool isSelected = base.id == selected;
    final bool isValid = base.isValid;
    final Color textColor =
        isSelected ? Colors.white : GlassTokens.textSecondary;

    return Semantics(
      selected: isSelected,
      button: true,
      enabled: isValid,
      child: Opacity(
        opacity: isValid ? 1.0 : 0.35,
        child: Material(
          color: isSelected ? GlassTokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: isValid && !isSelected ? () => onSelected(base.id) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isValid)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: base.state
                            ? (isSelected
                                ? Colors.lightGreenAccent
                                : GlassTokens.success)
                            : (isSelected
                                ? Colors.white54
                                : GlassTokens.textMuted),
                      ),
                    )
                  else
                    Icon(Icons.lock_outline, size: 16, color: textColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w500,
                      ),
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