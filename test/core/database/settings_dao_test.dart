import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  test('settings round-trip and sync into providers', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    expect(await db.settingsDao.get(SettingKeys.salaryDay), isNull);
    await db.settingsDao.set(SettingKeys.salaryDay, '25');
    await db.settingsDao.set(SettingKeys.salaryDay, '26'); // upsert
    await db.settingsDao.set(SettingKeys.reserveCreditCards, '0');
    expect(await db.settingsDao.getInt(SettingKeys.salaryDay), 26);

    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    await c.read(settingsSyncProvider).load();
    expect(c.read(userSalaryDayProvider), 26);
    expect(c.read(reserveCreditCardsProvider), isFalse);
    // No setup wizard: the app is ready, with the tour still to show.
    expect(c.read(onboardedProvider), isTrue);
    expect(c.read(tourPendingProvider), isTrue);
    expect(await db.accountsDao.getAllBuckets(), isNotEmpty);

    c.read(settingsSyncProvider).listen();
    c.read(monthlySalaryProvider.notifier).state = 8000000;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await db.settingsDao.getInt(SettingKeys.monthlySalary), 8000000);
  });

  test('wipeAll erases every table', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    await db.wipeAll();
    expect(await db.accountsDao.getAllActivePhysicalAccounts(), isEmpty);
    expect(await db.select(db.transactions).get(), isEmpty);
    expect(await db.select(db.mandates).get(), isEmpty);
    expect(await db.settingsDao.get(SettingKeys.onboarded), isNull);
  });
}
