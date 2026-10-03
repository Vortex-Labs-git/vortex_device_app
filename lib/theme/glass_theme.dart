import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// APP THEME  (file kept at theme/glass_theme.dart so imports stay stable)
// =============================================================================
// UI v2 — "deep forest". A farm-first palette replacing the flat blue system:
//
//   forest    #0E3B2C   brand headers (home hero, device headers, login)
//   leaf      #1F7A4D   every filled control and its white label (5.4:1)
//   gold      #F2B705   highlights on forest, direct-mode states (logo bulb)
//   ground    #F3F6F1   the page sits on a soft field tint, not white
//   surface   #FFFFFF   cards are the only pure white, so they read as raised
//   border    #DCE5DA   1px hairline; separation comes from the edge
//
// Category hues, used for what a control drives rather than for status:
//   water  #1769C2  valve opening      sun  #A8600A  schedules
//   info   #6D28D9  sensor control
//
// CONTRAST: white on leaf is 5.4:1 and white on forest 12:1 (both AA). Gold is
// never used for text on white — only as a fill (with dark text) or on forest.
//
// FONTS (bundled in assets/fonts, declared in pubspec.yaml — no network):
//   Manrope              body + labels (default family)
//   Bricolage Grotesque  titles and big readings ([displayFont])
//
// COMPATIBILITY: the old token names (paneGradient, accentGradient, blur, ...)
// are all still here so the screens built against them keep compiling. Names
// like [primary] / [interactive] / [aqua] now resolve to the forest palette.
// =============================================================================

class GlassTokens {
  GlassTokens._();

  // ---------------------------------------------------------------------------
  // SECTION 1: BRAND + STATUS COLORS
  // ---------------------------------------------------------------------------

  /// Leaf green: filled controls and their white labels. White on this 5.4:1.
  static const Color primary = Color(0xFF1F7A4D);

  /// Kept for API compatibility; all resolve to leaf green.
  static const Color primaryBright = primary;
  static const Color accent = primary;

  /// Pressed / hover shade of [primary].
  static const Color primaryDeep = Color(0xFF155C39);

  /// Icons, focus rings, selected outlines. Same leaf green as [primary] —
  /// the old mid-blue had to stay off text; this one is safe everywhere.
  static const Color interactive = primary;

  /// Quiet fills, dividers and disabled states. Decoration only.
  static const Color aqua = Color(0xFFBFDCC9);
  static const Color subtle = aqua;

  /// Pale leaf for selected backgrounds and soft icon wells.
  static const Color leafSoft = Color(0xFFE2F0E6);

  /// Deep forest: brand headers. White on this is 12:1, gold 7:1.
  static const Color forest = Color(0xFF0E3B2C);
  static const Color forest2 = Color(0xFF16503C);

  /// Bulb gold from the logo. A fill (with [onGold] text) or a highlight on
  /// [forest] — never text on white.
  static const Color gold = Color(0xFFF2B705);
  static const Color goldSoft = Color(0xFFFDF3D0);
  static const Color onGold = Color(0xFF1C1500);

  /// Valve opening / water.
  static const Color water = Color(0xFF1769C2);
  static const Color waterSoft = Color(0xFFE3EEFA);

  /// Schedules.
  static const Color sun = Color(0xFFA8600A);
  static const Color sunSoft = Color(0xFFFBEEDC);

  // Status colours — unchanged from v1. Each is checked on white.
  static const Color success = Color(0xFF1B7F4B); // 5.06:1
  static const Color warning = Color(0xFFB45309); // 4.88:1
  static const Color danger = Color(0xFFC62828); // 5.35:1

  /// Sensor-driven mode, beside manual (leaf) and schedule (sun). 7.02:1.
  static const Color info = Color(0xFF6D28D9);

  // ---------------------------------------------------------------------------
  // SECTION 2: SURFACES
  // ---------------------------------------------------------------------------

  /// The page ground. Cards are white on top of it.
  static const Color ground = Color(0xFFF3F6F1);

  /// Card / sheet fill. The only pure white in the system.
  static const Color surface = Color(0xFFFFFFFF);

  /// Recessed fill: segmented-control tracks, empty meters, inset panels.
  static const Color sunk = Color(0xFFEDF2EA);

  /// 1px hairline that separates a surface from the ground.
  static const Color border = Color(0xFFDCE5DA);

  // Backdrop stops are all the same value: the background is flat.
  static const Color bgTop = ground;
  static const Color bgMid = ground;
  static const Color bgBottom = ground;

  // ---------------------------------------------------------------------------
  // SECTION 3: TEXT
  // ---------------------------------------------------------------------------
  // Green-biased neutrals, measured on white. All clear AA.

  static const Color textPrimary = Color(0xFF14231B); // 15.9:1
  static const Color textSecondary = Color(0xFF46574C); //  7.4:1
  static const Color textMuted = Color(0xFF66766B); //  4.8:1

  /// Display face for titles and big numbers. Body text uses the theme
  /// default (Manrope), so most widgets never name a family.
  static const String displayFont = 'BricolageGrotesque';
  static const String bodyFont = 'Manrope';

  // ---------------------------------------------------------------------------
  // SECTION 4: GEOMETRY
  // ---------------------------------------------------------------------------
  // Softer than v1: friendly cards, but still clearly engineered.

  static const double radiusLg = 20;
  static const double radiusMd = 16;
  static const double radiusSm = 12;

  /// Minimum height for anything tappable — usable with wet or gloved hands.
  static const double touchTarget = 48;

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

  /// Soft two-layer lift: a tight contact shadow plus a wide, faint one, so
  /// cards read as raised off the field-tinted ground. The border still does
  /// the separating; this only adds depth.
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
      BoxShadow(
        color: textPrimary.withValues(alpha: alpha * 1.15),
        blurRadius: blurRadius * 6,
        offset: Offset(0, y * 6),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // SYSTEM BARS
  // ---------------------------------------------------------------------------
  // The OS draws the clock and battery, and by default colours them from the
  // PHONE's theme — so on a dark-themed phone they come out white and vanish
  // against this app's light chrome. Never leave it to the OS:
  //   [systemOverlay]          light chrome (app bars, plain screens) → dark icons
  //   [systemOverlayOnForest]  under a forest header → light icons
  // Screens with a ForestHeader wrap themselves in
  // AnnotatedRegion<SystemUiOverlayStyle>(value: systemOverlayOnForest).

  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // Android
    statusBarBrightness: Brightness.light, // iOS
    systemNavigationBarColor: ground,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );

  static const SystemUiOverlayStyle systemOverlayOnForest = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // Android
    statusBarBrightness: Brightness.dark, // iOS
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
      fontFamily: bodyFont,
    );

    return base.copyWith(
      dividerColor: border,

      // Headline / title styles take the display face; body and labels keep
      // Manrope from ThemeData.fontFamily.
      textTheme: base.textTheme
          .apply(bodyColor: textPrimary, displayColor: textPrimary)
          .copyWith(
            displayLarge: base.textTheme.displayLarge
                ?.copyWith(fontFamily: displayFont, color: textPrimary),
            displayMedium: base.textTheme.displayMedium
                ?.copyWith(fontFamily: displayFont, color: textPrimary),
            displaySmall: base.textTheme.displaySmall
                ?.copyWith(fontFamily: displayFont, color: textPrimary),
            headlineLarge: base.textTheme.headlineLarge
                ?.copyWith(fontFamily: displayFont, color: textPrimary),
            headlineMedium: base.textTheme.headlineMedium
                ?.copyWith(fontFamily: displayFont, color: textPrimary),
            headlineSmall: base.textTheme.headlineSmall
                ?.copyWith(fontFamily: displayFont, color: textPrimary),
            titleLarge: base.textTheme.titleLarge?.copyWith(
                fontFamily: displayFont,
                fontWeight: FontWeight.w700,
                color: textPrimary),
          ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: bodyFont,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface,
          minimumSize: const Size(64, touchTarget),
          side: const BorderSide(color: border, width: 1.5),
          textStyle: const TextStyle(
            fontFamily: bodyFont,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontFamily: bodyFont,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: leafSoft,
        side: const BorderSide(color: border),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          fontFamily: bodyFont,
          fontWeight: FontWeight.w700,
          color: textSecondary,
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
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
        backgroundColor: forest,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: bodyFont,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
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
          return states.contains(WidgetState.selected) ? primary : aqua;
        }),
        trackOutlineColor:
            WidgetStateProperty.resolveWith((states) => Colors.transparent),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),

      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: primary,
        inactiveTrackColor: sunk,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
      ),
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
    fillColor: GlassTokens.surface,
    hintStyle: const TextStyle(color: GlassTokens.textMuted),
    labelStyle: const TextStyle(
      color: GlassTokens.textSecondary,
      fontWeight: FontWeight.w600,
    ),
    prefixIconColor: GlassTokens.interactive,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(GlassTokens.border, 1.5),
    enabledBorder: border(GlassTokens.border, 1.5),
    // A 2px leaf ring is the focus indicator — visible without shifting
    // layout, which a width change on the whole field would do.
    focusedBorder: border(GlassTokens.interactive, 2),
    errorBorder: border(GlassTokens.danger),
    focusedErrorBorder: border(GlassTokens.danger, 2),
  );
}
