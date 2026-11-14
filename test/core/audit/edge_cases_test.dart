import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/sts_breakdown.dart';
import 'package:rivero/core/import/bill_parser.dart';
import 'package:rivero/core/import/statement_parser.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/core/utils/calc.dart';

final _now = DateTime(2026, 11, 14, 15);

AllocationBucket _bucket(
  String id,
  AccountRole role, {
  int allocated = 0,
  int carry = 0,
  int spent = 0,
  String? account,
}) => AllocationBucket(
  id: id,
  name: id,
  role: role,
  allocatedMinorUnits: allocated,
  carryOverMinorUnits: carry,
  spentMinorUnits: spent,
  linkedPhysicalAccountId: account,
  priorityOrder: 1,
  createdAt: _now,
  updatedAt: _now,
);

PhysicalAccount _account(
  String id,
  int balance, {
  bool card = false,
  int limit = 0,
}) => PhysicalAccount(
  id: id,
  name: id,
  institution: 'Bank',
  accountMask: '1234',
  balanceMinorUnits: balance,
  creditLimitMinorUnits: limit,
  accountType: 'Savings',
  currencyCode: 'INR',
  isLiability: card,
  isActive: true,
  sortOrder: 0,
  createdAt: _now,
  updatedAt: _now,
);

Mandate _mandate(int amount, DateTime due, {int? cap, bool active = true}) =>
    Mandate(
      id: 'm$amount',
      payee: 'Netflix',
      amountMinorUnits: amount,
      isVariableAmount: cap != null,
      maxCapMinorUnits: cap,
      frequency: MandateFrequency.monthly,
      physicalAccountId: 'a',
      startDate: _now,
      nextExecutionDate: due,
      status: active ? MandateStatus.active : MandateStatus.paused,
      createdAt: _now,
      updatedAt: _now,
    );

StsBreakdown _sts({
  List<AllocationBucket> buckets = const [],
  List<PhysicalAccount> accounts = const [],
  List<Mandate> mandates = const [],
  bool cards = true,
  DateTime? now,
}) => StsBreakdown.compute(
  buckets: buckets,
  accounts: accounts,
  mandates: mandates,
  dues: const [],
  cycle: Paycycle.fromSalaryDay(salaryCreditDay: 1, asOf: now ?? _now),
  reserveCards: cards,
  includeOwed: false,
  now: now ?? _now,
);

void main() {
  group('Safe to spend', () {
    test('₹52,000 salary, ₹5,000 invested, rest spendable: ₹47,000 to use', () {
      final b = _sts(
        buckets: [
          _bucket('exp', AccountRole.expense, allocated: 4700000),
          _bucket('inv', AccountRole.investment, allocated: 500000),
        ],
      );
      expect(b.budgetLeft, 4700000);
      expect(b.setAside, 500000);
      expect(b.result.effectiveSafeToSpend, 4700000);
      // 14 Nov, cycle starts 1st: payday on 1 Dec = 17 days.
      expect(b.result.dailySpendingPace, 4700000 ~/ b.daysToPayday);
    });

    test('mandates and card bills are subtracted, owed money is not added', () {
      final b = _sts(
        buckets: [_bucket('exp', AccountRole.expense, allocated: 4700000)],
        accounts: [_account('card', -1000000, card: true, limit: 10000000)],
        mandates: [
          _mandate(64900, DateTime(2026, 11, 20)),
          _mandate(10000, DateTime(2026, 12, 5)), // next cycle: excluded
          _mandate(99900, DateTime(2026, 11, 22), active: false),
        ],
      );
      expect(b.mandatesTotal, 64900);
      expect(b.cardBills, 1000000);
      expect(b.result.effectiveSafeToSpend, 4700000 - 64900 - 1000000);
    });

    test('card reservation off leaves card dues out', () {
      final b = _sts(
        buckets: [_bucket('exp', AccountRole.expense, allocated: 100000)],
        accounts: [_account('card', -50000, card: true)],
        cards: false,
      );
      expect(b.cardBills, 0);
    });

    test('an autopay due today still counts later in the day', () {
      final b = _sts(
        buckets: [_bucket('exp', AccountRole.expense, allocated: 1000000)],
        mandates: [
          _mandate(50000, DateTime(2026, 11, 14)),
        ], // midnight, 15:00 now
      );
      expect(b.mandatesTotal, 50000);
    });

    test('a variable autopay reserves its cap', () {
      final b = _sts(
        buckets: [_bucket('exp', AccountRole.expense, allocated: 1000000)],
        mandates: [_mandate(80000, DateTime(2026, 11, 18), cap: 150000)],
      );
      expect(b.mandatesTotal, 150000);
    });

    test('spending more than the budget is a deficit with zero per day', () {
      final b = _sts(
        buckets: [
          _bucket('exp', AccountRole.expense, allocated: 100000, spent: 160000),
        ],
      );
      expect(b.overBudget, isTrue);
      expect(b.budgetLeft, -60000);
      expect(b.result.isDeficit, isTrue);
      expect(b.result.dailySpendingPace, 0);
      expect(b.result.deficitAmount, 60000);
    });

    test(
      'carry-over adds to the budget; payday today never divides by zero',
      () {
        final b = _sts(
          buckets: [
            _bucket(
              'exp',
              AccountRole.expense,
              allocated: 100000,
              carry: 25000,
            ),
          ],
          now: DateTime(2026, 11, 30, 23, 59), // last day of the cycle
        );
        expect(b.budgetLeft, 125000);
        expect(b.daysToPayday, greaterThanOrEqualTo(1));
        expect(b.result.dailySpendingPace, greaterThan(0));
      },
    );

    test('no spending bucket at all: everything zero, no crash', () {
      final b = _sts();
      expect(b.result.effectiveSafeToSpend, 0);
      expect(b.result.dailySpendingPace, 0);
    });

    test('mid-month start: the account balance caps the budget', () {
      final b = _sts(
        buckets: [
          _bucket('exp', AccountRole.expense, allocated: 4700000, account: 'a'),
        ],
        accounts: [_account('a', 1000000)], // only ₹10,000 really there
      );
      expect(b.limitedByAccount, isTrue);
      expect(b.result.effectiveSafeToSpend, 1000000);
    });

    test('account holding more than the budget: the budget stays the cap', () {
      final b = _sts(
        buckets: [
          _bucket('exp', AccountRole.expense, allocated: 1000000, account: 'a'),
        ],
        accounts: [_account('a', 9000000)],
      );
      expect(b.limitedByAccount, isFalse);
      expect(b.result.effectiveSafeToSpend, 1000000);
    });

    test('money promised to plan-only categories is not spendable', () {
      final b = _sts(
        buckets: [
          _bucket('exp', AccountRole.expense, allocated: 3000000, account: 'a'),
          _bucket('rent', AccountRole.custom, allocated: 1500000),
        ],
        accounts: [
          _account('a', 3000000),
        ], // salary account doubles as spending
      );
      expect(b.reservedInAccount, 1500000);
      expect(b.result.effectiveSafeToSpend, 1500000);
    });

    test(
      'paid categories and ones moved to another account reserve nothing',
      () {
        final b = _sts(
          buckets: [
            _bucket(
              'exp',
              AccountRole.expense,
              allocated: 3000000,
              account: 'a',
            ),
            _bucket(
              'rent',
              AccountRole.custom,
              allocated: 1500000,
              spent: 1500000,
            ),
            _bucket(
              'inv',
              AccountRole.investment,
              allocated: 500000,
              account: 'b',
            ),
          ],
          accounts: [_account('a', 3000000), _account('b', 0)],
        );
        expect(b.reservedInAccount, 0);
        expect(b.result.effectiveSafeToSpend, 3000000);
      },
    );

    test('an overdrawn spending account is a deficit', () {
      final b = _sts(
        buckets: [
          _bucket('exp', AccountRole.expense, allocated: 1000000, account: 'a'),
        ],
        accounts: [_account('a', -20000)],
      );
      expect(b.result.isDeficit, isTrue);
      expect(b.result.dailySpendingPace, 0);
    });
  });

  group('amount parsing: no overflow, underflow or silent garbage', () {
    test('only plain non-negative amounts parse', () {
      expect(parseAmountMinorUnits('250'), 25000);
      expect(parseAmountMinorUnits(' 99.5 '), 9950);
      for (final bad in [
        '-5',
        '-0.5',
        '1e9',
        '12abc',
        '1,000',
        '--',
        '+5',
        'abc',
      ]) {
        expect(parseAmountMinorUnits(bad), 0, reason: bad);
      }
    });

    test('the maximum is ₹100 crore; one paisa above is refused', () {
      expect(parseAmountMinorUnits('1000000000'), maxAmountMinorUnits);
      expect(parseAmountMinorUnits('1000000000.01'), 0);
      expect(parseAmountMinorUnits('99999999999999999999'), 0); // no wrap
      expect(isAmountTooLarge('1000000001'), isTrue);
      expect(isAmountTooLarge('999'), isFalse);
      expect(isAmountTooLarge('-5'), isFalse);
    });

    test('calculator refuses results that could wrap', () {
      expect(evaluateExpression('99999999999×99999999999'), isNull);
      expect(evaluateExpression('1000000000×1000000000'), isNull);
      expect(evaluateExpression('1000000001'), isNull);
      expect(evaluateExpression('999999999+999999999'), isNull); // sum too big
      expect(evaluateExpression('5-10'), -500); // negative stays negative
      expect(evaluateExpression('5÷0'), isNull);
      expect(evaluateExpression('0÷5'), 0);
    });

    test('statement rows with absurd numbers are skipped, not crashes', () {
      const csv =
          'Date,Narration,Debit,Credit\n'
          '01/11/26,Normal,"1,000.00",\n'
          '02/11/26,Huge,99999999999999999999999,\n'
          '03/11/26,Salary,,50000';
      final rows = parseStatementCsv(csv);
      expect(rows.map((r) => r.description), ['Normal', 'Salary']);
    });

    test('a phone number on a bill is not read as the total', () {
      final b = parseBillText(
        'Chai Point\nPh 9876543210123456789\nTotal 120.00',
      );
      expect(b.amountMinorUnits, 12000);
    });
  });
}
