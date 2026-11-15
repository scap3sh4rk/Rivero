import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/mandates_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/mandate_tracker.dart';
import 'package:rivero/core/ledger/ledger_service.dart';

/// What the user can say about an overdue autopay whose debit was never
/// seen: it was paid, it failed (retry on a date), or skip this one.
class AutopayActions {
  const AutopayActions(this.db);

  final RiveroDatabase db;

  /// The kind shown for [m]: the user's choice, else a guess from the name.
  static MandateKind kindOf(Mandate m) =>
      m.kind != MandateKind.other ? m.kind : MandateKind.guess(m.payee);

  /// It went through: record the debit on its due date (a SIP is an
  /// investment, not spending) and move the autopay to its next date.
  Future<void> markPaid(Mandate m) async {
    final due = m.nextExecutionDate;
    if (due == null) return;
    final kind = kindOf(m);
    await LedgerService(db).recordManual(
      accountId: m.physicalAccountId,
      amountMinorUnits: -mandateReserve(m),
      type: kind == MandateKind.sip
          ? TransactionType.investmentContribution
          : TransactionType.expense,
      merchant: m.payee,
      category: kind.label,
      at: due,
    );
    // Recording a spend moves a matching autopay already; never twice.
    final now = await db.mandatesDao.getMandateById(m.id);
    if (now?.nextExecutionDate == due) await skip(m);
  }

  /// It failed: keep it reserved until [retry] (the bank's retry, or the
  /// day the user will pay it).
  Future<void> retryOn(Mandate m, DateTime retry) =>
      db.mandatesDao.patchMandate(
        m.id,
        MandatesCompanion(
          nextExecutionDate: Value(
            DateTime(retry.year, retry.month, retry.day),
          ),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Skip this debit: nothing recorded, the autopay moves to its next date.
  Future<void> skip(Mandate m) async {
    final due = m.nextExecutionDate;
    if (due == null) return;
    await db.mandatesDao.patchMandate(
      m.id,
      MandatesCompanion(
        nextExecutionDate: Value(MandateTracker.nextDue(due, m.frequency)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
