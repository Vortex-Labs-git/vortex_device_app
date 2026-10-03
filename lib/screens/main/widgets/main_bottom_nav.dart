import 'package:flutter/material.dart';

import '../../../utils/constants.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// MAIN BOTTOM NAV
// =============================================================================
// Floating bottom bar with 4 fixed tabs: Home / Account / Guide / About.
//
// ADD BUTTON DISABLED FOR NOW: the raised "+" add-device button is hidden
// until adding devices from the app is ready. To bring it back, restore the
// `centerAction:` line in build() — [onAddPressed] and the sheet in
// MainScreen are kept for that.
//
// Receives the currently selected index and an onTap callback that the
// parent uses to update its own _currentIndex state; [onAddPressed] opens the
// parent's add-device sheet. Tab order and indices are unchanged
// (0=Home, 1=User, 2=Manual, 3=About) — only the visible labels changed.
// =============================================================================

class MainBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onAddPressed;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onAddPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GlassBottomNav(
      currentIndex: currentIndex,
      onTap: onTap,
      // Add button hidden for now — re-enable with:
      // centerAction: AddDeviceFab(onPressed: onAddPressed),
      items: const [
        GlassNavItem(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: AppStrings.home,
        ),
        GlassNavItem(
          icon: Icons.person_outline,
          activeIcon: Icons.person_rounded,
          label: 'Account',
        ),
        GlassNavItem(
          icon: Icons.menu_book_outlined,
          activeIcon: Icons.menu_book_rounded,
          label: 'Guide',
        ),
        GlassNavItem(
          icon: Icons.info_outline,
          activeIcon: Icons.info_rounded,
          label: AppStrings.about,
        ),
      ],
    );
  }
}
