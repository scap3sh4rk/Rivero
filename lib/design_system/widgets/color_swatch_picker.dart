import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Colours to pick from for accounts and categories: 12 hues, each in four
/// shades (light, soft, base, deep), one hue per row.
abstract final class RiveroSwatches {
  static const List<Color> hues = [
    Color(0xFF4EA3F8), // blue
    Color(0xFF5AC8FA), // sky
    Color(0xFF22B8B0), // teal
    Color(0xFF2DBE6C), // green
    Color(0xFF9BCB3C), // lime
    Color(0xFFF5B841), // amber
    Color(0xFFFF8A3D), // orange
    Color(0xFFF2555A), // coral
    Color(0xFFEC4899), // pink
    Color(0xFF8B6CF6), // violet
    Color(0xFFA0785A), // brown
    Color(0xFF8E9AAF), // slate
  ];

  /// [hue] made lighter (positive) or deeper (negative), keeping its tint.
  static Color shade(Color hue, double lightness) {
    final hsl = HSLColor.fromColor(hue);
    return hsl
        .withLightness((hsl.lightness + lightness).clamp(0.12, 0.88))
        .toColor();
  }

  /// One row per hue: light, soft, base, deep.
  static final List<List<Color>> rows = [
    for (final h in hues) [shade(h, 0.22), shade(h, 0.11), h, shade(h, -0.16)],
  ];
}

/// Round colour buttons, a row per hue; [selected] is ARGB.
class ColorSwatchPicker extends StatelessWidget {
  const ColorSwatchPicker({
    required this.selected,
    required this.onPick,
    super.key,
    this.keyPrefix = 'color',
  });

  final int? selected;
  final ValueChanged<int> onPick;

  /// Each button is keyed `<keyPrefix>-<ARGB>` (for tests).
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    // Every colour offered: the shades, plus the original eight so colours
    // chosen before stay selectable.
    final rows = [
      ...RiveroSwatches.rows,
      [
        for (final c in RiveroColors.categorical)
          if (!RiveroSwatches.rows.any((r) => r.contains(c))) c,
      ],
    ].where((r) => r.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: RiveroSpacing.sm),
            child: Wrap(
              spacing: RiveroSpacing.sm,
              runSpacing: RiveroSpacing.sm,
              children: [
                for (final c in row)
                  GestureDetector(
                    key: ValueKey('$keyPrefix-${c.toARGB32()}'),
                    onTap: () => onPick(c.toARGB32()),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 3,
                          color: selected == c.toARGB32()
                              ? RiveroColors.textPrimary
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
