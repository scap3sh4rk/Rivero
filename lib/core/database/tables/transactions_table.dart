import 'package:drift/drift.dart';
import 'package:rivero/core/database/tables/allocation_buckets_table.dart';
import 'package:rivero/core/database/tables/physical_accounts_table.dart';
import 'package:rivero/core/database/tables/raw_ingestion_logs_table.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Core ledger entries recording all confirmed and provisional transactions.
@DataClassName('LedgerTransaction')
class Transactions extends Table {
  /// Unique UUID for the ledger entry.
  TextColumn get id => text()();

  /// Reference to originating raw ingestion log (if captured automatically).
  TextColumn get ingestionLogId => text().nullable().references(
    RawIngestionLogs,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Physical bank or card account impacted by this transaction.
  TextColumn get physicalAccountId =>
      text().references(PhysicalAccounts, #id, onDelete: KeyAction.cascade)();

  /// Virtual allocation bucket debited or credited (if classified).
  TextColumn get allocationBucketId => text().nullable().references(
    AllocationBuckets,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Amount strictly in integer minor units (paise in INR).
  /// Positive (+) indicates inflow / credit; negative (-) indicates outflow / debit.
  IntColumn get amountMinorUnits => integer()();

  /// Financial classification of the movement.
  TextColumn get transactionType => textEnum<TransactionType>()();

  /// Lifecycle state within the ledger.
  TextColumn get transactionState => textEnum<TransactionState>()();

  /// Clean merchant or counterparty name (e.g. "Swiggy", "Amazon", "Zerodha").
  TextColumn get merchant => text().withLength(min: 1, max: 120)();

  /// High-level spending category (e.g. "Food & Dining", "Investment", "Fuel").
  TextColumn get category => text().withLength(min: 1, max: 60)();

  /// Transaction reference identifier (UTR, UPI RRN, Bank Ref).
  TextColumn get referenceNumber =>
      text().nullable().withLength(min: 1, max: 80)();

  /// Exact timestamp of the financial event.
  DateTimeColumn get transactionTimestamp => dateTime()();

  /// Flag indicating this transaction is one leg of a self-transfer.
  BoolColumn get isInternalTransfer =>
      boolean().withDefault(const Constant(false))();

  /// Linked partner transaction leg (for transfers, refunds, or reimbursements).
  TextColumn get linkedTransactionId => text().nullable()();

  /// What this entry really changed its account's balance by when it was
  /// applied: less than the amount when the balance stopped at zero, 0 when
  /// the balance already included it. Null = the full amount (older rows).
  IntColumn get appliedMinorUnits => integer().nullable()();

  /// Optional user annotations.
  TextColumn get userNotes => text().nullable()();

  /// Path to an attached bill/receipt photo.
  TextColumn get attachmentPath => text().nullable()();

  /// Audit timestamp when the record was persisted.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
