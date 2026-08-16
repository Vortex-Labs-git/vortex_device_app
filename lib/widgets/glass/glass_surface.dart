import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// GLASS SURFACE
// =============================================================================
// The one primitive every other glass widget is built from: a rounded pane
// that blurs whatever is behind it, fills itself with a translucent sheen,
// and draws a bright hairline edge plus a soft drop shadow.
//
// Layer order (back to front):
//   1. drop shadow      — on the outer container, outside the clip
//   2. BackdropFilter   — blurs the backdrop, clipped to the rounded rect
//   3. sheen gradient   — the translucent "glass" itself
//   4. hairline border  — the lit edge of the pane
//   5. ink / child      — ripples stay inside the rounded rect
//
// [tint] pulls the whole pane towards a color (green when a device is online,
// red for errors) while keeping it translucent.
//
// PERFORMANCE: BackdropFilter is not free. Panes are wrapped in a
// RepaintBoundary, and callers rendering many at once (list rows) can pass
// a smaller [blur] or set [enableBlur] to false to fall back to a plain
// translucent fill, which is visually close and much cheaper.
// =============================================================================

class GlassSurface extends StatelessWidget {
  final Widget child;

  /// Blur sigma applied to the backdrop. Ignored when [enableBlur] is false.
  final double blur;

  /// Set false to skip the BackdropFilter and keep only the translucent fill.
  final bool enableBlur;

  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Color the glass leans towards. Null = neutral white glass.
  final Color? tint;

  /// How far towards [tint] the fill is pulled (0 = white, 1 = the tint).
  final double tintStrength;

  /// Scales the fill alpha. Below 1 makes a more transparent pane.
  final double opacity;

  final bool showBorder;
  final bool showShadow;

  final double? width;
  final double? height;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = GlassTokens.blur,
    this.enableBlur = true,
    this.borderRadius,
    this.padding,
    this.margin,
    this.tint,
    this.tintStrength = 0.35,
    this.opacity = 1.0,
    this.showBorder = true,
    this.showShadow = true,
    this.width,
    this.height,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(GlassTokens.radiusLg);

    // 1. Content, with the ripple clipped to the pane's own corners.
    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    if (onTap != null || onLongPress != null) {
      content = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          splashColor: GlassTokens.primary.withValues(alpha: 0.10),
          highlightColor: Colors.white.withValues(alpha: 0.18),
          child: content,
        ),
      );
    }

    // 2. The glass itself: sheen + hairline over the blurred backdrop.
    Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        gradient: GlassTokens.paneGradient(
          tint: tint,
          tintStrength: tintStrength,
          topAlpha: 0.62 * opacity,
          bottomAlpha: 0.34 * opacity,
        ),
        borderRadius: radius,
        border: showBorder
            ? Border.all(color: GlassTokens.paneBorder(tint: tint), width: 1)
            : null,
      ),
      child: content,
    );

    if (enableBlur) {
      pane = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: pane,
      );
    }

    // 3. Clip, then hang the shadow off the outer box (shadows must fall
    //    outside the clip or they get cut off).
    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: showShadow ? GlassTokens.paneShadow() : null,
        ),
        child: ClipRRect(borderRadius: radius, child: pane),
      ),
    );
  }
}

// =============================================================================
// GLASS CARD
// =============================================================================
// A GlassSurface pre-set for content blocks: comfortable padding and the
// large corner radius. This is the drop-in replacement for Material `Card`
// throughout the app.
// =============================================================================

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? tint;
  final double tintStrength;
  final double blur;
  final bool enableBlur;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.tint,
    this.tintStrength = 0.35,
    this.blur = GlassTokens.blur,
    this.enableBlur = true,
    this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: padding,
      margin: margin,
      tint: tint,
      tintStrength: tintStrength,
      blur: blur,
      enableBlur: enableBlur,
      borderRadius: borderRadius,
      onTap: onTap,
      child: child,
    );
  }
}

// =============================================================================
// GLASS PILL
// =============================================================================
// Small tinted capsule for statuses and labels — "Online", "Direct mode",
// "Live updates active". Lighter blur than a card so short text stays crisp.
// =============================================================================

class GlassPill extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  const GlassPill({
    super.key,
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    this.margin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      blur: GlassTokens.blurSoft,
      borderRadius: BorderRadius.circular(100),
      padding: padding,
      margin: margin,
      tint: tint,
      tintStrength: 0.42,
      onTap: onTap,
      showShadow: false,
      child: child,
    );
  }
}
