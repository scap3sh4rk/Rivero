import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  late LedgerService ledger;
  final now = DateTime(2026, 11, 14);

  Future<void> account(String id, {bool liability = false}) =>
      db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: Value(id),
          name: Value(id),
          institution: const Value('Bank'),
          accountMask: const Value('1234'),
          isLiability: Value(liability),
          balanceMinorUnits: const Value(0),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

  Future<LedgerTransaction> txn(
    String id,
    String acc,
    int amount,
    TransactionType type, {
    TransactionState state = TransactionState.needsReview,
  }) async {
    await db.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: Value(id),
        physicalAccountId: Value(acc),
        amountMinorUnits: Value(amount),
        transactionType: Value(type),
        transactionState: Value(state),
        merchant: const Value('m'),
        category: const Value('c'),
        transactionTimestamp: Value(now),
        createdAt: Value(now),
      ),
    );
    return (await db.transactionsDao.getTransactionById(id))!;
  }

  Future<int> spent() async =>
      (await db.accountsDao.getBucketById('b'))!.spentMinorUnits;
  Future<int> balance(String id) async =>
      (await db.accountsDao.getPhysicalAccountById(id))!.balanceMinorUnits;

  setUp(() async {
    db = RiveroDatabase.memory();
    ledger = LedgerService(db);
    await account('bank');
    await account('card', liability: true);
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('b'),
        name: const Value('Expenses'),
        role: const Value(AccountRole.expense),
        allocatedMinorUnits: const Value(1000000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });
  tearDown(() => db.close());

  test(
    'confirming a bank expense moves balance and bucket spend once',
    () async {
      await txn('e', 'bank', -50000, TransactionType.expense);
      await ledger.confirm('e');
      await ledger.confirm('e'); // idempotent
      expect(await balance('bank'), -50000);
      expect(await spent(), 50000);
    },
  );

  test(
    'card purchase is a liability, not budget spend; paying the bill is',
    () async {
      await txn('p', 'card', -200000, TransactionType.creditCardPurchase);
      await ledger.confirm('p');
      expect(await balance('card'), -200000);
      expect(await spent(), 0);

      await txn('s', 'bank', -200000, TransactionType.creditCardSettlement);
      await ledger.confirm('s');
      expect(await spent(), 200000);
    },
  );

  test(
    'settlement does not spend budget when card reservation is off',
    () async {
      await db.settingsDao.set(SettingKeys.reserveCreditCards, '0');
      await txn('s', 'bank', -200000, TransactionType.creditCardSettlement);
      await ledger.confirm('s');
      expect(await spent(), 0);
    },
  );

  test('refund returns budget and income does not touch it', () async {
    await txn('e', 'bank', -80000, TransactionType.expense);
    await ledger.confirm('e');
    await txn('r', 'bank', 30000, TransactionType.refund);
    await ledger.confirm('r');
    await txn('i', 'bank', 9000000, TransactionType.income);
    await ledger.confirm('i');
    expect(await spent(), 50000);
    expect(await balance('bank'), 9000000 - 80000 + 30000);
  });

  test('deleting a confirmed expense gives back balance and budget', () async {
    await txn('e', 'bank', -50000, TransactionType.expense);
    await ledger.confirm('e');
    await ledger.remove('e');
    expect(await balance('bank'), 0);
    expect(await spent(), 0);
    expect(await db.transactionsDao.getTransactionById('e'), isNull);
  });

  test('deleting an unconfirmed capture changes nothing else', () async {
    await txn('p', 'bank', -50000, TransactionType.expense);
    await ledger.remove('p');
    expect(await balance('bank'), 0);
    expect(await spent(), 0);
  });

  test('manual entries keep the note', () async {
    await ledger.recordManual(
      accountId: 'bank',
      amountMinorUnits: -12000,
      type: TransactionType.expense,
      merchant: 'Chai with Ravi',
      category: 'Food',
      note: '  split later  ',
    );
    final t = (await db.select(db.transactions).get()).single;
    expect(t.userNotes, 'split later');
    expect(await spent(), 12000);
  });
}
