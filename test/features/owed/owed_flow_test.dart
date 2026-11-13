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
}
