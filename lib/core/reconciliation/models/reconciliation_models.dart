import 'package:flutter/foundation.dart';
import 'package:rivero/core/database/database.dart';

/// Represents a matched pair of transactions comprising an internal transfer
/// between two custodial accounts owned by the user.
@immutable
class TransferPairMatch {
  const TransferPairMatch({
    required this.debitTransaction,
    required this.creditTransaction,
    required this.amountMinorUnits,
    required this.confidence,
    required this.timeDelta,
  }) : assert(
         amountMinorUnits > 0,
         'amountMinorUnits must be strictly positive',
       ),
       assert(
         confidence >= 0 && confidence <= 1.0,
         'confidence must be between 0 and 1.0',
       );

  /// The outgoing debit transaction leg (from Source Account).
  final LedgerTransaction debitTransaction;

  /// The incoming credit transaction leg (to Destination Account).
  final LedgerTransaction creditTransaction;

  /// The absolute transfer amount in minor units (paise).
  final int amountMinorUnits;

  /// Match confidence score (0.0 to 1.0).
  final double confidence;

  /// Time difference between debit and credit events.
  final Duration timeDelta;

  @override
  String toString() {
    return 'TransferPairMatch(debitId: ${debitTransaction.id}, creditId: ${creditTransaction.id}, '
        'amount: $amountMinorUnits paise, delta: ${timeDelta.inSeconds}s, '
        'confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
  }
}

/// Represents a match between an original expense and a subsequent refund or reversal.
@immutable
class RefundMatch {
  const RefundMatch({
    required this.originalTransaction,
    required this.refundTransaction,
    required this.refundAmountMinorUnits,
    required this.isPartialRefund,
    required this.confidence,
  }) : assert(
         refundAmountMinorUnits > 0,
         'refundAmountMinorUnits must be strictly positive',
       ),
       assert(
         confidence >= 0 && confidence <= 1.0,
         'confidence must be between 0 and 1.0',
       );

  /// The original outflow / debit transaction.
  final LedgerTransaction originalTransaction;

  /// The subsequent inflow / credit refund transaction.
  final LedgerTransaction refundTransaction;

  /// The refund amount in minor units (paise).
  final int refundAmountMinorUnits;

  /// True if the refund is less than the original transaction amount.
  final bool isPartialRefund;

  /// Match confidence score (0.0 to 1.0).
  final double confidence;

  @override
  String toString() {
    return 'RefundMatch(origId: ${originalTransaction.id}, refundId: ${refundTransaction.id}, '
        'amount: $refundAmountMinorUnits paise, isPartial: $isPartialRefund, '
        'confidence: ${(confidence * 100).toStringAsFixed(1)}%)';
  }
}

/// The result of comparing a reported custodial bank balance against the
/// calculated running balance from the Rivero encrypted ledger.
@immutable
class BalanceReconciliationResult {
  const BalanceReconciliationResult({
    required this.accountId,
    required this.reportedBalanceMinorUnits,
    required this.calculatedLedgerBalanceMinorUnits,
    required this.discrepancyMinorUnits,
    required this.hasDiscrepancy,
    required this.reconciledAt,
    this.adjustmentTransactionId,
  });

  /// The physical custodial account ID.
  final String accountId;

  /// Balance reported by the bank (via SMS, statement, or notification) in minor units.
  final int reportedBalanceMinorUnits;

  /// Cumulative running balance computed from all recorded ledger transactions in minor units.
  final int calculatedLedgerBalanceMinorUnits;

  /// The difference (`reportedBalance - calculatedLedgerBalance`) in minor units.
  final int discrepancyMinorUnits;

  /// True if a non-zero variance exists between reported and computed ledger balance.
  final bool hasDiscrepancy;

  /// ID of the explicit `balanceAdjustment` transaction created to reconcile the ledger, if any.
  final String? adjustmentTransactionId;

  /// Timestamp when reconciliation took place.
  final DateTime reconciledAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BalanceReconciliationResult &&
          runtimeType == other.runtimeType &&
          accountId == other.accountId &&
          reportedBalanceMinorUnits == other.reportedBalanceMinorUnits &&
          calculatedLedgerBalanceMinorUnits ==
              other.calculatedLedgerBalanceMinorUnits &&
          discrepancyMinorUnits == other.discrepancyMinorUnits &&
          hasDiscrepancy == other.hasDiscrepancy &&
          adjustmentTransactionId == other.adjustmentTransactionId &&
          reconciledAt == other.reconciledAt;

  @override
  int get hashCode => Object.hash(
    accountId,
    reportedBalanceMinorUnits,
    calculatedLedgerBalanceMinorUnits,
    discrepancyMinorUnits,
    hasDiscrepancy,
    adjustmentTransactionId,
    reconciledAt,
  );

  @override
  String toString() {
    return 'BalanceReconciliationResult(account: $accountId, '
        'reported: $reportedBalanceMinorUnits, calculated: $calculatedLedgerBalanceMinorUnits, '
        'delta: $discrepancyMinorUnits, hasDiscrepancy: $hasDiscrepancy, '
        'adjustmentTxnId: $adjustmentTransactionId)';
  }
}
