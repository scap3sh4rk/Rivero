import 'package:flutter/material.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Colour for an account: the one the user picked, else a stable choice
/// from the palette based on its name.
Color accountColor(PhysicalAccount a) => a.colorValue != null
    ? Color(a.colorValue!)
    : paletteFor(a.institution.isEmpty ? a.name : a.institution);

/// Stable palette colour for any label (category, person, bank).
Color paletteFor(String label) {
  final i = label.toLowerCase().codeUnits.fold(0, (a, b) => a + b);
  return RiveroColors.categorical[i % RiveroColors.categorical.length];
}

/// A small filled circle in [color].
class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 10});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
