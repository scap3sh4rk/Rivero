import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/accounts/screens/account_detail_screen.dart';
import 'package:rivero/features/accounts/screens/accounts_screen.dart';
import 'package:rivero/features/accounts/widgets/create_account_sheet.dart';

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
      expect(find.text('Net worth'), findsOneWidget);
      expect(find.text('Bank & cash'), findsOneWidget);
      expect(find.text('Cards'), findsOneWidget);

      // Verify credit card utilization card
      expect(find.text('ICICI Sapphiro Card'), findsOneWidget);
      // Usage pill shows only the percentage: 14,250 of 1,50,000 = 10%.
      expect(find.text('10%'), findsOneWidget);
      expect(find.textContaining('Pay before'), findsNothing);
      expect(find.textContaining('Limit'), findsOneWidget);
      // Which bank each account is with is shown.
      expect(find.textContaining('HDFC Bank ••4012'), findsOneWidget);

      // Verify bank accounts
      expect(find.text('Primary HDFC Salary'), findsOneWidget);
      expect(find.text('ICICI Daily Expenses'), findsOneWidget);

      // The eye in the top bar hides and shows every balance.
      await tester.tap(find.byKey(const ValueKey('toggle-balances')));
      await tester.pump();
      expect(find.text('••••'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('toggle-balances')));
      await tester.pump();
      expect(find.text('Primary HDFC Salary'), findsOneWidget);

      // Adding an account is the button under the list.
      final addAccount = find.byKey(const ValueKey('add-account'));
      await tester.ensureVisible(addAccount);
      await tester.tap(addAccount);
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
      // Net worth opens its breakdown.
      await tester.tap(find.byKey(const ValueKey('networth-card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('networth-total')), findsOneWidget);
      Navigator.of(tester.element(find.byType(NetWorthSheet))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Tapping an account opens its page; edit from there.
      await tester.tap(find.text('Primary HDFC Salary'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AccountDetailScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));

      // Set the balance by hand with the number keyboard.
      await tester.tap(find.byKey(const ValueKey('update-balance')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.byKey(const ValueKey('balance-field')),
        '2000',
      );
      await tester.tap(find.text('Update'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final updated = (await tester.runAsync(
        () => db.accountsDao.getPhysicalAccountById('acc-salary'),
      ))!;
      expect(updated.balanceMinorUnits, 200000);
      await tester.tap(find.byTooltip('Edit account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Edit account'), findsWidgets);
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
      expect(renamed.balanceMinorUnits, 200000); // the edit keeps the balance

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
