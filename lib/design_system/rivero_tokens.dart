import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic colors for Rivero's design system.
/// All hex codes strictly adhere to the approved architecture specifications.
abstract final class RiveroColors {
  /// Set by the app root before building; neutrals below follow it.
  static bool isLight = false;

  // Palette "Ink & Sky": blue-black ink and soft blue in dark mode, warm
  // paper and deeper blue in light mode. One accent; colour is used for
  // meaning (categories, accounts, money in/out), not decoration.

  // --- Core surfaces ---
  static Color get background =>
      isLight ? const Color(0xFFF6F3EE) : const Color(0xFF0E1116);
  static Color get surface =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF161B22);
  static Color get surfaceElevated =>
      isLight ? const Color(0xFFEFEBE4) : const Color(0xFF1D232C);
  static Color get surfaceInteractive =>
      isLight ? const Color(0xFFE5E0D7) : const Color(0xFF262D38);

  /// The one interactive accent (selection, primary buttons, active tab).
  static Color get accent =>
      isLight ? const Color(0xFF1A73D9) : const Color(0xFF4EA3F8);

  // --- Role accents (shared with the category palette) ---
  static const Color salaryAccent = Color(0xFFF2B33D); // amber
  static const Color expenseAccent = Color(0xFF4EA3F8); // blue
  static const Color investmentAccent = Color(0xFF9A85F2); // violet
  static const Color savingsAccent = Color(0xFF33B5A5); // teal
  static const Color mandateWarning = Color(0xFFF0717A); // coral
  static const Color customAccent = Color(0xFFE879A9); // pink
  static const Color liabilityAccent = Color(0xFFD9A47A); // sand
  static const Color walletAccent = Color(0xFF6CC4EE); // sky

  /// Distinct, calm colours for categories and accounts.
  static const List<Color> categorical = [
    Color(0xFF4EA3F8), // blue
    Color(0xFFF0717A), // coral
    Color(0xFFF2B33D), // amber
    Color(0xFF9A85F2), // violet
    Color(0xFF33B5A5), // teal
    Color(0xFFE879A9), // pink
    Color(0xFF6CC4EE), // sky
    Color(0xFFD9A47A), // sand
  ];

  // --- Semantic ---
  static const Color success = Color(0xFF34C77B); // money in
  static const Color danger = Color(0xFFF0616D);
  static const Color info = Color(0xFF4EA3F8);
  static const Color warning = Color(0xFFF2A93B);

  // --- Text ---
  static Color get textPrimary =>
      isLight ? const Color(0xFF14171C) : const Color(0xFFF2F4F7);
  static Color get textSecondary =>
      isLight ? const Color(0xFF4E5562) : const Color(0xFFA6AFBD);
  static Color get textMuted =>
      isLight ? const Color(0xFF7A8190) : const Color(0xFF6E7787);
  static Color get textDisabled =>
      isLight ? const Color(0xFFA9AEB8) : const Color(0xFF4B5260);

  // --- Borders ---
  static Color get borderSubtle =>
      isLight ? const Color(0xFFE3DED5) : const Color(0xFF222831);
  static Color get borderMedium =>
      isLight ? const Color(0xFFD4CEC3) : const Color(0xFF2C333D);
  static Color get borderHighlight =>
      isLight ? const Color(0xFFBDB6A9) : const Color(0xFF3A424E);
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
}

/// Typography scale implementing:
/// - Plus Jakarta Sans for headings & financial counters
/// - Inter for general UI text
/// - JetBrains Mono for account masks, transaction references, and timestamps
abstract final class RiveroTypography {
  // --- Plus Jakarta Sans: Financial Counters & Display ---
  static TextStyle get financialHero => GoogleFonts.plusJakartaSans(
    fontSize: 52,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get financialLarge => GoogleFonts.plusJakartaSans(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get financialMedium => GoogleFonts.plusJakartaSans(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get displayLarge => GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get displayMedium => GoogleFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: RiveroColors.textPrimary,
  );

  // --- Inter: UI Text ---
  static TextStyle get titleLarge => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get titleMedium => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textSecondary,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textMuted,
  );

  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: RiveroColors.textSecondary,
  );

  // --- JetBrains Mono: Account Masks, References, Timestamps ---
  static TextStyle get monoLarge => GoogleFonts.jetBrainsMono(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: RiveroColors.textPrimary,
  );

  static TextStyle get monoMedium => GoogleFonts.jetBrainsMono(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: RiveroColors.textSecondary,
  );

  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
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
  static ThemeData build({required bool light}) {
    RiveroColors.isLight = light;
    final scheme = light
        ? ColorScheme.light(
            surface: RiveroColors.surface,
            onSurface: RiveroColors.textPrimary,
            primary: RiveroColors.accent,
            secondary: RiveroColors.salaryAccent,
            error: RiveroColors.danger,
          )
        : ColorScheme.dark(
            surface: RiveroColors.surface,
            onSurface: RiveroColors.textPrimary,
            primary: RiveroColors.accent,
            onPrimary: const Color(0xFF0B1220),
            secondary: RiveroColors.salaryAccent,
            onSecondary: RiveroColors.background,
            error: RiveroColors.danger,
            onError: RiveroColors.textPrimary,
          );
    return ThemeData(
      useMaterial3: true,
      brightness: light ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: RiveroColors.background,
      colorScheme: scheme,
      // No ink splash spreading past a control's visible shape; press states
      // come from highlights clipped to the same shape (or the card's scale).
      splashFactory: NoSplash.splashFactory,
      highlightColor: RiveroColors.textPrimary.withValues(alpha: 0.06),
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
