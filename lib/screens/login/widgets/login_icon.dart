import 'package:flutter/material.dart';
import '../../../utils/constants.dart';

// =============================================================================
// LOGIN ICON
// =============================================================================
// Circular avatar-style icon shown at the top of the login card.
// =============================================================================

class LoginIcon extends StatelessWidget {
  const LoginIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person,
        size: 60,
        color: Colors.white,
      ),
    );
  }
}
