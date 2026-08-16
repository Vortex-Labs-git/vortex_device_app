import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';
import 'glass_surface.dart';

// =============================================================================
// GLASS BUTTONS
// =============================================================================
// Two weights, so a screen can show hierarchy without leaving the look:
//
//   GlassButton        — solid gradient fill, for the one primary action
//                        (Sign In, Save, Logout). Reads as "on top of" the
//                        glass rather than made of it.
//   GlassGhostButton   — a glass pane you can press, for secondary actions
//                        (Change WiFi, Calibrate, Retry).
//
// Both handle their own loading spinner and disabled state so callers don't
// have to rebuild that each time.
// =============================================================================

class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Base color for the gradient. Defaults to the brand indigo→violet sweep.
  final Color? color;

  final bool fullWidth;
  final double height;

  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.color,
    this.fullWidth = true,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || isLoading;
    final Gradient gradient = color == null
        ? GlassTokens.accentGradient
        : GlassTokens.tintedGradient(color!);

    final Widget button = Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          boxShadow: disabled
              ? null
              : [
                  BoxShadow(
                    color: (color ?? GlassTokens.primary)
                        .withValues(alpha: 0.32),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: disabled ? null : onPressed,
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.10),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Padding(
                      // Keeps the label off the edges when the button is
                      // shrink-wrapped (fullWidth: false).
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// -----------------------------------------------------------------------------
// GHOST (GLASS) BUTTON
// -----------------------------------------------------------------------------

class GlassGhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Tints the pane and the text — e.g. green for a direct-mode action.
  final Color? tint;

  final bool fullWidth;
  final double height;

  const GlassGhostButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.isLoading = false,
    this.tint,
    this.fullWidth = true,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final bool disabled = onPressed == null || isLoading;
    final Color foreground = tint == null
        ? GlassTokens.primary
        : Color.lerp(tint, Colors.black, 0.30)!;

    final Widget button = Opacity(
      opacity: disabled ? 0.55 : 1,
      child: GlassSurface(
        height: height,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        tint: tint,
        tintStrength: 0.30,
        blur: GlassTokens.blurSoft,
        onTap: disabled ? null : onPressed,
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: foreground, size: 20),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}

// -----------------------------------------------------------------------------
// GLASS FAB
// -----------------------------------------------------------------------------
// Circular gradient action button. Not a Material FAB — it needs the same
// gradient + glass edge as GlassButton, which FloatingActionButton can't do
// without fighting its own elevation and splash.
// -----------------------------------------------------------------------------

class GlassFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;

  const GlassFab({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 60,
  });

  @override
  Widget build(BuildContext context) {
    Widget fab = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: GlassTokens.accentGradient,
        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: GlassTokens.primary.withValues(alpha: 0.38),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          splashColor: Colors.white.withValues(alpha: 0.22),
          child: Icon(icon, color: Colors.white, size: size * 0.44),
        ),
      ),
    );

    if (tooltip != null) {
      fab = Tooltip(message: tooltip!, child: fab);
    }
    return fab;
  }
}
