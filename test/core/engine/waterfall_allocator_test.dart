import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/engine/allocation_rule.dart';
import 'package:rivero/core/engine/waterfall_allocator.dart';

void main() {
  group('WaterfallAllocator', () {
    const allocator = WaterfallAllocator();

    test('allocates fixed and percentage rules according to priority', () {
      // Salary: ₹1,00,000 (10,000,000 paise)
      // Rule 1: Rent ₹25,000 (2,500,000 paise) [Priority 1]
      // Rule 2: Investment 20% of Salary = ₹20,000 (2,000,000 paise) [Priority 2]
      // Rule 3: Savings 50% of Remaining = 50% of (100k - 25k - 20k = 55k) = ₹27,500 (2,750,000 paise) [Priority 3]
      // Remaining: ₹27,500 (2,750,000 paise)
      final rules = [
        const AllocationRule(
          id: 'rule-rent',
          bucketId: 'bucket-rent',
          type: AllocationType.fixed,
          fixedAmount: 2500000,
          priority: 1,
        ),
        const AllocationRule(
          id: 'rule-invest',
          bucketId: 'bucket-invest',
          type: AllocationType.percentageOfSalary,
          percentage: 20,
          priority: 2,
        ),
        const AllocationRule(
          id: 'rule-savings',
          bucketId: 'bucket-savings',
          type: AllocationType.percentageOfRemaining,
          percentage: 50,
          priority: 3,
        ),
      ];

      final result = allocator.allocate(salaryReceived: 10000000, rules: rules);

      expect(result.salaryReceived, 10000000);
      expect(result.allocations['bucket-rent'], 2500000);
      expect(result.allocations['bucket-invest'], 2000000);
      expect(result.allocations['bucket-savings'], 2750000);
      expect(result.unallocatedRemaining, 2750000);
      expect(result.isFullyFunded, isTrue);
      expect(result.shortfalls, isEmpty);

      // Verify conservation invariant.
      expect(result.totalAllocated + result.unallocatedRemaining, 10000000);
    });

    test('enforces caps on percentage allocations', () {
      // Salary: ₹2,00,000 (20,000,000 paise)
      // Rule: 20% of salary = ₹40,000, but capped at ₹25,000 (2,500,000 paise)
      final rules = [
        const AllocationRule(
          id: 'rule-capped',
          bucketId: 'bucket-savings',
          type: AllocationType.percentageOfSalary,
          percentage: 20,
          cap: 2500000,
          priority: 1,
        ),
      ];

      final result = allocator.allocate(salaryReceived: 20000000, rules: rules);

      expect(result.allocations['bucket-savings'], 2500000);
      expect(result.unallocatedRemaining, 17500000);
      expect(result.totalAllocated + result.unallocatedRemaining, 20000000);
    });

    test('handles partial salary credit with priority order and shortfalls', () {
      // Salary received: ₹30,000 (3,000,000 paise) - partial salary!
      // Rule 1: Rent ₹25,000 (2,500,000 paise) [Priority 1, mandatory]
      // Rule 2: Mandates/EMI ₹15,000 (1,500,000 paise) [Priority 2, mandatory]
      // Rule 3: Discretionary ₹5,000 [Priority 3, non-mandatory]
      final rules = [
        const AllocationRule(
          id: 'r1',
          bucketId: 'b-rent',
          type: AllocationType.fixed,
          fixedAmount: 2500000,
          priority: 1,
        ),
        const AllocationRule(
          id: 'r2',
          bucketId: 'b-emi',
          type: AllocationType.fixed,
          fixedAmount: 1500000,
          priority: 2,
        ),
        const AllocationRule(
          id: 'r3',
          bucketId: 'b-discretionary',
          type: AllocationType.fixed,
          fixedAmount: 500000,
          priority: 3,
          isMandatory: false,
        ),
      ];

      final result = allocator.allocate(salaryReceived: 3000000, rules: rules);

      // Rent gets full ₹25,000
      expect(result.allocations['b-rent'], 2500000);
      // EMI gets remaining ₹5,000 (500,000 paise) out of desired ₹15,000
      expect(result.allocations['b-emi'], 500000);
      // Discretionary gets ₹0
      expect(result.allocations['b-discretionary'], 0);
      // Unallocated is 0
      expect(result.unallocatedRemaining, 0);

      // Shortfall: EMI is short by ₹10,000 (1,000,000 paise)
      expect(result.isFullyFunded, isFalse);
      expect(result.shortfalls['b-emi'], 1000000);
      // Non-mandatory discretionary does not record shortfall
      expect(result.shortfalls.containsKey('b-discretionary'), isFalse);

      // Conservation invariant must hold
      expect(result.totalAllocated + result.unallocatedRemaining, 3000000);
    });

    test('handles zero incoming salary gracefully', () {
      final rules = [
        const AllocationRule(
          id: 'r1',
          bucketId: 'b1',
          type: AllocationType.fixed,
          fixedAmount: 500000,
        ),
      ];

      final result = allocator.allocate(salaryReceived: 0, rules: rules);
      expect(result.allocations['b1'], 0);
      expect(result.unallocatedRemaining, 0);
      expect(result.shortfalls['b1'], 500000);
      expect(result.isFullyFunded, isFalse);
      expect(result.totalAllocated + result.unallocatedRemaining, 0);
    });

    test('throws ArgumentError on negative salary received', () {
      expect(
        () => allocator.allocate(salaryReceived: -100, rules: []),
        throwsArgumentError,
      );
    });

    test('is strictly deterministic across multiple runs', () {
      final rules = [
        const AllocationRule(
          id: 'r1',
          bucketId: 'b1',
          type: AllocationType.percentageOfSalary,
          percentage: 33.33,
          priority: 1,
        ),
        const AllocationRule(
          id: 'r2',
          bucketId: 'b2',
          type: AllocationType.percentageOfRemaining,
          percentage: 50,
          priority: 2,
        ),
      ];

      final run1 = allocator.allocate(salaryReceived: 7777777, rules: rules);
      final run2 = allocator.allocate(salaryReceived: 7777777, rules: rules);

      expect(run1, equals(run2));
      expect(run1.totalAllocated + run1.unallocatedRemaining, 7777777);
    });
  });
}
