import 'package:flutter/foundation.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/ingestion/models/parsed_transaction.dart';

/// The result of evaluating a candidate [ParsedTransaction] against existing ledger entries.
@immutable
class DeduplicationMatch {
  const DeduplicationMatch._({
    required this.isDuplicate,
    required this.confidence,
    this.matchedTransaction,
    this.reason,
    this.mergedMerchant,
    this.mergedReferenceNumber,
  });

  /// No duplicate detected; candidate is safe to insert as a new ledger entry.
  factory DeduplicationMatch.noDuplicate() {
    return const DeduplicationMatch._(isDuplicate: false, confidence: 0);
  }

  /// Duplicate identified with matching candidate and confidence score.
  factory DeduplicationMatch.duplicate({
    required LedgerTransaction matchedTransaction,
    required double confidence,
    required String reason,
    String? mergedMerchant,
    String? mergedReferenceNumber,
  }) {
    return DeduplicationMatch._(
      isDuplicate: true,
      confidence: confidence,
      matchedTransaction: matchedTransaction,
      reason: reason,
      mergedMerchant: mergedMerchant,
      mergedReferenceNumber: mergedReferenceNumber,
    );
  }

  /// Whether the candidate matches an already persisted transaction.
  final bool isDuplicate;

  /// Confidence of the duplicate match (0.0 to 1.0).
  final double confidence;

  /// The existing ledger transaction that matched.
  final LedgerTransaction? matchedTransaction;

  /// Human-readable explanation of why this was identified as duplicate.
  final String? reason;

  /// Enriched merchant title merged from both events.
  final String? mergedMerchant;

  /// Reference number merged from either source if one was missing.
  final String? mergedReferenceNumber;

  @override
  String toString() {
    return 'DeduplicationMatch(isDuplicate: $isDuplicate, confidence: $confidence, '
        'matchedId: ${matchedTransaction?.id}, reason: $reason)';
  }
}

/// Evaluates newly parsed incoming transactions against the active ledger to prevent
/// double-counting when transactions trigger multiple notifications (e.g. UPI app + Bank SMS).
class DeduplicationEngine {
  const DeduplicationEngine({this.window = const Duration(seconds: 180)});

  /// Time tolerance window for temporal matching (default: ±180 seconds).
  final Duration window;

  /// Evaluates [candidate] against a list of recent [existingTransactions].
  DeduplicationMatch evaluate({
    required ParsedTransaction candidate,
    required List<LedgerTransaction> existingTransactions,
  }) {
    for (final existing in existingTransactions) {
      // Priority 1: Exact reference number match (UTR / UPI RRN)
      if (candidate.referenceNumber != null &&
          candidate.referenceNumber!.isNotEmpty &&
          existing.referenceNumber != null &&
          existing.referenceNumber!.isNotEmpty) {
        if (candidate.referenceNumber == existing.referenceNumber) {
          return DeduplicationMatch.duplicate(
            matchedTransaction: existing,
            confidence: 1,
            reason: 'Matching UTR/RRN reference (${candidate.referenceNumber})',
            mergedMerchant: _pickBestMerchant(
              existing.merchant,
              candidate.merchant,
            ),
            mergedReferenceNumber: existing.referenceNumber,
          );
        }
      }

      // Priority 2: Amount + Direction + Time window match
      final candidateSignedAmount = candidate.isDebit
          ? -candidate.amountMinorUnits
          : candidate.amountMinorUnits;

      if (existing.amountMinorUnits == candidateSignedAmount) {
        final timeDiff = candidate.timestamp
            .difference(existing.transactionTimestamp)
            .abs();

        if (timeDiff <= window) {
          final merchantMatch = _isMerchantMatch(
            existing.merchant,
            candidate.merchant,
          );

          if (merchantMatch) {
            return DeduplicationMatch.duplicate(
              matchedTransaction: existing,
              confidence: 0.95,
              reason:
                  'Matching amount (${candidate.amountMinorUnits} paise) and '
                  'merchant within ${timeDiff.inSeconds}s window',
              mergedMerchant: _pickBestMerchant(
                existing.merchant,
                candidate.merchant,
              ),
              mergedReferenceNumber:
                  existing.referenceNumber ?? candidate.referenceNumber,
            );
          }

          // If time is very close (within 60s) and same amount, even without merchant match
          if (timeDiff.inSeconds <= 60) {
            return DeduplicationMatch.duplicate(
              matchedTransaction: existing,
              confidence: 0.80,
              reason:
                  'Matching amount within immediate ${timeDiff.inSeconds}s window',
              mergedMerchant: _pickBestMerchant(
                existing.merchant,
                candidate.merchant,
              ),
              mergedReferenceNumber:
                  existing.referenceNumber ?? candidate.referenceNumber,
            );
          }
        }
      }
    }

    return DeduplicationMatch.noDuplicate();
  }

  bool _isMerchantMatch(String existing, String? candidate) {
    if (candidate == null || candidate.isEmpty) return true;
    final e = existing.toLowerCase().trim();
    final c = candidate.toLowerCase().trim();

    return e == c || e.contains(c) || c.contains(e);
  }

  String _pickBestMerchant(String existing, String? candidate) {
    if (candidate == null || candidate.isEmpty) return existing;
    // Prefer cleaner name (avoid names with '@' or technical prefixes)
    if (existing.contains('@') && !candidate.contains('@')) {
      return candidate;
    }
    return existing;
  }
}
