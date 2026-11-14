import 'package:drift/drift.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/domain/account_role.dart';
import 'package:rivero/core/domain/custom_account_types.dart';
import 'package:rivero/core/engine/paycycle.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';

/// Everything the first-run flow collects. Amounts are minor units (paise).
class OnboardingData {
  const OnboardingData({
    required this.salaryDay,
    required this.salaryMinor,
    required this.salaryAccountName,
    required this.salaryInstitution,
    this.salaryMask = '',
    this.salaryBalanceMinor = 0,
    this.expenseName,
    this.expenseInstitution,
    this.expenseMask = '',
    this.expenseBalanceMinor = 0,
    this.investMinor = 0,
    this.savingsMinor = 0,
    this.alreadySetAside = false,
  });

  final int salaryDay;
  final int salaryMinor;
  final String salaryAccountName;
  final String salaryInstitution;
  final String salaryMask;
  final int salaryBalanceMinor;

  /// Null when spending happens from the salary account itself.
  final String? expenseName;
  final String? expenseInstitution;
  final String expenseMask;
  final int expenseBalanceMinor;

  final int investMinor;
  final int savingsMinor;

  /// Set up mid-month: this month's investments and savings already went
  /// out (the balances entered show it), so they count as paid.
  final bool alreadySetAside;

  bool get hasSeparateExpenseAccount =>
      expenseName != null && expenseName!.trim().isNotEmpty;
}

/// Creates the user's accounts, buckets and first split, and marks setup done.
Future<void> completeOnboarding(RiveroDatabase db, OnboardingData d) async {
  if (d.investMinor + d.savingsMinor > d.salaryMinor) {
    throw ArgumentError('Investment and savings exceed the salary');
  }
  final now = DateTime.now();

  Future<void> account(
    String id,
    String name,
    String institution,
    String mask,
    int balance,
    String type,
  ) => db.accountsDao.upsertPhysicalAccount(
    PhysicalAccountsCompanion(
      id: Value(id),
      name: Value(name.trim()),
      institution: Value(
        institution.trim().isEmpty ? name.trim() : institution.trim(),
      ),
      accountMask: Value(mask.trim().isEmpty ? '••••' : mask.trim()),
      balanceMinorUnits: Value(balance),
      accountType: Value(type),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  Future<void> bucket(
    String id,
    String name,
    AccountRole role,
    String? accountId,
    int target,
    int order,
  ) => db.accountsDao.upsertBucket(
    AllocationBucketsCompanion(
      id: Value(id),
      name: Value(name),
      role: Value(role),
      targetMinorUnits: Value(target),
      linkedPhysicalAccountId: Value(accountId),
      priorityOrder: Value(order),
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  await account(
    'acc-salary',
    d.salaryAccountName,
    d.salaryInstitution,
    d.salaryMask,
    d.salaryBalanceMinor,
    StandardAccountTypes.salary,
  );
  var expenseAccountId = 'acc-salary';
  if (d.hasSeparateExpenseAccount) {
    expenseAccountId = 'acc-expense';
    await account(
      expenseAccountId,
      d.expenseName!,
      d.expenseInstitution ?? '',
      d.expenseMask,
      d.expenseBalanceMinor,
      StandardAccountTypes.expense,
    );
  }

  await bucket(
    'bucket-expense',
    'Monthly Expenses',
    AccountRole.expense,
    expenseAccountId,
    0,
    1,
  );
  if (d.investMinor > 0) {
    await bucket(
      'bucket-invest',
      'Investments',
      AccountRole.investment,
      null,
      d.investMinor,
      2,
    );
  }
  if (d.savingsMinor > 0) {
    await bucket(
      'bucket-savings',
      'Savings',
      AccountRole.savings,
      null,
      d.savingsMinor,
      3,
    );
  }

  await db.settingsDao.set(SettingKeys.salaryAccount, 'acc-salary');
  final plan = SalaryPlanService(db);
  final buckets = await db.accountsDao.getAllBuckets();
  final cycleStart = Paycycle.fromSalaryDay(salaryCreditDay: d.salaryDay)
      .cycleStartDate;
  await plan.apply(
    salary: d.salaryMinor,
    allocations: plan.preview(d.salaryMinor, buckets),
    // Balances were entered as they are today: setup moves no money.
    moveMoney: false,
    cycleStart: cycleStart,
  );
  if (d.alreadySetAside) {
    for (final id in ['bucket-invest', 'bucket-savings']) {
      await plan.markAlreadyPaid(id);
    }
    await db.settingsDao.set(
      SettingKeys.planMovedOutside,
      SalaryPlanService.cycleKey(cycleStart),
    );
  }

  await db.settingsDao.set(SettingKeys.salaryDay, '${d.salaryDay}');
  await db.settingsDao.set(SettingKeys.monthlySalary, '${d.salaryMinor}');
  await db.settingsDao.set(SettingKeys.onboarded, '1');
}
