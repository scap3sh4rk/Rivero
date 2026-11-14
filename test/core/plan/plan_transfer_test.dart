import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/plan/plan_transfer_service.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late SalaryPlanService plan;
  final now = DateTime(2026, 11, 14);
  final cycle = DateTime(2026, 11);

  Future<void> account(String id, String type, int balance, String mask) =>
      db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: Value(id),
          name: Value(id),
          institution: const Value('Bank'),
          accountMask: Value(mask),
          accountType: Value(type),
          balanceMinorUnits: Value(balance),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  Future<void> bucket(
    String id,
    AccountRole role,
    int order, {
    String? account,
  }) => db.accountsDao.upsertBucket(
    AllocationBucketsCompanion(
      id: Value(id),
      name: Value(id),
      role: Value(role),
      priorityOrder: Value(order),
      linkedPhysicalAccountId: Value(account),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  Future<int> bal(String id) async =>
      (await db.accountsDao.getPhysicalAccountById(id))!.balanceMinorUnits;
  Future<int> spent(String id) async =>
      (await db.accountsDao.getBucketById(id))!.spentMinorUnits;
  Future<List<LedgerTransaction>> planTxns() async =>
      (await db.select(db.transactions).get())
          .where((t) => t.id.startsWith('plan-'))
          .toList();

  Future<void> applyPlan({
    required int rent,
    required int invest,
    DateTime? at,
    String? salaryTxn = 'salary-credit',
  }) async {
    const salary = 5200000;
    await plan.apply(
      salary: salary,
      allocations: {'rent': rent, 'inv': invest, 'exp': salary - rent - invest},
      cycleStart: at ?? cycle,
      salaryTransactionId: salaryTxn,
    );
  }

  setUp(() async {
    db = RiveroDatabase.memory();
    plan = SalaryPlanService(db);
    await account('salary', 'Salary', 5200000, '4012'); // salary just landed
    await account('spend', 'Daily Expense', 0, '8841');
    await bucket('exp', AccountRole.expense, 1, account: 'spend');
    await bucket('inv', AccountRole.investment, 2);
    await bucket('rent', AccountRole.custom, 3);
    await db.settingsDao.set(SettingKeys.salaryAccount, 'salary');
  });
  tearDown(() => db.close());

  test(
    'moves only between tracked accounts; rent with no account changes nothing',
    () async {
      await applyPlan(rent: 1000000, invest: 500000);
      // Salary -> spending is a self-transfer. Rent and the (untracked)
      // investment have no account here, so they stay plan only.
      expect(await bal('salary'), 5200000 - 3700000);
      expect(await bal('spend'), 3700000);
      expect(await spent('rent'), 0); // not paid yet
      expect(await spent('inv'), 0);
      expect(await spent('exp'), 0); // the spending budget is untouched
      final exp = (await db.accountsDao.getBucketById('exp'))!;
      expect(exp.allocatedMinorUnits, 3700000); // = what the account received
      final txns = await planTxns();
      expect(txns, hasLength(2)); // one transfer, two legs
      expect(txns.every((t) => t.isInternalTransfer), isTrue);
      expect(txns.first.merchant, startsWith('Transfer: salary'));
    },
  );

  test(
    'revising the plan adjusts the same transfer, never duplicates',
    () async {
      await applyPlan(rent: 1000000, invest: 500000);
      await applyPlan(rent: 1200000, invest: 500000); // spending now ₹35,000
      expect(await bal('salary'), 5200000 - 3500000);
      expect(await bal('spend'), 3500000);
      expect(await planTxns(), hasLength(2));
      await applyPlan(rent: 1200000, invest: 500000); // identical: no change
      expect(await bal('spend'), 3500000);
      expect(await planTxns(), hasLength(2));
    },
  );

  test(
    'a category linked to a tracked account moves and counts as paid',
    () async {
      await account('mf', 'Investment / Demat', 0, '7777');
      await bucket('inv', AccountRole.investment, 2, account: 'mf');
      await applyPlan(rent: 0, invest: 500000);
      expect(await bal('mf'), 500000);
      expect(await bal('salary'), 5200000 - 500000 - 4700000);
      expect(await spent('inv'), 500000); // paid
      final inn = (await planTxns()).firstWhere((t) => t.id.endsWith('inv-in'));
      expect(inn.isInternalTransfer, isTrue);
      expect(inn.linkedTransactionId, endsWith('inv-out'));
      expect(inn.merchant, 'Transfer: salary → mf');

      // Dropping it gives everything back.
      await applyPlan(rent: 0, invest: 0);
      expect(await bal('mf'), 0);
      expect(await spent('inv'), 0);
    },
  );

  test('salary and spending in one account: no transfer at all', () async {
    await bucket('exp', AccountRole.expense, 1, account: 'salary');
    await applyPlan(rent: 1000000, invest: 500000);
    expect(await bal('salary'), 5200000);
    expect(await planTxns(), isEmpty);
  });

  test(
    'setup-style apply (no salary credit, nothing moved yet) moves no money',
    () async {
      await applyPlan(rent: 1000000, invest: 500000, salaryTxn: null);
      expect(await bal('salary'), 5200000);
      expect(await bal('spend'), 0);
      expect(await planTxns(), isEmpty);
      await applyPlan(rent: 900000, invest: 500000, salaryTxn: null);
      expect(await planTxns(), isEmpty); // quiet until money has moved
    },
  );

  test(
    'a new cycle moves its own money and leaves the old cycle alone',
    () async {
      await applyPlan(rent: 1000000, invest: 500000);
      await account('salary', 'Salary', 5200000, '4012'); // next salary lands
      await applyPlan(
        rent: 1000000,
        invest: 500000,
        at: DateTime(2026, 12),
        salaryTxn: 'dec',
      );
      final ids = (await planTxns()).map((t) => t.id).toSet();
      expect(ids.any((i) => i.startsWith('plan-20261101-')), isTrue);
      expect(ids.any((i) => i.startsWith('plan-20261201-')), isTrue);
    },
  );

  test('deleting the transfer from Activity undoes both legs', () async {
    await applyPlan(rent: 0, invest: 0);
    final out = (await planTxns()).firstWhere((t) => t.id.endsWith('exp-out'));
    await LedgerService(db).remove(out.linkedTransactionId!);
    await LedgerService(db).remove(out.id);
    expect(await bal('salary'), 5200000);
    expect(await bal('spend'), 0);
  });

  test('shortfall warns when the salary has not arrived yet', () async {
    final salary = (await db.accountsDao.getPhysicalAccountById('salary'))!;
    final moves = PlanTransferService(db).movesFor(
      allocations: {'rent': 1000000, 'inv': 500000, 'exp': 3700000},
      buckets: await db.accountsDao.getAllBuckets(),
      salary: salary,
      spending: await db.accountsDao.getPhysicalAccountById('spend'),
    );
    expect(moves, hasLength(1)); // only the spending transfer is a move
    expect(PlanTransferService.shortfall(salary, moves), 0);
    final poor = salary.copyWith(balanceMinorUnits: 1000000);
    expect(PlanTransferService.shortfall(poor, moves), 2700000);
  });

  test('plan-only categories are listed separately', () async {
    final salary = (await db.accountsDao.getPhysicalAccountById('salary'))!;
    final only = PlanTransferService(db).planOnly(
      allocations: {'rent': 1000000, 'inv': 500000, 'exp': 3700000},
      buckets: await db.accountsDao.getAllBuckets(),
      salary: salary,
    );
    expect(only.map((m) => m.bucketId), unorderedEquals(['rent', 'inv']));
  });

  group("the bank's own messages", () {
    Future<void> sms(String id, String body) => IngestionService(database: db)
        .processNotification(
          RawNotification(
            id: id,
            sender: 'VK-HDFCBK',
            receivedAt: now,
            body: body,
          ),
        );

    test('the planned self-transfer legs are matched, not doubled', () async {
      await applyPlan(rent: 1000000, invest: 500000);
      final before = (await db.select(db.transactions).get()).length;
      await sms(
        'out',
        'HDFC Bank: Rs 37,000.00 debited from a/c **4012 on 14-11-26 to VPA me@icici (UPI Ref No 431712340000).',
      );
      await sms(
        'in',
        'ICICI Bank: Rs 37,000.00 credited to a/c XX8841 on 14-11-26 by UPI Ref No 431712340000.',
      );
      expect((await db.select(db.transactions).get()).length, before);
      expect(await bal('salary'), 1500000); // not deducted twice
      expect(await bal('spend'), 3700000); // not credited twice
      final legs = await planTxns();
      expect(
        legs.every((t) => t.transactionState == TransactionState.reconciled),
        isTrue,
      );
    });

    test(
      'rent debit matches its plan-only category and waits for review',
      () async {
        await applyPlan(rent: 1000000, invest: 500000);
        await sms(
          'rent',
          'HDFC Bank: Rs 10,000.00 debited from a/c **4012 on 14-11-26 to VPA landlord@icici (UPI Ref No 431712349999).',
        );
        final t = (await db.select(db.transactions).get()).firstWhere(
          (t) => t.merchant.toLowerCase().contains('landlord'),
        );
        expect(t.transactionType, TransactionType.planTransfer);
        expect(t.category, 'rent');
        expect(t.allocationBucketId, 'rent');
        expect(t.transactionState, TransactionState.needsReview);
        expect(await spent('rent'), 0); // not paid until the user confirms

        await LedgerService(db).confirm(t.id);
        expect(await spent('rent'), 1000000);
        expect(await spent('exp'), 0); // never touches everyday spending
        await LedgerService(db).remove(t.id);
        expect(await spent('rent'), 0);
      },
    );

    test('an ambiguous amount is left as a normal expense', () async {
      await bucket('rent2', AccountRole.custom, 4);
      await applyPlan(rent: 1000000, invest: 0);
      await plan.apply(
        salary: 5200000,
        allocations: {'rent': 1000000, 'rent2': 1000000, 'exp': 3200000},
        cycleStart: cycle,
        salaryTransactionId: 'again',
      );
      await sms(
        'amb',
        'HDFC Bank: Rs 10,000.00 debited from a/c **4012 on 14-11-26 to VPA shop@icici (UPI Ref No 431712348888).',
      );
      final t = (await db.select(db.transactions).get()).firstWhere(
        (t) => t.merchant.toLowerCase().contains('shop'),
      );
      expect(t.transactionType, isNot(TransactionType.planTransfer));
    });
  });

  test('set balance records the difference as a visible entry', () async {
    final ledger = LedgerService(db);
    expect(await ledger.setBalance('salary', 6000000), 800000);
    expect(await bal('salary'), 6000000);
    final adj = (await db.select(db.transactions).get()).single;
    expect(adj.transactionType, TransactionType.balanceAdjustment);
    expect(adj.merchant, 'Balance update');
    expect(
      await ledger.setBalance('salary', 6000000),
      0,
    ); // no change, no entry
    expect(await ledger.setBalance('salary', 100), -5999900);
    expect(await bal('salary'), 100);
    expect(await ledger.setBalance('nope', 5), 0);
  });
}
