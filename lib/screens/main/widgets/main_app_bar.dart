import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../utils/constants.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// MAIN APP BAR
// =============================================================================
// Top app bar shown across all 4 tabs. Has the app name centered and a person
// icon in the top-right corner that jumps the user to the User tab.
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
      actions: [
        // Person icon → jumps to the User tab
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: const Icon(Icons.person_outline),
            color: GlassTokens.primary,
            onPressed: onPersonPressed,
            tooltip: AppStrings.user,
          ),
        ),
      ],
    );
  }
}
