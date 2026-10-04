import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// ERROR VIEW
// =============================================================================
// Shown when there's an error message AND no cached devices to display.
// Shows the error icon, message, and a Retry button that re-runs initialization.
//
// A white card with a red icon tile: the failure reads at a glance, and the
// message stays in dark, easy-to-read text.
// =============================================================================

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Error icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: GlassTokens.dangerSoft,
                ),
                child: const Icon(
                  Icons.wifi_off,
                  size: 34,
                  color: GlassTokens.danger,
                ),
              ),

              const SizedBox(height: 18),

              // Error message text
              Text(
                message,
                style: const TextStyle(
                  color: GlassTokens.textPrimary,
                  fontSize: 14.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 22),

              // Retry button
              GlassButton(
                label: 'Retry',
                icon: Icons.refresh,
                fullWidth: false,
                height: 48,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
