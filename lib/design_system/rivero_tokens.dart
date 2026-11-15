import 'package:flutter/material.dart';
import 'package:rivero/design_system/look.dart';

/// Semantic colors for Rivero's design system.
/// All hex codes strictly adhere to the approved architecture specifications.
abstract final class RiveroColors {
  /// Set by the app root before building; neutrals below follow it.
  static bool isLight = false;

  // Palette "Ink & Sky": blue-black ink and soft blue in dark mode, warm
  // paper and deeper blue in light mode. One accent; colour is used for
  // meaning (categories, accounts, money in/out), not decoration.

  /// One neutral in each background the user can pick (Appearance):
  /// light paper / white, dark black / charcoal / midnight.
  static Color _bg(int paper, int white, int black, int charcoal, int night) {
    final look = RiveroLook.current;
    if (isLight) {
      return Color(
        look.lightBackground == LightBackground.white ? white : paper,
      );
    }
    return Color(switch (look.darkBackground) {
      DarkBackground.black => black,
      DarkBackground.charcoal => charcoal,
      DarkBackground.midnight => night,
    });
  }

  // --- Core surfaces ---
  static Color get background =>
      _bg(0xFFF6F3EE, 0xFFF3F4F6, 0xFF000000, 0xFF121214, 0xFF060A12);
  static Color get surface =>
      _bg(0xFFFFFFFF, 0xFFFFFFFF, 0xFF0F0F11, 0xFF1B1B1E, 0xFF0E1420);
  static Color get surfaceElevated =>
      _bg(0xFFEFEBE4, 0xFFECEEF1, 0xFF18181B, 0xFF242428, 0xFF151D2D);
  static Color get surfaceInteractive =>
      _bg(0xFFE5E0D7, 0xFFE1E4E9, 0xFF232327, 0xFF2E2E33, 0xFF1D283C);

  /// Text/icon colour that sits on [accent]: dark on a light accent, white
  /// on a dark one, whichever accent was picked.
  static Color get onAccent =>
      ThemeData.estimateBrightnessForColor(accent) == Brightness.light
      ? const Color(0xFF04101F)
      : const Color(0xFFFFFFFF);

  /// The one interactive accent (selection, primary buttons, active tab).
  static Color get accent {
    final a = AccentChoice.all[RiveroLook.current.accent];
    return isLight ? a.light : a.dark;
  }

  // --- Role accents (shared with the category palette) ---
  static const Color salaryAccent = Color(0xFFF5B841); // amber
  static const Color expenseAccent = Color(0xFF4EA3F8); // blue
  static const Color investmentAccent = Color(0xFF8B6CF6); // violet
  static const Color savingsAccent = Color(0xFF22B8B0); // teal
  static const Color mandateWarning = Color(0xFFF2555A); // coral
  static const Color customAccent = Color(0xFFFF8A3D); // orange
  static const Color liabilityAccent = Color(0xFFFF8A3D); // orange
  static const Color walletAccent = Color(0xFF5AC8FA); // sky

  /// Distinct colours for categories and accounts (Slice-like, no pink):
  /// saturated enough to tell apart on pure black, never neon.
  static const List<Color> categorical = [
    Color(0xFF4EA3F8), // blue
    Color(0xFFFF8A3D), // orange
    Color(0xFFF2555A), // coral
    Color(0xFF8B6CF6), // violet
    Color(0xFF2DBE6C), // green
    Color(0xFFF5B841), // amber
    Color(0xFF22B8B0), // teal
    Color(0xFF5AC8FA), // sky
  ];

  // --- Semantic ---
  static const Color success = Color(0xFF2DBE6C); // money in
  static const Color danger = Color(0xFFF0616D);
  static const Color info = Color(0xFF4EA3F8);
  static const Color warning = Color(0xFFF2A93B);

  // --- Text ---
  static Color get textPrimary =>
      isLight ? const Color(0xFF14171C) : const Color(0xFFF5F5F7);
  static Color get textSecondary =>
      isLight ? const Color(0xFF4E5562) : const Color(0xFFA1A1AA);
  static Color get textMuted =>
      isLight ? const Color(0xFF7A8190) : const Color(0xFF71717A);
  static Color get textDisabled =>
      isLight ? const Color(0xFFA9AEB8) : const Color(0xFF52525B);

  // --- Borders ---
  static Color get borderSubtle =>
      _bg(0xFFE3DED5, 0xFFE3E5EA, 0xFF1C1C1F, 0xFF2A2A2E, 0xFF1A2333);
  static Color get borderMedium =>
      _bg(0xFFD4CEC3, 0xFFD2D6DD, 0xFF27272B, 0xFF343439, 0xFF243047);
  static Color get borderHighlight =>
      _bg(0xFFBDB6A9, 0xFFB8BEC8, 0xFF36363C, 0xFF44444A, 0xFF33415C);
}

/// Spacing scale based on an 8-point / 4-point harmonic grid.
abstract final class RiveroSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

/// Border radius scale.
abstract final class RiveroRadii {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double full = 9999;

  static const BorderRadius borderXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius borderSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius borderXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius borderFull = BorderRadius.all(
    Radius.circular(full),
  );

  /// Corners of cards, as picked in Appearance.
  static BorderRadius get card =>
      BorderRadius.circular(RiveroLook.current.corners);
}

/// Fonts bundled with the app (SIL Open Font License, see assets/fonts).
abstract final class RiveroFonts {
  /// Every family the user can choose, first is the default.
  /// Urbanist is the closest open-licence match to Slice's typeface.
  static const families = [
    'Urbanist',
    'Inter',
    'Plus Jakarta Sans',
    'Manrope',
    'DM Sans',
  ];

  static const mono = 'JetBrains Mono';

  /// Set by the app root before building, like [RiveroColors.isLight].
  static String current = families.first;

  /// [current] at the weight picked in Appearance: a sibling family (see
  /// pubspec) whose every weight is drawn one or two steps lighter or
  /// heavier, so ALL text follows, whatever weight a screen asks for.
  static String get active => switch (RiveroLook.current.weight) {
    -1 => '$current Light',
    1 => '$current Bold',
    2 => '$current Heavy',
    _ => current,
  };
}

/// Typography scale implementing:
/// - Plus Jakarta Sans for headings & financial counters
/// - Inter for general UI text
/// - JetBrains Mono for account masks, transaction references, and timestamps
abstract final class RiveroTypography {
  // --- Plus Jakarta Sans: Financial Counters & Display ---
  static TextStyle get financialHero => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 52 * RiveroLook.current.heroScale,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get financialLarge => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get financialMedium => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get displayLarge => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get displayMedium => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: RiveroColors.textPrimary,
  );

  // --- Inter: UI Text ---
  static TextStyle get titleLarge => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get titleMedium => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get bodyLarge => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get bodyMedium => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textSecondary,
  );

  static TextStyle get bodySmall => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textMuted,
  );

  static TextStyle get labelLarge => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get labelSmall => TextStyle(
    fontFamily: RiveroFonts.active,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: RiveroColors.textSecondary,
  );

  // --- JetBrains Mono: Account Masks, References, Timestamps ---
  static TextStyle get monoLarge => TextStyle(
    fontFamily: RiveroFonts.mono,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get monoMedium => TextStyle(
    fontFamily: RiveroFonts.mono,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textSecondary,
  );

  static TextStyle get monoSmall => TextStyle(
    fontFamily: RiveroFonts.mono,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textMuted,
  );
}

/// Rivero Theme configuration for MaterialApp.
abstract final class RiveroTheme {
  static ThemeData get darkTheme => build(light: false);
  static ThemeData get lightTheme => build(light: true);

  /// Builds the theme and points [RiveroColors] neutrals at the same mode,
  /// so widgets reading `RiveroColors.*` match the Material theme.
  static ThemeData build({required bool light, String? font, Look? look}) {
    RiveroColors.isLight = light;
    if (look != null) RiveroLook.current = look;
    if (font != null && RiveroFonts.families.contains(font)) {
      RiveroFonts.current = font;
    }
    final scheme = light
        ? ColorScheme.light(
            surface: RiveroColors.surface,
            onSurface: RiveroColors.textPrimary,
            primary: RiveroColors.accent,
            onPrimary: RiveroColors.onAccent,
            secondary: RiveroColors.accent,
            secondaryContainer: RiveroColors.accent.withValues(alpha: 0.2),
            error: RiveroColors.danger,
          )
        : ColorScheme.dark(
            surface: RiveroColors.surface,
            onSurface: RiveroColors.textPrimary,
            primary: RiveroColors.accent,
            onPrimary: RiveroColors.onAccent,
            secondary: RiveroColors.accent,
            secondaryContainer: RiveroColors.accent.withValues(alpha: 0.2),
            onSecondary: RiveroColors.background,
            error: RiveroColors.danger,
            onError: RiveroColors.textPrimary,
          );
    return ThemeData(
      useMaterial3: true,
      fontFamily: RiveroFonts.active,
      brightness: light ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: RiveroColors.background,
      colorScheme: scheme,
      // No ink splash spreading past a control's visible shape; press states
      // come from highlights clipped to the same shape (or the card's scale).
      splashFactory: NoSplash.splashFactory,
      highlightColor: RiveroColors.textPrimary.withValues(alpha: 0.06),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? RiveroColors.accent
                : RiveroColors.surfaceElevated,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? RiveroColors.onAccent
                : RiveroColors.textSecondary,
          ),
          side: WidgetStateProperty.all(BorderSide.none),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: RiveroColors.surfaceElevated,
        selectedColor: RiveroColors.accent,
        side: BorderSide(color: RiveroColors.borderMedium),
        // Selected chips are solid accent; their text flips to a dark/white
        // colour that stays readable on it.
        labelStyle: TextStyle(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? RiveroColors.onAccent
                : RiveroColors.textPrimary,
          ),
          fontWeight: FontWeight.w600,
        ),
        checkmarkColor: RiveroColors.accent,
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: RiveroRadii.borderLg),
      ),
      cardTheme: CardThemeData(
        color: RiveroColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: RiveroRadii.borderMd,
          side: BorderSide(color: RiveroColors.borderSubtle),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: RiveroColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: RiveroColors.textPrimary),
      ),
      // Hints/helpers are clearly secondary: muted grey, never body-text bright.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RiveroColors.surfaceElevated,
        hintStyle: TextStyle(color: RiveroColors.textMuted),
        helperStyle: TextStyle(color: RiveroColors.textMuted, fontSize: 12),
        labelStyle: TextStyle(color: RiveroColors.textSecondary),
        floatingLabelStyle: TextStyle(color: RiveroColors.textPrimary),
        prefixStyle: TextStyle(color: RiveroColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: RiveroSpacing.lg,
          vertical: RiveroSpacing.md,
        ),
        border: const OutlineInputBorder(
          borderRadius: RiveroRadii.borderMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: RiveroRadii.borderMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: RiveroRadii.borderMd,
          borderSide: BorderSide(color: RiveroColors.borderHighlight),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: RiveroColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
