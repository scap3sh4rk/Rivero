import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ingestion/parser/message_intent.dart';
import 'package:uuid/uuid.dart';

/// Keeps the Autopay list in step with bank messages:
/// pre-debit reminders set the next debit date (they are NOT debits),
/// "created" messages add a mandate, "revoked" messages cancel it, and the
/// real debit later moves the next date forward.
class MandateTracker {
  MandateTracker(this.db);

  final RiveroDatabase db;

  static bool _sameName(String a, String b) {
    final x = a.toLowerCase().trim();
    final y = b.toLowerCase().trim();
    return x.isNotEmpty && y.isNotEmpty && (x.contains(y) || y.contains(x));
  }

  Future<Mandate?> _find(String? payee) async {
    if (payee == null) return null;
    final all = await db.mandatesDao.getAllMandates();
    final matches = all.where((m) => _sameName(m.payee, payee)).toList()
      ..sort((a, b) {
        // Prefer live mandates over ended ones.
        int rank(Mandate m) => m.status == MandateStatus.active ? 0 : 1;
        return rank(a).compareTo(rank(b));
      });
    return matches.firstOrNull;
  }

  Future<void> apply(MandateNotice n, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final existing = await _find(n.payee);

    switch (n.intent) {
      case MessageIntent.mandateCancelled:
        if (existing != null) {
          await db.mandatesDao.updateMandateStatus(
            existing.id,
            MandateStatus.cancelled,
          );
        }
      case MessageIntent.preDebit:
        final due = n.date ?? at.add(const Duration(days: 1));
        if (existing != null) {
          await db.mandatesDao.patchMandate(
            existing.id,
            MandatesCompanion(
              nextExecutionDate: Value(due),
              status: const Value(MandateStatus.active),
              updatedAt: Value(at),
            ),
          );
        } else {
          await _create(n, due, at);
        }
      case MessageIntent.mandateCreated:
        if (existing != null) {
          await db.mandatesDao.updateMandateStatus(
            existing.id,
            MandateStatus.active,
          );
        } else {
          await _create(
            n,
            n.date ?? DateTime(at.year, at.month + 1, at.day),
            at,
          );
        }
      case MessageIntent.mandateFailed:
      case MessageIntent.statementDue:
      case MessageIntent.otp:
      case MessageIntent.transaction:
        break;
    }
  }

  Future<void> _create(MandateNotice n, DateTime due, DateTime at) async {
    final payee = n.payee;
    final amount = n.amountMinorUnits;
    if (payee == null || amount == null || amount <= 0) return;
    final accounts = (await db.accountsDao.getAllActivePhysicalAccounts())
        .where((a) => !a.isLiability)
        .toList();
    if (accounts.isEmpty) return;
    final account =
        accounts.where((a) => a.accountMask == n.accountMask).firstOrNull ??
        accounts.first;
    await db.mandatesDao.upsertMandate(
      MandatesCompanion(
        id: Value(const Uuid().v4()),
        payee: Value(payee),
        amountMinorUnits: Value(amount),
        frequency: const Value(MandateFrequency.monthly),
        physicalAccountId: Value(account.id),
        startDate: Value(at),
        nextExecutionDate: Value(due),
        status: const Value(MandateStatus.active),
        mandateUmn: Value(n.umn),
        createdAt: Value(at),
        updatedAt: Value(at),
      ),
    );
  }

  /// A real debit arrived: if it belongs to a live mandate due around now,
  /// roll its next debit date forward by one period.
  Future<void> onDebit({
    required String? merchant,
    required DateTime at,
  }) async {
    final m = await _find(merchant);
    final due = m?.nextExecutionDate;
    if (m == null ||
        due == null ||
        m.status != MandateStatus.active ||
        at.difference(due).inDays.abs() > 5) {
      return;
    }
    final next = switch (m.frequency) {
      MandateFrequency.weekly => due.add(const Duration(days: 7)),
      MandateFrequency.monthly => DateTime(due.year, due.month + 1, due.day),
      MandateFrequency.quarterly => DateTime(due.year, due.month + 3, due.day),
      MandateFrequency.semiAnnual => DateTime(due.year, due.month + 6, due.day),
      MandateFrequency.annual => DateTime(due.year + 1, due.month, due.day),
      MandateFrequency.asPresented => due,
    };
    await db.mandatesDao.patchMandate(
      m.id,
      MandatesCompanion(nextExecutionDate: Value(next), updatedAt: Value(at)),
    );
  }
}
