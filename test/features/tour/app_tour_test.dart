import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/daos/settings_dao.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/home/widgets/get_started_card.dart';
import 'package:rivero/main.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('a fresh install opens straight to Home, then tours the tabs', (
    tester,
  ) async {
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    // No setup wizard: Home with a get-started card.
    await container.read(settingsSyncProvider).load();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('SAFE TO SPEND PER DAY'), findsOneWidget);
    expect(find.byType(GetStartedCard), findsOneWidget);
    expect(find.text('Add your accounts'), findsOneWidget);

    // The tour starts a moment after Home appears, and walks the tabs.
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byKey(const ValueKey('tour-card')), findsOneWidget);
    expect(find.text('Welcome to Rivero'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tour-next')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start here: your accounts'), findsOneWidget);
    expect(container.read(selectedNavIndexProvider), 1);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Let Rivero capture payments'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tour-next')));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byKey(const ValueKey('tour-card')), findsNothing);
    expect(container.read(tourPendingProvider), isFalse);
    expect(
      await tester.runAsync(() => db.settingsDao.get(SettingKeys.tourDone)),
      '1',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
