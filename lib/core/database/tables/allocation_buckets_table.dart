import 'package:drift/drift.dart';
import 'package:rivero/core/database/tables/physical_accounts_table.dart';
import 'package:rivero/core/domain/account_role.dart';

/// Virtual allocation buckets distributing the salary waterfall.
@DataClassName('AllocationBucket')
class AllocationBuckets extends Table {
  /// Unique UUID identifying the allocation bucket.
  TextColumn get id => text()();

  /// User-defined bucket title (e.g. "Monthly Living Expenses", "SIP Investments").
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// Functional role in the salary waterfall hierarchy.
  TextColumn get role => textEnum<AccountRole>()();

  /// Allocated money in the current paycycle (integer minor units / paise).
  IntColumn get allocatedMinorUnits =>
      integer().withDefault(const Constant(0))();

  /// Unspent money carried in from the previous cycle (expense buckets).
  /// Kept apart from [allocatedMinorUnits] so allocations never exceed salary.
  IntColumn get carryOverMinorUnits =>
      integer().withDefault(const Constant(0))();

  /// Total spent from this bucket in the current cycle (integer minor units).
  IntColumn get spentMinorUnits => integer().withDefault(const Constant(0))();

  /// Monthly target or cap in minor units (optional).
  IntColumn get targetMinorUnits => integer().nullable()();

  /// Optional physical account backing this bucket.
  TextColumn get linkedPhysicalAccountId => text().nullable().references(
    PhysicalAccounts,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Priority sequence in the waterfall cascade (0 = highest priority).
  IntColumn get priorityOrder => integer().withDefault(const Constant(0))();

  /// Audit creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// Audit update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
