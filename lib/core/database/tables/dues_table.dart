import 'package:drift/drift.dart';
import 'package:rivero/core/database/tables/transactions_table.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Money owed to the user (split bills, money lent).
@DataClassName('Due')
class Dues extends Table {
  TextColumn get id => text()();

  /// Who owes it.
  TextColumn get person => text().withLength(min: 1, max: 60)();

  /// Total owed (minor units, > 0).
  IntColumn get amountMinorUnits => integer()();

  /// Paid back so far (minor units).
  IntColumn get receivedMinorUnits =>
      integer().withDefault(const Constant(0))();

  TextColumn get kind => textEnum<DueKind>()();
  TextColumn get status => textEnum<DueStatus>()();
  TextColumn get note => text().nullable()();

  /// A photo of the bill or proof of the loan (path in app storage).
  TextColumn get attachmentPath => text().nullable()();

  /// When money you owe is to be paid back (null = no date).
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// The bill that was split, or the lending outflow.
  TextColumn get sourceTransactionId => text().nullable().references(
    Transactions,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// The account their payment is expected to land in (null = not chosen).
  TextColumn get creditAccountId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
