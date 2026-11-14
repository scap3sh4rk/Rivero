import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

void main() {
  group('RiveroTokens tests', () {
    test('core surface colors match approved design specifications', () {
      expect(RiveroColors.background, equals(const Color(0xFF000000)));
      expect(RiveroColors.surface, equals(const Color(0xFF0F0F11)));
      expect(RiveroColors.surfaceElevated, equals(const Color(0xFF18181B)));
    });

    test('financial hierarchy accents match approved hex values', () {
      expect(RiveroColors.salaryAccent, equals(const Color(0xFFF5B841)));
      expect(RiveroColors.expenseAccent, equals(const Color(0xFF4EA3F8)));
      expect(RiveroColors.investmentAccent, equals(const Color(0xFF8B6CF6)));
      expect(RiveroColors.savingsAccent, equals(const Color(0xFF22B8B0)));
      expect(RiveroColors.mandateWarning, equals(const Color(0xFFF2555A)));
    });

    test('RiveroTheme produces a dark ThemeData with correct backgrounds', () {
      final theme = RiveroTheme.darkTheme;
      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(RiveroColors.background));
      expect(theme.colorScheme.surface, equals(RiveroColors.surface));
    });
  });
}
