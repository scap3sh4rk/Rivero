import 'package:drift/drift.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Immutable audit log of all ingested raw messages and notifications.
@DataClassName('RawIngestionLog')
class RawIngestionLogs extends Table {
  /// Unique UUID for the raw ingestion event.
  TextColumn get id => text()();

  /// Channel from which the event was received.
  TextColumn get sourceChannel => textEnum<IngestionChannel>()();

  /// Sender identifier or TRAI DLT header (e.g. "AD-HDFCBK", "VK-ICICIB").
  TextColumn get senderHeader =>
      text().nullable().withLength(min: 1, max: 50)();

  /// Complete raw message or notification body captured locally.
  TextColumn get rawPayload => text()();

  /// Timestamp when the message or notification was received by the OS.
  DateTimeColumn get receivedAt => dateTime()();

  /// Current parse and triage status.
  TextColumn get parseStatus => textEnum<ParseStatus>()();

  /// Confidence score computed by the regex/classifier engine (0.0 to 1.0).
  RealColumn get confidenceScore => real().withDefault(const Constant(0))();

  /// Error or reason if parsing failed or was quarantined.
  TextColumn get failureReason => text().nullable()();

  /// Audit timestamp when the record was persisted.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
