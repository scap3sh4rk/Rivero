import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';

void main() {
  group('SafeToSpendCalculator', () {
    const calculator = SafeToSpendCalculator();

    test('computes nominal and conservative Safe-to-Spend and daily pace', () {
      final now = DateTime(2026, 11, 13, 12);
      final lastSynced = DateTime(2026, 11, 13, 10); // 2 hours ago

      // Expense balance: ₹50,000 (5,000,000 paise)
      // Upcoming mandates: ₹10,000 (1,000,000 paise)
      // Unsettled CC: ₹15,000 (1,500,000 paise)
      // Pending reimbursements: ₹5,000 (500,000 paise)
      // Days left: 10
      final result = calculator.calculate(
        expenseBalance: 5000000,
        upcomingMandates: 1000000,
        unsettledCreditCardLiability: 1500000,
        pendingReimbursements: 500000,
        daysRemainingInCycle: 10,
        lastSyncedAt: lastSynced,
        asOf: now,
      );

      // Conservative STS: 50k - 10k - 15k = 25k (2,500,000 paise)
      expect(result.conservativeSafeToSpend, 2500000);
      // Nominal STS: 25k + 5k = 30k (3,000,000 paise)
      expect(result.nominalSafeToSpend, 3000000);
      // Effective is conservative by default
      expect(result.effectiveSafeToSpend, 2500000);
      // Daily pace: 25k / 10 days = ₹2,500/day (250,000 paise/day)
      expect(result.dailySpendingPace, 250000);
      expect(result.isDeficit, isFalse);
      expect(result.deficitAmount, 0);
      expect(result.reliability, BalanceReliability.verified);
      expect(result.daysRemainingInCycle, 10);
    });

    test('includes pending reimbursements when requested', () {
      final result = calculator.calculate(
        expenseBalance: 5000000,
        upcomingMandates: 1000000,
        unsettledCreditCardLiability: 1500000,
        pendingReimbursements: 500000,
        daysRemainingInCycle: 10,
        includePendingReimbursements: true,
      );

      expect(result.effectiveSafeToSpend, 3000000);
      // Daily pace: 30k / 10 days = ₹3,000/day (300,000 paise/day)
      expect(result.dailySpendingPace, 300000);
    });

    test('flags financial deficit correctly and clamps daily pace to 0', () {
      // Expense balance: ₹10,000 (1,000,000 paise)
      // Upcoming mandates: ₹20,000 (2,000,000 paise)
      // Unsettled CC: ₹5,000 (500,000 paise)
      // Deficit: 10k - 20k - 5k = -₹15,000 (-1,500,000 paise)
      final result = calculator.calculate(
        expenseBalance: 1000000,
        upcomingMandates: 2000000,
        unsettledCreditCardLiability: 500000,
        pendingReimbursements: 0,
        daysRemainingInCycle: 15,
      );

      expect(result.isDeficit, isTrue);
      expect(result.effectiveSafeToSpend, -1500000);
      expect(result.deficitAmount, 1500000);
      expect(result.dailySpendingPace, 0); // Must never be negative pace
    });

    test('evaluates balance reliability based on sync timestamp age', () {
      final now = DateTime(2026, 11, 13, 12);

      // Synced 5 hours ago -> verified
      final verifiedResult = calculator.calculate(
        expenseBalance: 1000000,
        upcomingMandates: 0,
        unsettledCreditCardLiability: 0,
        pendingReimbursements: 0,
        daysRemainingInCycle: 5,
        lastSyncedAt: now.subtract(const Duration(hours: 5)),
        asOf: now,
      );
      expect(verifiedResult.reliability, BalanceReliability.verified);

      // Synced 48 hours ago -> estimated
      final estimatedResult = calculator.calculate(
        expenseBalance: 1000000,
        upcomingMandates: 0,
        unsettledCreditCardLiability: 0,
        pendingReimbursements: 0,
        daysRemainingInCycle: 5,
        lastSyncedAt: now.subtract(const Duration(hours: 48)),
        asOf: now,
      );
      expect(estimatedResult.reliability, BalanceReliability.estimated);

      // Synced 90 hours ago -> stale
      final staleResult = calculator.calculate(
        expenseBalance: 1000000,
        upcomingMandates: 0,
        unsettledCreditCardLiability: 0,
        pendingReimbursements: 0,
        daysRemainingInCycle: 5,
        lastSyncedAt: now.subtract(const Duration(hours: 90)),
        asOf: now,
      );
      expect(staleResult.reliability, BalanceReliability.stale);

      // Null sync -> stale
      final nullResult = calculator.calculate(
        expenseBalance: 1000000,
        upcomingMandates: 0,
        unsettledCreditCardLiability: 0,
        pendingReimbursements: 0,
        daysRemainingInCycle: 5,
        asOf: now,
      );
      expect(nullResult.reliability, BalanceReliability.stale);
    });

    test('sanitizes daysRemainingInCycle <= 0 to 1', () {
      final result = calculator.calculate(
        expenseBalance: 100000,
        upcomingMandates: 0,
        unsettledCreditCardLiability: 0,
        pendingReimbursements: 0,
        daysRemainingInCycle: 0,
      );

      expect(result.daysRemainingInCycle, 1);
      expect(result.dailySpendingPace, 100000);
    });

    test('equality contract', () {
      final r1 = calculator.calculate(
        expenseBalance: 1000,
        upcomingMandates: 100,
        unsettledCreditCardLiability: 50,
        pendingReimbursements: 0,
        daysRemainingInCycle: 5,
      );
      final r2 = calculator.calculate(
        expenseBalance: 1000,
        upcomingMandates: 100,
        unsettledCreditCardLiability: 50,
        pendingReimbursements: 0,
        daysRemainingInCycle: 5,
      );

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
    });
  });
}
