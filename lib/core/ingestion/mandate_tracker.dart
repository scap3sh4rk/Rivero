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

  Future<Mandate?> _find(String? payee) async {
    if (payee == null) return null;
    final all = await db.mandatesDao.getAllMandates();
    final matches = all.where((m) => samePayee(m.payee, payee)).toList()
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
          await _create(n, n.date ?? addMonths(at, 1), at);
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

  /// How far either side of the due date a debit still counts as that
  /// autopay, and how long an unmatched autopay stays "overdue" (still
  /// reserved) before it is assumed paid and moved to its next date.
  static const grace = Duration(days: 5);

  /// The date after [due] for [f]. Month steps keep the day where it can and
  /// clamp to the month's last day (31 Jan -> 28 Feb, not 3 Mar). Null for
  /// "as presented" mandates, which have no schedule.
  static DateTime? nextDue(DateTime due, MandateFrequency f) => switch (f) {
    MandateFrequency.weekly => due.add(const Duration(days: 7)),
    MandateFrequency.monthly => addMonths(due, 1),
    MandateFrequency.quarterly => addMonths(due, 3),
    MandateFrequency.semiAnnual => addMonths(due, 6),
    MandateFrequency.annual => addMonths(due, 12),
    MandateFrequency.asPresented => null,
  };

  static Set<String> _words(String s) => s
      .toLowerCase()
      .split(RegExp('[^a-z0-9]+'))
      .where((w) => w.length >= 3)
      .toSet();

  /// Same payee: a shared whole word of 3+ letters ("Netflix" ~ "NETFLIX
  /// COM"), never a fragment ("Air" is not "Airtel").
  static bool samePayee(String a, String b) =>
      _words(a).intersection(_words(b)).isNotEmpty;

  static bool _amountFits(Mandate m, int amount) => m.isVariableAmount
      ? amount <= (m.maxCapMinorUnits ?? m.amountMinorUnits)
      : amount == m.amountMinorUnits;

  /// A real debit was recorded (captured or typed in): if it is a live
  /// autopay due around now, move that autopay to its next date so it is
  /// not reserved again. Matches on payee AND amount, or on the exact
  /// amount alone when only one autopay fits (a typed-in "Subscriptions").
  Future<void> onDebit({
    required String? merchant,
    required int amountMinorUnits,
    required DateTime at,
  }) async {
    final live = (await db.mandatesDao.getAllMandates()).where((m) {
      final due = m.nextExecutionDate;
      return m.status == MandateStatus.active &&
          due != null &&
          at.difference(due).abs() <= grace &&
          _amountFits(m, amountMinorUnits);
    }).toList();
    if (live.isEmpty) return;
    final byName = merchant == null
        ? const <Mandate>[]
        : live.where((m) => samePayee(m.payee, merchant)).toList();
    final exact = live
        .where((m) => m.amountMinorUnits == amountMinorUnits)
        .toList();
    final m = byName.length == 1
        ? byName.single
        : (byName.isEmpty && exact.length == 1 ? exact.single : null);
    if (m == null) return;
    await db.mandatesDao.patchMandate(
      m.id,
      MandatesCompanion(
        nextExecutionDate: Value(nextDue(m.nextExecutionDate!, m.frequency)),
        updatedAt: Value(at),
      ),
    );
  }

  /// Autopays whose date passed more than [grace] ago without a matching
  /// debit are moved to their next future date (assumed paid; the bank's
  /// balance already shows it). Run on start and on resume.
  Future<int> rollOverdue(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    var rolled = 0;
    for (final m in await db.mandatesDao.getAllMandates()) {
      var due = m.nextExecutionDate;
      if (m.status != MandateStatus.active || due == null) continue;
      if (!due.isBefore(today.subtract(grace))) continue;
      while (due != null && due.isBefore(today)) {
        due = nextDue(due, m.frequency);
      }
      await db.mandatesDao.patchMandate(
        m.id,
        MandatesCompanion(nextExecutionDate: Value(due), updatedAt: Value(now)),
      );
      rolled++;
    }
    return rolled;
  }
}

/// [d] moved by [months], the day clamped to the target month's length.
DateTime addMonths(DateTime d, int months) {
  final first = DateTime(d.year, d.month + months);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(
    first.year,
    first.month,
    d.day > last ? last : d.day,
    d.hour,
    d.minute,
  );
}
