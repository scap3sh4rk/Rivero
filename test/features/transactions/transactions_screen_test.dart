import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/transactions/screens/transactions_screen.dart';
import 'package:rivero/features/transactions/widgets/create_transaction_sheet.dart';

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
    'TransactionsScreen displays filter chips, activity feed, and opens log sheet',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: TransactionsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Transfers'), findsOneWidget);

      // Verify default seeded transactions
      expect(find.text('Zomato'), findsOneWidget);
      expect(find.text('Uber'), findsOneWidget);
      expect(find.text('Blinkit'), findsOneWidget);

      // Tap Log Expense FAB
      final logFab = find.byType(FloatingActionButton);
      expect(logFab, findsOneWidget);
      await tester.tap(logFab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateTransactionSheet), findsOneWidget);
      expect(find.text('Log Transaction'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
