import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
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

  testWidgets('tap a transaction to add a note, then delete it', (
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

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.tap(find.text('Zomato'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byKey(const ValueKey('detail-note')),
      'Team lunch, Ravi owes half',
    );
    await tester.tap(find.text('Food'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Ignore'));
    await settle();

    final row = (await tester.runAsync(
      () => db.transactionsDao.getTransactionById('txn-review-1'),
    ))!;
    expect(row.userNotes, 'Team lunch, Ravi owes half');
    expect(find.text('Team lunch, Ravi owes half'), findsOneWidget);

    await tester.tap(find.text('Zomato'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Delete entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle();
    expect(
      await tester.runAsync(
        () => db.transactionsDao.getTransactionById('txn-review-1'),
      ),
      isNull,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('month overview totals real spends; tapping a category filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    await tester.runAsync(
      () => LedgerService(db).recordManual(
        accountId: 'acc-expense',
        amountMinorUnits: -24000,
        type: TransactionType.expense,
        merchant: 'Groceries run',
        category: 'Shopping',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Spent since'), findsOneWidget);
    final total = tester.widget<Text>(
      find.byKey(const ValueKey('spent-total')),
    );
    expect(total.data, contains('240'));

    // Collapsed until asked; expanding shows categories.
    expect(find.text('Shopping'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('overview-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Shopping').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Groceries run'), findsOneWidget);
    expect(find.text('Zomato'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('day headings, and filtering by a date or a range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(() => DatabaseSeeder(db).seedIfEmpty());
    final ledger = LedgerService(db);
    final now = DateTime.now();
    final old = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 40));
    await tester.runAsync(
      () => ledger.recordManual(
        accountId: 'acc-expense',
        amountMinorUnits: -12300,
        type: TransactionType.expense,
        merchant: 'Old bookshop',
        category: 'Shopping',
        at: old.add(const Duration(hours: 12)),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // A heading starts each day.
    expect(find.byKey(ValueKey('day-$old')), findsOneWidget);
    expect(find.text('Old bookshop'), findsOneWidget);

    // Filter to that one day: only its entry is left, and the overview
    // shows what was spent then.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionsScreen)),
    );
    container.read(activityRangeProvider.notifier).state = DateTimeRange(
      start: old,
      end: old,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('range-chip')), findsOneWidget);
    expect(find.text('Old bookshop'), findsOneWidget);
    expect(find.text('Zomato'), findsNothing);
    expect(find.textContaining('Spent on'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('spent-total'))).data,
      '₹123.00',
    );

    // Clearing the chip shows everything again.
    await tester.tap(find.byKey(const ValueKey('range-clear')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(activityRangeProvider), isNull);
    expect(find.text('Zomato'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('quick date ranges', () {
    final now = DateTime(2026, 11, 14, 15);
    expect(ActivityRanges.month(now).start, DateTime(2026, 11));
    expect(ActivityRanges.month(now).end, DateTime(2026, 11, 30));
    expect(
      ActivityRanges.label(ActivityRanges.month(now), now),
      'November 2026',
    );
    expect(ActivityRanges.label(ActivityRanges.today(now), now), 'Today');
    expect(ActivityRanges.heading(DateTime(2026, 11, 13), now), 'Yesterday');
    expect(ActivityRanges.heading(DateTime(2026, 11, 10), now), 'Tue, 10 Nov');
    expect(
      ActivityRanges.contains(
        ActivityRanges.today(now),
        DateTime(2026, 11, 14, 23, 59),
      ),
      isTrue,
    );
    expect(
      ActivityRanges.contains(
        ActivityRanges.today(now),
        DateTime(2026, 11, 15),
      ),
      isFalse,
    );
  });
}
