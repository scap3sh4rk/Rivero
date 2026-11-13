import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/engine/paycycle.dart';

void main() {
  group('Paycycle', () {
    test(
      'standard cycle with salary on 1st of month (mid-month reference)',
      () {
        final asOf = DateTime(2026, 11, 13);
        final cycle = Paycycle.fromSalaryDay(salaryCreditDay: 1, asOf: asOf);

        expect(cycle.salaryCreditDay, 1);
        expect(cycle.cycleStartDate, DateTime(2026, 11));
        expect(cycle.nextCycleStartDate, DateTime(2026, 12));
        expect(cycle.totalDaysInCycle, 30); // November has 30 days
        expect(cycle.elapsedDays, 12);
        expect(cycle.daysRemaining, 18);
        expect(cycle.progress, closeTo(12 / 30, 0.001));
      },
    );

    test('salary on 25th with reference date before salary day', () {
      final asOf = DateTime(2026, 11, 13);
      final cycle = Paycycle.fromSalaryDay(salaryCreditDay: 25, asOf: asOf);

      expect(cycle.cycleStartDate, DateTime(2026, 10, 25));
      expect(cycle.nextCycleStartDate, DateTime(2026, 11, 25));
      expect(cycle.totalDaysInCycle, 31); // Oct 25 to Nov 25 is 31 days
      expect(cycle.elapsedDays, 19);
      expect(cycle.daysRemaining, 12);
      expect(cycle.progress, closeTo(19 / 31, 0.001));
    });

    test('salary on 25th on salary day itself', () {
      final asOf = DateTime(2026, 11, 25);
      final cycle = Paycycle.fromSalaryDay(salaryCreditDay: 25, asOf: asOf);

      expect(cycle.cycleStartDate, DateTime(2026, 11, 25));
      expect(cycle.nextCycleStartDate, DateTime(2026, 12, 25));
      expect(cycle.elapsedDays, 0);
      expect(cycle.daysRemaining, 30);
      expect(cycle.progress, 0.0);
    });

    test('31st salary day clamping on 30-day month (April)', () {
      final asOf = DateTime(2026, 4, 15);
      final cycle = Paycycle.fromSalaryDay(salaryCreditDay: 31, asOf: asOf);

      // Previous month is March (31 days), so starts March 31.
      expect(cycle.cycleStartDate, DateTime(2026, 3, 31));
      // Next cycle in April (30 days), so clamped to April 30.
      expect(cycle.nextCycleStartDate, DateTime(2026, 4, 30));
      expect(cycle.totalDaysInCycle, 30);
      expect(cycle.daysRemaining, 15);
    });

    test('February leap year vs non-leap year clamping', () {
      // 2024 is leap year: Feb has 29 days
      final leapCycle = Paycycle.fromSalaryDay(
        salaryCreditDay: 31,
        asOf: DateTime(2024, 2, 10),
      );
      expect(leapCycle.cycleStartDate, DateTime(2024, 1, 31));
      expect(leapCycle.nextCycleStartDate, DateTime(2024, 2, 29));

      // 2025 is non-leap year: Feb has 28 days
      final nonLeapCycle = Paycycle.fromSalaryDay(
        salaryCreditDay: 31,
        asOf: DateTime(2025, 2, 10),
      );
      expect(nonLeapCycle.cycleStartDate, DateTime(2025, 1, 31));
      expect(nonLeapCycle.nextCycleStartDate, DateTime(2025, 2, 28));
    });

    test('year boundary transition across December and January', () {
      // Reference date in early January with 25th salary day
      final cycleJan = Paycycle.fromSalaryDay(
        salaryCreditDay: 25,
        asOf: DateTime(2027, 1, 5),
      );
      expect(cycleJan.cycleStartDate, DateTime(2026, 12, 25));
      expect(cycleJan.nextCycleStartDate, DateTime(2027, 1, 25));

      // Reference date in late December with 5th salary day
      final cycleDec = Paycycle.fromSalaryDay(
        salaryCreditDay: 5,
        asOf: DateTime(2026, 12, 28),
      );
      expect(cycleDec.cycleStartDate, DateTime(2026, 12, 5));
      expect(cycleDec.nextCycleStartDate, DateTime(2027, 1, 5));
    });

    test('last day of cycle clamps daysRemaining to minimum 1', () {
      // On Nov 30 when salary is on 1st of month, next cycle is Dec 1 (tomorrow)
      final cycle = Paycycle.fromSalaryDay(
        salaryCreditDay: 1,
        asOf: DateTime(2026, 11, 30),
      );
      expect(cycle.daysRemaining, 1);
      expect(cycle.nextCycleStartDate, DateTime(2026, 12));
    });

    test('throws ArgumentError on invalid salaryCreditDay (< 1 or > 31)', () {
      expect(
        () => Paycycle.fromSalaryDay(salaryCreditDay: 0),
        throwsArgumentError,
      );
      expect(
        () => Paycycle.fromSalaryDay(salaryCreditDay: 32),
        throwsArgumentError,
      );
    });

    test('equality and toString contract', () {
      final c1 = Paycycle.fromSalaryDay(
        salaryCreditDay: 1,
        asOf: DateTime(2026, 11, 13),
      );
      final c2 = Paycycle.fromSalaryDay(
        salaryCreditDay: 1,
        asOf: DateTime(2026, 11, 13),
      );
      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
      expect(c1.toString(), contains('Paycycle'));
    });
  });
}
