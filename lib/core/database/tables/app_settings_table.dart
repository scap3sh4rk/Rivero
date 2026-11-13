import 'package:drift/drift.dart';

/// Small key/value store for user configuration (salary day, plan, toggles).
@DataClassName('AppSetting')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
