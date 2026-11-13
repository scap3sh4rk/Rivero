import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/reconciliation/models/reconciliation_models.dart';

/// Identifies pairs of corresponding debit and credit transactions across
/// different physical accounts that represent internal self-transfers.
class InternalTransferMatcher {
  const InternalTransferMatcher({
    this.defaultWindow = const Duration(seconds: 300),
  });

  /// Maximum time delta allowed between corresponding legs (default: 300s).
  final Duration defaultWindow;

  /// Scans [unlinkedTransactions] and returns all identified transfer pairs.
  List<TransferPairMatch> findTransferPairs({
    required List<LedgerTransaction> unlinkedTransactions,
    Duration? window,
  }) {
    final searchWindow = window ?? defaultWindow;
    final debits = <LedgerTransaction>[];
    final credits = <LedgerTransaction>[];

    // Filter unlinked candidates by direction
    for (final txn in unlinkedTransactions) {
      if (txn.linkedTransactionId != null || txn.isInternalTransfer) {
        continue; // Already linked
      }
      if (txn.amountMinorUnits < 0) {
        debits.add(txn);
      } else if (txn.amountMinorUnits > 0) {
        credits.add(txn);
      }
    }

    final matchedPairs = <TransferPairMatch>[];
    final pairedCreditIds = <String>{};

    for (final debit in debits) {
      final targetAmount = debit.amountMinorUnits.abs();

      for (final credit in credits) {
        if (pairedCreditIds.contains(credit.id)) {
          continue; // Already matched in this pass
        }

        // Must be on different physical accounts
        if (debit.physicalAccountId == credit.physicalAccountId) {
          continue;
        }

        // Amounts must match exactly
        if (credit.amountMinorUnits != targetAmount) {
          continue;
        }

        // Time delta must fall within tolerance window
        final delta = debit.transactionTimestamp
            .difference(credit.transactionTimestamp)
            .abs();
        if (delta > searchWindow) {
          continue;
        }

        // Confidence evaluation
        var confidence = 0.90;
        if (debit.referenceNumber != null &&
            credit.referenceNumber != null &&
            debit.referenceNumber == credit.referenceNumber) {
          confidence = 1;
        } else if (delta.inSeconds <= 60) {
          confidence = 0.95;
        }

        matchedPairs.add(
          TransferPairMatch(
            debitTransaction: debit,
            creditTransaction: credit,
            amountMinorUnits: targetAmount,
            confidence: confidence,
            timeDelta: delta,
          ),
        );

        pairedCreditIds.add(credit.id);
        break; // Debit is matched; move to next debit
      }
    }

    return matchedPairs;
  }
}
