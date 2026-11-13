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
