import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// SETTINGS LIST  (UI v2)
// =============================================================================
// Grouped rows for the Account and About tabs:
//
//   SettingsLabel   small upper-case group title ("ACCOUNT INFO")
//   SettingsGroup   white rounded card holding rows, with hairlines between
//   SettingsRow     tinted icon tile · title / subtitle · chevron (when
//                   tappable)
// =============================================================================

class SettingsLabel extends StatelessWidget {
  final String text;

  const SettingsLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: GlassTokens.textMuted,
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const SettingsGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GlassTokens.surface,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        border: Border.all(color: GlassTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 60,
                color: GlassTokens.border,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? subtitle;

  /// Title colour, e.g. red for Log out.
  final Color? titleColor;

  /// Tappable rows get a chevron unless [showChevron] is false.
  final VoidCallback? onTap;
  final bool showChevron;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 10, 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(GlassTokens.radiusSm - 1),
              ),
              child: Icon(icon, color: iconColor, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: titleColor ?? GlassTokens.textPrimary,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: GlassTokens.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (onTap != null && showChevron)
              const Icon(Icons.chevron_right_rounded,
                  color: GlassTokens.textMuted),
          ],
        ),
      ),
    );
  }
}
