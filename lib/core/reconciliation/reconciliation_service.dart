import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/balance_reconciler.dart';
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
    BalanceReconciler? balanceReconciler,
  }) : balanceReconciler =
           balanceReconciler ?? BalanceReconciler(database: database);

  final RiveroDatabase database;
  final InternalTransferMatcher transferMatcher;
  final RefundMatcher refundMatcher;
  final BalanceReconciler balanceReconciler;

  /// Scans active transactions, detects unlinked internal self-transfers,
  /// and links corresponding debit and credit legs.
  Future<List<TransferPairMatch>> reconcileInternalTransfers({
    int scanLimit = 100,
    Duration? window,
  }) async {
    final recent = await database.transactionsDao
        .watchRecentTransactions(limit: scanLimit)
        .first;

    final pairs = transferMatcher.findTransferPairs(
      unlinkedTransactions: recent,
      window: window,
    );

    for (final pair in pairs) {
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
    final recent = await database.transactionsDao
        .watchRecentTransactions(limit: scanLimit)
        .first;

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

  /// Reconciles an account balance against its calculated ledger running balance.
  Future<BalanceReconciliationResult> reconcileAccountBalance({
    required String accountId,
    required int reportedBalanceMinorUnits,
    DateTime? asOf,
    bool autoAdjust = true,
  }) {
    return balanceReconciler.reconcileAccount(
      accountId: accountId,
      reportedBalanceMinorUnits: reportedBalanceMinorUnits,
      asOf: asOf,
      autoAdjust: autoAdjust,
    );
  }
}
