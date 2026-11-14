import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/design_system/category_icons.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// WCAG contrast ratio between two colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final light in [false, true]) {
    testWidgets('selected chips and segments are readable (light=$light)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: RiveroTheme.build(light: light),
          home: Scaffold(
            body: Column(
              children: [
                ChoiceChip(
                  label: const Text('Nov'),
                  selected: true,
                  onSelected: (_) {},
                ),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Categories')),
                    ButtonSegment(value: 1, label: Text('Top spends')),
                  ],
                  selected: const {0},
                  onSelectionChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      Color textColor(String t) => tester
          .widget<RichText>(
            find
                .descendant(
                  of: find
                      .ancestor(
                        of: find.text(t),
                        matching: find.byType(Material),
                      )
                      .first,
                  matching: find.byType(RichText),
                )
                .first,
          )
          .text
          .style!
          .color!;
      // Selected: text on the solid accent.
      expect(contrast(textColor('Nov'), RiveroColors.accent), greaterThan(4.5));
      expect(
        contrast(textColor('Categories'), RiveroColors.accent),
        greaterThan(4.5),
      );
      // Unselected segment: secondary text on its dark/light surface.
      expect(
        contrast(textColor('Top spends'), RiveroColors.surfaceElevated),
        greaterThan(3.0),
      );
    });
  }

  test('palette text colours meet contrast on every surface', () {
    for (final light in [false, true]) {
      RiveroColors.isLight = light;
      for (final bg in [
        RiveroColors.background,
        RiveroColors.surface,
        RiveroColors.surfaceElevated,
      ]) {
        expect(contrast(RiveroColors.textPrimary, bg), greaterThan(7));
        expect(contrast(RiveroColors.textSecondary, bg), greaterThan(4.5));
      }
    }
    RiveroColors.isLight = false;
  });

  test('categories and merchants get consistent icons', () {
    expect(iconForLabel('Starbucks'), Icons.local_cafe_rounded);
    expect(iconForLabel('Blinkit'), Icons.local_grocery_store_rounded);
    expect(iconForLabel('Uber trip'), Icons.local_taxi_rounded);
    // The category wins over an unknown merchant name.
    expect(
      iconForLabel("Ravi's place", category: 'Food'),
      Icons.restaurant_rounded,
    );
    expect(iconForLabel('Food'), Icons.restaurant_rounded);
    expect(iconForLabel('Food & dining'), Icons.restaurant_rounded);
    expect(iconForLabel('Groceries'), Icons.local_grocery_store_rounded);
    expect(iconForLabel('Transportation'), Icons.directions_car_rounded);
    expect(iconForLabel('General expense'), Icons.category_rounded);
    expect(hasSpecificIcon('Ravi', category: 'Other'), isTrue); // Other has one
    expect(hasSpecificIcon('Ravi'), isFalse); // a person: initials instead
  });
}
