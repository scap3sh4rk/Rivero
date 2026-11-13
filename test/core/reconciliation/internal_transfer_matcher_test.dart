import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/internal_transfer_matcher.dart';

void main() {
  group('InternalTransferMatcher', () {
    const matcher = InternalTransferMatcher();
    final now = DateTime(2026, 11, 13, 17);

    test('matches valid transfer pair across two physical accounts', () {
      final debit = LedgerTransaction(
        id: 'txn-debit-1',
        physicalAccountId: 'acc-salary',
        amountMinorUnits: -2500000, // Debit ₹25,000
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'Transfer to HDFC',
        category: 'Transfer',
        referenceNumber: 'IMPS43123456',
        transactionTimestamp: now,
        isInternalTransfer: false,
        createdAt: now,
      );

      final credit = LedgerTransaction(
        id: 'txn-credit-1',
        physicalAccountId: 'acc-expense',
        amountMinorUnits: 2500000, // Credit ₹25,000
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'IMPS from Salary A/c',
        category: 'Transfer',
        referenceNumber: 'IMPS43123456',
        transactionTimestamp: now.add(const Duration(seconds: 45)),
        isInternalTransfer: false,
        createdAt: now,
      );

      final pairs = matcher.findTransferPairs(
        unlinkedTransactions: [debit, credit],
      );

      expect(pairs.length, 1);
      final pair = pairs.first;
      expect(pair.debitTransaction.id, 'txn-debit-1');
      expect(pair.creditTransaction.id, 'txn-credit-1');
      expect(pair.amountMinorUnits, 2500000);
      expect(pair.confidence, 1); // Exact reference match
      expect(pair.timeDelta.inSeconds, 45);
    });

    test('does not pair transactions on the same account', () {
      final debit = LedgerTransaction(
        id: 'txn-1',
        physicalAccountId: 'acc-same',
        amountMinorUnits: -100000,
        transactionType: TransactionType.expense,
        transactionState: TransactionState.confirmed,
        merchant: 'Store',
        category: 'General',
        transactionTimestamp: now,
        isInternalTransfer: false,
        createdAt: now,
      );

      final credit = LedgerTransaction(
        id: 'txn-2',
        physicalAccountId: 'acc-same', // Same account
        amountMinorUnits: 100000,
        transactionType: TransactionType.income,
        transactionState: TransactionState.confirmed,
        merchant: 'Deposit',
        category: 'General',
        transactionTimestamp: now.add(const Duration(seconds: 10)),
        isInternalTransfer: false,
        createdAt: now,
      );

      final pairs = matcher.findTransferPairs(
        unlinkedTransactions: [debit, credit],
      );

      expect(pairs, isEmpty);
    });

    test('does not pair transactions with different amounts', () {
      final debit = LedgerTransaction(
        id: 'txn-1',
        physicalAccountId: 'acc-1',
        amountMinorUnits: -500000, // ₹5,000
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'Transfer',
        category: 'Transfer',
        transactionTimestamp: now,
        isInternalTransfer: false,
        createdAt: now,
      );

      final credit = LedgerTransaction(
        id: 'txn-2',
        physicalAccountId: 'acc-2',
        amountMinorUnits: 600000, // ₹6,000 (mismatch)
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'Transfer',
        category: 'Transfer',
        transactionTimestamp: now.add(const Duration(seconds: 10)),
        isInternalTransfer: false,
        createdAt: now,
      );

      final pairs = matcher.findTransferPairs(
        unlinkedTransactions: [debit, credit],
      );

      expect(pairs, isEmpty);
    });

    test('does not pair transactions outside time window', () {
      final debit = LedgerTransaction(
        id: 'txn-1',
        physicalAccountId: 'acc-1',
        amountMinorUnits: -500000,
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'Transfer',
        category: 'Transfer',
        transactionTimestamp: now,
        isInternalTransfer: false,
        createdAt: now,
      );

      final credit = LedgerTransaction(
        id: 'txn-2',
        physicalAccountId: 'acc-2',
        amountMinorUnits: 500000,
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'Transfer',
        category: 'Transfer',
        transactionTimestamp: now.add(
          const Duration(minutes: 30),
        ), // 30 mins later
        isInternalTransfer: false,
        createdAt: now,
      );

      final pairs = matcher.findTransferPairs(
        unlinkedTransactions: [debit, credit],
        window: const Duration(minutes: 5),
      );

      expect(pairs, isEmpty);
    });

    test('ignores transactions that are already linked', () {
      final debit = LedgerTransaction(
        id: 'txn-1',
        physicalAccountId: 'acc-1',
        amountMinorUnits: -500000,
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'Transfer',
        category: 'Transfer',
        transactionTimestamp: now,
        isInternalTransfer: true, // Already linked
        linkedTransactionId: 'txn-already-linked',
        createdAt: now,
      );

      final credit = LedgerTransaction(
        id: 'txn-2',
        physicalAccountId: 'acc-2',
        amountMinorUnits: 500000,
        transactionType: TransactionType.internalTransfer,
        transactionState: TransactionState.confirmed,
        merchant: 'Transfer',
        category: 'Transfer',
        transactionTimestamp: now.add(const Duration(seconds: 10)),
        isInternalTransfer: false,
        createdAt: now,
      );

      final pairs = matcher.findTransferPairs(
        unlinkedTransactions: [debit, credit],
      );

      expect(pairs, isEmpty);
    });
  });
}
