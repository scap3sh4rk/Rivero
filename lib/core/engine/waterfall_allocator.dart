import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:rivero/core/engine/allocation_rule.dart';

/// The immutable result of executing a waterfall allocation on an incoming salary amount.
@immutable
class WaterfallAllocationResult {
  const WaterfallAllocationResult({
    required this.salaryReceived,
    required this.allocations,
    required this.unallocatedRemaining,
    required this.shortfalls,
  }) : assert(
         unallocatedRemaining >= 0,
         'unallocatedRemaining cannot be negative',
       );

  /// Total incoming salary in minor units (paise) that was partitioned.
  final int salaryReceived;

  /// Partitioned amounts per bucket ID in minor units (paise).
  final Map<String, int> allocations;

  /// Amount remaining in the Salary Root that was not allocated to any bucket.
  final int unallocatedRemaining;

  /// Unfulfilled amounts for mandatory rules where incoming funds were insufficient.
  final Map<String, int> shortfalls;

  /// Returns true if all mandatory rules were fully funded with zero shortfall.
  bool get isFullyFunded => shortfalls.isEmpty;

  /// Total minor units successfully allocated across all buckets.
  int get totalAllocated =>
      allocations.values.fold<int>(0, (sum, val) => sum + val);

  /// Total minor units in shortfall across all underfunded mandatory rules.
  int get totalShortfall =>
      shortfalls.values.fold<int>(0, (sum, val) => sum + val);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WaterfallAllocationResult &&
          runtimeType == other.runtimeType &&
          salaryReceived == other.salaryReceived &&
          unallocatedRemaining == other.unallocatedRemaining &&
          mapEquals(allocations, other.allocations) &&
          mapEquals(shortfalls, other.shortfalls);

  @override
  int get hashCode => Object.hash(
    salaryReceived,
    unallocatedRemaining,
    Object.hashAll(allocations.entries),
    Object.hashAll(shortfalls.entries),
  );

  @override
  String toString() {
    return 'WaterfallAllocationResult(salary: $salaryReceived, '
        'allocated: $totalAllocated, remaining: $unallocatedRemaining, '
        'shortfalls: $shortfalls)';
  }
}

/// Core financial engine that allocates incoming salary credits sequentially
/// across virtual allocation buckets according to user-defined priority rules.
///
/// Guaranteed Properties:
/// 1. Conservation of Value: `salaryReceived == sum(allocations) + unallocatedRemaining`.
/// 2. Determinism: Given identical rules and salary, output is identical.
/// 3. Priority Order: Lower priority numbers are fulfilled before higher numbers.
/// 4. Mandatory Protection: Mandatory underfunding is surfaced as explicit shortfalls.
class WaterfallAllocator {
  const WaterfallAllocator();

  /// Distributes [salaryReceived] across [rules] in strict ascending priority order.
  ///
  /// [salaryReceived] must be in minor units (paise) and non-negative.
  WaterfallAllocationResult allocate({
    required int salaryReceived,
    required List<AllocationRule> rules,
  }) {
    if (salaryReceived < 0) {
      throw ArgumentError.value(
        salaryReceived,
        'salaryReceived',
        'Incoming salary must be non-negative',
      );
    }

    // Sort rules by priority ascending (1 is processed before 2).
    final sortedRules = List<AllocationRule>.from(rules)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    final allocations = <String, int>{};
    final shortfalls = <String, int>{};
    var remainingFunds = salaryReceived;

    for (final rule in sortedRules) {
      final desiredAmount = _calculateDesiredAmount(
        rule: rule,
        salaryReceived: salaryReceived,
        remainingFunds: remainingFunds,
      );

      // Apply cap if one is specified.
      final cappedAmount = rule.cap != null
          ? math.min(desiredAmount, rule.cap!)
          : desiredAmount;

      // Determine actual allocatable amount based on available remaining funds.
      final actualAllocated = math.min(remainingFunds, cappedAmount);

      // Accumulate into bucket (multiple rules can target the same bucket).
      allocations[rule.bucketId] =
          (allocations[rule.bucketId] ?? 0) + actualAllocated;
      remainingFunds -= actualAllocated;

      // Check for shortfall if this rule is mandatory and was not fully funded.
      if (rule.isMandatory && actualAllocated < cappedAmount) {
        final deficit = cappedAmount - actualAllocated;
        shortfalls[rule.bucketId] = (shortfalls[rule.bucketId] ?? 0) + deficit;
      }
    }

    final result = WaterfallAllocationResult(
      salaryReceived: salaryReceived,
      allocations: Map.unmodifiable(allocations),
      unallocatedRemaining: remainingFunds,
      shortfalls: Map.unmodifiable(shortfalls),
    );

    // Strict conservation of value invariant verification.
    assert(
      result.totalAllocated + result.unallocatedRemaining == salaryReceived,
      'Conservation invariant violated: '
      'allocated (${result.totalAllocated}) + remaining (${result.unallocatedRemaining}) '
      '!= salaryReceived ($salaryReceived)',
    );

    return result;
  }

  /// Calculates the desired allocation amount in minor units for a given rule.
  int _calculateDesiredAmount({
    required AllocationRule rule,
    required int salaryReceived,
    required int remainingFunds,
  }) {
    switch (rule.type) {
      case AllocationType.fixed:
        return rule.fixedAmount ?? 0;

      case AllocationType.percentageOfSalary:
        // Whole-number maths (hundredths of a percent), half-up rounding.
        return _percentOf(salaryReceived, rule.percentage ?? 0);

      case AllocationType.percentageOfRemaining:
        return _percentOf(remainingFunds, rule.percentage ?? 0);
    }
  }

  /// [percent] of [amount] using integers only: percent is taken to two
  /// decimals (12.5% = 1250), so no floating-point drift on large amounts.
  static int _percentOf(int amount, double percent) {
    final basis = BigInt.from((percent * 100).round());
    final scaled = BigInt.from(amount) * basis + BigInt.from(5000);
    return (scaled ~/ BigInt.from(10000)).toInt();
  }
}
