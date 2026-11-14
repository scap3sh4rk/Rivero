import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/reconciliation/models/reconciliation_models.dart';

/// Identifies pairs of corresponding debit and credit transactions across
/// different physical accounts that represent internal self-transfers.
class InternalTransferMatcher {
  const InternalTransferMatcher({
    this.defaultWindow = const Duration(seconds: 300),
  });

  /// Maximum time delta allowed between corresponding legs (default: 300s).
  final Duration defaultWindow;

  static const Set<TransactionType> _debitKinds = {
    TransactionType.expense,
    TransactionType.internalTransfer,
    TransactionType.creditCardSettlement,
    TransactionType.walletTopup,
    TransactionType.bucketFunding,
    TransactionType.investmentContribution,
  };

  static const Set<TransactionType> _creditKinds = {
    TransactionType.income,
    TransactionType.internalTransfer,
    TransactionType.creditCardSettlement,
    TransactionType.walletTopup,
    TransactionType.bucketFunding,
    TransactionType.investmentRedemption,
  };

  /// Scans [unlinkedTransactions] and returns all identified transfer pairs.
  List<TransferPairMatch> findTransferPairs({
    required List<LedgerTransaction> unlinkedTransactions,
    Duration? window,
  }) {
    final searchWindow = window ?? defaultWindow;
    final debits = <LedgerTransaction>[];
    final credits = <LedgerTransaction>[];

    // Filter unlinked candidates by direction. Only kinds that can be one
    // side of moving money between your own accounts: never a card
    // purchase, a loan, a repayment, a refund, a hand-set balance, or a
    // salary without the same bank reference.
    for (final txn in unlinkedTransactions) {
      if (txn.linkedTransactionId != null || txn.isInternalTransfer) {
        continue; // Already linked
      }
      if (txn.amountMinorUnits < 0 &&
          _debitKinds.contains(txn.transactionType)) {
        debits.add(txn);
      } else if (txn.amountMinorUnits > 0 &&
          _creditKinds.contains(txn.transactionType)) {
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

        // Bank references decide when both sides have one: different ones
        // are two unrelated payments. Without them, only an almost
        // simultaneous pair is trusted (paying one friend while another
        // pays you the same amount is not a transfer).
        final dr = debit.referenceNumber;
        final cr = credit.referenceNumber;
        final bothRefs = dr != null && cr != null;
        if (bothRefs && dr != cr) continue;
        if (!bothRefs && delta > const Duration(seconds: 120)) continue;
        // A salary is only a transfer when the bank says so (same ref).
        final looksLikeSalary =
            credit.transactionType == TransactionType.income &&
            '${credit.merchant} ${credit.category}'.toLowerCase().contains(
              'salary',
            );
        if (looksLikeSalary && !bothRefs) continue;

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
