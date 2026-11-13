import 'package:drift/drift.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/tables/app_settings_table.dart';

part 'settings_dao.g.dart';

/// Well-known setting keys.
abstract final class SettingKeys {
  static const salaryDay = 'salary_day';
  static const monthlySalary = 'monthly_salary_minor';
  static const reserveCreditCards = 'reserve_credit_cards';
  static const onboarded = 'onboarded';
  static const lastPlannedSalaryTxn = 'last_planned_salary_txn';
  static const lastPlannedCycleStart = 'last_planned_cycle_start';
  static const openOnLog = 'open_on_log';
  static const accountTypes = 'account_types_json';
  static const countOwed = 'count_owed_in_sts';
}

@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<RiveroDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Future<String?> get(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  Future<void> set(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}
