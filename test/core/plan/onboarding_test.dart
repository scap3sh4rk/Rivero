import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/plan/onboarding.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';

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

  test(
    'setup with ₹52,000 / ₹5,000, then revising the plan, stays ₹47,000',
    () async {
      final db = RiveroDatabase.memory();
      addTearDown(db.close);
      await completeOnboarding(
        db,
        const OnboardingData(
          salaryDay: 1,
          salaryMinor: 5200000,
          salaryAccountName: 'Salary',
          salaryInstitution: 'HDFC',
          investMinor: 500000,
        ),
      );
      Future<int> left() async {
        final b = (await db.accountsDao.getBucketById('bucket-expense'))!;
        return b.allocatedMinorUnits +
            b.carryOverMinorUnits -
            b.spentMinorUnits;
      }

      expect(await left(), 4700000);

      // The plan screen applies with the same cycle start the setup used.
      final cycle = Paycycle.fromSalaryDay(salaryCreditDay: 1).cycleStartDate;
      final plan = SalaryPlanService(db);
      for (var i = 0; i < 3; i++) {
        final buckets = await db.accountsDao.getAllBuckets();
        await plan.apply(
          salary: 5200000,
          allocations: plan.preview(5200000, buckets),
          cycleStart: cycle,
        );
        expect(await left(), 4700000, reason: 'revision #${i + 1}');
      }
    },
  );
}
