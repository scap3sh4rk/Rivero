import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/deduplication_engine.dart';
import 'package:rivero/core/ingestion/models/parsed_transaction.dart';

void main() {
  group('DeduplicationEngine', () {
    const engine = DeduplicationEngine();
    final now = DateTime(2026, 11, 13, 15);

    final existingTransaction = LedgerTransaction(
      id: 'txn-existing-1',
      physicalAccountId: 'acc-1',
      amountMinorUnits: -45000, // Debit ₹450
      transactionType: TransactionType.expense,
      transactionState: TransactionState.confirmed,
      merchant: 'swiggy@hdfcbank',
      category: 'Food & Dining',
      referenceNumber: '431712345678',
      transactionTimestamp: now,
      isInternalTransfer: false,
      createdAt: now,
    );

    test('detects duplicate via matching UTR/RRN reference number', () {
      final candidate = ParsedTransaction(
        amountMinorUnits: 45000,
        isDebit: true,
        timestamp: now.add(const Duration(seconds: 45)),
        confidenceScore: 0.90,
        rawPayload: 'Payment of ₹450 to Swiggy was successful.',
        suggestedTransactionType: TransactionType.expense,
        suggestedRole: AccountRole.expense,
        merchant: 'Swiggy',
        referenceNumber: '431712345678',
      );

      final match = engine.evaluate(
        candidate: candidate,
        existingTransactions: [existingTransaction],
      );

      expect(match.isDuplicate, isTrue);
      expect(match.confidence, 1.0);
      expect(match.matchedTransaction?.id, 'txn-existing-1');
      expect(match.mergedMerchant, 'Swiggy');
      expect(match.reason, contains('431712345678'));
    });

    test('detects duplicate via temporal window and amount match', () {
      final candidateWithoutRef = ParsedTransaction(
        amountMinorUnits: 45000,
        isDebit: true,
        timestamp: now.add(const Duration(seconds: 30)),
        confidenceScore: 0.85,
        rawPayload: 'Paid ₹450 to Swiggy',
        suggestedTransactionType: TransactionType.expense,
        suggestedRole: AccountRole.expense,
        merchant: 'Swiggy',
      );

      final match = engine.evaluate(
        candidate: candidateWithoutRef,
        existingTransactions: [existingTransaction],
      );

      expect(match.isDuplicate, isTrue);
      expect(match.confidence, greaterThanOrEqualTo(0.95));
      expect(match.matchedTransaction?.id, 'txn-existing-1');
    });

    test('does not flag transaction outside time window as duplicate', () {
      final candidateLate = ParsedTransaction(
        amountMinorUnits: 45000,
        isDebit: true,
        // 10 minutes later (e.g. user made another ₹450 purchase later)
        timestamp: now.add(const Duration(minutes: 10)),
        confidenceScore: 0.85,
        rawPayload: 'Paid ₹450 to Swiggy',
        suggestedTransactionType: TransactionType.expense,
        suggestedRole: AccountRole.expense,
        merchant: 'Swiggy',
      );

      final match = engine.evaluate(
        candidate: candidateLate,
        existingTransactions: [existingTransaction],
      );

      expect(match.isDuplicate, isFalse);
    });

    test('does not flag transaction with different amount as duplicate', () {
      final candidateDiffAmount = ParsedTransaction(
        amountMinorUnits: 55000, // ₹550 instead of ₹450
        isDebit: true,
        timestamp: now.add(const Duration(seconds: 15)),
        confidenceScore: 0.85,
        rawPayload: 'Paid ₹550 to Swiggy',
        suggestedTransactionType: TransactionType.expense,
        suggestedRole: AccountRole.expense,
        merchant: 'Swiggy',
      );

      final match = engine.evaluate(
        candidate: candidateDiffAmount,
        existingTransactions: [existingTransaction],
      );

      expect(match.isDuplicate, isFalse);
    });
  });
}
