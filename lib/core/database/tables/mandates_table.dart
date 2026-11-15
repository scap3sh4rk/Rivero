import 'package:drift/drift.dart';
import 'package:rivero/core/database/tables/allocation_buckets_table.dart';
import 'package:rivero/core/database/tables/physical_accounts_table.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Recurring commitments, UPI Autopay mandates, and e-NACH standing instructions.
@DataClassName('Mandate')
class Mandates extends Table {
  /// Unique UUID for the mandate record.
  TextColumn get id => text()();

  /// Payee or service name (e.g. "Netflix", "HDFC Life Insurance", "SIP").
  TextColumn get payee => text().withLength(min: 1, max: 120)();

  /// Expected debit amount in integer minor units (paise in INR).
  IntColumn get amountMinorUnits => integer()();

  /// Flag indicating whether the execution amount varies up to a maximum cap.
  BoolColumn get isVariableAmount =>
      boolean().withDefault(const Constant(false))();

  /// Upper limit cap for variable mandates (e.g. electricity, credit card autopay).
  IntColumn get maxCapMinorUnits => integer().nullable()();

  /// Execution schedule recurrence.
  TextColumn get frequency => textEnum<MandateFrequency>()();

  /// Source bank account debited by this mandate.
  TextColumn get physicalAccountId =>
      text().references(PhysicalAccounts, #id, onDelete: KeyAction.cascade)();

  /// Optional virtual bucket budget linked to this recurring commitment.
  TextColumn get allocationBucketId => text().nullable().references(
    AllocationBuckets,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Commencement date of the recurring mandate.
  DateTimeColumn get startDate => dateTime()();

  /// Expiry or end date of the mandate (if finite).
  DateTimeColumn get endDate => dateTime().nullable()();

  /// Next scheduled auto-debit execution date.
  DateTimeColumn get nextExecutionDate => dateTime().nullable()();

  /// What it is for (SIP, subscription, EMI...). "other" = not chosen yet;
  /// screens then show a guess from the payee.
  TextColumn get kind =>
      textEnum<MandateKind>().withDefault(const Constant('other'))();

  /// Lifecycle state of the commitment.
  TextColumn get status => textEnum<MandateStatus>()();

  /// Unique Mandate Number (UMN) registered with NPCI / bank.
  TextColumn get mandateUmn => text().nullable().withLength(min: 1, max: 100)();

  /// Audit creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// Audit update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
