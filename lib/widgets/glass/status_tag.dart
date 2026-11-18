import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// STATUS TAG
// =============================================================================
// Small pill for a state or a category: "● Online", "● Offline",
// "Direct connected", "💧 Valve". Pale fill of [color] with text in [color],
// so state never relies on hue alone — there is always a word, and a dot or
// icon.
//
// Factories cover the device states used across the app; the plain
// constructor takes any colour (water / sun / info for device types).
// =============================================================================

class StatusTag extends StatelessWidget {
  final String label;
  final Color color;

  /// Leading icon. Ignored when [showDot] is true.
  final IconData? icon;

  /// Leading filled dot instead of an icon — used for live states.
  final bool showDot;

  /// Fill override. Defaults to [color] mixed into white.
  final Color? background;

  /// Text / dot override. Defaults to [color].
  final Color? foreground;

  const StatusTag({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.showDot = false,
    this.background,
    this.foreground,
  });

  factory StatusTag.online({Key? key, String label = 'Online'}) => StatusTag(
        key: key,
        label: label,
        color: GlassTokens.success,
        showDot: true,
      );

  factory StatusTag.offline({Key? key, String label = 'Offline'}) =>
      StatusTag(
        key: key,
        label: label,
        color: GlassTokens.danger,
        showDot: true,
      );

  /// Direct (AP) link: gold fill with dark text — gold is never text on white.
  factory StatusTag.direct({Key? key, String label = 'Direct connected'}) =>
      StatusTag(
        key: key,
        label: label,
        color: GlassTokens.gold,
        showDot: true,
        background: GlassTokens.goldSoft,
        foreground: GlassTokens.textPrimary,
      );

  @override
  Widget build(BuildContext context) {
    final Color fg = foreground ?? color;
    final Color bg = background ?? Color.lerp(Colors.white, color, 0.12)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                // Direct: gold dot beside dark text.
                color: foreground != null ? color : fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
