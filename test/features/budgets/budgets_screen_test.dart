import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
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
      expect(find.text('AUTOPAY'), findsOneWidget);
      expect(find.text('OWED TO YOU'), findsOneWidget);

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
}
