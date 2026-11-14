import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/import/statement_parser.dart';

/// Adds past transactions from a statement to one account.
///
/// History is already part of today's balance, so imported rows do not move
/// balances or budgets; they fill Activity and spending history. Rows that
/// match an existing entry (same day, amount and description) are skipped.
class StatementImporter {
  StatementImporter(this.db);

  final RiveroDatabase db;

  Future<({int added, int skipped})> importRows(
    String accountId,
    List<StatementRow> rows,
  ) async {
    final existing = (await db.select(db.transactions).get())
        .where((t) => t.physicalAccountId == accountId)
        .map(_key)
        .toSet();
    var added = 0;
    var skipped = 0;
    final now = DateTime.now();
    await db.transaction(() async {
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final desc = r.description.length > 120
            ? r.description.substring(0, 120)
            : r.description;
        final key =
            '${_day(r.date)}|${r.amountMinorUnits}|${desc.toLowerCase()}';
        if (!existing.add(key)) {
          skipped++;
          continue;
        }
        await db.transactionsDao.insertTransaction(
          TransactionsCompanion(
            id: Value('import-${now.microsecondsSinceEpoch}-$i'),
            physicalAccountId: Value(accountId),
            amountMinorUnits: Value(r.amountMinorUnits),
            transactionType: Value(
              r.amountMinorUnits < 0
                  ? TransactionType.expense
                  : TransactionType.income,
            ),
            // Already reflected in the balance: never re-applied.
            transactionState: const Value(TransactionState.reconciled),
            merchant: Value(desc),
            category: Value(r.amountMinorUnits < 0 ? 'Imported' : 'Income'),
            transactionTimestamp: Value(r.date),
            createdAt: Value(now),
          ),
        );
        added++;
      }
    });
    return (added: added, skipped: skipped);
  }

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static String _key(LedgerTransaction t) =>
      '${_day(t.transactionTimestamp)}|${t.amountMinorUnits}|'
      '${t.merchant.toLowerCase()}';
}
