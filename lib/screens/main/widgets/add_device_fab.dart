import 'package:flutter/material.dart';

import '../../../utils/constants.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// ADD DEVICE FAB
// =============================================================================
// The raised "+" in the middle of the bottom bar (see MainBottomNav). The
// actual sheet (device type, name, snackbar confirmation) lives in the parent
// screen and is invoked through [onPressed].
// =============================================================================

class AddDeviceFab extends StatelessWidget {
  final VoidCallback onPressed;

  const AddDeviceFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GlassFab(
      icon: Icons.add_rounded,
      size: 54,
      onPressed: onPressed,
      tooltip: AppStrings.addDevice,
    );
  }
}
