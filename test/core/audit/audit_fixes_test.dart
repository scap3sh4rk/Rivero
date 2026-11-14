import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
import 'package:rivero/core/import/statement_importer.dart';
import 'package:rivero/core/import/statement_parser.dart';
import 'package:rivero/core/ledger/ledger_service.dart';

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
}
