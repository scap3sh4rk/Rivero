import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/engine/safe_to_spend_calculator.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/security/app_lock.dart';

import '../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  SafeToSpendResult sts({int perDay = 120000, bool deficit = false}) =>
      SafeToSpendResult(
        expenseBalance: 0,
        upcomingMandates: 0,
        unsettledCreditCardLiability: 0,
        pendingReimbursements: 0,
        effectiveSafeToSpend: deficit ? -200000 : 0,
        nominalSafeToSpend: 0,
        conservativeSafeToSpend: 0,
        dailySpendingPace: perDay,
        isDeficit: deficit,
        deficitAmount: deficit ? 200000 : 0,
        reliability: BalanceReliability.verified,
        daysRemainingInCycle: 5,
      );

  ({String amount, String caption})? text({
    SafeToSpendResult? result,
    bool privacy = false,
    bool lock = false,
    bool negative = false,
  }) {
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveSafeToSpendResultProvider.overrideWithValue(
          AsyncData(result ?? sts()),
        ),
        stsBreakdownProvider.overrideWithValue(const AsyncLoading()),
        awaitingSalaryProvider.overrideWith((ref) async => false),
      ],
    );
    addTearDown(c.dispose);
    c.read(privacyModeProvider.notifier).state = privacy;
    c.read(appLockEnabledProvider.notifier).state = lock;
    c.read(showNegativeStsProvider.notifier).state = negative;
    return c.read(homeWidgetTextProvider);
  }

  test('the widget shows the per-day number and days to payday', () {
    final t = text()!;
    expect(t.amount, '₹1,200');
    expect(t.caption, endsWith('to payday'));
  });

  test('amounts are hidden when Rivero hides them or App lock is on', () {
    expect(text(privacy: true)!.amount, '₹••••');
    expect(text(lock: true)!.amount, '₹••••');
  });

  test('a shortfall shows 0, or the negative amount when asked to', () {
    expect(text(result: sts(deficit: true))!.amount, '₹0');
    expect(
      text(result: sts(deficit: true), negative: true)!.amount,
      contains('2,000'),
    );
  });
}
