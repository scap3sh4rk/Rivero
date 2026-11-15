import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
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

  testWidgets('one account balance can be hidden, and shown again', (
    tester,
  ) async {
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

    Text balance(String id) =>
        tester.widget<Text>(find.byKey(ValueKey('balance-$id')));
    expect(balance('acc-salary').data, isNot('••••'));
    await tester.tap(find.byKey(const ValueKey('hide-acc-salary')));
    await tester.pump();
    expect(balance('acc-salary').data, '••••');
    expect(balance('acc-expense').data, isNot('••••')); // only that one
    await tester.tap(find.byKey(const ValueKey('hide-acc-salary')));
    await tester.pump();
    expect(balance('acc-salary').data, isNot('••••'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets("with everything hidden, one account's eye reveals only it", (
    tester,
  ) async {
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AccountsScreen)),
    );
    Text balance(String id) =>
        tester.widget<Text>(find.byKey(ValueKey('balance-$id')));

    // The global eye hides everything.
    await tester.tap(find.byKey(const ValueKey('toggle-balances')));
    await tester.pump();
    expect(balance('acc-salary').data, '••••');
    expect(balance('acc-expense').data, '••••');

    // Showing one account wins over the global switch: only it is shown.
    await tester.tap(find.byKey(const ValueKey('hide-acc-salary')));
    await tester.pump();
    expect(container.read(privacyModeProvider), isFalse);
    expect(balance('acc-salary').data, isNot('••••'));
    expect(balance('acc-expense').data, '••••');

    // The global eye then hides all, and shows all again.
    await tester.tap(find.byKey(const ValueKey('toggle-balances')));
    await tester.pump();
    expect(balance('acc-salary').data, '••••');
    await tester.tap(find.byKey(const ValueKey('toggle-balances')));
    await tester.pump();
    expect(balance('acc-salary').data, isNot('••••'));
    expect(balance('acc-expense').data, isNot('••••'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('sections fold; FDs show maturity; net worth can leave one out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    await db.accountsDao.upsertPhysicalAccount(
      PhysicalAccountsCompanion(
        id: const Value('fd'),
        name: const Value('SBI FD'),
        institution: const Value('SBI'),
        accountMask: const Value('9999'),
        accountType: const Value('Fixed Deposit'),
        balanceMinorUnits: const Value(10000000),
        fdRateBps: const Value(700),
        fdStartDate: Value(DateTime(now.year, now.month, now.day)),
        fdMaturityDate: Value(DateTime(now.year + 1, now.month, now.day)),
        includeInNetWorth: const Value(false),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: AccountsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // Its own section, with what it will be worth.
    expect(find.text('Fixed deposits'), findsOneWidget);
    expect(find.byKey(const ValueKey('fd-maturity-fd')), findsOneWidget);
    expect(find.textContaining('7.00% a year'), findsOneWidget);
    // Left out of net worth, and the card says so.
    expect(find.textContaining('1 left out'), findsOneWidget);

    // Folding a section hides its accounts; tapping again shows them.
    expect(find.byKey(const ValueKey('balance-acc-salary')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fold-bank')));
    await tester.pump();
    expect(find.byKey(const ValueKey('balance-acc-salary')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('fold-bank')));
    await tester.pump();
    expect(find.byKey(const ValueKey('balance-acc-salary')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
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
      expect(find.text('Credit cards'), findsOneWidget);

      // Verify credit card utilization card
      expect(find.text('ICICI Sapphiro Card'), findsOneWidget);
      // Usage pill shows only the percentage: 14,250 of 1,50,000 = 10%.
      expect(find.text('10%'), findsOneWidget);
      expect(find.textContaining('Pay before'), findsNothing);
      // Billing cycle: days left, due date, and whether you can pay it.
      expect(find.byKey(const ValueKey('cycle-days-acc-cc')), findsOneWidget);
      expect(find.byKey(const ValueKey('due-acc-cc')), findsOneWidget);
      expect(find.byKey(const ValueKey('afford-acc-cc')), findsOneWidget);
      expect(find.byKey(const ValueKey('cards-summary')), findsOneWidget);
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

      // Adding an account is the plus at the bottom right.
      final addAccount = find.byTooltip('Add account or card');
      expect(addAccount, findsOneWidget);
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

  testWidgets('an FD asks for its rate and dates and is saved with them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: Scaffold(body: CreateAccountSheet())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Account type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // A real dropdown under the field: scroll it to Fixed Deposit.
    await tester.ensureVisible(
      find.byKey(const ValueKey('pick-Fixed Deposit')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pick-Fixed Deposit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // FD-only questions appear.
    expect(find.text('Amount deposited (INR)'), findsOneWidget);
    expect(find.byKey(const ValueKey('fd-rate')), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'SBI FD');
    await tester.enterText(find.byType(TextFormField).at(1), 'SBI');
    await tester.enterText(
      find.widgetWithText(TextFormField, '50000.00'),
      '100000',
    );
    await tester.enterText(find.byKey(const ValueKey('fd-rate')), '7.25');
    await tester.pump();
    await tester.ensureVisible(find.text('Add account').last);
    await tester.tap(find.text('Add account').last);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    final fd = (await tester.runAsync(
      () => db.select(db.physicalAccounts).get(),
    ))!.firstWhere((a) => a.name == 'SBI FD');
    expect(fd.fdRateBps, 725);
    expect(fd.balanceMinorUnits, 10000000);
    expect(fd.includeInNetWorth, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('an account can take one of the bank icons already added', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = Directory.systemTemp.createTempSync('rivero_icons');
    final icon = File('${dir.path}/kotak.png')..writeAsBytesSync([1, 2, 3]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          bankIconsProvider.overrideWith((ref) => {'kotak': icon.path}),
        ],
        child: const MaterialApp(home: Scaffold(body: CreateAccountSheet())),
      ),
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('account-bank-icon')));
    await tester.tap(find.byKey(const ValueKey('account-bank-icon')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('pick-icon-kotak')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The account's picture is now that icon.
    expect(
      tester
          .widgetList<BankBadge>(find.byType(BankBadge))
          .any((b) => b.imagePath == icon.path && b.size == 48),
      isTrue,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
