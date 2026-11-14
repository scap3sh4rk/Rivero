import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/ledger/ledger_service.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late DuesService dues;
  late LedgerService ledger;
  final now = DateTime.now();

  setUp(() async {
    db = RiveroDatabase.memory();
    dues = DuesService(db);
    ledger = LedgerService(db);
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('bank'),
        name: const Value('Bank'),
        institution: const Value('Bank'),
        accountMask: const Value('1234'),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('b'),
        name: const Value('Spending'),
        role: const Value(AccountRole.expense),
        allocatedMinorUnits: const Value(5000000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> spent() async =>
      (await db.accountsDao.getBucketById('b'))!.spentMinorUnits;
  Future<List<Due>> all() => db.select(db.dues).get();

  test('equal split keeps whole paise; remainder stays with you', () {
    expect(DuesService.equalShares(300000, 4), [75000, 75000, 75000]);
    expect(DuesService.equalShares(100000, 3), [33333, 33333]);
    expect(DuesService.equalShares(100, 1), isEmpty);
  });

  test('the dinner: ₹3000 for four shows ₹750 spent; budget refills as friends pay', () async {
    final id = await ledger.recordManual(
      accountId: 'bank',
      amountMinorUnits: -300000,
      type: TransactionType.expense,
      merchant: 'Dinner',
      category: 'Food',
    );
    expect(await spent(), 300000);

    await dues.splitExpense(
      transactionId: id,
      shares: {'Ravi': 75000, 'Asha': 75000, 'Kiran': 75000},
    );
    final txns = await db.select(db.transactions).get();
    final summary = SpendingSummary.of(
      txns,
      start: now.subtract(const Duration(days: 1)),
      end: now.add(const Duration(minutes: 1)),
      othersShare: DuesService.othersShareByTransaction(await all()),
    );
    expect(summary.total, 75000); // your share only
    expect(DuesService.totalOutstanding(await all()), 225000);
    expect(await spent(), 300000); // money not back yet

    // Ravi pays back by UPI: tagged as paid back, not income; budget refills.
    final credit = await ledger.recordManual(
      accountId: 'bank',
      amountMinorUnits: 75000,
      type: TransactionType.income,
      merchant: 'RAVI K',
      category: 'Income',
    );
    final ravi = (await all()).firstWhere((d) => d.person == 'Ravi');
    expect(
      (await dues.repaymentCandidates(ravi.id)).map((t) => t.id),
      contains(credit),
    );
    await dues.receive(ravi.id, 75000, creditTransactionId: credit);
    expect(
      (await db.transactionsDao.getTransactionById(credit))!.transactionType,
      TransactionType.reimbursement,
    );
    expect(await spent(), 225000);
    expect(
      (await all()).firstWhere((d) => d.person == 'Ravi').status,
      DueStatus.settled,
    );

    // Asha pays half in cash: partial, still open.
    final asha = (await all()).firstWhere((d) => d.person == 'Asha');
    await dues.receive(asha.id, 30000);
    final asha2 = (await all()).firstWhere((d) => d.person == 'Asha');
    expect(asha2.status, DueStatus.open);
    expect(dues.outstandingOf(asha2), 45000);
    expect(
      () => dues.receive(asha.id, 50000),
      throwsA(isA<DueValidationException>()),
    );
  });

  test(
    'shares larger than the bill, or splitting income, are rejected',
    () async {
      final id = await ledger.recordManual(
        accountId: 'bank',
        amountMinorUnits: -10000,
        type: TransactionType.expense,
        merchant: 'Cab',
        category: 'Transport',
      );
      expect(
        () => dues.splitExpense(transactionId: id, shares: {'Ravi': 20000}),
        throwsA(isA<DueValidationException>()),
      );
      final income = await ledger.recordManual(
        accountId: 'bank',
        amountMinorUnits: 10000,
        type: TransactionType.income,
        merchant: 'Salary',
        category: 'Income',
      );
      expect(
        () => dues.splitExpense(transactionId: income, shares: {'Ravi': 100}),
        throwsA(isA<DueValidationException>()),
      );
    },
  );

  test('lending is not spending; writing it off is', () async {
    await db.accountsDao.updateAccountBalance('bank', 100000);
    await dues.lend(
      person: 'Kiran',
      amountMinorUnits: 50000,
      accountId: 'bank',
    );
    expect(
      (await db.accountsDao.getPhysicalAccountById('bank'))!.balanceMinorUnits,
      50000,
    );
    expect(await spent(), 0);
    final d = (await all()).single;
    expect(d.kind, DueKind.lent);
    await dues.writeOff(d.id);
    expect(await spent(), 50000);
    expect((await all()).single.status, DueStatus.writtenOff);
  });

  group('money you owe', () {
    Future<int> balance() async =>
        (await db.accountsDao.getPhysicalAccountById('bank'))!
            .balanceMinorUnits;

    test(
      'borrowing adds to the account but is not income or spending',
      () async {
        await db.accountsDao.updateAccountBalance('bank', 100000);
        await dues.borrow(
          person: 'Ravi',
          amountMinorUnits: 500000,
          accountId: 'bank',
          dueDate: DateTime(2026, 12, 5),
        );
        expect(await balance(), 600000);
        final d = (await all()).single;
        expect(d.kind, DueKind.borrowed);
        expect(DuesService.totalYouOwe(await all()), 500000);
        // Not "owed to you", not spending, no budget used.
        expect(DuesService.totalOutstanding(await all()), 0);
        expect(await spent(), 0);
        final t = (await db.transactionsDao.getAllTransactions()).single;
        expect(t.transactionType, TransactionType.borrowing);
        expect(SpendingSummary.isSpending(t), isFalse);
      },
    );

    test('repaying leaves the account, is not spending, and settles', () async {
      await db.accountsDao.updateAccountBalance('bank', 100000);
      await dues.borrow(person: 'Ravi', amountMinorUnits: 300000);
      final d = (await all()).single;
      await dues.repay(d.id, 100000, accountId: 'bank');
      expect(await balance(), 0);
      expect(DuesService.totalYouOwe(await all()), 200000);
      expect(await spent(), 0);
      await dues.repay(d.id, 200000); // in cash
      expect((await all()).single.status, DueStatus.settled);
      expect(await balance(), 0);
    });

    test('guards: too much, wrong kind, receiving what you owe', () async {
      await dues.borrow(person: 'Ravi', amountMinorUnits: 100000);
      final d = (await all()).single;
      await expectLater(
        dues.repay(d.id, 200000),
        throwsA(isA<DueValidationException>()),
      );
      await expectLater(
        dues.receive(d.id, 1000),
        throwsA(isA<DueValidationException>()),
      );
      await dues.lend(person: 'Mina', amountMinorUnits: 50000);
      final lent = (await all()).firstWhere((x) => x.kind == DueKind.lent);
      await expectLater(
        dues.repay(lent.id, 1000),
        throwsA(isA<DueValidationException>()),
      );
      await expectLater(
        dues.borrow(person: ' ', amountMinorUnits: 100),
        throwsA(isA<DueValidationException>()),
      );
    });

    test('dated debts due before payday are reserved', () async {
      await dues.borrow(
        person: 'Ravi',
        amountMinorUnits: 400000,
        dueDate: DateTime(2026, 11, 20),
      );
      await dues.borrow(
        person: 'Mina',
        amountMinorUnits: 900000,
        dueDate: DateTime(2026, 12, 20),
      );
      final list = await all();
      expect(DuesService.youOweDueBy(list, DateTime(2026, 11, 30)), 400000);
      expect(DuesService.youOweDueBy(list, DateTime(2026, 12, 31)), 1300000);
    });
  });

  group('logged later than it happened', () {
    test('a loan keeps the day it really happened, and its photo', () async {
      await db.accountsDao.updateAccountBalance('bank', 500000);
      final n = DateTime.now().subtract(const Duration(days: 3));
      final day = DateTime(n.year, n.month, n.day, 10);
      await dues.lend(
        person: 'Kiran',
        amountMinorUnits: 100000,
        accountId: 'bank',
        on: day,
        attachmentPath: '/tmp/proof.jpg',
      );
      final d = (await all()).single;
      expect(d.createdAt, day);
      expect(d.attachmentPath, '/tmp/proof.jpg');
      final t = (await db.transactionsDao.getAllTransactions()).single;
      expect(t.transactionTimestamp, day);
      expect(t.attachmentPath, '/tmp/proof.jpg');
    });

    test('borrowing too, and a future date is refused', () async {
      final n = DateTime.now().subtract(const Duration(days: 10));
      final day = DateTime(n.year, n.month, n.day, 10);
      await dues.borrow(person: 'Meera', amountMinorUnits: 50000, on: day);
      expect((await all()).single.createdAt, day);
      await expectLater(
        dues.borrow(
          person: 'Meera',
          amountMinorUnits: 50000,
          on: DateTime.now().add(const Duration(days: 30)),
        ),
        throwsA(isA<DueValidationException>()),
      );
    });
  });
}
