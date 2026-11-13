import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

void main() {
  group('RiveroTokens tests', () {
    test('core surface colors match approved design specifications', () {
      expect(RiveroColors.background, equals(const Color(0xFF08080C)));
      expect(RiveroColors.surface, equals(const Color(0xFF12121A)));
      expect(RiveroColors.surfaceElevated, equals(const Color(0xFF1A1A26)));
    });

    test('financial hierarchy accents match approved hex values', () {
      expect(RiveroColors.salaryAccent, equals(const Color(0xFFF59E0B)));
      expect(RiveroColors.expenseAccent, equals(const Color(0xFF8B5CF6)));
      expect(RiveroColors.investmentAccent, equals(const Color(0xFF10B981)));
      expect(RiveroColors.savingsAccent, equals(const Color(0xFF06B6D4)));
      expect(RiveroColors.mandateWarning, equals(const Color(0xFFF43F5E)));
    });

    test('RiveroTheme produces a dark ThemeData with correct backgrounds', () {
      final theme = RiveroTheme.darkTheme;
      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(RiveroColors.background));
      expect(theme.colorScheme.surface, equals(RiveroColors.surface));
    });
  });
}
