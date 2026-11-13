import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/accounts/screens/accounts_screen.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';
import 'package:rivero/features/accounts/widgets/credit_utilization_card.dart';

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
    'AccountsScreen displays Net Worth, Credit Lines, and Bank Accounts',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: AccountsScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Accounts'), findsOneWidget);
      expect(find.text('TOTAL NET WORTH'), findsOneWidget);
      expect(find.text('CREDIT LINE USAGE'), findsOneWidget);
      expect(find.text('BANK & CASH'), findsOneWidget);

      // Verify credit card utilization card
      expect(find.byType(CreditUtilizationCard), findsOneWidget);
      expect(find.text('ICICI Sapphiro Card'), findsOneWidget);
      expect(find.text('Safe (<=10%)'), findsOneWidget);

      // Verify bank accounts
      expect(find.text('Primary HDFC Salary'), findsOneWidget);
      expect(find.text('ICICI Daily Expenses'), findsOneWidget);

      // Tap New Account FAB
      final newAccountFab = find.byTooltip('Add Account');
      expect(newAccountFab, findsOneWidget);
      await tester.tap(newAccountFab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CreateAccountSheet), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Add account'),
        findsOneWidget,
      );

      // Close the add sheet, then edit an existing account by tapping it.
      Navigator.of(tester.element(find.byType(CreateAccountSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Primary HDFC Salary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Edit account'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Primary HDFC Salary'),
        'HDFC Salary',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save changes'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      final renamed = (await tester.runAsync(
        () => db.accountsDao.getPhysicalAccountById('acc-salary'),
      ))!;
      expect(renamed.name, 'HDFC Salary');
      expect(renamed.balanceMinorUnits, 15000000); // untouched by the edit

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
