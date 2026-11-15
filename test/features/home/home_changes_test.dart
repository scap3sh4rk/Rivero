import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/home/widgets/add_from_message_sheet.dart';
import 'package:rivero/features/home/widgets/safe_to_spend_hero_card.dart';
import 'package:rivero/features/transactions/screens/transactions_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  late RiveroDatabase db;
  setUp(() async {
    db = RiveroDatabase.memory();
    await DatabaseSeeder(db).seedIfEmpty();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('the Safe to spend bar shows what is left: ₹700 of ₹10,000 is '
      'nearly empty', (tester) async {
    // Spending account holds ₹700; the month's spending plan is ₹10,000.
    await tester.runAsync(() async {
      await (db.update(
        db.physicalAccounts,
      )..where((a) => a.id.equals('acc-expense'))).write(
        const PhysicalAccountsCompanion(balanceMinorUnits: Value(70000)),
      );
      await (db.update(
        db.allocationBuckets,
      )..where((b) => b.id.equals('bucket-expense'))).write(
        const AllocationBucketsCompanion(
          allocatedMinorUnits: Value(1000000),
          carryOverMinorUnits: Value(0),
          spentMinorUnits: Value(0),
        ),
      );
      // Nothing waiting for Accept, so ₹700 is what is left.
      await db.delete(db.transactions).go();
    });
    await pump(tester, const SafeToSpendHeroCard());
    await tester.pump(const Duration(milliseconds: 900));
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('budget-bar')),
    );
    expect(bar.value, closeTo(0.07, 0.01));
    expect(find.text('₹700.00 left of ₹10,000.00'), findsOneWidget);
    await done(tester);
  });

  testWidgets('a message added from Home needs a category; its text is not '
      'the note', (tester) async {
    const message =
        'Union Bank of India A/c*0485 Dr Rs25.00 on 15-11-26 19:19 by MB '
        '631977745590 Fv.IRANI, Bal Rs701.83';
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => AddFromMessageSheet.show(
            context,
            message: message,
            prefill: LogPrefill.fromMessage(message),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final add = find.byKey(const ValueKey('msg-add'));
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('msg-note')))
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('msg-cat-Food')));
    await tester.pump();
    await tester.tap(add);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final saved = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!.where((t) => t.amountMinorUnits == -2500).single;
    expect(saved.category, 'Food');
    expect(saved.userNotes, isNull);
    expect(saved.transactionState, TransactionState.confirmed);
    await done(tester);
  });

  testWidgets('Activity rows show the bank (first word) under the amount; '
      'the detail sheet shows it opposite the amount', (tester) async {
    await pump(tester, const TransactionsScreen());
    final expense = (await tester.runAsync(
      () => db.accountsDao.getPhysicalAccountById('acc-expense'),
    ))!;
    final first = expense.institution.split(' ').first;
    final bank = find.byKey(const ValueKey('row-bank-txn-review-1'));
    expect(bank, findsOneWidget);
    expect(
      find.descendant(of: bank, matching: find.text(first)),
      findsOneWidget,
    );
    // Under the amount: same right edge, lower down.
    final amount = find.text('₹450.00').first;
    expect(
      tester.getBottomRight(bank).dx,
      closeTo(tester.getBottomRight(amount).dx, 1),
    );
    expect(
      tester.getTopLeft(bank).dy,
      greaterThan(tester.getTopLeft(amount).dy),
    );

    await tester.tap(find.text('Zomato'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final detail = find.byKey(const ValueKey('detail-account'));
    expect(detail, findsOneWidget);
    expect(
      find.descendant(
        of: detail,
        matching: find.textContaining(expense.institution),
      ),
      findsOneWidget,
    );
    await done(tester);
  });
}
