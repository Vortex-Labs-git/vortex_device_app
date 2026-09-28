import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// PLUG MANUAL CARD
// =============================================================================
// Manual control of the selected base: the current state on top, the live
// wattage, and one round ON/OFF button.
//
// TWO FIELDS, ONE TRUTH:
//   base.usrState  usr_state — the COMMAND. The app writes it; the plug reads it.
//   base.state     state     — what the PLUG REPORTS it actually did.
// Everything shown as "current state" is [PlugBase.state], so the user only
// ever sees ON once the plug itself says ON. A command the plug hasn't carried
// out yet (usrState != state) is shown as a separate warning line.
//
// The plug's version of ValveControlCard. After a tap the parent waits for the
// plug to report the new state; while it waits ([waitingForConfirmation]) the
// button is locked and shows the countdown.
// =============================================================================

class PlugManualCard extends StatelessWidget {
  final PlugBase base;

  /// True while the REST request is in flight.
  final bool isUpdating;

  /// True while waiting for the plug to report [pendingState].
  final bool waitingForConfirmation;
  final bool? pendingState;
  final int confirmationCountdown;

  /// Receives the state to switch TO (true = ON).
  final ValueChanged<bool> onToggle;

  const PlugManualCard({
    super.key,
    required this.base,
    required this.isUpdating,
    required this.waitingForConfirmation,
    required this.pendingState,
    required this.confirmationCountdown,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool on = base.state;
    final bool busy = isUpdating || waitingForConfirmation;
    final Color stateColor = on ? GlassTokens.success : GlassTokens.textMuted;

    // The button offers the opposite of the current state.
    final Color buttonColor = on ? GlassTokens.danger : GlassTokens.success;

    // A command is stored but the plug hasn't carried it out, and we're not
    // counting down for it any more (timed out, or the screen was reopened).
    final bool commandNotApplied =
        !busy && base.usrState != base.state;

    final String hint;
    if (commandNotApplied) {
      hint = 'Requested ${base.usrState ? 'ON' : 'OFF'} — '
          '${base.name} has not switched yet';
    } else if (waitingForConfirmation) {
      hint = 'Waiting for ${base.name} to turn '
          '${pendingState == true ? 'ON' : 'OFF'} … ${confirmationCountdown}s';
    } else if (isUpdating) {
      hint = 'Sending…';
    } else {
      hint = 'Tap to switch ${base.name}';
    }

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Plug control',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),

          const SizedBox(height: 8),

          // ─── Current state ──────────────────────────────────────────────
          const Text(
            'Current state',
            style: TextStyle(fontSize: 13, color: GlassTokens.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            on ? 'ON' : 'OFF',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: stateColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${base.wattageLabel} now',
            style: const TextStyle(
              fontSize: 13,
              color: GlassTokens.textSecondary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Round ON/OFF button ────────────────────────────────────────
          SizedBox(
            width: 132,
            height: 132,
            child: Material(
              color: busy ? buttonColor.withValues(alpha: 0.6) : buttonColor,
              shape: const CircleBorder(),
              elevation: busy ? 0 : 6,
              shadowColor: GlassTokens.textPrimary.withValues(alpha: 0.35),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : () => onToggle(!on),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(
                        Icons.power_settings_new,
                        size: 44,
                        color: Colors.white,
                      ),
                    const SizedBox(height: 6),
                    Text(
                      busy ? 'Waiting…' : (on ? 'Turn OFF' : 'Turn ON'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: commandNotApplied
                  ? GlassTokens.warning
                  : GlassTokens.textMuted,
              fontWeight:
                  commandNotApplied ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
