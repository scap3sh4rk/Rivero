import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/domain/transaction_enums.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/widgets/bank_badge.dart';
import 'package:rivero/features/mandates/mandates_screen.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  test('BankBadge.initials takes up to two initials', () {
    expect(BankBadge.initials('HDFC Bank'), 'HB');
    expect(BankBadge.initials('sbi'), 'S');
    expect(BankBadge.initials('  '), '');
  });

  testWidgets('cancelling a mandate removes it from the active list', (
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
        child: const MaterialApp(home: MandatesScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final before = (await tester.runAsync(
      () => db.mandatesDao.watchActiveMandates().first,
    ))!;
    expect(before, isNotEmpty);
    await tester.tap(find.text(before.first.payee));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('I cancelled this in my bank'), findsOneWidget);
    await tester.tap(find.text('I cancelled this in my bank'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    final after = (await tester.runAsync(
      () => db.mandatesDao.watchActiveMandates().first,
    ))!;
    expect(after.length, before.length - 1);
    expect(find.text('PAUSED & ENDED'), findsOneWidget);
    final all = (await tester.runAsync(
      () => db.mandatesDao.watchAllMandates().first,
    ))!;
    expect(all.any((m) => m.status == MandateStatus.cancelled), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
