import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/budgets/screens/budgets_screen.dart';
import 'package:rivero/features/plan/salary_plan_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;

  setUp(() async {
    db = RiveroDatabase.memory();
    await DatabaseSeeder(db).seedIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'BudgetsScreen displays salary pool, autopay and pay-cycle tiles, and buckets',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: BudgetsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('MONTHLY SALARY'), findsOneWidget);
      // Autopay and owed money live on Home, not here.
      expect(find.text('AUTOPAY'), findsNothing);
      expect(find.text('OWED TO YOU'), findsNothing);

      // Full category names, no truncation, no account plumbing text
      expect(find.text('Monthly Expenses'), findsOneWidget);
      expect(find.text('Mutual Funds & Equity SIP'), findsOneWidget);
      expect(find.text('Emergency Fund'), findsOneWidget);
      expect(find.textContaining('Deducts'), findsNothing);

      await tester.tap(find.text('MONTHLY SALARY'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SalaryPlanScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  test('already paid (mid-month start) never touches the balance', () async {
    final before = (await db.accountsDao.getPhysicalAccountById('acc-salary'))!
        .balanceMinorUnits;
    await SalaryPlanService(db).markAlreadyPaid('bucket-savings');
    final after = (await db.accountsDao.getPhysicalAccountById('acc-salary'))!
        .balanceMinorUnits;
    expect(after, before);
    final bucket = (await db.accountsDao.getBucketById('bucket-savings'))!;
    expect(bucket.spentMinorUnits, bucket.allocatedMinorUnits);
  });

  testWidgets(
    'a plan-only category can be marked paid out of the salary account',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = RiveroDatabase.memory();
      addTearDown(db.close);
      await DatabaseSeeder(db).seedIfEmpty();
      final before = (await db.accountsDao.getPhysicalAccountById(
        'acc-salary',
      ))!.balanceMinorUnits;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: BudgetsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Emergency Fund'));
      // The handler reads the database first (real async), then opens a dialog.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Mark Emergency Fund as paid'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pay-now')));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final after = (await tester.runAsync(
        () => db.accountsDao.getPhysicalAccountById('acc-salary'),
      ))!.balanceMinorUnits;
      expect(before - after, 3000000); // the category's ₹30,000 left salary
      final bucket = (await tester.runAsync(
        () => db.accountsDao.getBucketById('bucket-savings'),
      ))!;
      expect(bucket.spentMinorUnits, 3000000);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}
