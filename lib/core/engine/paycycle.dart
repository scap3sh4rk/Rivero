import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Models a user's monthly paycycle based on their configured recurring salary credit day.
///
/// Handles all calendar complexities including leap years, 28/29/30/31-day months,
/// cycle boundary clamping, and division-by-zero protection.
@immutable
class Paycycle {
  const Paycycle._({
    required this.salaryCreditDay,
    required this.asOf,
    required this.cycleStartDate,
    required this.cycleEndDate,
    required this.nextCycleStartDate,
    required this.daysRemaining,
    required this.totalDaysInCycle,
    required this.elapsedDays,
    required this.progress,
  });

  /// Factory constructor computing paycycle properties relative to [asOf].
  ///
  /// [salaryCreditDay] must be between 1 and 31.
  /// If [asOf] is omitted, defaults to the current UTC or local timestamp.
  factory Paycycle.fromSalaryDay({
    required int salaryCreditDay,
    DateTime? asOf,
  }) {
    if (salaryCreditDay < 1 || salaryCreditDay > 31) {
      throw ArgumentError.value(
        salaryCreditDay,
        'salaryCreditDay',
        'Salary credit day must be between 1 and 31',
      );
    }

    final reference = asOf ?? DateTime.now();
    // Normalize reference date to beginning of day to avoid timezone drift in date calculations.
    final refDate = DateTime(reference.year, reference.month, reference.day);

    final int targetYear;
    final int targetMonth;
    final int nextYear;
    final int nextMonth;

    // Check if the reference date is on or after the salary credit day for this month.
    final currentMonthMaxDay = _daysInMonth(reference.year, reference.month);
    final clampedCurrentMonthDay = math.min(
      salaryCreditDay,
      currentMonthMaxDay,
    );

    if (refDate.day >= clampedCurrentMonthDay) {
      // Current cycle started in reference month.
      targetYear = reference.year;
      targetMonth = reference.month;

      // Next cycle starts in next month.
      if (reference.month == 12) {
        nextYear = reference.year + 1;
        nextMonth = 1;
      } else {
        nextYear = reference.year;
        nextMonth = reference.month + 1;
      }
    } else {
      // Current cycle started in previous month.
      if (reference.month == 1) {
        targetYear = reference.year - 1;
        targetMonth = 12;
      } else {
        targetYear = reference.year;
        targetMonth = reference.month - 1;
      }

      // Next cycle starts in reference month.
      nextYear = reference.year;
      nextMonth = reference.month;
    }

    final cycleStartDay = math.min(
      salaryCreditDay,
      _daysInMonth(targetYear, targetMonth),
    );
    final cycleStartDate = DateTime(targetYear, targetMonth, cycleStartDay);

    final nextCycleStartDay = math.min(
      salaryCreditDay,
      _daysInMonth(nextYear, nextMonth),
    );
    final nextCycleStartDate = DateTime(nextYear, nextMonth, nextCycleStartDay);

    // End date is 23:59:59 on the day before the next cycle starts.
    final cycleEndDate = DateTime(
      nextCycleStartDate.year,
      nextCycleStartDate.month,
      nextCycleStartDate.day - 1,
      23,
      59,
      59,
      999,
    );

    final totalDays = nextCycleStartDate.difference(cycleStartDate).inDays;
    final elapsed = refDate.difference(cycleStartDate).inDays;

    // Calculate days remaining until next salary credit.
    // Clamp to minimum 1 day to prevent division-by-zero when calculating daily pace.
    final rawRemaining = nextCycleStartDate.difference(refDate).inDays;
    final daysRemaining = math.max(1, rawRemaining);

    final progress = (elapsed / (totalDays > 0 ? totalDays : 1)).clamp(
      0.0,
      1.0,
    );

    return Paycycle._(
      salaryCreditDay: salaryCreditDay,
      asOf: refDate,
      cycleStartDate: cycleStartDate,
      cycleEndDate: cycleEndDate,
      nextCycleStartDate: nextCycleStartDate,
      daysRemaining: daysRemaining,
      totalDaysInCycle: totalDays,
      elapsedDays: elapsed,
      progress: progress,
    );
  }

  /// The configured day of the month when salary arrives (1..31).
  final int salaryCreditDay;

  /// The reference date for this paycycle snapshot.
  final DateTime asOf;

  /// Date when the current paycycle began.
  final DateTime cycleStartDate;

  /// Date and time when the current paycycle ends (day before next cycle at 23:59:59.999).
  final DateTime cycleEndDate;

  /// Date when the next salary credit and new cycle is expected.
  final DateTime nextCycleStartDate;

  /// Days remaining in the cycle, clamped to minimum 1 to prevent division-by-zero.
  final int daysRemaining;

  /// Total duration of this paycycle in calendar days (typically 28 to 31).
  final int totalDaysInCycle;

  /// Number of calendar days elapsed since this cycle began.
  final int elapsedDays;

  /// Fractional progress through the paycycle (0.0 at start to 1.0 at end).
  final double progress;

  /// Helper returning total days in any given month and year.
  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Paycycle &&
          runtimeType == other.runtimeType &&
          salaryCreditDay == other.salaryCreditDay &&
          asOf == other.asOf &&
          cycleStartDate == other.cycleStartDate &&
          cycleEndDate == other.cycleEndDate &&
          nextCycleStartDate == other.nextCycleStartDate &&
          daysRemaining == other.daysRemaining &&
          totalDaysInCycle == other.totalDaysInCycle &&
          elapsedDays == other.elapsedDays &&
          (progress - other.progress).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(
    salaryCreditDay,
    asOf,
    cycleStartDate,
    cycleEndDate,
    nextCycleStartDate,
    daysRemaining,
    totalDaysInCycle,
    elapsedDays,
  );

  @override
  String toString() {
    return 'Paycycle(day: $salaryCreditDay, start: ${cycleStartDate.toIso8601String().substring(0, 10)}, '
        'next: ${nextCycleStartDate.toIso8601String().substring(0, 10)}, remaining: $daysRemaining/$totalDaysInCycle days, '
        'progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}
