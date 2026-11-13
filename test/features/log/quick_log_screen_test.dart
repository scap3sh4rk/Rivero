import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/plan/salary_plan_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/amount_parser.dart';
import 'package:rivero/features/log/quick_log_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  test('parseAmountMinorUnits avoids floating point', () {
    expect(parseAmountMinorUnits('250'), 25000);
    expect(parseAmountMinorUnits('99.5'), 9950);
    expect(parseAmountMinorUnits('0.07'), 7);
    expect(parseAmountMinorUnits('12.'), 1200);
    expect(parseAmountMinorUnits(''), 0);
  });

  testWidgets('typing 45 and saving posts an expense and spends the budget', (
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
        child: const MaterialApp(home: QuickLogScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final before = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!.spentMinorUnits;

    await tester.tap(find.byKey(const ValueKey('key-4')));
    await tester.tap(find.byKey(const ValueKey('key-5')));
    await tester.pump();
    expect(find.text('₹45'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final after = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!.spentMinorUnits;
    expect(after - before, 4500);
    expect(
      find.text('Saved to Food'),
      findsOneWidget,
    ); // inline, not a snackbar
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('₹0'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('recent chip refills; rent can be paid from its own category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    final rentId = (await tester.runAsync(
      () => SalaryPlanService(db).addCustomCategory('Rent', 2500000),
    ))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: QuickLogScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Log ₹45 once; it then shows up as a one-tap recent.
    await tester.tap(find.byKey(const ValueKey('key-4')));
    await tester.tap(find.byKey(const ValueKey('key-5')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('₹0'), findsOneWidget);

    final recent = find.descendant(
      of: find.byKey(const ValueKey('recents')),
      matching: find.byType(ActionChip),
    );
    expect(recent, findsWidgets);
    await tester.tap(recent.first);
    await tester.pump();
    expect(find.text('₹45'), findsOneWidget);

    // Pay rent from the Rent category, not the spending budget.
    await tester.longPress(find.byKey(const ValueKey('key-<'))); // clear
    for (final k in ['2', '5', '0', '0', '0']) {
      await tester.tap(find.byKey(ValueKey('key-$k')));
    }
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pay-from')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Rent').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final spendingBefore = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!.spentMinorUnits;
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final rent = (await tester.runAsync(
      () => db.accountsDao.getBucketById(rentId),
    ))!;
    final spending = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!;
    expect(rent.spentMinorUnits, 2500000);
    expect(spending.spentMinorUnits, spendingBefore);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a note becomes the title and remembers its category', (
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
        child: const MaterialApp(home: QuickLogScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.enterText(
      find.byKey(const ValueKey('log-note')),
      'Metro card',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Transport'));
    await tester.tap(find.byKey(const ValueKey('key-2')));
    await tester.tap(find.byKey(const ValueKey('key-0')));
    await tester.tap(find.byKey(const ValueKey('key-0')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 1600));

    final saved = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!.firstWhere((t) => t.merchant == 'Metro card');
    expect(saved.category, 'Transport');

    // Switch away, then type the same note: Transport comes back by itself.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Food'));
    await tester.enterText(
      find.byKey(const ValueKey('log-note')),
      'metro card',
    );
    await tester.pump();
    final transport = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Transport'),
    );
    expect(transport.selected, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('calculator pane: 120 + 80 × 2 logs ₹280', (tester) async {
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
        child: const MaterialApp(home: QuickLogScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    Future<void> press(String key) async {
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    await press('calc-toggle');
    await tester.pump(const Duration(milliseconds: 400));
    for (final k in [
      'key-1',
      'key-2',
      'key-0',
      'op-+',
      'key-8',
      'key-0',
      'op-×',
      'key-2',
    ]) {
      await press(k);
    }
    expect(find.text('120+80×2'), findsOneWidget);
    expect(find.text('₹280'), findsOneWidget);

    await press('op-=');
    expect(find.text('120+80×2'), findsNothing);
    expect(find.text('₹280'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 1600));
    final txns = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!;
    expect(txns.any((t) => t.amountMinorUnits == -28000), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
