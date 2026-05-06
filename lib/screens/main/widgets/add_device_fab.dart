import 'package:flutter/material.dart';
import '../../../utils/constants.dart';

// =============================================================================
// ADD DEVICE FAB
// =============================================================================
// Floating action button shown only on the Home tab. The actual dialog logic
// (TextField for name, snackbar confirmation) lives in the parent screen and
// is invoked through [onPressed].
// =============================================================================

class AddDeviceFab extends StatelessWidget {
  final VoidCallback onPressed;

  const AddDeviceFab({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: AppColors.primary,
      onPressed: onPressed,
      child: const Icon(Icons.add, color: Colors.white),
    );
  }
}
