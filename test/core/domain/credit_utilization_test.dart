import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/domain/credit_utilization.dart';

void main() {
  group('CreditUtilization tests', () {
    test('Calculates safe tier for <= 10% utilization', () {
      // Limit ₹1,00,000 (10000000 paise), spent ₹9,500 (-950000 paise)
      final u = CreditUtilization.fromBalance(
        creditLimitMinorUnits: 10000000,
        balanceMinorUnits: -950000,
      );

      expect(u.tier, equals(CreditUtilizationTier.safe));
      expect(u.utilizationPercent, closeTo(9.5, 0.01));
      expect(u.usedMinorUnits, equals(950000));
      expect(u.availableMinorUnits, equals(9050000));
      expect(u.badgeLabel, contains('Safe'));
    });

    test('Calculates moderate tier for 10% - 30% utilization', () {
      // Limit ₹1,00,000, spent ₹25,000 (-2500000 paise)
      final u = CreditUtilization.fromBalance(
        creditLimitMinorUnits: 10000000,
        balanceMinorUnits: -2500000,
      );

      expect(u.tier, equals(CreditUtilizationTier.moderate));
      expect(u.utilizationPercent, closeTo(25.0, 0.01));
      expect(u.badgeLabel, contains('Moderate'));
    });

    test('Calculates risky tier for > 30% utilization', () {
      // Limit ₹1,00,000, spent ₹45,000 (-4500000 paise)
      final u = CreditUtilization.fromBalance(
        creditLimitMinorUnits: 10000000,
        balanceMinorUnits: -4500000,
      );

      expect(u.tier, equals(CreditUtilizationTier.risky));
      expect(u.utilizationPercent, closeTo(45.0, 0.01));
      expect(u.badgeLabel, contains('Score'));
      expect(u.adviceMessage, contains('Warning'));
    });

    test('Handles positive/zero liability balance cleanly', () {
      // Fully paid credit card
      final u = CreditUtilization.fromBalance(
        creditLimitMinorUnits: 10000000,
        balanceMinorUnits: 0,
      );

      expect(u.tier, equals(CreditUtilizationTier.safe));
      expect(u.utilizationPercent, equals(0.0));
      expect(u.usedMinorUnits, equals(0));
      expect(u.availableMinorUnits, equals(10000000));
    });

    test('Handles zero credit limit edge case', () {
      final u = CreditUtilization.fromBalance(
        creditLimitMinorUnits: 0,
        balanceMinorUnits: -50000,
      );

      expect(u.tier, equals(CreditUtilizationTier.risky));
      expect(u.utilizationPercent, equals(100.0));
    });
  });
}
