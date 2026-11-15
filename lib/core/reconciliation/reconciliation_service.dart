import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/reconciliation/internal_transfer_matcher.dart';
import 'package:rivero/core/reconciliation/models/reconciliation_models.dart';
import 'package:rivero/core/reconciliation/refund_matcher.dart';

/// Central coordinator for financial ledger reconciliation, self-transfer pairing,
/// refund linking, and balance alignment.
class ReconciliationService {
  ReconciliationService({
    required this.database,
    this.transferMatcher = const InternalTransferMatcher(),
    this.refundMatcher = const RefundMatcher(),
  });

  final RiveroDatabase database;
  final InternalTransferMatcher transferMatcher;
  final RefundMatcher refundMatcher;

  /// Scans active transactions, detects unlinked internal self-transfers,
  /// and links corresponding debit and credit legs.
  Future<List<TransferPairMatch>> reconcileInternalTransfers({
    int scanLimit = 100,
    Duration? window,
  }) async {
    // Only confirmed legs: unconfirmed ones have not touched balances yet and
    // must not be marked reconciled (that would skip their effects).
    final recent =
        (await database.transactionsDao.getRecentTransactions(limit: scanLimit))
            .where(
              (t) =>
                  t.transactionState == TransactionState.confirmed &&
                  !t.id.startsWith('plan-'),
            )
            .toList();

    final pairs = transferMatcher.findTransferPairs(
      unlinkedTransactions: recent,
      window: window,
    );

    final ledger = LedgerService(database);
    for (final pair in pairs) {
      await ledger.convertToTransfer(
        pair.debitTransaction,
        pair.creditTransaction,
      );
      await database.transactionsDao.linkTransactionLegs(
        pair.debitTransaction.id,
        pair.creditTransaction.id,
      );

      // Transition paired legs to reconciled state
      await database.transactionsDao.updateTransactionState(
        pair.debitTransaction.id,
        TransactionState.reconciled,
      );
      await database.transactionsDao.updateTransactionState(
        pair.creditTransaction.id,
        TransactionState.reconciled,
      );
    }

    return pairs;
  }

  /// Scans active transactions, detects unlinked refunds or reversals,
  /// and links them back to their originating debit purchases.
  Future<List<RefundMatch>> reconcileRefunds({int scanLimit = 100}) async {
    final recent =
        (await database.transactionsDao.getRecentTransactions(limit: scanLimit))
            .where(
              (t) =>
                  t.transactionState == TransactionState.confirmed &&
                  !t.id.startsWith('plan-'),
            )
            .toList();

    final matches = refundMatcher.findRefundMatches(transactions: recent);

    for (final match in matches) {
      await database.transactionsDao.linkTransactionLegs(
        match.originalTransaction.id,
        match.refundTransaction.id,
      );

      await database.transactionsDao.updateTransactionState(
        match.refundTransaction.id,
        TransactionState.reconciled,
      );
    }

    return matches;
  }

  /// Runs every matcher; call after new transactions are confirmed.
  Future<void> reconcileAll() async {
    await reconcileInternalTransfers();
    await reconcileRefunds();
  }
}
