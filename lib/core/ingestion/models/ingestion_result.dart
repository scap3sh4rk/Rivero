import 'package:flutter/foundation.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/models/parsed_transaction.dart';

/// The final outcome of processing an incoming raw notification through the ingestion pipeline.
@immutable
class IngestionResult {
  const IngestionResult({
    required this.rawLogId,
    required this.status,
    required this.isDuplicate,
    this.parsedTransaction,
    this.persistedTransactionId,
    this.failureReason,
  });

  /// The unique audit log ID stored in the raw ingestion logs table.
  final String rawLogId;

  /// Classification status of the raw event (parsed, quarantined, failed, ignored).
  final ParseStatus status;

  /// Whether this event was merged into an existing transaction via deduplication.
  final bool isDuplicate;

  /// The normalized transaction entity if successfully parsed.
  final ParsedTransaction? parsedTransaction;

  /// ID of the ledger transaction created or matched.
  final String? persistedTransactionId;

  /// Explanation if parsing failed, was quarantined, or ignored.
  final String? failureReason;

  @override
  String toString() {
    return 'IngestionResult(logId: $rawLogId, status: $status, '
        'isDuplicate: $isDuplicate, txnId: $persistedTransactionId)';
  }
}
