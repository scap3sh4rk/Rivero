import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/database/database_seeder.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/features/home/widgets/home_shortcuts.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(setupTestDatabase);

  testWidgets('a long autopay name never makes its tile bigger', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = RiveroDatabase.memory();
    addTearDown(db.close);
    await DatabaseSeeder(db).seedIfEmpty();
    // Make every autopay's name very long.
    await db
        .update(db.mandates)
        .write(
          const MandatesCompanion(
            payee: Value(
              'Systematic Investment Plan into a very long mutual fund name',
            ),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: HomeShortcuts())),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('Systematic Investment'), findsOneWidget);
    final sizes = [
      for (final k in ['home-plan', 'home-owed', 'home-autopay', 'home-spent'])
        tester.getSize(find.byKey(ValueKey(k))),
    ];
    expect(sizes.map((s) => s.height).toSet().length, 1);
    expect(sizes.map((s) => s.width).toSet().length, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('only the chosen cards show, in the chosen order, same size', (
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
        overrides: [
          databaseProvider.overrideWithValue(db),
          homeWidgetsProvider.overrideWith(
            (ref) => ['netWorth', 'cardBills', 'spent'],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: HomeShortcuts())),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('home-plan')), findsNothing);
    expect(find.byKey(const ValueKey('home-networth')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-cardbills')), findsOneWidget);
    // In order: net worth left of card bills; spent on the next row, alone
    // but no wider than the others.
    final nw = tester.getRect(find.byKey(const ValueKey('home-networth')));
    final cb = tester.getRect(find.byKey(const ValueKey('home-cardbills')));
    final sp = tester.getRect(find.byKey(const ValueKey('home-spent')));
    expect(nw.left, lessThan(cb.left));
    expect(sp.top, greaterThan(nw.bottom));
    expect(sp.width, nw.width);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
