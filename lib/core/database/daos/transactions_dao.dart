import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/tables/transactions_table.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

part 'transactions_dao.g.dart';

/// Data Access Object for ledger transactions.
@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<RiveroDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.attachedDatabase);

  /// Watch all transactions ordered newest first.
  /// One-shot read of every transaction, newest first.
  Future<List<LedgerTransaction>> getAllTransactions() {
    return (select(transactions)..orderBy([
          (t) => OrderingTerm(
            expression: t.transactionTimestamp,
            mode: OrderingMode.desc,
          ),
        ]))
        .get();
  }

  Stream<List<LedgerTransaction>> watchAllTransactions() {
    return (select(transactions)..orderBy([
          (t) => OrderingTerm(
            expression: t.transactionTimestamp,
            mode: OrderingMode.desc,
          ),
        ]))
        .watch();
  }

  /// Watch recent transactions ordered newest first.
  Stream<List<LedgerTransaction>> watchRecentTransactions({int limit = 50}) {
    return (select(transactions)
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.transactionTimestamp,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(limit))
        .watch();
  }

  /// Watch transactions requiring user review / triage.
  Stream<List<LedgerTransaction>> watchPendingReviewTransactions() {
    return (select(transactions)
          ..where(
            (tbl) =>
                tbl.transactionState.equals(TransactionState.needsReview.name),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.transactionTimestamp,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Watch transactions for a specific physical account.
  Stream<List<LedgerTransaction>> watchTransactionsByAccount(String accountId) {
    return (select(transactions)
          ..where((tbl) => tbl.physicalAccountId.equals(accountId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.transactionTimestamp,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Watch transactions for a specific virtual allocation bucket.
  Stream<List<LedgerTransaction>> watchTransactionsByBucket(String bucketId) {
    return (select(transactions)
          ..where((tbl) => tbl.allocationBucketId.equals(bucketId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.transactionTimestamp,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  /// Get transaction by ID.
  Future<LedgerTransaction?> getTransactionById(String id) {
    return (select(
      transactions,
    )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  /// Insert a new ledger transaction.
  Future<int> insertTransaction(TransactionsCompanion entry) {
    return into(transactions).insert(entry);
  }

  /// Update the lifecycle state of a transaction (e.g. confirm, reconcile, ignore).
  Future<bool> updateTransactionState(
    String transactionId,
    TransactionState newState,
  ) async {
    final updatedRows =
        await (update(transactions)
              ..where((tbl) => tbl.id.equals(transactionId)))
            .write(TransactionsCompanion(transactionState: Value(newState)));
    return updatedRows > 0;
  }

  /// Reclassify transaction bucket.
  Future<bool> updateTransactionBucket(
    String transactionId,
    String? bucketId,
  ) async {
    final updatedRows =
        await (update(transactions)
              ..where((tbl) => tbl.id.equals(transactionId)))
            .write(TransactionsCompanion(allocationBucketId: Value(bucketId)));
    return updatedRows > 0;
  }

  /// Link two partner transaction legs together (e.g. internal transfers or refund).
  Future<void> linkTransactionLegs(
    String transactionId1,
    String transactionId2,
  ) async {
    await (update(
      transactions,
    )..where((tbl) => tbl.id.equals(transactionId1))).write(
      TransactionsCompanion(
        linkedTransactionId: Value(transactionId2),
        isInternalTransfer: const Value(true),
      ),
    );
    await (update(
      transactions,
    )..where((tbl) => tbl.id.equals(transactionId2))).write(
      TransactionsCompanion(
        linkedTransactionId: Value(transactionId1),
        isInternalTransfer: const Value(true),
      ),
    );
  }

  /// Update category and merchant description for a transaction.
  Future<bool> updateTransactionCategory(
    String transactionId, {
    String? category,
    String? merchant,
    String? bucketId,
  }) async {
    final updatedRows =
        await (update(
          transactions,
        )..where((tbl) => tbl.id.equals(transactionId))).write(
          TransactionsCompanion(
            category: category != null ? Value(category) : const Value.absent(),
            merchant: merchant != null ? Value(merchant) : const Value.absent(),
            allocationBucketId: bucketId != null
                ? Value(bucketId)
                : const Value.absent(),
          ),
        );
    return updatedRows > 0;
  }

  /// Delete a transaction by ID.
  Future<int> deleteTransaction(String transactionId) {
    return (delete(
      transactions,
    )..where((tbl) => tbl.id.equals(transactionId))).go();
  }

  /// Find potential duplicate candidates within a timestamp window with matching amount.
  Future<List<LedgerTransaction>> findDuplicateCandidates({
    required int amountMinorUnits,
    required DateTime timestamp,
    Duration window = const Duration(seconds: 180),
  }) {
    final start = timestamp.subtract(window);
    final end = timestamp.add(window);

    return (select(transactions)..where(
          (tbl) =>
              tbl.amountMinorUnits.equals(amountMinorUnits) &
              tbl.transactionTimestamp.isBetweenValues(start, end),
        ))
        .get();
  }
}
