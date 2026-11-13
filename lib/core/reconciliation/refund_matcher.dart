import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/models/reconciliation_models.dart';

/// Matches incoming refunds, reversals, and cashbacks against their
/// original debit expenditures.
class RefundMatcher {
  const RefundMatcher();

  /// Scans [transactions] and returns all identified refund pairs.
  List<RefundMatch> findRefundMatches({
    required List<LedgerTransaction> transactions,
  }) {
    final debits = <LedgerTransaction>[];
    final refunds = <LedgerTransaction>[];

    for (final txn in transactions) {
      if (txn.linkedTransactionId != null) {
        continue; // Already linked to an original or partner leg
      }

      if (txn.amountMinorUnits < 0) {
        debits.add(txn);
      } else if (txn.transactionType == TransactionType.refund ||
          txn.transactionType == TransactionType.reversal ||
          txn.merchant.toLowerCase().contains('refund') ||
          txn.category.toLowerCase().contains('refund')) {
        refunds.add(txn);
      }
    }

    final matches = <RefundMatch>[];
    final pairedRefundIds = <String>{};

    for (final refund in refunds) {
      final refundAmount = refund.amountMinorUnits;

      for (final debit in debits) {
        if (pairedRefundIds.contains(refund.id)) break;

        final debitAmount = debit.amountMinorUnits.abs();

        // Refund must not exceed original transaction amount
        if (refundAmount > debitAmount) continue;

        // Refund timestamp should be equal to or after original transaction
        if (refund.transactionTimestamp.isBefore(debit.transactionTimestamp)) {
          continue;
        }

        // Must be related merchant / counterparty
        if (!_isMerchantMatch(debit.merchant, refund.merchant)) {
          continue;
        }

        final isPartial = refundAmount < debitAmount;
        var confidence = isPartial ? 0.85 : 0.95;

        // If reference number matches, confidence is 1.0
        if (refund.referenceNumber != null &&
            debit.referenceNumber != null &&
            refund.referenceNumber == debit.referenceNumber) {
          confidence = 1;
        }

        matches.add(
          RefundMatch(
            originalTransaction: debit,
            refundTransaction: refund,
            refundAmountMinorUnits: refundAmount,
            isPartialRefund: isPartial,
            confidence: confidence,
          ),
        );

        pairedRefundIds.add(refund.id);
        break;
      }
    }

    return matches;
  }

  bool _isMerchantMatch(String debitMerchant, String refundMerchant) {
    final d = debitMerchant.toLowerCase().trim();
    final r = refundMerchant.toLowerCase().trim();

    // Clean out "refund" or "reversal" prefixes
    final cleanRefund = r
        .replaceAll(RegExp(r'\b(?:refund|reversal|cashback)\b'), '')
        .trim();

    if (cleanRefund.isEmpty) {
      // If refund description is just "Refund", we can't be sure on merchant alone
      return false;
    }

    return d.contains(cleanRefund) || cleanRefund.contains(d);
  }
}
