import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter tests', () {
    test('formats zero minor units correctly', () {
      final result = CurrencyFormatter.formatMinorUnits(0);
      expect(result, equals('₹0.00'));
    });

    test('formats positive amounts with Indian rupee notation', () {
      expect(CurrencyFormatter.formatMinorUnits(100), equals('₹1.00'));
      expect(CurrencyFormatter.formatMinorUnits(5050), equals('₹50.50'));
      expect(CurrencyFormatter.formatMinorUnits(100000), equals('₹1,000.00'));
      expect(
        CurrencyFormatter.formatMinorUnits(10000000),
        equals('₹1,00,000.00'),
      ); // 1 Lakh
      expect(
        CurrencyFormatter.formatMinorUnits(1000000000),
        equals('₹1,00,00,000.00'),
      ); // 1 Crore
    });

    test('formats negative amounts correctly', () {
      expect(CurrencyFormatter.formatMinorUnits(-5000), equals('-₹50.00'));
      expect(
        CurrencyFormatter.formatMinorUnits(-1425000),
        equals('-₹14,250.00'),
      );
    });

    test('formats without decimals when requested', () {
      expect(
        CurrencyFormatter.formatMinorUnits(15000000, includeDecimals: false),
        equals('₹1,50,000'),
      );
    });

    test('shows positive sign when explicitly requested', () {
      expect(
        CurrencyFormatter.formatMinorUnits(250000, showSign: true),
        equals('+₹2,500.00'),
      );
    });

    test('compact formatting produces readable denominations', () {
      expect(CurrencyFormatter.formatCompact(50000), equals('₹500'));
      expect(CurrencyFormatter.formatCompact(250000), equals('₹2.5k'));
      expect(CurrencyFormatter.formatCompact(15000000), equals('₹1.5L'));
      expect(CurrencyFormatter.formatCompact(1000000000), equals('₹1Cr'));
    });

    test('parseToMinorUnits parses clean and formatted strings', () {
      expect(CurrencyFormatter.parseToMinorUnits('₹1,000.50'), equals(100050));
      expect(CurrencyFormatter.parseToMinorUnits('500'), equals(50000));
      expect(CurrencyFormatter.parseToMinorUnits('0.25'), equals(25));
      expect(CurrencyFormatter.parseToMinorUnits('-50.00'), equals(-5000));
      expect(CurrencyFormatter.parseToMinorUnits(''), isNull);
      expect(CurrencyFormatter.parseToMinorUnits('invalid'), isNull);
    });
  });
}
