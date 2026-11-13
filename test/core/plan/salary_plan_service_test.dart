import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late SalaryPlanService plan;
  final now = DateTime(2026, 11, 14);

  Future<void> bucket(String id, AccountRole role, int target, int order) =>
      db.accountsDao.upsertBucket(
        AllocationBucketsCompanion(
          id: Value(id),
          name: Value(id),
          role: Value(role),
          targetMinorUnits: Value(target),
          priorityOrder: Value(order),
          spentMinorUnits: const Value(500),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  setUp(() async {
    db = RiveroDatabase.memory();
    plan = SalaryPlanService(db);
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('a'),
        name: const Value('a'),
        institution: const Value('b'),
        accountMask: const Value('1'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await bucket('exp', AccountRole.expense, 0, 1);
    await bucket('inv', AccountRole.investment, 3000000, 2);
    await bucket('sav', AccountRole.savings, 1000000, 3);
  });
  tearDown(() => db.close());

  test(
    'preview funds fixed buckets first and expense takes the rest',
    () async {
      final b = await db.accountsDao.getAllBuckets();
      final p = plan.preview(10000000, b);
      expect(p['inv'], 3000000);
      expect(p['sav'], 1000000);
      expect(p['exp'], 6000000);
      expect(p.values.fold<int>(0, (a, c) => a + c), 10000000);
    },
  );

  test('a small salary never over-allocates', () async {
    final b = await db.accountsDao.getAllBuckets();
    final p = plan.preview(2000000, b);
    expect(p.values.fold<int>(0, (a, c) => a + c) <= 2000000, isTrue);
  });

  test(
    'apply writes allocations, resets spend and rejects over-allocation',
    () async {
      await plan.apply(
        salary: 10000000,
        allocations: {'exp': 7000000, 'inv': 3000000, 'sav': 0},
        salaryTransactionId: 't1',
      );
      final b = {for (final x in await db.accountsDao.getAllBuckets()) x.id: x};
      expect(b['exp']!.allocatedMinorUnits, 7000000);
      expect(b['exp']!.spentMinorUnits, 0);
      expect(b['sav']!.targetMinorUnits, 0); // remembered: skipped savings

      expect(
        () => plan.apply(salary: 100, allocations: {'exp': 101}),
        throwsArgumentError,
      );
    },
  );

  test(
    'pendingSalary finds a big confirmed credit once, then not after planning',
    () async {
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('t1'),
          physicalAccountId: const Value('a'),
          amountMinorUnits: const Value(9000000),
          transactionType: const Value(TransactionType.income),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('ACME'),
          category: const Value('Income'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );
      final start = DateTime(2026, 11);
      expect(
        await plan.pendingSalary(cycleStart: start, expectedSalary: 10000000),
        isNotNull,
      );
      expect(
        await plan.pendingSalary(cycleStart: start, expectedSalary: 90000000),
        isNull,
      );
      await plan.apply(
        salary: 9000000,
        allocations: {'exp': 9000000},
        salaryTransactionId: 't1',
      );
      expect(
        await plan.pendingSalary(cycleStart: start, expectedSalary: 10000000),
        isNull,
      );
    },
  );

  test('unspent spending money carries over; overspend does not', () async {
    await plan.apply(salary: 10000000, allocations: {'exp': 6000000});
    await db.accountsDao.recordBucketSpend('exp', 4000000); // 20k unspent
    await plan.apply(salary: 10000000, allocations: {'exp': 6000000});
    var exp = (await db.accountsDao.getBucketById('exp'))!;
    expect(exp.allocatedMinorUnits, 6000000); // allocation never exceeds salary
    expect(exp.carryOverMinorUnits, 2000000);
    expect(exp.spentMinorUnits, 0);

    await db.accountsDao.recordBucketSpend('exp', 9000000); // overspend by 1k
    await plan.apply(salary: 10000000, allocations: {'exp': 6000000});
    exp = (await db.accountsDao.getBucketById('exp'))!;
    expect(exp.carryOverMinorUnits, 0);

    await db.accountsDao.recordBucketSpend('exp', 1000000);
    await plan.apply(
      salary: 10000000,
      allocations: {'exp': 6000000},
      carryOver: false,
    );
    expect((await db.accountsDao.getBucketById('exp'))!.carryOverMinorUnits, 0);
  });

  test('awaiting salary once a new cycle starts without a split', () async {
    final nov = DateTime(2026, 11);
    final dec = DateTime(2026, 12);
    expect(await plan.awaitingSalary(dec), isFalse); // never planned: no nag
    await plan.apply(salary: 100, allocations: {'exp': 100}, cycleStart: nov);
    expect(await plan.awaitingSalary(nov), isFalse);
    expect(await plan.awaitingSalary(dec), isTrue);
  });

  test(
    'custom categories: add, reject duplicates/blank, remove only custom',
    () async {
      final id = await plan.addCustomCategory('Rent', 2500000);
      final rent = (await db.accountsDao.getBucketById(id))!;
      expect(rent.role, AccountRole.custom);
      expect(rent.targetMinorUnits, 2500000);
      expect(
        () => plan.addCustomCategory(' rent ', 1),
        throwsA(isA<PlanValidationException>()),
      );
      expect(
        () => plan.addCustomCategory('   ', 1),
        throwsA(isA<PlanValidationException>()),
      );
      // Rent is set aside before spending gets the rest
      final p = plan.preview(10000000, await db.accountsDao.getAllBuckets());
      expect(p[id], 2500000);
      expect(p['exp'], 10000000 - 3000000 - 1000000 - 2500000);

      await plan.removeCategory('inv'); // default bucket: kept
      expect(await db.accountsDao.getBucketById('inv'), isNotNull);
      await plan.removeCategory(id);
      expect(await db.accountsDao.getBucketById(id), isNull);
    },
  );

  test('a salary landing two days before pay day still counts', () async {
    await db.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: const Value('early'),
        physicalAccountId: const Value('a'),
        amountMinorUnits: const Value(9000000),
        transactionType: const Value(TransactionType.income),
        transactionState: const Value(TransactionState.confirmed),
        merchant: const Value('ACME SALARY'),
        category: const Value('Income'),
        transactionTimestamp: Value(DateTime(2026, 11, 29)),
        createdAt: Value(now),
      ),
    );
    final found = await plan.pendingSalary(
      cycleStart: DateTime(2026, 12),
      expectedSalary: 10000000,
    );
    expect(found?.id, 'early');
  });
}
