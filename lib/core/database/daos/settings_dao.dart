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
  static const logCategories = 'log_categories_json';
  static const appLock = 'app_lock';
  static const lastLogAccount = 'last_log_account';
  static const font = 'font_family';
  static const salaryAccount = 'salary_account_id';
  static const tourDone = 'tour_done';

  /// Automatic backup frequency (off, daily, weekly) and the last backup.
  static const autoBackup = 'auto_backup';
  static const lastBackupAt = 'last_backup_at';

  /// '1' = confident captures count straight away; '0' (the app default) =
  /// every capture waits on Home for Accept or Ignore.
  static const captureAutoAccept = 'capture_auto_accept';
  static const primaryUpi = 'primary_upi_package';
  static const primaryUpiName = 'primary_upi_name';

  /// Cycle (yyyy-mm-dd of its start) whose plan money already moved before
  /// Rivero was set up: Apply never moves it again.
  static const planMovedOutside = 'plan_moved_outside_cycle';
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

  /// The value of [key], updated whenever it changes.
  Stream<String?> watch(String key) => (select(
    appSettings,
  )..where((t) => t.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  Future<void> set(String key, String value) => into(
    appSettings,
  ).insertOnConflictUpdate(AppSettingsCompanion.insert(key: key, value: value));
}
