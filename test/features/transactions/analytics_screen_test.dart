import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/ledger/ledger_service.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/transactions/screens/analytics_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('shows the month total, categories and top spends', (
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
      await ledger.recordManual(
        accountId: 'acc-expense',
        amountMinorUnits: -60000,
        type: TransactionType.expense,
        merchant: 'Biryani house',
        category: 'Food',
      );
      await ledger.recordManual(
        accountId: 'acc-expense',
        amountMinorUnits: -20000,
        type: TransactionType.expense,
        merchant: 'Metro',
        category: 'Transport',
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: AnalyticsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<Text>(find.byKey(const ValueKey('analytics-total'))).data,
      contains('800'),
    );
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);

    await tester.tap(find.text('Top spends'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Biryani house'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
