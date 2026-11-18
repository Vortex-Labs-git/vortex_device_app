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

  /// Fill color. Defaults to leaf green ([GlassTokens.primary]).
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
                        .withValues(alpha: 0.26),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: disabled ? null : onPressed,
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            splashColor: Colors.white.withValues(alpha: 0.18),
            highlightColor: Colors.white.withValues(alpha: 0.10),
            child: _ButtonContent(
              isLoading: isLoading,
              spinnerColor: Colors.white,
              child: Padding(
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
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
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


class _ButtonContent extends StatelessWidget {
  final bool isLoading;
  final Color spinnerColor;
  final Widget child;

  const _ButtonContent({
    required this.isLoading,
    required this.spinnerColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    const Duration fade = Duration(milliseconds: 160);
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Stays in the layout while loading, so the width never changes.
          AnimatedOpacity(
            opacity: isLoading ? 0 : 1,
            duration: fade,
            curve: Curves.easeOut,
            child: child,
          ),
          // Built ONLY while loading: a CircularProgressIndicator spins even at
          // opacity 0, which would leave every button animating forever and
          // stop the app ever idling.
          if (isLoading)
            IgnorePointer(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
                ),
              ),
            ),
        ],
      ),
    );
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
                          fontWeight: FontWeight.w800,
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
// GLASS ICON BUTTON
// -----------------------------------------------------------------------------
// Small rounded-square button for chrome (back, profile, more). A bare
// IconButton has almost no visible affordance, so this gives it a white tile
// with a hairline plus a press-down scale — the touch feedback a ripple alone
// doesn't provide on a light background.
// -----------------------------------------------------------------------------

class GlassIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  /// Small colored dot on the upper-right of the button, for unread/live hints.
  final Color? badgeColor;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
    this.color,
    this.badgeColor,
  });

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final Color fg = widget.color ?? GlassTokens.primary;

    Widget button = AnimatedScale(
      scale: _pressed ? 0.90 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.size * 0.35),
          color: _pressed ? GlassTokens.leafSoft : GlassTokens.surface,
          border: Border.all(color: GlassTokens.border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onPressed,
            onTapDown: (_) => _setPressed(true),
            onTapUp: (_) => _setPressed(false),
            onTapCancel: () => _setPressed(false),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.size * 0.35),
            ),
            splashColor: fg.withValues(alpha: 0.14),
            child: Icon(widget.icon, size: widget.size * 0.52, color: fg),
          ),
        ),
      ),
    );

    if (widget.badgeColor != null) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: 1,
            right: 1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: widget.badgeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

// -----------------------------------------------------------------------------
// GLASS FAB
// -----------------------------------------------------------------------------
// Rounded-square leaf action button with a soft green glow. Not a Material
// FAB — it needs the same fill + shadow as GlassButton, which
// FloatingActionButton can't do without fighting its own elevation and splash.
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
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: GlassTokens.accentGradient,
        boxShadow: [
          BoxShadow(
            color: GlassTokens.primary.withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(size * 0.34),
          ),
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
