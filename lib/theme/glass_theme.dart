import 'package:flutter/material.dart';

// =============================================================================
// GLASS THEME
// =============================================================================
// Design tokens + the global ThemeData behind the app's frosted-glass look.
//
// The visual language is: a soft indigo/violet/cyan gradient backdrop, and
// every surface on top of it is a translucent, blurred "pane" with a bright
// hairline edge and a low, wide shadow. Nothing is fully opaque, so the
// backdrop keeps showing through the whole UI.
//
// The widgets that actually draw the panes live in widgets/glass/. This file
// only holds the numbers and colors they share, so the whole look can be
// retuned from one place.
//
// NOTE ON ThemeData: only theme slots whose type has been stable across
// Flutter versions are set here (SnackBarThemeData, SwitchThemeData, ...).
// Surfaces that Flutter has been renaming (cards, dialogs, app bars, input
// decorations) are styled by the explicit glass widgets and by
// glassInputDecoration() below instead, so this file does not depend on which
// side of those migrations the local SDK sits on.
// =============================================================================

class GlassTokens {
  GlassTokens._();

  // ---------------------------------------------------------------------------
  // SECTION 1: BRAND + STATUS COLORS
  // ---------------------------------------------------------------------------
  // Kept close to the original indigo so the app still feels like the same
  // product — only the surfaces changed, not the brand.

  static const Color primary = Color(0xFF3F51B5);
  static const Color primaryBright = Color(0xFF5C6BC0);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF22B8CF);

  static const Color success = Color(0xFF15A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE11D48);

  // ---------------------------------------------------------------------------
  // SECTION 2: BACKDROP
  // ---------------------------------------------------------------------------
  // The gradient the glass panes blur. Light enough that the dark text used
  // across the app stays readable without restyling every Text widget.

  static const Color bgTop = Color(0xFFEDF0FF);
  static const Color bgMid = Color(0xFFF4F1FE);
  static const Color bgBottom = Color(0xFFE7F3FF);

  // ---------------------------------------------------------------------------
  // SECTION 3: TEXT
  // ---------------------------------------------------------------------------

  static const Color textPrimary = Color(0xFF1A1D3A);
  static const Color textSecondary = Color(0xFF5B6180);
  static const Color textMuted = Color(0xFF8A90AC);

  // ---------------------------------------------------------------------------
  // SECTION 4: GEOMETRY + BLUR
  // ---------------------------------------------------------------------------

  static const double radiusLg = 24;
  static const double radiusMd = 18;
  static const double radiusSm = 12;

  /// Blur strength for panes sitting directly on the backdrop.
  static const double blur = 18;

  /// Lighter blur for small chips and pills, where a heavy blur reads as muddy.
  static const double blurSoft = 12;

  /// Heavier blur for chrome that must stay legible over scrolling content
  /// (app bars, bottom nav, dialogs).
  static const double blurStrong = 26;

  // ---------------------------------------------------------------------------
  // SECTION 5: SURFACE RECIPES
  // ---------------------------------------------------------------------------

  /// The two-stop sheen every pane is filled with. [tint] pulls the glass
  /// towards a status color (green for online, red for errors, ...).
  static LinearGradient paneGradient({
    Color? tint,
    double tintStrength = 0.35,
    double topAlpha = 0.62,
    double bottomAlpha = 0.34,
  }) {
    final Color base = tint == null
        ? Colors.white
        : Color.lerp(Colors.white, tint, tintStrength)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        base.withValues(alpha: topAlpha),
        base.withValues(alpha: bottomAlpha),
      ],
    );
  }

  /// The bright hairline that sells the "edge of a pane of glass" illusion.
  static Color paneBorder({Color? tint, double alpha = 0.70}) {
    if (tint == null) return Colors.white.withValues(alpha: alpha);
    return Color.lerp(tint, Colors.white, 0.45)!
        .withValues(alpha: (alpha + 0.05).clamp(0.0, 1.0));
  }

  /// Low, wide, slightly blue shadow — glass floats, it doesn't sit.
  static List<BoxShadow> paneShadow({
    double y = 10,
    double blurRadius = 24,
    double alpha = 0.10,
  }) {
    return [
      BoxShadow(
        color: textPrimary.withValues(alpha: alpha),
        blurRadius: blurRadius,
        offset: Offset(0, y),
      ),
    ];
  }

  /// Gradient used for solid accents (primary buttons, the FAB, avatars).
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBright, violet],
  );

  /// Same idea, tinted to an arbitrary color (status buttons, destructive
  /// actions). Produces a slightly lighter → slightly darker sweep.
  static LinearGradient tintedGradient(Color color) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(color, Colors.white, 0.22)!,
        Color.lerp(color, Colors.black, 0.10)!,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 6: GLOBAL THEME
  // ---------------------------------------------------------------------------

  static ThemeData themeData() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // GlassBackground paints the real gradient. This flat color is the
      // stand-in for screens not yet wrapped in one — transparent would render
      // as black.
      scaffoldBackgroundColor: bgMid,
    );

    return base.copyWith(
      dividerColor: primary.withValues(alpha: 0.14),

      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary.withValues(alpha: 0.92),
        contentTextStyle: const TextStyle(color: Colors.white),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white.withValues(alpha: 0.92),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.white.withValues(alpha: 0.45),
        ),
        trackOutlineColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.70),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}

// =============================================================================
// GLASS INPUT DECORATION
// =============================================================================
// Shared InputDecoration for text fields sitting on glass. Applied per-field
// rather than through ThemeData.inputDecorationTheme — see the note at the top
// of this file.
// =============================================================================

InputDecoration glassInputDecoration({
  String? labelText,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.55),
    hintStyle: const TextStyle(color: GlassTokens.textMuted),
    labelStyle: const TextStyle(color: GlassTokens.textSecondary),
    prefixIconColor: GlassTokens.primary,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(Colors.white.withValues(alpha: 0.75)),
    enabledBorder: border(Colors.white.withValues(alpha: 0.75)),
    focusedBorder: border(GlassTokens.primary.withValues(alpha: 0.55), 1.6),
    errorBorder: border(GlassTokens.danger.withValues(alpha: 0.60)),
    focusedErrorBorder: border(GlassTokens.danger.withValues(alpha: 0.80), 1.6),
  );
}
