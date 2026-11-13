import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/budgets/screens/budgets_screen.dart';
import 'package:rivero/features/budgets/widgets/create_budget_sheet.dart';

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
    'BudgetsScreen displays salary pool, waterfall conservation, and purpose buckets',
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

      expect(find.text('Budgets & Allocations'), findsOneWidget);
      expect(find.text('MONTHLY SALARY POOL'), findsOneWidget);
      expect(find.text('Waterfall Invariant'), findsOneWidget);
      expect(find.text('Allocated to Purposes'), findsOneWidget);
      expect(find.text('Unallocated Remaining'), findsOneWidget);

      // Verify default purpose buckets
      expect(find.text('Monthly Expenses'), findsOneWidget);
      expect(find.text('Mutual Funds & Equity SIP'), findsOneWidget);
      expect(find.text('Emergency Fund'), findsOneWidget);

      // Tap New Purpose FAB
      final newPurposeFab = find.byTooltip('Add Purpose Bucket');
      expect(newPurposeFab, findsOneWidget);
      await tester.tap(newPurposeFab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateBudgetSheet), findsOneWidget);
      expect(find.text('New Budget Purpose'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
