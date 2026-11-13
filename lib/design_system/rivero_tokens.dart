import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic colors for Rivero's design system.
/// All hex codes strictly adhere to the approved architecture specifications.
abstract final class RiveroColors {
  /// Set by the app root before building; neutrals below follow it.
  static bool isLight = false;

  // --- Core Surfaces ---
  /// Deep pitch dark background: `#08080C`
  static Color get background =>
      isLight ? const Color(0xFFF6F5F2) : const Color(0xFF09090B);

  /// Primary card and container surface: `#12121A`
  static Color get surface =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF131316);

  /// Elevated card, modal, or floating surface: `#1A1A26`
  static Color get surfaceElevated =>
      isLight ? const Color(0xFFF0EFEB) : const Color(0xFF1B1B1F);

  /// Higher level interactive surface (hover/active state): `#222233`
  static Color get surfaceInteractive =>
      isLight ? const Color(0xFFE6E4DF) : const Color(0xFF25252B);

  // --- Financial Hierarchy Accents ---
  /// Salary root accent (Warm Amber): `#F59E0B`
  static const Color salaryAccent = Color(0xFFD4A85A);

  /// Expense bucket accent (Vibrant Violet): `#8B5CF6`
  static const Color expenseAccent = Color(0xFF9A93D9);

  /// Investment bucket accent (Emerald Green): `#10B981`
  static const Color investmentAccent = Color(0xFF6FBF9F);

  /// Savings bucket accent (Cyan): `#06B6D4`
  static const Color savingsAccent = Color(0xFF6BAFC4);

  /// Recurring mandate and liquidity deficit warning (Rose Red): `#F43F5E`
  static const Color mandateWarning = Color(0xFFD9695F);

  /// Custom bucket accent (Fuchsia): `#EC4899`
  static const Color customAccent = Color(0xFFC27BA0);

  /// Credit card liability accent (Tangerine): `#FB923C`
  static const Color liabilityAccent = Color(0xFFD89868);

  /// Virtual wallet accent (Sky): `#38BDF8`
  static const Color walletAccent = Color(0xFF7FAAD6);

  // --- Semantic State Colors ---
  /// Success green: `#10B981`
  static const Color success = Color(0xFF6FBF9F);

  /// Danger/Alert red: `#F43F5E`
  static const Color danger = Color(0xFFD9695F);

  /// Info blue: `#3B82F6`
  static const Color info = Color(0xFF7C9ED9);

  /// Warning amber: `#F59E0B`
  static const Color warning = Color(0xFFD4A85A);

  // --- Text & Foreground ---
  /// Primary high-contrast text: `#F8FAFC`
  static Color get textPrimary =>
      isLight ? const Color(0xFF16161A) : const Color(0xFFF8FAFC);

  /// Secondary subdued text: `#94A3B8`
  static Color get textSecondary =>
      isLight ? const Color(0xFF55596A) : const Color(0xFF94A3B8);

  /// Muted helper text: `#64748B`
  static Color get textMuted =>
      isLight ? const Color(0xFF7C8091) : const Color(0xFF64748B);

  /// Disabled text/icon: `#475569`
  static Color get textDisabled =>
      isLight ? const Color(0xFFA5A8B5) : const Color(0xFF475569);

  // --- Borders & Dividers ---
  /// Subtle surface outline: `#1E1E2E`
  static Color get borderSubtle =>
      isLight ? const Color(0xFFE4E2DC) : const Color(0xFF1F1F25);

  /// Distinct component border: `#2E2E42`
  static Color get borderMedium =>
      isLight ? const Color(0xFFD3D0C8) : const Color(0xFF2D2D35);

  /// Highlight/focused border: `#3E3E58`
  static Color get borderHighlight =>
      isLight ? const Color(0xFFBDB9AF) : const Color(0xFF3D3D48);
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
            primary: RiveroColors.textPrimary,
            onPrimary: RiveroColors.background,
            secondary: RiveroColors.salaryAccent,
            error: RiveroColors.danger,
          )
        : ColorScheme.dark(
            surface: RiveroColors.surface,
            onSurface: RiveroColors.textPrimary,
            primary: RiveroColors.expenseAccent,
            onPrimary: RiveroColors.textPrimary,
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
      dividerTheme: DividerThemeData(
        color: RiveroColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
