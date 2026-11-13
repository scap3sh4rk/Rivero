import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/balance_reconciler.dart';

import '../../test_helper.dart';

void main() {
  setupTestDatabase();

  group('BalanceReconciler', () {
    late RiveroDatabase db;
    late BalanceReconciler reconciler;
    final now = DateTime(2026, 11, 13, 18);

    setUp(() async {
      db = RiveroDatabase.memory();
      reconciler = BalanceReconciler(database: db);

      // Create test account
      await db.accountsDao.upsertPhysicalAccount(
        PhysicalAccountsCompanion(
          id: const Value('acc-hdfc'),
          name: const Value('HDFC Savings'),
          institution: const Value('HDFC Bank'),
          accountMask: const Value('1234'),
          balanceMinorUnits: const Value(1000000), // ₹10,000
          isActive: const Value(true),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'confirms zero discrepancy when ledger matches reported balance',
      () async {
        // Insert credit of ₹10,000 matching account balance
        await db.transactionsDao.insertTransaction(
          TransactionsCompanion(
            id: const Value('txn-init'),
            physicalAccountId: const Value('acc-hdfc'),
            amountMinorUnits: const Value(1000000),
            transactionType: const Value(TransactionType.income),
            transactionState: const Value(TransactionState.confirmed),
            merchant: const Value('Opening Balance'),
            category: const Value('Income'),
            transactionTimestamp: Value(now),
            createdAt: Value(now),
          ),
        );

        final result = await reconciler.reconcileAccount(
          accountId: 'acc-hdfc',
          reportedBalanceMinorUnits: 1000000,
          asOf: now,
        );

        expect(result.hasDiscrepancy, isFalse);
        expect(result.discrepancyMinorUnits, 0);
        expect(result.calculatedLedgerBalanceMinorUnits, 1000000);
        expect(result.adjustmentTransactionId, isNull);

        // No adjustment transaction should have been inserted
        final txns = await db.transactionsDao.watchRecentTransactions().first;
        expect(txns.length, 1);
      },
    );

    test(
      'detects variance and creates explicit balanceAdjustment ledger entry',
      () async {
        // Ledger has only ₹8,000 (800,000 paise)
        await db.transactionsDao.insertTransaction(
          TransactionsCompanion(
            id: const Value('txn-1'),
            physicalAccountId: const Value('acc-hdfc'),
            amountMinorUnits: const Value(800000),
            transactionType: const Value(TransactionType.income),
            transactionState: const Value(TransactionState.confirmed),
            merchant: const Value('Deposit'),
            category: const Value('Income'),
            transactionTimestamp: Value(now),
            createdAt: Value(now),
          ),
        );

        // Bank reports ₹10,000 (+₹2,000 discrepancy)
        final result = await reconciler.reconcileAccount(
          accountId: 'acc-hdfc',
          reportedBalanceMinorUnits: 1000000,
          asOf: now,
        );

        expect(result.hasDiscrepancy, isTrue);
        expect(result.discrepancyMinorUnits, 200000); // +₹2,000
        expect(result.calculatedLedgerBalanceMinorUnits, 800000);
        expect(result.adjustmentTransactionId, isNotNull);

        // Verify explicit adjustment transaction exists in ledger
        final txns = await db.transactionsDao.watchRecentTransactions().first;
        expect(txns.length, 2);

        final adjustment = txns.firstWhere(
          (t) => t.id == result.adjustmentTransactionId,
        );
        expect(adjustment.amountMinorUnits, 200000);
        expect(adjustment.transactionType, TransactionType.balanceAdjustment);
        expect(adjustment.transactionState, TransactionState.reconciled);

        // Verify physical account balance was updated to bank authoritative balance
        final account = await db.accountsDao.getPhysicalAccountById('acc-hdfc');
        expect(account?.balanceMinorUnits, 1000000);

        // Re-running ledger balance computation now yields exactly 1000000
        final newLedgerBalance = await reconciler.computeLedgerBalance(
          'acc-hdfc',
        );
        expect(newLedgerBalance, 1000000);
      },
    );
  });
}
