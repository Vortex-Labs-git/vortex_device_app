import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../utils/constants.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// MAIN APP BAR
// =============================================================================
// Top app bar shown across all 4 tabs: a brand mark, the app name, and a
// profile button that jumps to the User tab.
//
// The profile control is a GlassIconButton rather than a bare IconButton —
// on a translucent bar a plain icon reads as decoration, so it gets its own
// pane and a press-down scale to make it obviously tappable.
//
// Translucent: tab content scrolls underneath and blurs through it. That only
// works because MainScreen uses GlassScaffold (extendBodyBehindAppBar).
//
// Implements PreferredSizeWidget so it can be used in Scaffold.appBar.
// =============================================================================

class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onPersonPressed;

  const MainAppBar({super.key, required this.onPersonPressed});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return GlassAppBar(
      title: AppStrings.appName,
      titleMark: const _BrandMark(),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GlassIconButton(
            icon: Icons.person_outline,
            onPressed: onPersonPressed,
            tooltip: AppStrings.user,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Brand mark: the one solid, saturated element in the bar, so the eye has
// something to anchor on when the glass behind it is busy.
// -----------------------------------------------------------------------------

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: GlassTokens.accentGradient,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: GlassTokens.primary.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(Icons.water_drop_rounded, size: 17, color: Colors.white),
    );
  }
}
