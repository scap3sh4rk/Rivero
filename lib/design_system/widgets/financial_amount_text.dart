import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

enum FinancialAmountSize { hero, large, medium, small }

enum FinancialAmountColor { auto, primary, positive, negative, warning, muted }

/// Displays an integer minor unit monetary value using Plus Jakarta Sans.
/// Optionally supports live animated counting via [AnimatedFlipCounter].
class FinancialAmountText extends StatelessWidget {
  const FinancialAmountText({
    required this.minorUnits,
    super.key,
    this.size = FinancialAmountSize.medium,
    this.colorType = FinancialAmountColor.auto,
    this.customColor,
    this.isAnimated = false,
    this.includeDecimals = true,
  });

  final int minorUnits;
  final FinancialAmountSize size;
  final FinancialAmountColor colorType;
  final Color? customColor;
  final bool isAnimated;
  final bool includeDecimals;

  Color _resolveColor() {
    if (customColor != null) return customColor!;
    switch (colorType) {
      case FinancialAmountColor.primary:
        return RiveroColors.textPrimary;
      case FinancialAmountColor.positive:
        return RiveroColors.investmentAccent;
      case FinancialAmountColor.negative:
        return RiveroColors.danger;
      case FinancialAmountColor.warning:
        return RiveroColors.mandateWarning;
      case FinancialAmountColor.muted:
        return RiveroColors.textMuted;
      case FinancialAmountColor.auto:
        if (minorUnits > 0) return RiveroColors.textPrimary;
        if (minorUnits < 0) return RiveroColors.danger;
        return RiveroColors.textSecondary;
    }
  }

  TextStyle _resolveStyle(Color color) {
    switch (size) {
      case FinancialAmountSize.hero:
        // The headline figure: extra bold.
        return RiveroTypography.financialHero.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        );
      case FinancialAmountSize.large:
        return RiveroTypography.financialLarge.copyWith(color: color);
      case FinancialAmountSize.medium:
        return RiveroTypography.financialMedium.copyWith(color: color);
      case FinancialAmountSize.small:
        return RiveroTypography.displayMedium.copyWith(color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor();
    final style = _resolveStyle(color);

    if (isAnimated) {
      final doubleValue = minorUnits / 100.0;
      return AnimatedFlipCounter(
        value: doubleValue,
        prefix: '₹',
        fractionDigits: includeDecimals ? 2 : 0,
        textStyle: style,
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 650),
      );
    }

    final formatted = CurrencyFormatter.formatMinorUnits(
      minorUnits,
      includeDecimals: includeDecimals,
    );

    return Text(formatted, style: style);
  }
}
