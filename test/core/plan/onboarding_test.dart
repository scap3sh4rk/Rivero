import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/plan/onboarding.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  test(
    'onboarding creates accounts, buckets and an exact first split',
    () async {
      final db = RiveroDatabase.memory();
      addTearDown(db.close);
      await completeOnboarding(
        db,
        const OnboardingData(
          salaryDay: 28,
          salaryMinor: 10000000,
          salaryAccountName: 'HDFC Salary',
          salaryInstitution: 'HDFC',
          salaryBalanceMinor: 500000,
          expenseName: 'ICICI Spends',
          expenseInstitution: 'ICICI',
          investMinor: 3000000,
        ),
      );
      final accounts = await db.accountsDao.getAllActivePhysicalAccounts();
      expect(
        accounts.map((a) => a.id),
        containsAll(['acc-salary', 'acc-expense']),
      );
      final b = {for (final x in await db.accountsDao.getAllBuckets()) x.id: x};
      expect(b.keys, unorderedEquals(['bucket-expense', 'bucket-invest']));
      expect(b['bucket-invest']!.allocatedMinorUnits, 3000000);
      expect(b['bucket-expense']!.allocatedMinorUnits, 7000000);
      expect(b['bucket-expense']!.linkedPhysicalAccountId, 'acc-expense');
      expect(await db.settingsDao.get(SettingKeys.onboarded), '1');
      expect(await db.settingsDao.getInt(SettingKeys.salaryDay), 28);
    },
  );

  test('rejects a split larger than the salary', () async {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    expect(
      () => completeOnboarding(
        db,
        const OnboardingData(
          salaryDay: 1,
          salaryMinor: 100,
          salaryAccountName: 'A',
          salaryInstitution: 'B',
          investMinor: 200,
        ),
      ),
      throwsArgumentError,
    );
  });
}
