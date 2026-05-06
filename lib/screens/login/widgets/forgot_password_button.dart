import 'package:flutter/material.dart';

// =============================================================================
// FORGOT PASSWORD BUTTON
// =============================================================================
// Text button shown below the Sign In button. Currently just shows a snackbar
// telling the user to contact admin (no self-service reset flow exists).
// =============================================================================

class ForgotPasswordButton extends StatelessWidget {
  const ForgotPasswordButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contact admin to reset password'),
          ),
        );
      },
      child: const Text('Forgot Password?'),
    );
  }
}
