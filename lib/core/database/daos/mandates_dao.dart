import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/tables/mandates_table.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

part 'mandates_dao.g.dart';

/// Data Access Object for recurring UPI Autopay and e-NACH commitments.
@DriftAccessor(tables: [Mandates])
class MandatesDao extends DatabaseAccessor<RiveroDatabase>
    with _$MandatesDaoMixin {
  MandatesDao(super.attachedDatabase);

  /// One-shot read of every mandate.
  Future<List<Mandate>> getAllMandates() => select(mandates).get();

  /// Watch every mandate regardless of status (for the Autopay screen).
  Stream<List<Mandate>> watchAllMandates() {
    return (select(
      mandates,
    )..orderBy([(t) => OrderingTerm(expression: t.nextExecutionDate)])).watch();
  }

  /// Watch all currently active mandates.
  Stream<List<Mandate>> watchActiveMandates() {
    return (select(mandates)
          ..where((tbl) => tbl.status.equals(MandateStatus.active.name))
          ..orderBy([(t) => OrderingTerm(expression: t.nextExecutionDate)]))
        .watch();
  }

  /// Get mandates due between [start] and [end] dates.
  Future<List<Mandate>> getUpcomingMandates(DateTime start, DateTime end) {
    return (select(mandates)
          ..where(
            (tbl) =>
                tbl.status.equals(MandateStatus.active.name) &
                tbl.nextExecutionDate.isBetweenValues(start, end),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.nextExecutionDate)]))
        .get();
  }

  /// Calculate the sum of upcoming active mandate commitments in minor units
  /// scheduled to execute before [untilDate].
  Future<int> calculateUpcomingCommitmentMinorUnits(DateTime untilDate) async {
    final now = DateTime.now();
    final upcoming =
        await (select(mandates)..where(
              (tbl) =>
                  tbl.status.equals(MandateStatus.active.name) &
                  tbl.nextExecutionDate.isBetweenValues(now, untilDate),
            ))
            .get();

    return upcoming.fold<int>(
      0,
      (sum, m) =>
          sum +
          (m.isVariableAmount
              ? (m.maxCapMinorUnits ?? m.amountMinorUnits)
              : m.amountMinorUnits),
    );
  }

  /// Insert or update a mandate record.
  Future<int> upsertMandate(MandatesCompanion mandate) {
    return into(mandates).insertOnConflictUpdate(mandate);
  }

  /// Update only the given fields of an existing mandate.
  Future<Mandate?> getMandateById(String id) =>
      (select(mandates)..where((m) => m.id.equals(id))).getSingleOrNull();

  Future<int> patchMandate(String id, MandatesCompanion changes) {
    return (update(mandates)..where((t) => t.id.equals(id))).write(changes);
  }

  /// Update mandate status (e.g. pause, revoke, expire).
  Future<bool> updateMandateStatus(
    String mandateId,
    MandateStatus status,
  ) async {
    final updatedRows =
        await (update(
          mandates,
        )..where((tbl) => tbl.id.equals(mandateId))).write(
          MandatesCompanion(
            status: Value(status),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return updatedRows > 0;
  }
}

/// Active mandates that will still debit before the end of [cycleEnd]:
/// from today (the whole of today counts), plus overdue ones whose debit
/// has not been seen yet. Those stay reserved until the debit arrives, the
/// user says what happened, or they are rolled forward (see
/// MandateTracker.rollOverdue, which leaves alone autopays whose account was
/// short, since those most likely failed).
List<Mandate> upcomingMandates(
  Iterable<Mandate> mandates,
  DateTime now,
  DateTime cycleEnd,
) {
  final end = DateTime(cycleEnd.year, cycleEnd.month, cycleEnd.day + 1);
  return mandates.where((m) => m.status == MandateStatus.active).where((m) {
      final d = m.nextExecutionDate;
      return d != null && d.isBefore(end);
    }).toList()
    ..sort((a, b) => a.nextExecutionDate!.compareTo(b.nextExecutionDate!));
}

/// Whether [m]'s date has passed without its debit being seen.
bool isOverdue(Mandate m, DateTime now) {
  final d = m.nextExecutionDate;
  return d != null &&
      d.isBefore(DateTime(now.year, now.month, now.day)) &&
      m.status == MandateStatus.active;
}

/// What one debit of a mandate reserves: its amount, or its cap when the
/// amount varies.
int mandateReserve(Mandate m) => m.isVariableAmount
    ? (m.maxCapMinorUnits ?? m.amountMinorUnits)
    : m.amountMinorUnits;

/// How many times [m] debits from its next date until [cycleEnd] (a weekly
/// autopay can debit four or five times in one pay cycle).
int debitsUntil(Mandate m, DateTime cycleEnd) {
  final d = m.nextExecutionDate;
  if (d == null) return 0;
  if (m.frequency != MandateFrequency.weekly) return 1;
  final end = DateTime(cycleEnd.year, cycleEnd.month, cycleEnd.day + 1);
  var n = 0;
  for (var x = d; x.isBefore(end); x = x.add(const Duration(days: 7))) {
    n++;
  }
  return n < 1 ? 1 : n;
}

/// Everything [m] reserves until [cycleEnd].
int reserveUntil(Mandate m, DateTime cycleEnd) =>
    mandateReserve(m) * debitsUntil(m, cycleEnd);

/// Sum of [upcomingMandates].
int sumUpcomingCommitments(
  Iterable<Mandate> mandates,
  DateTime now,
  DateTime cycleEnd,
) => upcomingMandates(
  mandates,
  now,
  cycleEnd,
).fold(0, (s, m) => s + reserveUntil(m, cycleEnd));
