import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// LOGIN ICON
// =============================================================================
// The Vortex Labs logo on a white rounded tile, top-left of the forest header.
// The logo keeps its own navy — it is the one place the old brand colour
// stays. Falls back to a leaf icon if the image is missing.
// =============================================================================

class LoginIcon extends StatelessWidget {
  final double size;

  const LoginIcon({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.31),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        'assets/images/logo.jpeg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          Icons.eco_rounded,
          size: size * 0.55,
          color: GlassTokens.forest,
        ),
      ),
    );
  }
}
