import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/models/reconciliation_models.dart';
import 'package:uuid/uuid.dart';

/// Reconciles custodial physical account balances against the Rivero encrypted ledger.
///
/// Guaranteed Properties:
/// 1. Audit Invariant: Discrepancies are NEVER silently overwritten. Every adjustment
///    is recorded as an explicit `balanceAdjustment` ledger transaction.
/// 2. Determinism: Given identical transactions, calculated balance is identical.
class BalanceReconciler {
  const BalanceReconciler({required this.database, this.uuid = const Uuid()});

  final RiveroDatabase database;
  final Uuid uuid;

  /// Calculates the cumulative running balance in minor units (paise)
  /// from all recorded transactions for [accountId].
  Future<int> computeLedgerBalance(String accountId) async {
    final txns = await database.transactionsDao
        .watchTransactionsByAccount(accountId)
        .first;

    var sum = 0;
    for (final t in txns) {
      if (t.transactionState == TransactionState.failed ||
          t.transactionState == TransactionState.ignored) {
        continue;
      }
      sum += t.amountMinorUnits;
    }
    return sum;
  }

  /// Compares [reportedBalanceMinorUnits] against the calculated ledger balance.
  ///
  /// If a variance exists and [autoAdjust] is true, persists an explicit
  /// `balanceAdjustment` ledger entry and brings the account into reconciliation.
  Future<BalanceReconciliationResult> reconcileAccount({
    required String accountId,
    required int reportedBalanceMinorUnits,
    DateTime? asOf,
    bool autoAdjust = true,
  }) async {
    final now = asOf ?? DateTime.now();
    final calculated = await computeLedgerBalance(accountId);
    final discrepancy = reportedBalanceMinorUnits - calculated;
    final hasDiscrepancy = discrepancy != 0;

    String? adjustmentTxnId;

    if (hasDiscrepancy && autoAdjust) {
      adjustmentTxnId = uuid.v4();

      // Create an explicit balanceAdjustment transaction preserving audit history
      await database.transactionsDao.insertTransaction(
        TransactionsCompanion(
          id: Value(adjustmentTxnId),
          physicalAccountId: Value(accountId),
          amountMinorUnits: Value(discrepancy),
          transactionType: const Value(TransactionType.balanceAdjustment),
          transactionState: const Value(TransactionState.reconciled),
          merchant: const Value('Balance Reconciliation Adjustment'),
          category: const Value('Adjustment'),
          userNotes: Value(
            'Reconciliation variance: calculated $calculated paise, '
            'reported $reportedBalanceMinorUnits paise (delta: $discrepancy paise)',
          ),
          transactionTimestamp: Value(now),
          createdAt: Value(now),
        ),
      );

      // Align physical account balance to authoritative bank balance
      await database.accountsDao.updateAccountBalance(
        accountId,
        reportedBalanceMinorUnits,
      );
    }

    return BalanceReconciliationResult(
      accountId: accountId,
      reportedBalanceMinorUnits: reportedBalanceMinorUnits,
      calculatedLedgerBalanceMinorUnits: calculated,
      discrepancyMinorUnits: discrepancy,
      hasDiscrepancy: hasDiscrepancy,
      adjustmentTransactionId: adjustmentTxnId,
      reconciledAt: now,
    );
  }
}
