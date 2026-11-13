import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/deduplication_engine.dart';
import 'package:rivero/core/ingestion/models/ingestion_result.dart';
import 'package:rivero/core/ingestion/models/parsed_transaction.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/ingestion/parser/financial_parser.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:uuid/uuid.dart';

/// Central ingestion orchestrator coordinating the audit trail,
/// regex financial parser, deduplication engine, and ledger persistence.
class IngestionService {
  IngestionService({
    required this.database,
    this.parser = const FinancialParser(),
    this.deduplicator = const DeduplicationEngine(),
    this.uuid = const Uuid(),
  });

  final RiveroDatabase database;
  final FinancialParser parser;
  final DeduplicationEngine deduplicator;
  final Uuid uuid;

  /// Ingests and processes a [RawNotification] through the end-to-end pipeline.
  Future<IngestionResult> processNotification(
    RawNotification notification,
  ) async {
    final now = DateTime.now();
    final logId = notification.id.isNotEmpty ? notification.id : uuid.v4();

    // 1. Attempt parsing
    final parsed = parser.parse(notification);

    if (parsed == null) {
      // Failed to parse financial details
      await database.ingestionLogsDao.insertLog(
        RawIngestionLogsCompanion(
          id: Value(logId),
          sourceChannel: Value(notification.channel),
          senderHeader: Value(notification.sender ?? notification.packageName),
          rawPayload: Value(notification.body),
          receivedAt: Value(notification.receivedAt),
          parseStatus: const Value(ParseStatus.failed),
          confidenceScore: const Value(0),
          failureReason: const Value(
            'No recognizable financial entities found',
          ),
          createdAt: Value(now),
        ),
      );

      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.failed,
        isDuplicate: false,
        failureReason: 'No recognizable financial entities found',
      );
    }

    // 2. Check for low confidence / quarantine (EC-10)
    if (parsed.isLowConfidence) {
      await database.ingestionLogsDao.insertLog(
        RawIngestionLogsCompanion(
          id: Value(logId),
          sourceChannel: Value(notification.channel),
          senderHeader: Value(notification.sender ?? notification.packageName),
          rawPayload: Value(notification.body),
          receivedAt: Value(notification.receivedAt),
          parseStatus: const Value(ParseStatus.quarantined),
          confidenceScore: Value(parsed.confidenceScore),
          failureReason: const Value('Confidence score below 0.60 threshold'),
          createdAt: Value(now),
        ),
      );

      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.quarantined,
        isDuplicate: false,
        parsedTransaction: parsed,
        failureReason: 'Confidence score below 0.60 threshold',
      );
    }

    // 3. Persist successful raw audit log
    await database.ingestionLogsDao.insertLog(
      RawIngestionLogsCompanion(
        id: Value(logId),
        sourceChannel: Value(notification.channel),
        senderHeader: Value(notification.sender ?? notification.packageName),
        rawPayload: Value(notification.body),
        receivedAt: Value(notification.receivedAt),
        parseStatus: const Value(ParseStatus.parsed),
        confidenceScore: Value(parsed.confidenceScore),
        createdAt: Value(now),
      ),
    );

    // 4. Query recent transactions for deduplication
    final signedAmount = parsed.isDebit
        ? -parsed.amountMinorUnits
        : parsed.amountMinorUnits;

    final candidates = await database.transactionsDao.findDuplicateCandidates(
      amountMinorUnits: signedAmount,
      timestamp: parsed.timestamp,
    );

    final match = deduplicator.evaluate(
      candidate: parsed,
      existingTransactions: candidates,
    );

    if (match.isDuplicate && match.matchedTransaction != null) {
      // Duplicate identified - avoid double-counting in ledger
      return IngestionResult(
        rawLogId: logId,
        status: ParseStatus.parsed,
        isDuplicate: true,
        parsedTransaction: parsed,
        persistedTransactionId: match.matchedTransaction!.id,
      );
    }

    // 5. Resolve target physical account or create a fallback default
    final accountId = await _resolveOrCreatePhysicalAccount(parsed);

    final txnId = uuid.v4();
    final state = parsed.isHighConfidence
        ? TransactionState.confirmed
        : TransactionState.needsReview;

    await database.transactionsDao.insertTransaction(
      TransactionsCompanion(
        id: Value(txnId),
        ingestionLogId: Value(logId),
        physicalAccountId: Value(accountId),
        amountMinorUnits: Value(signedAmount),
        transactionType: Value(parsed.suggestedTransactionType),
        transactionState: Value(state),
        merchant: Value(parsed.merchant ?? 'Unknown Merchant'),
        category: Value(parsed.category ?? 'General Expense'),
        referenceNumber: Value(parsed.referenceNumber),
        transactionTimestamp: Value(parsed.timestamp),
        createdAt: Value(now),
      ),
    );

    // Auto-confirmed transactions take effect immediately; others wait for
    // the user's swipe, which goes through LedgerService.confirm.
    if (state == TransactionState.confirmed) {
      final saved = await database.transactionsDao.getTransactionById(txnId);
      if (saved != null) await LedgerService(database).applyEffects(saved);
    }

    return IngestionResult(
      rawLogId: logId,
      status: ParseStatus.parsed,
      isDuplicate: false,
      parsedTransaction: parsed,
      persistedTransactionId: txnId,
    );
  }

  Future<String> _resolveOrCreatePhysicalAccount(
    ParsedTransaction parsed,
  ) async {
    final accounts = await database.accountsDao.getAllActivePhysicalAccounts();

    // Try finding by account mask
    if (parsed.accountMask != null) {
      for (final acc in accounts) {
        if (acc.accountMask == parsed.accountMask) {
          return acc.id;
        }
      }
    }

    // If an existing account exists, use the first active one
    if (accounts.isNotEmpty) {
      return accounts.first.id;
    }

    // Create a default primary account
    final newId = uuid.v4();
    final now = DateTime.now();
    await database.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: Value(newId),
        name: Value(
          '${parsed.financialInstitution ?? "Bank"} Account'
          '${parsed.accountMask != null ? " (**${parsed.accountMask})" : ""}',
        ),
        institution: Value(parsed.financialInstitution ?? 'Primary Bank'),
        accountMask: Value(parsed.accountMask ?? '••••'),
        isLiability: Value(
          parsed.suggestedTransactionType ==
                  TransactionType.creditCardPurchase ||
              parsed.suggestedTransactionType ==
                  TransactionType.creditCardSettlement,
        ),
        balanceMinorUnits: const Value(0),
        isActive: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    return newId;
  }
}
