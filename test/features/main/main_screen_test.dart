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

  testWidgets('MainScreen switches between pages and opens settings', (
    tester,
  ) async {
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

    expect(find.text('SAFE TO SPEND'), findsOneWidget);

    Future<void> open(String tab) async {
      await tester.tap(nav(tab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await open('Accounts');
    expect(find.text('CUSTODIAL ACCOUNTS'), findsOneWidget);

    await open('Log');
    expect(find.byKey(const ValueKey('key-5')), findsOneWidget);

    await open('Activity');
    expect(find.text('Encrypted Expense Ledger'), findsOneWidget);

    await open('Plan');
    expect(find.text('MONTHLY SALARY POOL'), findsOneWidget);

    // Settings is reached from the profile button
    await tester.tap(find.byTooltip('Profile & Settings').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('PAYCYCLE CONFIGURATION'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
