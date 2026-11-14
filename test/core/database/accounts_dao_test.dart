import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/account_role.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;

  setUp(() {
    db = RiveroDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('AccountsDao tests', () {
    test('upsert and retrieve physical account', () async {
      final now = DateTime.now();
      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('acc-hdfc-01'),
          name: const Value('HDFC Salary Account'),
          institution: const Value('HDFC'),
          accountMask: const Value('••4012'),
          balanceMinorUnits: const Value(15000000), // ₹1,50,000.00
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final account = await db.accountsDao.getPhysicalAccountById(
        'acc-hdfc-01',
      );
      expect(account, isNotNull);
      expect(account!.name, equals('HDFC Salary Account'));
      expect(account.balanceMinorUnits, equals(15000000));
      expect(account.isLiability, isFalse);

      final byMask = await db.accountsDao.findAccountByMask('HDFC', '••4012');
      expect(byMask, isNotNull);
      expect(byMask!.id, equals('acc-hdfc-01'));
    });

    test('adjust account balance with positive and negative deltas', () async {
      final now = DateTime.now();
      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('acc-icici-01'),
          name: const Value('ICICI Savings'),
          institution: const Value('ICICI'),
          accountMask: const Value('••8841'),
          balanceMinorUnits: const Value(5000000), // ₹50,000.00
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Debit ₹5,000.00 (-500000 minor units)
      await db.accountsDao.adjustAccountBalance('acc-icici-01', -500000);
      var account = await db.accountsDao.getPhysicalAccountById('acc-icici-01');
      expect(account!.balanceMinorUnits, equals(4500000)); // ₹45,000.00

      // Credit ₹10,000.00 (+1000000 minor units)
      await db.accountsDao.adjustAccountBalance('acc-icici-01', 1000000);
      account = await db.accountsDao.getPhysicalAccountById('acc-icici-01');
      expect(account!.balanceMinorUnits, equals(5500000)); // ₹55,000.00
    });

    test('upsert allocation bucket and record spend', () async {
      final now = DateTime.now();
      await db.accountsDao.upsertBucket(
        AllocationBucketsCompanion(
          id: const Value('bucket-expense-01'),
          name: const Value('Living Expenses'),
          role: const Value(AccountRole.expense),
          allocatedMinorUnits: const Value(4000000), // ₹40,000
          spentMinorUnits: const Value(0),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Spend ₹2,500.00 (250000 paise)
      await db.accountsDao.recordBucketSpend('bucket-expense-01', 250000);
      var bucket = await db.accountsDao.getBucketById('bucket-expense-01');
      expect(bucket, isNotNull);
      expect(bucket!.spentMinorUnits, equals(250000));

      // Reset cycle
      await db.accountsDao.resetBucketsForNewCycle();
      bucket = await db.accountsDao.getBucketById('bucket-expense-01');
      expect(bucket!.spentMinorUnits, equals(0));
    });
  });

  test('reorderAccounts sets the list order', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    final before = await db.accountsDao.watchActivePhysicalAccounts().first;
    final reversed = before.reversed.map((a) => a.id).toList();
    await db.accountsDao.reorderAccounts(reversed);
    final after = await db.accountsDao.watchActivePhysicalAccounts().first;
    expect(after.map((a) => a.id).toList(), reversed);
  });
}
