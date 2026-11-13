import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/refund_matcher.dart';

void main() {
  group('RefundMatcher', () {
    const matcher = RefundMatcher();
    final debitDate = DateTime(2026, 11, 10, 14);
    final refundDate = DateTime(2026, 11, 12, 10);

    test('matches full refund to original purchase', () {
      final original = LedgerTransaction(
        id: 'orig-1',
        physicalAccountId: 'acc-card',
        amountMinorUnits: -129900, // Debit ₹1,299.00
        transactionType: TransactionType.creditCardPurchase,
        transactionState: TransactionState.confirmed,
        merchant: 'Amazon',
        category: 'Shopping',
        referenceNumber: 'AMZ12345',
        transactionTimestamp: debitDate,
        isInternalTransfer: false,
        createdAt: debitDate,
      );

      final refund = LedgerTransaction(
        id: 'refund-1',
        physicalAccountId: 'acc-card',
        amountMinorUnits: 129900, // Refund ₹1,299.00
        transactionType: TransactionType.refund,
        transactionState: TransactionState.parsed,
        merchant: 'Amazon Refund',
        category: 'Shopping',
        referenceNumber: 'AMZ12345',
        transactionTimestamp: refundDate,
        isInternalTransfer: false,
        createdAt: refundDate,
      );

      final matches = matcher.findRefundMatches(
        transactions: [original, refund],
      );

      expect(matches.length, 1);
      final match = matches.first;
      expect(match.originalTransaction.id, 'orig-1');
      expect(match.refundTransaction.id, 'refund-1');
      expect(match.refundAmountMinorUnits, 129900);
      expect(match.isPartialRefund, isFalse);
      expect(match.confidence, 1); // Reference match
    });

    test('matches partial refund correctly', () {
      final original = LedgerTransaction(
        id: 'orig-2',
        physicalAccountId: 'acc-card',
        amountMinorUnits: -129900, // Debit ₹1,299.00
        transactionType: TransactionType.creditCardPurchase,
        transactionState: TransactionState.confirmed,
        merchant: 'Amazon India',
        category: 'Shopping',
        transactionTimestamp: debitDate,
        isInternalTransfer: false,
        createdAt: debitDate,
      );

      final refund = LedgerTransaction(
        id: 'refund-2',
        physicalAccountId: 'acc-card',
        amountMinorUnits: 49900, // Partial refund ₹499.00
        transactionType: TransactionType.refund,
        transactionState: TransactionState.parsed,
        merchant: 'Amazon',
        category: 'Shopping',
        transactionTimestamp: refundDate,
        isInternalTransfer: false,
        createdAt: refundDate,
      );

      final matches = matcher.findRefundMatches(
        transactions: [original, refund],
      );

      expect(matches.length, 1);
      final match = matches.first;
      expect(match.isPartialRefund, isTrue);
      expect(match.refundAmountMinorUnits, 49900);
      expect(match.confidence, 0.85);
    });

    test('does not match if refund amount exceeds original purchase', () {
      final original = LedgerTransaction(
        id: 'orig-3',
        physicalAccountId: 'acc-card',
        amountMinorUnits: -50000, // ₹500
        transactionType: TransactionType.expense,
        transactionState: TransactionState.confirmed,
        merchant: 'Store',
        category: 'Shopping',
        transactionTimestamp: debitDate,
        isInternalTransfer: false,
        createdAt: debitDate,
      );

      final refund = LedgerTransaction(
        id: 'refund-3',
        physicalAccountId: 'acc-card',
        amountMinorUnits: 75000, // ₹750 (greater than debit!)
        transactionType: TransactionType.refund,
        transactionState: TransactionState.parsed,
        merchant: 'Store',
        category: 'Shopping',
        transactionTimestamp: refundDate,
        isInternalTransfer: false,
        createdAt: refundDate,
      );

      final matches = matcher.findRefundMatches(
        transactions: [original, refund],
      );

      expect(matches, isEmpty);
    });

    test('does not match unrelated merchants', () {
      final original = LedgerTransaction(
        id: 'orig-4',
        physicalAccountId: 'acc-card',
        amountMinorUnits: -100000,
        transactionType: TransactionType.expense,
        transactionState: TransactionState.confirmed,
        merchant: 'Swiggy',
        category: 'Food',
        transactionTimestamp: debitDate,
        isInternalTransfer: false,
        createdAt: debitDate,
      );

      final refund = LedgerTransaction(
        id: 'refund-4',
        physicalAccountId: 'acc-card',
        amountMinorUnits: 100000,
        transactionType: TransactionType.refund,
        transactionState: TransactionState.parsed,
        merchant: 'Uber', // Different merchant
        category: 'Travel',
        transactionTimestamp: refundDate,
        isInternalTransfer: false,
        createdAt: refundDate,
      );

      final matches = matcher.findRefundMatches(
        transactions: [original, refund],
      );

      expect(matches, isEmpty);
    });
  });
}
