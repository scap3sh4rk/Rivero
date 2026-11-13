import 'package:drift/drift.dart';
import 'package:rivero/core/domain/account_role.dart';

/// Merchant categorization memory mapping raw SMS/notification strings
/// to clean counterparty titles, default categories, and bucket roles.
@DataClassName('AssociatedTitle')
class AssociatedTitles extends Table {
  /// Unique UUID for the memory mapping.
  TextColumn get id => text()();

  /// Normalized lowercase pattern to match (e.g. "swiggy", "amzn", "zerodha").
  TextColumn get rawPattern => text().withLength(min: 1, max: 100)();

  /// Polished human-readable display title (e.g. "Swiggy", "Amazon").
  TextColumn get cleanTitle => text().withLength(min: 1, max: 100)();

  /// Default financial category (e.g. "Food & Dining", "Shopping").
  TextColumn get defaultCategory => text().withLength(min: 1, max: 60)();

  /// Target bucket role associated with this merchant.
  TextColumn get suggestedRole => textEnum<AccountRole>()();

  /// Confidence score of this mapping rule (0.0 to 1.0).
  RealColumn get confidence => real().withDefault(const Constant(1))();

  /// Number of times this categorization rule has been matched.
  IntColumn get matchCount => integer().withDefault(const Constant(1))();

  /// Audit creation timestamp.
  DateTimeColumn get createdAt => dateTime()();

  /// Audit update timestamp.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
