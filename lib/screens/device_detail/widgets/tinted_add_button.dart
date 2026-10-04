import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// TINTED ADD BUTTON  (UI v2)
// =============================================================================
// The big "+ Add rule / Add time / Add slot" button under a list: light green
// fill, dashed green border, bold green label. Shared by the valve and plug
// schedule and sensor-rule cards. Null [onPressed] shows it faded and inert.
// =============================================================================

class TintedAddButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const TintedAddButton({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(GlassTokens.radiusMd);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Material(
        color: GlassTokens.leafSoft,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: CustomPaint(
            painter: _DashedBorderPainter(radius: GlassTokens.radiusMd),
            child: SizedBox(
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_rounded,
                      color: GlassTokens.primary, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: GlassTokens.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final double radius;

  const _DashedBorderPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = GlassTokens.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.75),
        Radius.circular(radius),
      ));
    const double dash = 6;
    const double gap = 4;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.radius != radius;
}
