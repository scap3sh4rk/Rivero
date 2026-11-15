import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/owed/owed_screen.dart';
import 'package:rivero/features/transactions/screens/transactions_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('split a bill from Activity, then settle it on Owed to you', (
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
        amountMinorUnits: -300000,
        type: TransactionType.expense,
        merchant: 'Team dinner',
        category: 'Food',
      ),
    );

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Team dinner'));
    await settle();
    await tester.tap(find.byKey(const ValueKey('split-bill')));
    await settle();

    await tester.enterText(find.byKey(const ValueKey('split-name-0')), 'Ravi');
    await tester.tap(find.text('Add person'));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('split-name-1')), 'Asha');
    await tester.tap(find.text('Split equally'));
    await tester.pump();
    expect(find.textContaining('Your share: ₹1,000'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('split-save')));
    await settle();

    final dues = (await tester.runAsync(() => db.select(db.dues).get()))!;
    expect(dues.map((d) => d.person), unorderedEquals(['Ravi', 'Asha']));
    expect(dues.every((d) => d.amountMinorUnits == 100000), isTrue);

    // Owed to you: settle Ravi in cash
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: OwedScreen()),
      ),
    );
    await settle();
    // Two frames; the first opens everyone who owes you.
    await tester.tap(find.byKey(const ValueKey('owed-card-to-you')));
    await settle();
    expect(find.text('Ravi'), findsOneWidget);
    await tester.tap(find.text('Ravi'));
    await settle();
    await tester.tap(find.text('Received in cash'));
    await settle();

    final ravi = (await tester.runAsync(() => db.select(db.dues).get()))!
        .firstWhere((d) => d.person == 'Ravi');
    expect(ravi.status, DueStatus.settled);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('track money you owe, and see every bill in one place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();

    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: OwedScreen()),
      ),
    );
    await settle();

    // The page is just two frames, nothing else.
    expect(find.byKey(const ValueKey('owed-card-to-you')), findsOneWidget);
    expect(find.byKey(const ValueKey('owed-card-you-owe')), findsOneWidget);
    expect(find.text('Bills & commitments'), findsNothing);
    // The frames share the screen height (no scrolling).
    final h = tester
        .getSize(find.byKey(const ValueKey('owed-card-to-you')))
        .height;
    expect(h, greaterThanOrEqualTo(3000 * 0.28));
    // A small net line sits below them.
    expect(find.byKey(const ValueKey('owed-net')), findsOneWidget);
    // Autopay lives on the Owed tab.
    expect(find.byKey(const ValueKey('owed-autopay')), findsOneWidget);
    expect(find.text('All square'), findsOneWidget);
    expect(find.byType(Scrollable), findsNothing);

    // Borrow ₹5,000 from Meera into the salary account (the plus, bottom right).
    await tester.tap(find.byTooltip('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('add-borrowed')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Borrowed money'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('lend-person')), 'Meera');
    await tester.enterText(find.byKey(const ValueKey('lend-amount')), '5000');
    await tester.tap(find.byKey(const ValueKey('money-save')));
    await settle();

    final dues = (await tester.runAsync(() => db.select(db.dues).get()))!;
    expect(dues.single.kind, DueKind.borrowed);
    expect(find.byKey(const ValueKey('owe-total')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('owe-total'))).data,
      '₹5,000.00',
    );
    // Owed nothing, owe ₹5,000: the net line says so.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('owed-net-text'))).data,
      'Net: you owe ₹5,000.00',
    );

    // "You owe people": the debt, and Bills & commitments (the demo card
    // with its due date, autopays due before payday).
    await tester.tap(find.byKey(const ValueKey('owed-card-you-owe')));
    await settle();
    expect(find.text('Meera'), findsOneWidget);
    expect(find.text('Bills & commitments'), findsOneWidget);
    // Each card: what to settle, by when, from which account. No "before
    // payday" total, no "you hold", no limit or available credit.
    expect(find.byKey(const ValueKey('commitments-total')), findsNothing);
    expect(find.textContaining('You hold'), findsNothing);
    expect(find.byKey(const ValueKey('commit-card-acc-cc')), findsOneWidget);
    // Credit cards together: what they owe in all, beside the title.
    expect(find.text('Credit cards'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('cards-owed-total'))).data,
      startsWith('Owe ₹'),
    );
    expect(find.textContaining('Settle by'), findsWidgets);
    expect(find.textContaining('From '), findsWidgets);
    expect(find.textContaining('limit'), findsNothing);

    // Pay it back in cash.
    await tester.tap(find.text('Meera'));
    await settle();
    expect(find.textContaining('You owe Meera'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repay-save')));
    await settle();
    final after = (await tester.runAsync(() => db.select(db.dues).get()))!;
    expect(after.single.status, DueStatus.settled);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a small phone still shows everything without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1400);
    tester.view.devicePixelRatio = 2.0; // 360 x 700, a small phone
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(() => DatabaseSeeder(db).seedIfEmpty());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: OwedScreen()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull); // no overflow
    expect(find.byKey(const ValueKey('owed-net')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
