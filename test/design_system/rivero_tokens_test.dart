import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

void main() {
  group('RiveroTokens tests', () {
    test('core surface colors match approved design specifications', () {
      expect(RiveroColors.background, equals(const Color(0xFF0E1116)));
      expect(RiveroColors.surface, equals(const Color(0xFF161B22)));
      expect(RiveroColors.surfaceElevated, equals(const Color(0xFF1D232C)));
    });

    test('financial hierarchy accents match approved hex values', () {
      expect(RiveroColors.salaryAccent, equals(const Color(0xFFF2B33D)));
      expect(RiveroColors.expenseAccent, equals(const Color(0xFF4EA3F8)));
      expect(RiveroColors.investmentAccent, equals(const Color(0xFF9A85F2)));
      expect(RiveroColors.savingsAccent, equals(const Color(0xFF33B5A5)));
      expect(RiveroColors.mandateWarning, equals(const Color(0xFFF0717A)));
    });

    test('RiveroTheme produces a dark ThemeData with correct backgrounds', () {
      final theme = RiveroTheme.darkTheme;
      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(RiveroColors.background));
      expect(theme.colorScheme.surface, equals(RiveroColors.surface));
    });
  });
}
