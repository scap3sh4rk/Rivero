import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
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

  testWidgets('typing 45 and saving posts an expense and spends the budget', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
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

    final before = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!.spentMinorUnits;

    await tester.tap(find.byKey(const ValueKey('key-4')));
    await tester.tap(find.byKey(const ValueKey('key-5')));
    await tester.pump();
    expect(find.text('₹45'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final after = (await tester.runAsync(
      () => db.accountsDao.getBucketById('bucket-expense'),
    ))!.spentMinorUnits;
    expect(after - before, 4500);
    expect(find.text('₹0'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
