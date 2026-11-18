import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// PLUG MANUAL CARD  (UI v2)
// =============================================================================
// Manual control of the selected socket: "PUMP IS ON · 62.4 W NOW" on top,
// one big round power button, and a hint line.
//
//   ON   green button with a soft green ring — "Turn OFF"
//   OFF  white button with a grey ring       — "Turn ON"
//   busy spinner + "Sending…" / "Waiting… 7s" while the plug confirms
//
// TWO FIELDS, ONE TRUTH:
//   base.usrState  usr_state — the COMMAND. The app writes it; the plug reads it.
//   base.state     state     — what the PLUG REPORTS it actually did.
// Everything shown as "current state" is [PlugBase.state], so the user only
// ever sees ON once the plug itself says ON. A command the plug hasn't carried
// out yet (usrState != state) is shown as a separate warning line.
//
// After a tap the parent waits for the plug to report the new state; while it
// waits ([waitingForConfirmation]) the button is locked and shows the
// countdown.
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

    // A command is stored but the plug hasn't carried it out, and we're not
    // counting down for it any more (timed out, or the screen was reopened).
    final bool commandNotApplied = !busy && base.usrState != base.state;

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

    final String label = waitingForConfirmation
        ? 'Waiting… ${confirmationCountdown}s'
        : isUpdating
            ? 'Sending…'
            : on
                ? 'Turn OFF'
                : 'Turn ON';

    // The button keeps the current state's look while busy, faded.
    final Color fill = on ? GlassTokens.primary : GlassTokens.surface;
    final Color fg = on ? Colors.white : GlassTokens.textSecondary;
    final Color ring = on ? GlassTokens.leafSoft : GlassTokens.sunk;

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          Text(
            '${base.name} is ${on ? 'ON · ${base.wattageLabel} now' : 'OFF'}'
                .toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: GlassTokens.textMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),

          const SizedBox(height: 22),

          // ─── Round power button ─────────────────────────────────────────
          Semantics(
            button: true,
            enabled: !busy,
            label: label,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
              child: Opacity(
                opacity: busy ? 0.7 : 1,
                child: SizedBox(
                  width: 132,
                  height: 132,
                  child: Material(
                    color: fill,
                    shape: CircleBorder(
                      side: on
                          ? BorderSide.none
                          : const BorderSide(
                              color: GlassTokens.border, width: 2),
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: busy ? null : () => onToggle(!on),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (busy)
                            SizedBox(
                              width: 34,
                              height: 34,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: on ? Colors.white : GlassTokens.gold,
                              ),
                            )
                          else
                            Icon(
                              Icons.power_settings_new_rounded,
                              size: 42,
                              color: fg,
                            ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: commandNotApplied
                  ? GlassTokens.warning
                  : GlassTokens.textMuted,
              fontWeight:
                  commandNotApplied ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
