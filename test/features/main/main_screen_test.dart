import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/main/main_screen.dart';

import '../../test_helper.dart';

Finder nav(String label) => find.byKey(ValueKey('nav-$label'));

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
    'MainScreen renders bottom navigation bar and switches tabs smoothly',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: MainScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // 1. Initial Overview Tab
      for (final label in [
        'Overview',
        'Accounts',
        'Budgets',
        'Transactions',
        'Settings',
      ]) {
        expect(nav(label), findsOneWidget);
      }

      expect(find.text('SAFE TO SPEND'), findsOneWidget);

      // 2. Switch to Accounts Tab
      await tester.tap(nav('Accounts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('CUSTODIAL ACCOUNTS'), findsOneWidget);
      expect(find.text('CREDIT LINE USAGE'), findsOneWidget);

      // 3. Switch to Budgets Tab
      await tester.tap(nav('Budgets'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('MONTHLY SALARY POOL'), findsOneWidget);
      expect(find.text('MONTHLY ALLOCATION PURPOSES'), findsOneWidget);

      // 4. Switch to Transactions Tab
      await tester.tap(nav('Transactions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Encrypted Expense Ledger'), findsOneWidget);

      // 5. Switch to Settings Tab
      await tester.tap(nav('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('PAYCYCLE CONFIGURATION'), findsOneWidget);

      // 6. Test Quick Action FAB
      final quickFab = find.byTooltip('Quick Actions');
      expect(quickFab, findsOneWidget);
      await tester.tap(quickFab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Log Expense / Income'), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);
      expect(find.text('New Monthly Purpose Bucket'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
