import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/plan/salary_plan_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('split fits the salary, skip works, over-allocation is blocked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SalaryPlanScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    FilledButton apply() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));

    await tester.enterText(
      find.byKey(const ValueKey('salary-field')),
      '100000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-bucket-invest')),
      '30000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('plan-bucket-savings')),
      '0',
    );
    await tester.pump();
    expect(apply().onPressed, isNotNull);

    // Over-allocation disables Apply
    await tester.enterText(
      find.byKey(const ValueKey('plan-bucket-invest')),
      '200000',
    );
    await tester.pump();
    expect(apply().onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('plan-bucket-invest')),
      '30000',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final b = (await tester.runAsync(() => db.accountsDao.getAllBuckets()))!;
    int alloc(String id) => b.firstWhere((x) => x.id == id).allocatedMinorUnits;
    expect(alloc('bucket-invest'), 3000000);
    expect(alloc('bucket-savings'), 0);
    expect(alloc('bucket-expense'), 7000000);

    // The expected salary (the Plan page "pool") follows what was applied.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.read(monthlySalaryProvider), 10000000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the plan shows where money goes and what stays plan-only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SalaryPlanScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('salary-field')),
      '100000',
    );
    await tester.pump();

    // Salary and spending accounts are chosen here...
    expect(find.text('Salary arrives in'), findsOneWidget);
    expect(find.text('Spending money goes to'), findsOneWidget);
    // ...and Apply moves money between them straight away.
    expect(find.textContaining('Moves out of'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('moves-card')),
        matching: find.textContaining('→'),
      ),
      findsOneWidget, // only salary -> spending is a self-transfer
    );
    expect(find.byKey(const ValueKey('dest-bucket-invest')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
