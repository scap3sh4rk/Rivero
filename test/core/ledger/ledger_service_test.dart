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
      await db.accountsDao.updateAccountBalance('bank', 100000);
      await txn('e', 'bank', -50000, TransactionType.expense);
      await ledger.confirm('e');
      await ledger.confirm('e'); // idempotent
      expect(await balance('bank'), 50000);
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
    await db.accountsDao.updateAccountBalance('bank', 100000);
    await txn('e', 'bank', -80000, TransactionType.expense);
    await ledger.confirm('e');
    await txn('r', 'bank', 30000, TransactionType.refund);
    await ledger.confirm('r');
    await txn('i', 'bank', 9000000, TransactionType.income);
    await ledger.confirm('i');
    expect(await spent(), 50000);
    expect(await balance('bank'), 100000 + 9000000 - 80000 + 30000);
  });

  test(
    'editing a counted spend moves balance and budget by the difference',
    () async {
      await db.accountsDao.updateAccountBalance('bank', 100000);
      await txn('e', 'bank', -50000, TransactionType.expense);
      await ledger.confirm('e');
      await ledger.edit(
        'e',
        amountMinorUnits: 60000,
        timestamp: DateTime(2026, 11, 13, 9),
        merchant: ' Swiggy ',
      );
      final t = (await db.transactionsDao.getTransactionById('e'))!;
      expect(t.amountMinorUnits, -60000); // still a spend
      expect(t.merchant, 'Swiggy');
      expect(t.transactionTimestamp, DateTime(2026, 11, 13, 9));
      expect(await balance('bank'), 40000);
      expect(await spent(), 60000);
      // Deleting it afterwards undoes exactly the corrected amount.
      await ledger.remove('e');
      expect(await balance('bank'), 100000);
      expect(await spent(), 0);
    },
  );

  test('editing a waiting entry only changes the entry', () async {
    await db.accountsDao.updateAccountBalance('bank', 100000);
    await txn('e', 'bank', -50000, TransactionType.expense);
    await ledger.edit('e', amountMinorUnits: 70000);
    expect(await balance('bank'), 100000);
    await ledger.confirm('e');
    expect(await balance('bank'), 30000);
    expect(await spent(), 70000);
  });

  test('money in stays money in when its amount is corrected', () async {
    await txn('i', 'bank', 900000, TransactionType.income);
    await ledger.confirm('i');
    await ledger.edit('i', amountMinorUnits: 1000000);
    expect(await balance('bank'), 1000000);
    expect(await spent(), 0);
  });

  test(
    'a transfer leg cannot be edited; nonsense amounts are refused',
    () async {
      final t = await txn('a', 'bank', -50000, TransactionType.expense);
      expect(LedgerService.canEdit(t), isTrue);
      expect(
        () => ledger.edit('a', amountMinorUnits: 0),
        throwsA(isA<ArgumentError>()),
      );
      await (db.update(db.transactions)..where((x) => x.id.equals('a'))).write(
        const TransactionsCompanion(isInternalTransfer: Value(true)),
      );
      final leg = (await db.transactionsDao.getTransactionById('a'))!;
      expect(LedgerService.canEdit(leg), isFalse);
      expect(
        () => ledger.edit('a', amountMinorUnits: 1000),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('deleting a confirmed expense gives back balance and budget', () async {
    await db.accountsDao.updateAccountBalance('bank', 100000);
    await txn('e', 'bank', -50000, TransactionType.expense);
    await ledger.confirm('e');
    await ledger.remove('e');
    expect(await balance('bank'), 100000);
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

  test('changing the account moves balance and budget, bank to card', () async {
    await db.accountsDao.updateAccountBalance('bank', 100000);
    await txn('e', 'bank', -50000, TransactionType.expense);
    await ledger.confirm('e');
    expect(await balance('bank'), 50000);
    expect(await spent(), 50000);

    await ledger.changeAccount('e', 'card');
    final t = (await db.transactionsDao.getTransactionById('e'))!;
    expect(t.physicalAccountId, 'card');
    expect(t.transactionType, TransactionType.creditCardPurchase);
    expect(await balance('bank'), 100000); // given back
    expect(await balance('card'), -50000); // now owed
    expect(await spent(), 0); // card spend is not budget until the bill

    await ledger.changeAccount('e', 'bank');
    expect(await balance('bank'), 50000);
    expect(await balance('card'), 0);
    expect(await spent(), 50000);
    expect(
      (await db.transactionsDao.getTransactionById('e'))!.transactionType,
      TransactionType.expense,
    );
  });

  test('changing the account of a waiting entry just repoints it', () async {
    await txn('w', 'bank', -50000, TransactionType.expense);
    await ledger.changeAccount('w', 'card');
    expect(
      (await db.transactionsDao.getTransactionById('w'))!.physicalAccountId,
      'card',
    );
    expect(await balance('card'), 0);
    await ledger.confirm('w');
    expect(await balance('card'), -50000);
  });
}
