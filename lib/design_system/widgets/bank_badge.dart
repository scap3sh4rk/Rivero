import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Coloured monogram for an institution (no licensed logos).
/// The tint is derived from the name so it is stable across launches.
class BankBadge extends StatelessWidget {
  const BankBadge({
    required this.name,
    super.key,
    this.size = 44,
    this.circle = false,
  });

  final String name;
  final double size;

  /// Round (Slice activity rows) instead of a rounded square.
  final bool circle;

  static const List<Color> _tints = [
    RiveroColors.salaryAccent,
    RiveroColors.expenseAccent,
    RiveroColors.investmentAccent,
    RiveroColors.savingsAccent,
    RiveroColors.customAccent,
    RiveroColors.liabilityAccent,
    RiveroColors.walletAccent,
  ];

  /// First one or two initials, e.g. "HDFC Bank" -> "HB", "SBI" -> "S".
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final tint =
        _tints[name.codeUnits.fold(0, (a, b) => a + b) % _tints.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initials(name),
        style: RiveroTypography.titleMedium.copyWith(
          color: tint,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
