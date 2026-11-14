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

  late RiveroDatabase db;

  Future<ProviderContainer> pumpLog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    db = RiveroDatabase.memory();
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
    return ProviderScope.containerOf(
      tester.element(find.byType(QuickLogScreen)),
    );
  }

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  Future<void> saveAndSettle(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    // Saving is one database transaction: give it real time, in steps.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('nothing pre-selected; an unlabelled spend goes to Other', (
    tester,
  ) async {
    await pumpLog(tester);
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
    expect(chips.any((c) => c.selected), isFalse);
    expect(find.byKey(const ValueKey('recents')), findsNothing);

    final before = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!.spentMinorUnits;
    await press(tester, 'key-4');
    await press(tester, 'key-5');
    expect(find.text('₹45'), findsOneWidget);
    await saveAndSettle(tester);

    final after = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!.spentMinorUnits;
    expect(after - before, 4500);
    await tester.pump();
    expect(find.text('Saved to Other'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('₹0'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('long-press 0 types a decimal point', (tester) async {
    await pumpLog(tester);
    await press(tester, 'key-1');
    await tester.longPress(find.byKey(const ValueKey('key-0')));
    await tester.pump();
    await press(tester, 'key-5');
    expect(find.text('₹1.5'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a note becomes the title and remembers its category', (
    tester,
  ) async {
    await pumpLog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('log-note')),
      'Metro card',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Transport'));
    await press(tester, 'key-2');
    await press(tester, 'key-0');
    await press(tester, 'key-0');
    await saveAndSettle(tester);
    await tester.pump(const Duration(milliseconds: 1600));

    final saved = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!.firstWhere((t) => t.merchant == 'Metro card');
    expect(saved.category, 'Transport');

    await tester.enterText(
      find.byKey(const ValueKey('log-note')),
      'metro card',
    );
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Transport'))
          .selected,
      isTrue,
    );
    await finish(tester);
  });

  testWidgets('no "comes out of" picker: Plan is not an action here', (
    tester,
  ) async {
    await pumpLog(tester);
    await tester.runAsync(
      () => SalaryPlanService(db).addCustomCategory('Rent', 2500000),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('pay-from')), findsNothing);
    expect(find.text('Comes out of'), findsNothing);
    await finish(tester);
  });

  testWidgets('a spend bigger than the account or budget asks first', (
    tester,
  ) async {
    await pumpLog(tester);
    // Seeded spending account holds ₹48,250: log ₹99,999.
    for (final k in ['9', '9', '9', '9', '9']) {
      await press(tester, 'key-$k');
    }
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Log this anyway?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final none = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!;
    expect(none.any((t) => t.amountMinorUnits == -9999900), isFalse);

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('log-anyway')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    final saved = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!;
    expect(saved.any((t) => t.amountMinorUnits == -9999900), isTrue);
    await tester.pump(const Duration(milliseconds: 1600));
    await finish(tester);
  });

  testWidgets('a too-large amount is flagged and cannot be saved', (
    tester,
  ) async {
    await pumpLog(tester);
    for (var i = 0; i < 11; i++) {
      await press(tester, 'key-9');
    }
    expect(find.byKey(const ValueKey('too-large')), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
    await finish(tester);
  });

  testWidgets('calculator key on the keypad: 120 + 80 × 2 logs ₹280', (
    tester,
  ) async {
    await pumpLog(tester);
    await press(tester, 'calc-toggle');
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
      await press(tester, k);
    }
    expect(find.text('120+80×2'), findsOneWidget);
    expect(find.text('₹280'), findsOneWidget);
    await press(tester, 'op-=');
    expect(find.text('120+80×2'), findsNothing);
    await saveAndSettle(tester);
    final txns = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!;
    expect(txns.any((t) => t.amountMinorUnits == -28000), isTrue);
    await finish(tester);
  });

  testWidgets('New creates a category and selects it', (tester) async {
    final container = await pumpLog(tester);
    await tester.tap(find.byKey(const ValueKey('new-category')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'Pets');
    await tester.tap(find.text('Save').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      container.read(logCategoriesProvider).map((c) => c.name),
      contains('Pets'),
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pets'))
          .selected,
      isTrue,
    );
    await finish(tester);
  });
}
