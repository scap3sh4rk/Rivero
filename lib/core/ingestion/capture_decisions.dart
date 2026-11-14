import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/reconciliation/reconciliation_service.dart';

/// Choices made in the popup of a capture notification (Add with a category
/// and note, or Ignore), applied once that capture has been processed.
/// Keyed by the capture id, which is also the capture's ingestion log id.
class CaptureDecisions {
  const CaptureDecisions(this.db);

  final RiveroDatabase db;

  /// The entry Rivero made from capture [captureId], if any.
  Future<LedgerTransaction?> entryFor(String captureId) =>
      (db.select(db.transactions)
            ..where((t) => t.ingestionLogId.equals(captureId))
            ..limit(1))
          .getSingleOrNull();

  /// Applies [decisions] ({captureId: {action, category, note}}). Returns how
  /// many were applied; captures that made no entry (a duplicate, a
  /// promotion) are skipped.
  Future<int> apply(Map<String, dynamic> decisions) async {
    final ledger = LedgerService(db);
    var applied = 0;
    for (final e in decisions.entries) {
      final d = (e.value as Map).cast<String, dynamic>();
      final t = await entryFor(e.key);
      if (t == null) continue;
      if (d['action'] == 'ignore') {
        final counted =
            t.transactionState == TransactionState.confirmed ||
            t.transactionState == TransactionState.reconciled;
        // Already counted (automatic acceptance on): undo it.
        counted ? await ledger.remove(t.id) : await ledger.ignore(t.id);
      } else {
        final category = d['category'] as String?;
        final note = d['note'] as String?;
        await (db.update(
          db.transactions,
        )..where((x) => x.id.equals(t.id))).write(
          TransactionsCompanion(
            category: category == null || category.isEmpty
                ? const Value.absent()
                : Value(category),
            userNotes: note == null || note.isEmpty
                ? const Value.absent()
                : Value(note),
          ),
        );
        await ledger.confirm(t.id);
        await ReconciliationService(database: db).reconcileAll();
      }
      applied++;
    }
    return applied;
  }
}
