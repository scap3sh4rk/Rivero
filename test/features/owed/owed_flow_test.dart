import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/dues/dues_service.dart';
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
    // One row per person, with what they owe in all.
    expect(find.byKey(const ValueKey('person-row-ravi')), findsOneWidget);
    expect(find.byKey(const ValueKey('person-row-asha')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('person-row-amount-ravi')))
          .data,
      '₹1,000.00',
    );
    expect(find.textContaining('1 split bill'), findsNWidgets(2));
    // Opening a person shows the whole breakdown.
    await tester.tap(find.byKey(const ValueKey('person-row-ravi')));
    await settle();
    expect(find.byKey(const ValueKey('person-totals')), findsOneWidget);
    expect(find.text('Split bills'), findsOneWidget);
    // Each entry settles it, into the account the bill came from.
    await tester.tap(find.textContaining('Their share').first);
    await settle();
    expect(find.byKey(const ValueKey('receive-account')), findsOneWidget);
    await tester.tap(find.text('Mark received'));
    await settle();

    final ravi = (await tester.runAsync(() => db.select(db.dues).get()))!
        .firstWhere((d) => d.person == 'Ravi');
    expect(ravi.status, DueStatus.settled);
    final credit = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!.where((t) => t.transactionType == TransactionType.reimbursement);
    expect(credit.single.amountMinorUnits, 100000);
    expect(credit.single.physicalAccountId, ravi.creditAccountId);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('one person across several split bills is one group', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    await tester.runAsync(() async {
      final ledger = LedgerService(db);
      final dues = DuesService(db);
      for (final (merchant, ravi) in [
        ('Swiggy', 'Ravi'),
        ('Movie', ' ravi '), // the same person, typed differently
      ]) {
        final id = await ledger.recordManual(
          accountId: 'acc-expense',
          amountMinorUnits: -200000,
          type: TransactionType.expense,
          merchant: merchant,
          category: 'Food',
        );
        await dues.splitExpense(
          transactionId: id,
          shares: {ravi: 50000, 'Asha': 50000},
          note: merchant,
        );
      }
    });

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
        child: const MaterialApp(home: OwedToYouScreen()),
      ),
    );
    await settle();
    // Ravi once, for both bills: ₹500 + ₹500.
    expect(find.byKey(const ValueKey('person-row-ravi')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('person-row-amount-ravi')))
          .data,
      '₹1,000.00',
    );
    expect(find.textContaining('2 split bills'), findsNWidgets(2));
    // Ravi's breakdown: each bill by name.
    await tester.tap(find.byKey(const ValueKey('person-row-ravi')));
    await settle();
    expect(find.text('Swiggy'), findsOneWidget);
    expect(find.text('Movie'), findsOneWidget);

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

    // Pay it back in cash: open Meera, then the loan.
    await tester.tap(find.byKey(const ValueKey('person-row-meera')));
    await settle();
    expect(find.text('You owe them'), findsWidgets);
    await tester.tap(find.text('Borrowed'));
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
