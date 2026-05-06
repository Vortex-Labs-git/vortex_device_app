import 'package:flutter/material.dart';
import '../../../utils/constants.dart';

// =============================================================================
// MAIN APP BAR
// =============================================================================
// Top app bar shown across all 4 tabs. Has the app name centered and a person
// icon in the top-right corner that jumps the user to the User tab.
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
    return AppBar(
      backgroundColor: AppColors.primary,
      centerTitle: true,
      title: const Text(
        AppStrings.appName,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        // Person icon → jumps to the User tab
        IconButton(
          icon: const Icon(Icons.person_outline, color: Colors.white),
          onPressed: onPersonPressed,
        ),
      ],
    );
  }
}
