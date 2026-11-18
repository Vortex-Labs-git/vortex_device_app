import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/glass_theme.dart';

// =============================================================================
// FOREST HEADER
// =============================================================================
// The brand band at the top of Home, the device screens and Login: deep forest
// fill, rounded bottom corners and a soft gold glow in the lower-right — the
// bulb from the logo, lighting the field.
//
// It draws behind the status bar (the app runs edge-to-edge), pads its own
// content below it, and switches the status-bar icons to light while it is on
// screen via AnnotatedRegion. A screen using it needs no AppBar.
//
// View only: whatever goes inside is the caller's [child].
// =============================================================================

class ForestHeader extends StatelessWidget {
  final Widget child;

  /// Padding around [child], below the status bar.
  final EdgeInsetsGeometry padding;

  /// Bottom corner radius. 0 for a square-edged band.
  final double radius;

  /// Draw the gold glow. Off where the header is small (device headers).
  final bool showGlow;

  /// Add the status-bar height above [child]. False when the header sits
  /// lower on the page (e.g. a device card under an app bar).
  final bool coverStatusBar;

  const ForestHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 20),
    this.radius = 28,
    this.showGlow = true,
    this.coverStatusBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final double top =
        coverStatusBar ? MediaQuery.paddingOf(context).top : 0;
    final BorderRadius shape = coverStatusBar
        ? BorderRadius.vertical(bottom: Radius.circular(radius))
        : BorderRadius.circular(radius);

    final Widget band = ClipRRect(
      borderRadius: shape,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: GlassTokens.forest),
        child: Stack(
          children: [
            if (showGlow)
              Positioned(
                right: -40,
                bottom: -70,
                child: IgnorePointer(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          GlassTokens.gold.withValues(alpha: 0.26),
                          GlassTokens.gold.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(top: top),
              child: Padding(
                padding: padding,
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!coverStatusBar) return band;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: GlassTokens.systemOverlayOnForest,
      child: band,
    );
  }
}

// -----------------------------------------------------------------------------
// FOREST STAT
// -----------------------------------------------------------------------------
// One translucent tile for a header summary row: an optional icon chip, a big
// number and a small label ("4/5" / "devices online"). [highlight] paints the
// number gold. [iconColor] tints the icon — use the light "on forest"
// category hues from [ForestStat] (water, sensor, plug) so they read on green.
// -----------------------------------------------------------------------------

class ForestStat extends StatelessWidget {
  final String value;
  final String label;
  final bool highlight;
  final IconData? icon;
  final Color? iconColor;

  // Category hues lifted for the forest background (the on-white versions —
  // water / info / sun — are too dark to read on green).
  // Kept as aliases; the values live in GlassTokens.
  static const Color onForestWater = GlassTokens.onForestWater;
  static const Color onForestSensor = GlassTokens.onForestSensor;
  static const Color onForestPlug = GlassTokens.onForestPlug;

  const ForestStat({
    super.key,
    required this.value,
    required this.label,
    this.highlight = false,
    this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: iconColor ?? Colors.white),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            value,
            style: TextStyle(
              fontFamily: GlassTokens.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              height: 1.1,
              color: highlight ? GlassTokens.gold : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.75),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
