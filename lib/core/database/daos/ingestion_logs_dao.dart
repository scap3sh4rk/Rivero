import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/tables/raw_ingestion_logs_table.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

part 'ingestion_logs_dao.g.dart';

/// Data Access Object for raw notification and SMS ingestion logs.
@DriftAccessor(tables: [RawIngestionLogs])
class IngestionLogsDao extends DatabaseAccessor<RiveroDatabase>
    with _$IngestionLogsDaoMixin {
  IngestionLogsDao(super.attachedDatabase);

  /// Watch logs placed in quarantine for manual review (EC-10).
  Stream<List<RawIngestionLog>> watchQuarantinedLogs() {
    return (select(rawIngestionLogs)
          ..where((tbl) => tbl.parseStatus.equals(ParseStatus.quarantined.name))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.receivedAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  /// Watch recent ingestion logs.
  Stream<List<RawIngestionLog>> watchRecentLogs({int limit = 50}) {
    return (select(rawIngestionLogs)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.receivedAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  /// Insert a raw ingestion log event.
  Future<int> insertLog(RawIngestionLogsCompanion log) {
    return into(rawIngestionLogs).insert(log);
  }

  /// Update the parse status and confidence score of an ingestion log.
  Future<bool> updateParseStatus(
    String logId,
    ParseStatus status, {
    String? failureReason,
  }) async {
    final updatedRows =
        await (update(
          rawIngestionLogs,
        )..where((tbl) => tbl.id.equals(logId))).write(
          RawIngestionLogsCompanion(
            parseStatus: Value(status),
            failureReason: Value(failureReason),
          ),
        );
    return updatedRows > 0;
  }

  /// Purge old raw message logs older than [cutoff] for user privacy.
  Future<int> purgeLogsOlderThan(DateTime cutoff) {
    return (delete(
      rawIngestionLogs,
    )..where((tbl) => tbl.receivedAt.isSmallerThanValue(cutoff))).go();
  }
}
