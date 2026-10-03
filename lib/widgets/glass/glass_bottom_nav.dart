
import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// GLASS BOTTOM NAV
// =============================================================================
// A floating navigation island: a rounded, translucent bar inset from the
// screen edges with content sliding underneath it. Pair it with
// `extendBody: true` on the Scaffold (GlassScaffold does this) — otherwise the
// Scaffold reserves opaque space below the body and the bar has nothing to
// float over.
//
// The selected tab is marked by a capsule that SLIDES between tabs rather than
// appearing in place, so a tab change reads as one continuous movement.
//
// [centerAction] (UI v2) puts a raised button in the middle — the add-device
// "+" — with the tabs split evenly either side of it.
//
// This is one of the few places blur is kept (see the note in glass_surface):
// real content passes under it, so the frosting is visible and worth its cost.
//
// Screens whose content scrolls should add MediaQuery.paddingOf(context).bottom
// to their bottom padding — with extendBody that value already accounts for the
// island's full height plus its margins, so the last row clears the bar while
// the list still scrolls behind it.
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

  /// Optional raised action in the middle of the bar (the "+" button). The
  /// tabs split evenly around it; it is not a tab and has no selected state.
  final Widget? centerAction;

  /// Height of the island itself, excluding the margins around it.
  static const double barHeight = 64;

  /// Width reserved for [centerAction].
  static const double centerSlotWidth = 68;

  const GlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.centerAction,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(24);
    // Clear the system navigation area completely. The app runs edge-to-edge,
    // so that area is ours to draw into — which means nothing stops this island
    // from landing on top of Android's 3-button bar unless the FULL inset is
    // reserved. A slightly airy gap under gesture navigation is the acceptable
    // side of that trade; overlapping the Back button is not.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    // With a centre action the tabs split into a left and a right half.
    final int leftCount =
        centerAction == null ? items.length : (items.length / 2).ceil();

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 10 + bottomInset),
      child: SizedBox(
        height: barHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: GlassTokens.surface,
                  borderRadius: radius,
                  border: Border.all(color: GlassTokens.border, width: 1),
                  // Floating bar, so it keeps a real (if quiet) shadow — this
                  // is the one place elevation carries meaning.
                  boxShadow: GlassTokens.paneShadow(),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                // Not inside the Scaffold body's Material, so the tab
                // ripples need one of their own.
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double centerW =
                          centerAction == null ? 0 : centerSlotWidth;
                      final double tabWidth =
                          (constraints.maxWidth - centerW) / items.length;
                      // Left edge of the selected tab, skipping the centre
                      // slot for tabs on the right half.
                      final double selectedLeft = tabWidth * currentIndex +
                          (currentIndex >= leftCount ? centerW : 0);

                      return Stack(
                        children: [
                          // Sliding selection capsule, behind the tabs.
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            left: selectedLeft,
                            width: tabWidth,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: GlassTokens.leafSoft,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (int i = 0; i < items.length; i++) ...[
                                if (centerAction != null && i == leftCount)
                                  const SizedBox(width: centerSlotWidth),
                                Expanded(
                                  child: _NavButton(
                                    item: items[i],
                                    selected: i == currentIndex,
                                    onTap: () => onTap(i),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            // The centre action sits on top, raised above the bar's edge.
            if (centerAction != null)
              Positioned(
                top: -20,
                left: 0,
                right: 0,
                child: Center(child: centerAction!),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// One tab. The capsule behind it is drawn by the parent (it slides), so this
// only animates the icon and label.
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
    return InkWell(
      onTap: onTap,
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      splashColor: GlassTokens.primary.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Selected icon lifts slightly and takes the brand color.
          AnimatedScale(
            scale: selected ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 260),
              tween: ColorTween(
                end: selected ? GlassTokens.primary : GlassTokens.textMuted,
              ),
              builder: (context, color, _) => Icon(
                selected ? (item.activeIcon ?? item.icon) : item.icon,
                size: 22,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 260),
            // AnimatedDefaultTextStyle replaces the inherited style, so the
            // family has to be named here or it falls back to Roboto.
            style: TextStyle(
              fontFamily: GlassTokens.bodyFont,
              fontSize: 10.5,
              color: selected ? GlassTokens.primary : GlassTokens.textMuted,
              fontWeight: FontWeight.w700,
            ),
            child: Text(item.label),
          ),
        ],
      ),
    );
  }
}
