import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// LOGIN FIELD ART
// =============================================================================
// Decorative strip along the bottom of the login header: two rolling green
// hills with crop rows in faint gold running towards the horizon. Painted, not
// an image, so it stays sharp at any width and costs no asset.
// =============================================================================

class LoginFieldArt extends StatelessWidget {
  final double height;

  const LoginFieldArt({super.key, this.height = 104});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _FieldPainter()),
      ),
    );
  }
}

class _FieldPainter extends CustomPainter {
  static const Color _hill = GlassTokens.leafBright;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Back hill.
    final Path back = Path()
      ..moveTo(0, h * 0.42)
      ..quadraticBezierTo(w * 0.5, h * 0.05, w, h * 0.42)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = _hill.withValues(alpha: 0.55));

    // Front hill.
    final Path front = Path()
      ..moveTo(0, h * 0.68)
      ..quadraticBezierTo(w * 0.5, h * 0.36, w, h * 0.68)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = _hill.withValues(alpha: 0.85));

    // Crop rows converging on a point on the back hill.
    final Paint row = Paint()
      ..color = GlassTokens.gold.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    final Offset vanish = Offset(w * 0.5, h * 0.32);
    for (int i = 0; i < 9; i++) {
      final double x = w * (i / 8);
      canvas.drawLine(Offset(x, h), Offset.lerp(Offset(x, h), vanish, 0.62)!, row);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
