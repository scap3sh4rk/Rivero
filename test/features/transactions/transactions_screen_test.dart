import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/transactions/screens/transactions_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('Activity lists transactions, searches and filters', (
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
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Zomato'), findsOneWidget);
    expect(find.text('Uber'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zom');
    await tester.pump();
    expect(find.text('Zomato'), findsOneWidget);
    expect(find.text('Uber'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing-matches');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('Filter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Income'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Zomato'), findsNothing); // an expense is filtered out

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
