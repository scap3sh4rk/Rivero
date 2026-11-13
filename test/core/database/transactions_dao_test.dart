import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;

  setUp(() async {
    db = RiveroDatabase.memory();

    // Create a base physical account and bucket
    final now = DateTime.now();
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('acc-01'),
        name: const Value('HDFC Salary'),
        institution: const Value('HDFC'),
        accountMask: const Value('••4012'),
        balanceMinorUnits: const Value(10000000),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await db.accountsDao.upsertBucket(
      AllocationBucketsCompanion(
        id: const Value('bucket-01'),
        name: const Value('Expenses'),
        role: const Value(AccountRole.expense),
        allocatedMinorUnits: const Value(4000000),
        spentMinorUnits: const Value(0),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('TransactionsDao tests', () {
    test('insert and retrieve ledger transactions', () async {
      final now = DateTime.now();
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('txn-01'),
          physicalAccountId: const Value('acc-01'),
          allocationBucketId: const Value('bucket-01'),
          amountMinorUnits: const Value(-45000), // -₹450.00
          transactionType: const Value(TransactionType.expense),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('Swiggy'),
          category: const Value('Food & Dining'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );

      final txn = await db.transactionsDao.getTransactionById('txn-01');
      expect(txn, isNotNull);
      expect(txn!.merchant, equals('Swiggy'));
      expect(txn.amountMinorUnits, equals(-45000));
      expect(txn.transactionState, equals(TransactionState.confirmed));
    });

    test('link internal transfer partner legs', () async {
      final now = DateTime.now();
      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('acc-02'),
          name: const Value('ICICI Savings'),
          institution: const Value('ICICI'),
          accountMask: const Value('••8841'),
          balanceMinorUnits: const Value(2000000),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // Debit leg on HDFC
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('txn-transfer-debit'),
          physicalAccountId: const Value('acc-01'),
          amountMinorUnits: const Value(-1000000), // -₹10,000
          transactionType: const Value(TransactionType.internalTransfer),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('Self Transfer to ICICI'),
          category: const Value('Transfer'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );

      // Credit leg on ICICI
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('txn-transfer-credit'),
          physicalAccountId: const Value('acc-02'),
          amountMinorUnits: const Value(1000000), // +₹10,000
          transactionType: const Value(TransactionType.internalTransfer),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('Self Transfer from HDFC'),
          category: const Value('Transfer'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );

      // Link both legs
      await db.transactionsDao.linkTransactionLegs(
        'txn-transfer-debit',
        'txn-transfer-credit',
      );

      final debit = await db.transactionsDao.getTransactionById(
        'txn-transfer-debit',
      );
      final credit = await db.transactionsDao.getTransactionById(
        'txn-transfer-credit',
      );

      expect(debit!.linkedTransactionId, equals('txn-transfer-credit'));
      expect(debit.isInternalTransfer, isTrue);
      expect(credit!.linkedTransactionId, equals('txn-transfer-debit'));
      expect(credit.isInternalTransfer, isTrue);
    });

    test('find duplicate candidates within time window', () async {
      final baseTime = DateTime(2026, 11, 13, 14, 30);
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('txn-original'),
          physicalAccountId: const Value('acc-01'),
          amountMinorUnits: const Value(-50000), // -₹500.00
          transactionType: const Value(TransactionType.expense),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('Chai Point'),
          category: const Value('Food'),
          transactionTimestamp: Value(baseTime),
          createdAt: Value(baseTime),
        ),
      );

      // Candidate 60 seconds later with identical amount
      final candidates = await db.transactionsDao.findDuplicateCandidates(
        amountMinorUnits: -50000,
        timestamp: baseTime.add(const Duration(seconds: 60)),
      );
      expect(candidates.length, equals(1));
      expect(candidates.first.id, equals('txn-original'));

      // Candidate 10 minutes later (outside 180s window)
      final outsideCandidates = await db.transactionsDao
          .findDuplicateCandidates(
            amountMinorUnits: -50000,
            timestamp: baseTime.add(const Duration(minutes: 10)),
          );
      expect(outsideCandidates, isEmpty);
    });
  });
}
