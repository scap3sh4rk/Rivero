import 'package:drift/drift.dart';

/// Physical bank, card, or cash accounts holding actual custodial balances.
@DataClassName('PhysicalAccount')
class PhysicalAccounts extends Table {
  /// Unique UUID identifying the physical account.
  TextColumn get id => text()();

  /// User-defined friendly name (e.g. "Primary HDFC Savings").
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// Banking or financial institution (e.g. "HDFC", "ICICI", "SBI", "CASH").
  TextColumn get institution => text().withLength(min: 1, max: 50)();

  /// Masked identifier for notification correlation (e.g. "••4012").
  TextColumn get accountMask => text().withLength(min: 1, max: 20)();

  /// Current balance strictly stored as integer minor units (paise in INR).
  IntColumn get balanceMinorUnits => integer().withDefault(const Constant(0))();

  /// Credit limit in minor units (for credit cards / credit lines, e.g. 15000000 for ₹1,50,000).
  IntColumn get creditLimitMinorUnits =>
      integer().withDefault(const Constant(0))();

  /// Custom account type / category (e.g. "Salary", "Savings", "Credit Card", "Cash", or custom).
  TextColumn get accountType =>
      text().withLength(min: 1, max: 50).withDefault(const Constant('Bank'))();

  /// ISO-4217 three-letter currency code.
  TextColumn get currencyCode =>
      text().withLength(min: 3, max: 3).withDefault(const Constant('INR'))();

  /// Flag indicating revolving debt liability (Credit Card, Overdraft, Loan).
  BoolColumn get isLiability => boolean().withDefault(const Constant(false))();

  /// Soft deletion / archival flag.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Colour the user picked for this account (ARGB), if any.
  IntColumn get colorValue => integer().nullable()();

  /// User-chosen position in lists (long-press to reorder).
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Path to a picture/thumbnail the user chose for this account.
  TextColumn get imagePath => text().nullable()();

  /// Audit timestamp when the account record was created.
  DateTimeColumn get createdAt => dateTime()();

  /// Audit timestamp when the account balance or properties were last updated.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
