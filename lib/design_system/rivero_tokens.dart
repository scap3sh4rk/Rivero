import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic colors for Rivero's design system.
/// All hex codes strictly adhere to the approved architecture specifications.
abstract final class RiveroColors {
  // --- Core Surfaces ---
  /// Deep pitch dark background: `#08080C`
  static const Color background = Color(0xFF09090B);

  /// Primary card and container surface: `#12121A`
  static const Color surface = Color(0xFF131316);

  /// Elevated card, modal, or floating surface: `#1A1A26`
  static const Color surfaceElevated = Color(0xFF1B1B1F);

  /// Higher level interactive surface (hover/active state): `#222233`
  static const Color surfaceInteractive = Color(0xFF25252B);

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
  static const Color textPrimary = Color(0xFFF8FAFC);

  /// Secondary subdued text: `#94A3B8`
  static const Color textSecondary = Color(0xFF94A3B8);

  /// Muted helper text: `#64748B`
  static const Color textMuted = Color(0xFF64748B);

  /// Disabled text/icon: `#475569`
  static const Color textDisabled = Color(0xFF475569);

  // --- Borders & Dividers ---
  /// Subtle surface outline: `#1E1E2E`
  static const Color borderSubtle = Color(0xFF1F1F25);

  /// Distinct component border: `#2E2E42`
  static const Color borderMedium = Color(0xFF2D2D35);

  /// Highlight/focused border: `#3E3E58`
  static const Color borderHighlight = Color(0xFF3D3D48);
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
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: RiveroColors.background,
      colorScheme: const ColorScheme.dark(
        surface: RiveroColors.surface,
        onSurface: RiveroColors.textPrimary,
        primary: RiveroColors.expenseAccent,
        onPrimary: RiveroColors.textPrimary,
        secondary: RiveroColors.salaryAccent,
        onSecondary: RiveroColors.background,
        error: RiveroColors.danger,
        onError: RiveroColors.textPrimary,
      ),
      cardTheme: const CardThemeData(
        color: RiveroColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: RiveroRadii.borderMd,
          side: BorderSide(color: RiveroColors.borderSubtle),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: RiveroColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: RiveroColors.textPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: RiveroColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
