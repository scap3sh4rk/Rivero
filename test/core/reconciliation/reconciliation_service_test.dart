import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';

import '../../test_helper.dart';

void main() {
  setupTestDatabase();

  group('ReconciliationService', () {
    late RiveroDatabase db;
    late ReconciliationService service;
    final now = DateTime(2026, 11, 13, 19);

    setUp(() async {
      db = RiveroDatabase.memory();
      service = ReconciliationService(database: db);

      // Create two physical accounts for transfers
      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('acc-salary'),
          name: const Value('Salary Bank'),
          institution: const Value('HDFC'),
          accountMask: const Value('1111'),
          balanceMinorUnits: const Value(5000000),
          isActive: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('acc-expense'),
          name: const Value('Expense Bank'),
          institution: const Value('ICICI'),
          accountMask: const Value('2222'),
          balanceMinorUnits: const Value(1000000),
          isActive: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('reconciles and links internal self-transfer legs', () async {
      // 1. Debit leg on Salary account
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('debit-1'),
          physicalAccountId: const Value('acc-salary'),
          amountMinorUnits: const Value(-2000000), // -₹20,000
          transactionType: const Value(TransactionType.internalTransfer),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('Transfer to ICICI'),
          category: const Value('Transfer'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );

      // 2. Credit leg on Expense account 20s later
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('credit-1'),
          physicalAccountId: const Value('acc-expense'),
          amountMinorUnits: const Value(2000000), // +₹20,000
          transactionType: const Value(TransactionType.internalTransfer),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('From HDFC Salary'),
          category: const Value('Transfer'),
          transactionTimestamp: Value(now.add(const Duration(seconds: 20))),
          createdAt: Value(now),
        ),
      );

      // Run reconciliation
      final pairs = await service.reconcileInternalTransfers();

      expect(pairs.length, 1);
      expect(pairs.first.debitTransaction.id, 'debit-1');
      expect(pairs.first.creditTransaction.id, 'credit-1');

      // Verify both transactions are now linked and marked reconciled
      final debitTxn = await db.transactionsDao.getTransactionById('debit-1');
      final creditTxn = await db.transactionsDao.getTransactionById('credit-1');

      expect(debitTxn?.isInternalTransfer, isTrue);
      expect(debitTxn?.linkedTransactionId, 'credit-1');
      expect(debitTxn?.transactionState, TransactionState.reconciled);

      expect(creditTxn?.isInternalTransfer, isTrue);
      expect(creditTxn?.linkedTransactionId, 'debit-1');
      expect(creditTxn?.transactionState, TransactionState.reconciled);
    });

    test('reconciles and links refund to original purchase', () async {
      // 1. Original debit
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('orig-amazon'),
          physicalAccountId: const Value('acc-expense'),
          amountMinorUnits: const Value(-149900), // -₹1,499.00
          transactionType: const Value(TransactionType.expense),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('Amazon India'),
          category: const Value('Shopping'),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );

      // 2. Refund credit
      await db.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: const Value('refund-amazon'),
          physicalAccountId: const Value('acc-expense'),
          amountMinorUnits: const Value(149900), // +₹1,499.00
          transactionType: const Value(TransactionType.refund),
          transactionState: const Value(TransactionState.confirmed),
          merchant: const Value('Amazon Refund'),
          category: const Value('Shopping'),
          transactionTimestamp: Value(now.add(const Duration(days: 2))),
          createdAt: Value(now),
        ),
      );

      // Run refund reconciliation
      final refunds = await service.reconcileRefunds();

      expect(refunds.length, 1);
      expect(refunds.first.originalTransaction.id, 'orig-amazon');
      expect(refunds.first.refundTransaction.id, 'refund-amazon');

      // Verify refund is linked and marked reconciled
      final refundTxn = await db.transactionsDao.getTransactionById(
        'refund-amazon',
      );
      expect(refundTxn?.linkedTransactionId, 'orig-amazon');
      expect(refundTxn?.transactionState, TransactionState.reconciled);
    });
  });
}
