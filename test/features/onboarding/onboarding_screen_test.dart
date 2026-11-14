import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/main.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets(
    'empty install runs onboarding and lands on Home with no fake data',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = RiveroDatabase.memory();
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const RiveroApp(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('When do you get paid?'), findsOneWidget);
      expect(find.text('Your Money - In Flow'), findsOneWidget);

      Future<void> next() async {
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const ValueKey('ob-salary')), '80000');
      await tester.pump();
      await next();
      await tester.enterText(
        find.byKey(const ValueKey('ob-name')),
        'HDFC Salary',
      );
      await tester.pump();
      await next();
      await tester.runAsync(() async {
        await tester.tap(find.byType(FilledButton));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(milliseconds: 600));

      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('SAFE TO SPEND PER DAY'), findsOneWidget);
      final accounts = (await tester.runAsync(
        () => db.accountsDao.getAllActivePhysicalAccounts(),
      ))!;
      expect(accounts.map((a) => a.name), ['HDFC Salary']);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}
