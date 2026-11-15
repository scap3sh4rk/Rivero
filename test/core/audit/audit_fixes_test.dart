import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/engine/spending_summary.dart';
import 'package:rivero/core/import/statement_importer.dart';
import 'package:rivero/core/import/statement_parser.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/reconciliation/internal_transfer_matcher.dart';

import '../../test_helper.dart';

/// Regression tests for the 14 Nov 2026 audit (see each test's name).
void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late LedgerService ledger;
  final now = DateTime(2026, 11, 14);

  Future<void> account(String id, int balance, {bool card = false}) =>
      db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: Value(id),
          name: Value(id),
          institution: const Value('Bank'),
          accountMask: Value(card ? '7102' : '4012'),
          balanceMinorUnits: Value(balance),
          isLiability: Value(card),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  setUp(() async {
    db = RiveroDatabase.memory();
    ledger = LedgerService(db);
    await account('bank', 100000);
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('b'),
        name: const Value('Spending'),
        role: const Value(AccountRole.expense),
        allocatedMinorUnits: const Value(100000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });
  tearDown(() => db.close());

  Future<int> bal(String id) async =>
      (await db.accountsDao.getPhysicalAccountById(id))!.balanceMinorUnits;

  test(
    'H1: deleting an imported statement row leaves the balance alone',
    () async {
      await StatementImporter(db).importRows('bank', [
        StatementRow(
          date: now,
          description: 'Old coffee',
          amountMinorUnits: -5000,
        ),
      ]);
      final row = (await db.transactionsDao.getAllTransactions()).single;
      await ledger.remove(row.id);
      expect(await bal('bank'), 100000);
      expect(await db.transactionsDao.getAllTransactions(), isEmpty);
    },
  );

  test('H4: confirming twice at once applies the money once', () async {
    await db.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: const Value('t1'),
        physicalAccountId: const Value('bank'),
        amountMinorUnits: const Value(-20000),
        transactionType: const Value(TransactionType.expense),
        transactionState: const Value(TransactionState.needsReview),
        merchant: const Value('Shop'),
        category: const Value('Other'),
        transactionTimestamp: Value(now),
        createdAt: Value(now),
      ),
    );
    final results = await Future.wait([
      ledger.confirm('t1'),
      ledger.confirm('t1'),
      ledger.confirm('t1'),
    ]);
    expect(results.where((r) => r), hasLength(1));
    expect(await bal('bank'), 80000);
  });

  test('H4: parallel balance changes are never lost', () async {
    await Future.wait([
      for (var i = 0; i < 20; i++)
        db.accountsDao.adjustAccountBalance('bank', -100),
    ]);
    expect(await bal('bank'), 100000 - 2000);
  });

  test('M13: deleting the bill removes its unpaid split shares', () async {
    final id = await ledger.recordManual(
      accountId: 'bank',
      amountMinorUnits: -60000,
      type: TransactionType.expense,
      merchant: 'Dinner',
      category: 'Food',
    );
    final dues = DuesService(db);
    await dues.splitExpense(transactionId: id, shares: {'Ravi': 20000});
    await ledger.remove(id);
    expect(await db.select(db.dues).get(), isEmpty);
  });

  group('autopay', () {
    Future<void> mandate(
      String id,
      String payee,
      int amount,
      DateTime due, {
      MandateFrequency f = MandateFrequency.monthly,
    }) => db.mandatesDao.upsertMandate(
      MandatesCompanion(
        id: Value(id),
        payee: Value(payee),
        amountMinorUnits: Value(amount),
        frequency: Value(f),
        physicalAccountId: const Value('bank'),
        startDate: Value(now),
        nextExecutionDate: Value(due),
        status: const Value(MandateStatus.active),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    Future<DateTime?> next(String id) async =>
        (await db.mandatesDao.getAllMandates())
            .firstWhere((m) => m.id == id)
            .nextExecutionDate;

    test('M10: 31 Jan rolls to 28 Feb, not 3 Mar', () {
      expect(addMonths(DateTime(2027, 1, 31), 1), DateTime(2027, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(addMonths(DateTime(2026, 11, 30), 3), DateTime(2027, 2, 28));
      expect(addMonths(DateTime(2026, 12, 15), 1), DateTime(2027, 1, 15));
    });

    test('M12: payee matching is by whole words, never fragments', () {
      expect(MandateTracker.samePayee('Netflix', 'NETFLIX.COM'), isTrue);
      expect(MandateTracker.samePayee('Air', 'Airtel Broadband'), isFalse);
      expect(MandateTracker.samePayee('Airtel', 'Airtel Broadband'), isTrue);
    });

    test('M11: an autopay paid by hand moves to its next date', () async {
      await mandate('m', 'Netflix', 64900, now);
      await ledger.recordManual(
        accountId: 'bank',
        amountMinorUnits: -64900,
        type: TransactionType.expense,
        merchant: 'Subscriptions', // typed name differs; amount is exact
        category: 'Bills',
        at: now,
      );
      expect(await next('m'), DateTime(2026, 12, 14));
    });

    test(
      'M12: a different amount from the same shop does not roll it',
      () async {
        await mandate('m', 'Netflix', 64900, now);
        await ledger.recordManual(
          accountId: 'bank',
          amountMinorUnits: -19900,
          type: TransactionType.expense,
          merchant: 'Netflix',
          category: 'Fun',
          at: now,
        );
        expect(await next('m'), now);
      },
    );

    test('H6: overdue autopays stay reserved, then roll forward', () async {
      await mandate('m', 'Gym', 100000, now.subtract(const Duration(days: 2)));
      final cycleEnd = DateTime(2026, 11, 30, 23, 59);
      // Two days late, never seen: still reserved and shown as overdue.
      final up = upcomingMandates(
        await db.mandatesDao.getAllMandates(),
        now,
        cycleEnd,
      );
      expect(up.map((m) => m.id), ['m']);
      expect(isOverdue(up.single, now), isTrue);
      // A week late: assumed paid, moved to next month.
      await MandateTracker(db).rollOverdue(now.add(const Duration(days: 5)));
      expect(await next('m'), DateTime(2026, 12, 12));
    });

    test('L1: a weekly autopay is reserved for every week left', () async {
      await mandate(
        'w',
        'Milk',
        10000,
        DateTime(2026, 11, 15),
        f: MandateFrequency.weekly,
      );
      final m = (await db.mandatesDao.getAllMandates()).single;
      // 15, 22, 29 Nov before a 30 Nov cycle end.
      expect(debitsUntil(m, DateTime(2026, 11, 30, 23, 59)), 3);
      expect(reserveUntil(m, DateTime(2026, 11, 30, 23, 59)), 30000);
    });
  });

  group('salary timing', () {
    test('H5: salary two days early belongs to the next cycle', () {
      final cycle = Paycycle.fromSalaryDay(
        salaryCreditDay: 1,
        asOf: DateTime(2026, 11, 29),
      );
      expect(
        SalaryPlanService.cycleForSalary(cycle, DateTime(2026, 11, 29)),
        DateTime(2026, 12),
      );
      expect(
        SalaryPlanService.cycleForSalary(cycle, DateTime(2026, 11, 10)),
        DateTime(2026, 11),
      );
      // Once split, the new cycle counts days to the pay day after.
      final early = Paycycle.startedEarly(
        salaryCreditDay: 1,
        plannedStart: DateTime(2026, 12),
        asOf: DateTime(2026, 11, 29),
      );
      expect(early.cycleStartDate, DateTime(2026, 12));
      expect(early.daysRemaining, 33); // 29 Nov -> 1 Jan
    });

    test(
      'M5: once split, a big non-salary credit does not ask again',
      () async {
        final plan = SalaryPlanService(db);
        await db.settingsDao.set(
          SettingKeys.lastPlannedCycleStart,
          DateTime(2026, 11).toIso8601String(),
        );
        await ledger.recordManual(
          accountId: 'bank',
          amountMinorUnits: 4000000,
          type: TransactionType.income,
          merchant: 'Bonus',
          category: 'Income',
          at: now,
        );
        expect(
          await plan.pendingSalary(
            cycleStart: DateTime(2026, 11),
            expectedSalary: 5000000,
          ),
          isNull,
        );
      },
    );

    test("M7: moving pay day keeps the month's plan and its moves", () async {
      final plan = SalaryPlanService(db);
      await db.settingsDao.set(
        SettingKeys.lastPlannedCycleStart,
        DateTime(2026, 11).toIso8601String(),
      );
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('plan-20261101-b-out'),
          physicalAccountId: const Value('bank'),
          amountMinorUnits: const Value(-100),
          transactionType: const Value(TransactionType.internalTransfer),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('x'),
          category: const Value('x'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
          linkedTransactionId: const Value('plan-20261101-b-in'),
        ),
      );
      await plan.moveCycle(from: DateTime(2026, 11), to: DateTime(2026, 11, 5));
      final t = (await db.transactionsDao.getAllTransactions()).single;
      expect(t.id, 'plan-20261105-b-out');
      expect(t.linkedTransactionId, 'plan-20261105-b-in');
      expect(
        await db.settingsDao.get(SettingKeys.lastPlannedCycleStart),
        DateTime(2026, 11, 5).toIso8601String(),
      );
    });
  });

  group('M3: self-transfer matching', () {
    LedgerTransaction leg(
      String id,
      String acc,
      int amount,
      TransactionType type,
      DateTime at, {
      String? ref,
    }) => LedgerTransaction(
      id: id,
      physicalAccountId: acc,
      amountMinorUnits: amount,
      transactionType: type,
      transactionState: TransactionState.confirmed,
      merchant: id,
      category: 'x',
      referenceNumber: ref,
      transactionTimestamp: at,
      isInternalTransfer: false,
      createdAt: at,
    );
    const matcher = InternalTransferMatcher();

    test('paying one friend while another pays you is not a transfer', () {
      final pairs = matcher.findTransferPairs(
        unlinkedTransactions: [
          leg('out', 'sbi', -50000, TransactionType.expense, now, ref: 'A1'),
          leg(
            'in',
            'spend',
            50000,
            TransactionType.income,
            now.add(const Duration(seconds: 30)),
            ref: 'B2',
          ),
        ],
      );
      expect(pairs, isEmpty);
    });

    test('without references only an almost simultaneous pair counts', () {
      List<Object> pairsAfter(Duration d) => matcher.findTransferPairs(
        unlinkedTransactions: [
          leg('out', 'sbi', -50000, TransactionType.expense, now),
          leg('in', 'spend', 50000, TransactionType.income, now.add(d)),
        ],
      );
      expect(pairsAfter(const Duration(seconds: 40)), hasLength(1));
      expect(pairsAfter(const Duration(minutes: 4)), isEmpty);
    });

    test('a loan or a hand-set balance is never half of a transfer', () {
      final pairs = matcher.findTransferPairs(
        unlinkedTransactions: [
          leg('out', 'sbi', -50000, TransactionType.lending, now),
          leg('in', 'spend', 50000, TransactionType.balanceAdjustment, now),
        ],
      );
      expect(pairs, isEmpty);
    });
  });

  test(
    'M4: confirming a capture moves the balance by its amount only, never to '
    'the "Avl bal" in the message',
    () async {
      await db.ingestionLogsDao.insertLog(
        RawIngestionLogsCompanion(
          id: const Value('log1'),
          sourceChannel: const Value(IngestionChannel.notificationAndroid),
          rawPayload: const Value(
            'Rs 200.00 debited from A/c XX4012. Avl bal: Rs 777.00',
          ),
          receivedAt: Value(now),
          parseStatus: const Value(ParseStatus.parsed),
          confidenceScore: const Value(0.7),
          createdAt: Value(now),
        ),
      );
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('t'),
          ingestionLogId: const Value('log1'),
          physicalAccountId: const Value('bank'),
          amountMinorUnits: const Value(-20000),
          transactionType: const Value(TransactionType.expense),
          transactionState: const Value(TransactionState.needsReview),
          merchant: const Value('Shop'),
          category: const Value('Other'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );
      await ledger.confirm('t');
      expect(await bal('bank'), 80000); // ₹1,000 - ₹200; ₹777 is ignored
    },
  );

  test('M16/L5: one rule for what counts as spending', () {
    LedgerTransaction t(TransactionType type, int amount) => LedgerTransaction(
      id: '$type',
      physicalAccountId: 'bank',
      amountMinorUnits: amount,
      transactionType: type,
      transactionState: TransactionState.confirmed,
      merchant: 'm',
      category: 'c',
      transactionTimestamp: now,
      isInternalTransfer: false,
      createdAt: now,
    );
    expect(SpendingSummary.isSpending(t(TransactionType.expense, -1)), isTrue);
    expect(SpendingSummary.isSpending(t(TransactionType.refund, 1)), isTrue);
    for (final not in [
      TransactionType.lending,
      TransactionType.atmWithdrawal,
      TransactionType.balanceAdjustment,
      TransactionType.creditCardSettlement,
      TransactionType.reimbursement,
    ]) {
      expect(SpendingSummary.isSpending(t(not, -1)), isFalse, reason: '$not');
    }
    final rent = t(TransactionType.planTransfer, -1500000);
    expect(SpendingSummary.isSpending(rent), isTrue);
    expect(SpendingSummary.isSpending(rent, includePlan: false), isFalse);
  });

  test('L8: lookups are indexed', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'idx_%'",
        )
        .get();
    expect(
      rows.map((r) => r.read<String>('name')),
      containsAll(['idx_txn_time', 'idx_txn_account', 'idx_logs_status']),
    );
  });

  test('a bank balance never goes negative; a card can owe', () async {
    await account('card', -50000, card: true);
    await db.accountsDao.adjustAccountBalance('bank', -999999);
    expect(await bal('bank'), 0);
    await db.accountsDao.updateAccountBalance('bank', -500);
    expect(await bal('bank'), 0);
    await db.accountsDao.adjustAccountBalance('card', -100000);
    expect(await bal('card'), -150000); // debts are stored negative
  });
}
