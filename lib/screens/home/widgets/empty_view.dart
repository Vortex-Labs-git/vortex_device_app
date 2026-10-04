import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// EMPTY VIEW
// =============================================================================
// Shown when device loading is complete but the user has no devices assigned.
// A sprout illustration and one plain next step — contact Vortex Labs to get
// devices assigned. Static, no callbacks.
// =============================================================================

class EmptyView extends StatelessWidget {
  const EmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 36, 32, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 150,
              height: 120,
              child: CustomPaint(painter: _SproutPainter()),
            ),
          ),
          SizedBox(height: 18),
          Text(
            'Plant your first device',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GlassTokens.displayFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: GlassTokens.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'No devices are assigned to your account yet. Please contact '
            'Vortex Labs to get your valves, sensors and plugs added.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: GlassTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// Soil shadow, a stem with two leaves, and a small gold sun.
class _SproutPainter extends CustomPainter {
  const _SproutPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(75, 104), width: 120, height: 20),
      Paint()..color = GlassTokens.sunk,
    );
    canvas.drawLine(
      const Offset(75, 102),
      const Offset(75, 60),
      Paint()
        ..color = GlassTokens.primary
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    final Path left = Path()
      ..moveTo(75, 70)
      ..cubicTo(75, 52, 61, 40, 39, 40)
      ..cubicTo(39, 58, 53, 70, 75, 70)
      ..close();
    canvas.drawPath(left, Paint()..color = GlassTokens.primary);
    final Path right = Path()
      ..moveTo(75, 60)
      ..cubicTo(75, 45, 87, 32, 107, 32)
      ..cubicTo(107, 48, 95, 60, 75, 60)
      ..close();
    canvas.drawPath(right, Paint()..color = GlassTokens.primaryDeep);
    canvas.drawCircle(
        const Offset(118, 22), 9, Paint()..color = GlassTokens.gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
