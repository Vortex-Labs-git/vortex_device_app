import 'package:flutter/material.dart';
import '../../../utils/constants.dart';

// =============================================================================
// MAIN BOTTOM NAV
// =============================================================================
// Bottom navigation bar with 4 fixed tabs: Home / User / Manual / About.
// Receives the currently selected index and an onTap callback that the
// parent uses to update its own _currentIndex state.
// =============================================================================

class MainBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: AppStrings.home,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: AppStrings.user,
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.menu_book),
          label: 'Manual',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.info),
          label: AppStrings.about,
        ),
      ],
    );
  }
}
