import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// APP THEME  (file kept at theme/glass_theme.dart so imports stay stable)
// =============================================================================
// The frosted-glass look was replaced with a flat, high-contrast blue system.
//
// WHY FLAT:
//   Glass panes only read as glass when something interesting shows through
//   them, which means a busy backdrop, translucency and a live BackdropFilter
//   on every surface. That cost real frames on mid-range hardware, and outdoors
//   — where this app is actually used — translucency is the first thing to go
//   muddy. Opaque surfaces with a hairline border give the same separation for
//   one draw call and stay readable in daylight.
//
// THE SYSTEM:
//   ground    #E3F2FD   the page sits on tinted blue, not white
//   surface   #FFFFFF   cards are the only pure white, so they read as raised
//                       without needing a shadow
//   border    #C9DFF5   1px hairline; separation comes from the edge, not blur
//   primary   #0D47A1   every filled control and its white label
//   accent    #2196F3   icons, focus rings, selected states, emphasis borders
//   subtle    #90CAF9   quiet fills, dividers, disabled states
//
// THE ONE CONTRAST TRAP:
//   White text on #2196F3 is 3.1:1 — it FAILS WCAG AA for body text. So the
//   mid blue is never a fill behind a label; filled controls use #0D47A1
//   (white on it is 9.3:1). #2196F3 is for icons, borders and large text only.
//   Every text colour below was checked against the surface it sits on.
//
// COMPATIBILITY: the old token names (paneGradient, accentGradient, blur, ...)
// are all still here so the ~50 screens built against them keep compiling. The
// gradients now return flat single-colour fills, and the blur constants are 0,
// which makes the glass widgets skip their BackdropFilter entirely.
// =============================================================================

class GlassTokens {
  GlassTokens._();

  // ---------------------------------------------------------------------------
  // SECTION 1: BRAND + STATUS COLORS
  // ---------------------------------------------------------------------------

  /// Filled controls and their white labels. White on this is 9.3:1.
  static const Color primary = Color(0xFF0D47A1);

  /// Kept for API compatibility; both now resolve to the same solid blue so
  /// anything that used to draw a sweep draws a flat fill instead.
  static const Color primaryBright = Color(0xFF0D47A1);
  static const Color accent = Color(0xFF0D47A1);

  /// Mid blue — icons, focus rings, selected outlines, large text.
  /// 3.1:1 on white, so NEVER put small text or a white label on it.
  static const Color interactive = Color(0xFF2196F3);

  /// Light blue for quiet fills, dividers and disabled states.
  /// Decoration only — 1.7:1 on white.
  static const Color aqua = Color(0xFF90CAF9);
  static const Color subtle = Color(0xFF90CAF9);

  // Status colours. Deliberately outside the blue family: blue is the brand,
  // so it cannot also mean "online". Each is checked on white.
  static const Color success = Color(0xFF1B7F4B); // 5.06:1
  static const Color warning = Color(0xFFB45309); // 4.88:1
  static const Color danger = Color(0xFFC62828); // 5.35:1

  /// Fourth category hue for sensor-driven mode, which sits beside manual
  /// (brand blue) and schedule (amber) and must not read as either. Violet is
  /// the only family left that clashes with neither. 7.02:1.
  static const Color info = Color(0xFF6D28D9);

  // ---------------------------------------------------------------------------
  // SECTION 2: SURFACES
  // ---------------------------------------------------------------------------

  /// The tinted page ground. Cards are white on top of it.
  static const Color ground = Color(0xFFE3F2FD);

  /// Card / sheet fill. The only pure white in the system.
  static const Color surface = Color(0xFFFFFFFF);

  /// 1px hairline that separates a surface from the ground. This does the job
  /// blur and shadow used to do.
  static const Color border = Color(0xFFC9DFF5);

  // Backdrop stops are all the same value now: the background is flat.
  static const Color bgTop = ground;
  static const Color bgMid = ground;
  static const Color bgBottom = ground;

  // ---------------------------------------------------------------------------
  // SECTION 3: TEXT
  // ---------------------------------------------------------------------------
  // Measured on white (#FFFFFF). All three clear AA; the first two clear AAA.

  static const Color textPrimary = Color(0xFF0F1E33); // 15.8:1
  static const Color textSecondary = Color(0xFF42546B); //  7.6:1
  static const Color textMuted = Color(0xFF64748B); //  4.8:1

  // ---------------------------------------------------------------------------
  // SECTION 4: GEOMETRY
  // ---------------------------------------------------------------------------
  // Tighter than the glass build. Large radii plus translucency reads as
  // consumer/playful; a utility tool people operate in a field wants edges that
  // look engineered.

  static const double radiusLg = 16;
  static const double radiusMd = 12;
  static const double radiusSm = 8;

  // Blur is off. The glass widgets check these and skip BackdropFilter when
  // they are 0, so no filter layer is created at all.
  static const double blur = 0;
  static const double blurSoft = 0;
  static const double blurStrong = 0;

  // ---------------------------------------------------------------------------
  // SECTION 5: SURFACE RECIPES
  // ---------------------------------------------------------------------------

  /// Flat surface fill. Signature kept from the glass build; the alpha
  /// arguments are ignored because surfaces are opaque now — a half-transparent
  /// card over a flat ground just looks like a lighter card.
  ///
  /// [tint] still works: a status-tinted card is the tint mixed into white at
  /// [tintStrength], which stays light enough for dark text.
  static LinearGradient paneGradient({
    Color? tint,
    double tintStrength = 0.35,
    double topAlpha = 1.0,
    double bottomAlpha = 1.0,
  }) {
    final Color fill = tint == null
        ? surface
        : Color.lerp(surface, tint, tintStrength.clamp(0.0, 0.14))!;
    return LinearGradient(colors: [fill, fill]);
  }

  /// The hairline. Untinted it is the standard border; tinted it takes the
  /// status hue so a warning card is outlined in amber, not blue.
  static Color paneBorder({Color? tint, double alpha = 1.0}) {
    if (tint == null) return border;
    return Color.lerp(tint, Colors.white, 0.55)!;
  }

  /// Barely-there shadow. Separation is the border's job; this only lifts
  /// floating chrome (nav bar, dialogs) a fraction off the content.
  static List<BoxShadow> paneShadow({
    double y = 1,
    double blurRadius = 3,
    double alpha = 0.06,
  }) {
    return [
      BoxShadow(
        color: textPrimary.withValues(alpha: alpha),
        blurRadius: blurRadius,
        offset: Offset(0, y),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // SYSTEM BARS
  // ---------------------------------------------------------------------------
  // The OS draws the clock and battery, and by default colours them from the
  // PHONE's theme — so on a dark-themed phone they come out white and vanish
  // against this app's light chrome. The chrome is light in every state, so we
  // always ask for dark icons rather than leaving it to the OS.

  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS
    systemNavigationBarColor: ground,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );

  /// Solid fill for primary actions. Still a LinearGradient for API
  /// compatibility, but both stops are [primary] — no visible sweep.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [primary, primary],
  );

  /// Same, tinted to an arbitrary status colour.
  static LinearGradient tintedGradient(Color color) {
    return LinearGradient(colors: [color, color]);
  }

  // ---------------------------------------------------------------------------
  // SECTION 6: GLOBAL THEME
  // ---------------------------------------------------------------------------

  static ThemeData themeData() {
    final ColorScheme scheme =
        ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: textPrimary,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: ground,
    );

    return base.copyWith(
      dividerColor: border,

      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
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
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return textMuted.withValues(alpha: 0.55);
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return subtle.withValues(alpha: 0.45);
          }
          return states.contains(WidgetState.selected) ? primary : textMuted;
        }),
        trackOutlineColor:
            WidgetStateProperty.resolveWith((states) => Colors.transparent),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}

// =============================================================================
// INPUT DECORATION
// =============================================================================
// Applied per-field rather than through ThemeData.inputDecorationTheme, whose
// type Flutter has been renaming across versions.
// =============================================================================

InputDecoration glassInputDecoration({
  String? labelText,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: GlassTokens.surface,
    hintStyle: const TextStyle(color: GlassTokens.textMuted),
    labelStyle: const TextStyle(color: GlassTokens.textSecondary),
    prefixIconColor: GlassTokens.interactive,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(GlassTokens.border),
    enabledBorder: border(GlassTokens.border),
    // A 2px mid-blue ring is the focus indicator — visible without shifting
    // layout, which a width change on the whole field would do.
    focusedBorder: border(GlassTokens.interactive, 2),
    errorBorder: border(GlassTokens.danger),
    focusedErrorBorder: border(GlassTokens.danger, 2),
  );
}
