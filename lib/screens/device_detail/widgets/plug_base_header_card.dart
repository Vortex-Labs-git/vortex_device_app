import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// PLUG BASE HEADER CARD
// =============================================================================
// Top of the selected base's section: plug icon | base name + Edit,
// "Base A · 1180 W" | ON/OFF badge.
//
// Always shows the state the PLUG REPORTS — a pending command is shown by
// PlugManualCard, not here.
// =============================================================================

class PlugBaseHeaderCard extends StatelessWidget {
  final PlugBase base;
  final VoidCallback onEditName;

  const PlugBaseHeaderCard({
    super.key,
    required this.base,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    final bool on = base.state;
    final Color stateColor = on ? GlassTokens.success : GlassTokens.textMuted;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // ─── Plug icon tile ─────────────────────────────────────────────
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.power, color: stateColor),
          ),

          const SizedBox(width: 12),

          // ─── Name + Edit, then "Base A · 1180 W" ────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        base.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: GlassTokens.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onEditName,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Edit',
                        style: TextStyle(color: GlassTokens.primary),
                      ),
                    ),
                  ],
                ),
                Text(
                  'Base ${base.id.letter} · ${base.wattageLabel}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: GlassTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),

          // ─── ON / OFF badge ─────────────────────────────────────────────
          GlassPill(
            tint: stateColor,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              on ? 'ON' : 'OFF',
              style: TextStyle(
                color: stateColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}