import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/engine/allocation_rule.dart';

void main() {
  group('AllocationRule', () {
    test('creates valid fixed allocation rule', () {
      const rule = AllocationRule(
        id: 'rule-rent',
        bucketId: 'bucket-rent',
        type: AllocationType.fixed,
        fixedAmount: 2500000, // ₹25,000
        priority: 1,
      );

      expect(rule.id, 'rule-rent');
      expect(rule.bucketId, 'bucket-rent');
      expect(rule.type, AllocationType.fixed);
      expect(rule.fixedAmount, 2500000);
      expect(rule.percentage, isNull);
      expect(rule.priority, 1);
      expect(rule.isMandatory, isTrue);
    });

    test('creates valid percentage of salary rule', () {
      const rule = AllocationRule(
        id: 'rule-savings',
        bucketId: 'bucket-savings',
        type: AllocationType.percentageOfSalary,
        percentage: 20,
        priority: 2,
        cap: 3000000,
      );

      expect(rule.type, AllocationType.percentageOfSalary);
      expect(rule.percentage, 20);
      expect(rule.cap, 3000000);
    });

    test('creates valid percentage of remaining rule', () {
      const rule = AllocationRule(
        id: 'rule-splurge',
        bucketId: 'bucket-fun',
        type: AllocationType.percentageOfRemaining,
        percentage: 50,
        priority: 5,
        isMandatory: false,
      );

      expect(rule.type, AllocationType.percentageOfRemaining);
      expect(rule.percentage, 50);
      expect(rule.isMandatory, isFalse);
    });

    test('asserts on invalid fixed rule without amount', () {
      expect(
        () => AllocationRule(
          id: 'invalid',
          bucketId: 'b',
          type: AllocationType.fixed,
        ),
        throwsAssertionError,
      );
    });

    test('asserts on invalid fixed rule with negative amount', () {
      expect(
        () => AllocationRule(
          id: 'invalid',
          bucketId: 'b',
          type: AllocationType.fixed,
          fixedAmount: -500,
        ),
        throwsAssertionError,
      );
    });

    test('asserts on percentage rule without percentage', () {
      expect(
        () => AllocationRule(
          id: 'invalid',
          bucketId: 'b',
          type: AllocationType.percentageOfSalary,
        ),
        throwsAssertionError,
      );
    });

    test('asserts on percentage rule with percentage <= 0 or > 100', () {
      expect(
        () => AllocationRule(
          id: 'invalid',
          bucketId: 'b',
          type: AllocationType.percentageOfSalary,
          percentage: 0,
        ),
        throwsAssertionError,
      );

      expect(
        () => AllocationRule(
          id: 'invalid',
          bucketId: 'b',
          type: AllocationType.percentageOfSalary,
          percentage: 105,
        ),
        throwsAssertionError,
      );
    });

    test('asserts on negative cap or negative priority', () {
      expect(
        () => AllocationRule(
          id: 'invalid',
          bucketId: 'b',
          type: AllocationType.fixed,
          fixedAmount: 1000,
          cap: -100,
        ),
        throwsAssertionError,
      );

      expect(
        () => AllocationRule(
          id: 'invalid',
          bucketId: 'b',
          type: AllocationType.fixed,
          fixedAmount: 1000,
          priority: -1,
        ),
        throwsAssertionError,
      );
    });

    test('copyWith updates properties correctly', () {
      const original = AllocationRule(
        id: 'r1',
        bucketId: 'b1',
        type: AllocationType.fixed,
        fixedAmount: 1000,
        priority: 1,
      );

      final updated = original.copyWith(fixedAmount: 2000, priority: 2);
      expect(updated.fixedAmount, 2000);
      expect(updated.priority, 2);
      expect(updated.id, 'r1');
      expect(updated.bucketId, 'b1');
    });

    test('equality and hashCode contract', () {
      const r1 = AllocationRule(
        id: 'r1',
        bucketId: 'b1',
        type: AllocationType.fixed,
        fixedAmount: 1000,
      );
      const r2 = AllocationRule(
        id: 'r1',
        bucketId: 'b1',
        type: AllocationType.fixed,
        fixedAmount: 1000,
      );
      const r3 = AllocationRule(
        id: 'r2',
        bucketId: 'b1',
        type: AllocationType.fixed,
        fixedAmount: 1000,
      );

      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
      expect(r1, isNot(equals(r3)));
    });
  });
}
