import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

void main() {
  group('RiveroTokens tests', () {
    test('core surface colors match approved design specifications', () {
      expect(RiveroColors.background, equals(const Color(0xFF09090B)));
      expect(RiveroColors.surface, equals(const Color(0xFF131316)));
      expect(RiveroColors.surfaceElevated, equals(const Color(0xFF1B1B1F)));
    });

    test('financial hierarchy accents match approved hex values', () {
      expect(RiveroColors.salaryAccent, equals(const Color(0xFFD4A85A)));
      expect(RiveroColors.expenseAccent, equals(const Color(0xFF9A93D9)));
      expect(RiveroColors.investmentAccent, equals(const Color(0xFF6FBF9F)));
      expect(RiveroColors.savingsAccent, equals(const Color(0xFF6BAFC4)));
      expect(RiveroColors.mandateWarning, equals(const Color(0xFFD9695F)));
    });

    test('RiveroTheme produces a dark ThemeData with correct backgrounds', () {
      final theme = RiveroTheme.darkTheme;
      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(RiveroColors.background));
      expect(theme.colorScheme.surface, equals(RiveroColors.surface));
    });
  });
}
