import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// GLASS BOTTOM NAV
// =============================================================================
// Translucent bottom navigation bar. Pair it with `extendBody: true` on the
// Scaffold (GlassScaffold does this) so list content slides underneath and
// blurs through the bar instead of stopping at a hard edge.
//
// Screens whose content scrolls should add MediaQuery.paddingOf(context).bottom
// to their bottom padding — with extendBody that value already includes this
// bar's height, so the last row stays reachable above it.
// =============================================================================

class GlassNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  const GlassNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}

class GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: GlassTokens.blurStrong,
          sigmaY: GlassTokens.blurStrong,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.38),
                Colors.white.withValues(alpha: 0.66),
              ],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.60),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            // The nav bar is not inside the Scaffold's body Material, so it
            // needs its own for the tab ripples to render.
            child: Material(
              type: MaterialType.transparency,
              child: SizedBox(
                height: 62,
                child: Row(
                  children: [
                    for (int i = 0; i < items.length; i++)
                      Expanded(
                        child: _NavButton(
                          item: items[i],
                          selected: i == currentIndex,
                          onTap: () => onTap(i),
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

// -----------------------------------------------------------------------------
// One tab. The selected tab gets a tinted glass capsule behind its icon, which
// reads more clearly against a busy backdrop than a color change alone.
// -----------------------------------------------------------------------------

class _NavButton extends StatelessWidget {
  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color =
        selected ? GlassTokens.primary : GlassTokens.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
      splashColor: GlassTokens.primary.withValues(alpha: 0.10),
      highlightColor: Colors.white.withValues(alpha: 0.20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              color: selected
                  ? GlassTokens.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.70)
                    : Colors.transparent,
              ),
            ),
            child: Icon(
              selected ? (item.activeIcon ?? item.icon) : item.icon,
              size: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
